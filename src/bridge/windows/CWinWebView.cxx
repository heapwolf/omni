// WebView2.h ships with the WebView2 SDK, not the Windows SDK.

#include "CWinWebView.h"
#include <windows.h>
#include <string>
#include <vector>
#include <unordered_map>

// Swift receivers, in WebView+Windows.swift. Keyed by HWND rather than a
// Swift object pointer, matching WindowsEventRegistry.
extern "C" {
    /// Returns 1 to cancel.
    int  omni_swift_win_web_policy(void* hwnd, const char* url);
    /// kind: 0 title, 1 started, 2 finished, 3 error, 4 message.
    void omni_swift_win_web_event(void* hwnd, int kind, const char* value);
    void omni_swift_win_web_state(void* hwnd, double progress, int can_go_back, int can_go_forward);
}

static const int OMNI_WEB_TITLE    = 0;
static const int OMNI_WEB_STARTED  = 1;
static const int OMNI_WEB_FINISHED = 2;
static const int OMNI_WEB_ERROR    = 3;
static const int OMNI_WEB_MESSAGE  = 4;

// window.omni.postMessage(value), the same call on every backend.
static const wchar_t* OMNI_WEB_SHIM =
    L"window.omni = window.omni || {};"
    L"window.omni.postMessage = function (value) {"
    L"  window.chrome.webview.postMessage(String(value));"
    L"};";

#if defined(__has_include)
#  if __has_include(<WebView2.h>)
#    define OMNI_HAS_WEBVIEW2 1
#  endif
#endif

#ifdef OMNI_HAS_WEBVIEW2

#include <WebView2.h>
#include <wrl.h>
#include <wrl/event.h>

using namespace Microsoft::WRL;

static std::wstring omni_utf8_to_utf16(const char* input) {
    if (!input || !*input) return L"";
    int needed = MultiByteToWideChar(CP_UTF8, 0, input, -1, NULL, 0);
    if (needed <= 0) return L"";
    std::wstring out(needed, 0);
    MultiByteToWideChar(CP_UTF8, 0, input, -1, &out[0], needed);
    if (!out.empty() && out.back() == L'\0') out.pop_back();
    return out;
}

static std::string omni_utf16_to_utf8(const wchar_t* input) {
    if (!input || !*input) return "";
    int needed = WideCharToMultiByte(CP_UTF8, 0, input, -1, NULL, 0, NULL, NULL);
    if (needed <= 0) return "";
    std::string out(needed, 0);
    WideCharToMultiByte(CP_UTF8, 0, input, -1, &out[0], needed, NULL, NULL);
    if (!out.empty() && out.back() == '\0') out.pop_back();
    return out;
}

namespace {

/// Replayed once the controller exists.
struct PendingCommand {
    enum Kind { Navigate, NavigateToString, Back, Forward, Reload, Stop, Evaluate } kind;
    std::wstring payload;
};

struct WebHost {
    HWND hwnd = nullptr;
    ComPtr<ICoreWebView2Controller> controller;
    ComPtr<ICoreWebView2> webview;
    std::vector<PendingCommand> pending;
    bool ready = false;
};

std::unordered_map<HWND, WebHost*>& hosts() {
    static std::unordered_map<HWND, WebHost*> map;
    return map;
}

WebHost* hostFor(void* hwnd) {
    if (!hwnd) return nullptr;
    auto it = hosts().find(static_cast<HWND>(hwnd));
    return it == hosts().end() ? nullptr : it->second;
}

void reportNavigationState(WebHost* host) {
    if (!host || !host->webview) return;
    BOOL back = FALSE, forward = FALSE;
    host->webview->get_CanGoBack(&back);
    host->webview->get_CanGoForward(&forward);
    // WebView2 exposes no progress fraction, only started and completed.
    omni_swift_win_web_state(host->hwnd, host->ready ? 1.0 : 0.0, back ? 1 : 0, forward ? 1 : 0);
}

void run(WebHost* host, const PendingCommand& command) {
    if (!host->webview) return;
    switch (command.kind) {
        case PendingCommand::Navigate:
            host->webview->Navigate(command.payload.c_str());
            break;
        case PendingCommand::NavigateToString:
            host->webview->NavigateToString(command.payload.c_str());
            break;
        case PendingCommand::Back:    host->webview->GoBack();   break;
        case PendingCommand::Forward: host->webview->GoForward(); break;
        case PendingCommand::Reload:  host->webview->Reload();    break;
        case PendingCommand::Stop:    host->webview->Stop();      break;
        case PendingCommand::Evaluate:
            host->webview->ExecuteScript(command.payload.c_str(), nullptr);
            break;
    }
}

void submit(void* hwnd, PendingCommand command) {
    WebHost* host = hostFor(hwnd);
    if (!host) return;
    if (host->ready) {
        run(host, command);
    } else {
        host->pending.push_back(command);
    }
}

void attachEventHandlers(WebHost* host) {
    HWND key = host->hwnd;
    EventRegistrationToken token;

    host->webview->add_NavigationStarting(
        Callback<ICoreWebView2NavigationStartingEventHandler>(
            [key](ICoreWebView2*, ICoreWebView2NavigationStartingEventArgs* args) -> HRESULT {
                LPWSTR uri = nullptr;
                if (SUCCEEDED(args->get_Uri(&uri)) && uri) {
                    std::string utf8 = omni_utf16_to_utf8(uri);
                    CoTaskMemFree(uri);
                    if (omni_swift_win_web_policy(key, utf8.c_str()) == 1) {
                        args->put_Cancel(TRUE);
                        return S_OK;
                    }
                    omni_swift_win_web_event(key, OMNI_WEB_STARTED, utf8.c_str());
                }
                return S_OK;
            }).Get(), &token);

    host->webview->add_NavigationCompleted(
        Callback<ICoreWebView2NavigationCompletedEventHandler>(
            [key](ICoreWebView2* sender, ICoreWebView2NavigationCompletedEventArgs* args) -> HRESULT {
                BOOL success = FALSE;
                args->get_IsSuccess(&success);

                LPWSTR uri = nullptr;
                std::string utf8;
                if (SUCCEEDED(sender->get_Source(&uri)) && uri) {
                    utf8 = omni_utf16_to_utf8(uri);
                    CoTaskMemFree(uri);
                }

                if (success) {
                    omni_swift_win_web_event(key, OMNI_WEB_FINISHED, utf8.c_str());
                } else {
                    COREWEBVIEW2_WEB_ERROR_STATUS status = COREWEBVIEW2_WEB_ERROR_STATUS_UNKNOWN;
                    args->get_WebErrorStatus(&status);
                    // A cancelled navigation is what a policy decision looks
                    // like from WebView2's side, not a failure to report.
                    if (status != COREWEBVIEW2_WEB_ERROR_STATUS_OPERATION_CANCELED) {
                        std::string message = "Navigation failed (WebView2 status "
                            + std::to_string(static_cast<int>(status)) + ").";
                        omni_swift_win_web_event(key, OMNI_WEB_ERROR, message.c_str());
                    }
                }
                if (WebHost* host = hostFor(key)) reportNavigationState(host);
                return S_OK;
            }).Get(), &token);

    host->webview->add_DocumentTitleChanged(
        Callback<ICoreWebView2DocumentTitleChangedEventHandler>(
            [key](ICoreWebView2* sender, IUnknown*) -> HRESULT {
                LPWSTR title = nullptr;
                if (SUCCEEDED(sender->get_DocumentTitle(&title)) && title) {
                    std::string utf8 = omni_utf16_to_utf8(title);
                    CoTaskMemFree(title);
                    omni_swift_win_web_event(key, OMNI_WEB_TITLE, utf8.c_str());
                }
                return S_OK;
            }).Get(), &token);

    host->webview->add_WebMessageReceived(
        Callback<ICoreWebView2WebMessageReceivedEventHandler>(
            [key](ICoreWebView2*, ICoreWebView2WebMessageReceivedEventArgs* args) -> HRESULT {
                LPWSTR message = nullptr;
                if (SUCCEEDED(args->TryGetWebMessageAsString(&message)) && message) {
                    std::string utf8 = omni_utf16_to_utf8(message);
                    CoTaskMemFree(message);
                    omni_swift_win_web_event(key, OMNI_WEB_MESSAGE, utf8.c_str());
                }
                return S_OK;
            }).Get(), &token);
}

void finishSetup(WebHost* host, ICoreWebView2Controller* controller) {
    host->controller = controller;
    controller->get_CoreWebView2(&host->webview);
    if (!host->webview) return;

    host->webview->AddScriptToExecuteOnDocumentCreated(OMNI_WEB_SHIM, nullptr);
    attachEventHandlers(host);

    RECT bounds;
    GetClientRect(host->hwnd, &bounds);
    controller->put_Bounds(bounds);
    controller->put_IsVisible(TRUE);

    host->ready = true;
    for (const PendingCommand& command : host->pending) run(host, command);
    host->pending.clear();
    reportNavigationState(host);
}

} // namespace

extern "C" {

int omni_win_web_available(void) {
    // The SDK was present at build time; the runtime is a separate install.
    LPWSTR version = nullptr;
    HRESULT hr = GetAvailableCoreWebView2BrowserVersionString(nullptr, &version);
    if (SUCCEEDED(hr) && version) {
        CoTaskMemFree(version);
        return 1;
    }
    return 0;
}

void* omni_win_create_webview(void* parent_hwnd, int x, int y, int w, int h) {
    HWND host = CreateWindowExW(
        0, L"STATIC", L"",
        WS_VISIBLE | WS_CHILD | WS_CLIPSIBLINGS | WS_CLIPCHILDREN,
        x, y, w, h,
        static_cast<HWND>(parent_hwnd), NULL, GetModuleHandleW(NULL), NULL);
    if (!host) return nullptr;

    WebHost* state = new WebHost();
    state->hwnd = host;
    hosts()[host] = state;

    CreateCoreWebView2EnvironmentWithOptions(nullptr, nullptr, nullptr,
        Callback<ICoreWebView2CreateCoreWebView2EnvironmentCompletedHandler>(
            [host](HRESULT result, ICoreWebView2Environment* environment) -> HRESULT {
                WebHost* state = hostFor(host);
                if (!state) return S_OK;   // destroyed while we were waiting
                if (FAILED(result) || !environment) {
                    omni_swift_win_web_event(host, OMNI_WEB_ERROR,
                        "WebView2 environment could not be created. The Evergreen runtime is usually missing.");
                    return S_OK;
                }
                environment->CreateCoreWebView2Controller(host,
                    Callback<ICoreWebView2CreateCoreWebView2ControllerCompletedHandler>(
                        [host](HRESULT result, ICoreWebView2Controller* controller) -> HRESULT {
                            WebHost* state = hostFor(host);
                            if (!state) return S_OK;
                            if (FAILED(result) || !controller) {
                                omni_swift_win_web_event(host, OMNI_WEB_ERROR,
                                    "WebView2 controller could not be created.");
                                return S_OK;
                            }
                            finishSetup(state, controller);
                            return S_OK;
                        }).Get());
                return S_OK;
            }).Get());

    return host;
}

void omni_win_web_load(void* hwnd, const char* url) {
    submit(hwnd, { PendingCommand::Navigate, omni_utf8_to_utf16(url) });
}

void omni_win_web_load_html(void* hwnd, const char* html) {
    submit(hwnd, { PendingCommand::NavigateToString, omni_utf8_to_utf16(html) });
}

void omni_win_web_go_back(void* hwnd)    { submit(hwnd, { PendingCommand::Back, L"" }); }
void omni_win_web_go_forward(void* hwnd) { submit(hwnd, { PendingCommand::Forward, L"" }); }
void omni_win_web_reload(void* hwnd)     { submit(hwnd, { PendingCommand::Reload, L"" }); }
void omni_win_web_stop(void* hwnd)       { submit(hwnd, { PendingCommand::Stop, L"" }); }

void omni_win_web_evaluate(void* hwnd, const char* source) {
    submit(hwnd, { PendingCommand::Evaluate, omni_utf8_to_utf16(source) });
}

void omni_win_web_set_bounds(void* hwnd, int x, int y, int w, int h) {
    WebHost* host = hostFor(hwnd);
    if (!host) return;
    MoveWindow(host->hwnd, x, y, w, h, TRUE);
    if (host->controller) {
        RECT bounds = { 0, 0, w, h };
        host->controller->put_Bounds(bounds);
    }
}

void omni_win_web_destroy(void* hwnd) {
    WebHost* host = hostFor(hwnd);
    if (!host) return;
    if (host->controller) host->controller->Close();
    hosts().erase(host->hwnd);
    DestroyWindow(host->hwnd);
    delete host;
}

} // extern "C"

#else // no WebView2 SDK at build time

extern "C" {

int omni_win_web_available(void) { return 0; }

void* omni_win_create_webview(void* parent_hwnd, int x, int y, int w, int h) {
    // A readable notice rather than an empty rectangle.
    return CreateWindowExW(
        0, L"STATIC",
        L"No web engine: this build has no WebView2 SDK.",
        WS_VISIBLE | WS_CHILD | WS_CLIPSIBLINGS,
        x, y, w, h,
        static_cast<HWND>(parent_hwnd), NULL, GetModuleHandleW(NULL), NULL);
}

void omni_win_web_load(void* hwnd, const char* url) { (void)hwnd; (void)url; }
void omni_win_web_load_html(void* hwnd, const char* html) { (void)hwnd; (void)html; }
void omni_win_web_go_back(void* hwnd) { (void)hwnd; }
void omni_win_web_go_forward(void* hwnd) { (void)hwnd; }
void omni_win_web_reload(void* hwnd) { (void)hwnd; }
void omni_win_web_stop(void* hwnd) { (void)hwnd; }
void omni_win_web_evaluate(void* hwnd, const char* source) { (void)hwnd; (void)source; }

void omni_win_web_set_bounds(void* hwnd, int x, int y, int w, int h) {
    if (hwnd) MoveWindow(static_cast<HWND>(hwnd), x, y, w, h, TRUE);
}

void omni_win_web_destroy(void* hwnd) {
    if (hwnd) DestroyWindow(static_cast<HWND>(hwnd));
}

} // extern "C"

#endif
