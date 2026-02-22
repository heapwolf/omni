
#if os(Linux)
import Foundation
import Glibc

private nonisolated(unsafe) let libwebkit: UnsafeMutableRawPointer? =
    dlopen("libwebkit2gtk-4.1.so.0", RTLD_LAZY | RTLD_GLOBAL)
    ?? dlopen("libwebkit2gtk-4.0.so.37", RTLD_LAZY | RTLD_GLOBAL)

private nonisolated(unsafe) let libjsc: UnsafeMutableRawPointer? =
    dlopen("libjavascriptcoregtk-4.1.so.0", RTLD_LAZY | RTLD_GLOBAL)
    ?? dlopen("libjavascriptcoregtk-4.0.so.18", RTLD_LAZY | RTLD_GLOBAL)
    ?? libwebkit

var linuxWebEngineAvailable: Bool {
    guard let libwebkit else { return false }
    return dlsym(libwebkit, "webkit_web_view_new") != nil
}

// MARK: - The C surface

private nonisolated(unsafe) let webkit_web_view_new: @convention(c) () -> NativeView =
    fn(libwebkit, "webkit_web_view_new")
private nonisolated(unsafe) let webkit_web_view_load_uri: @convention(c) (NativeView, UnsafePointer<CChar>) -> Void =
    fn(libwebkit, "webkit_web_view_load_uri")
private nonisolated(unsafe) let webkit_web_view_load_html: @convention(c) (NativeView, UnsafePointer<CChar>, UnsafePointer<CChar>?) -> Void =
    fn(libwebkit, "webkit_web_view_load_html")
private nonisolated(unsafe) let webkit_web_view_go_back: @convention(c) (NativeView) -> Void =
    fn(libwebkit, "webkit_web_view_go_back")
private nonisolated(unsafe) let webkit_web_view_go_forward: @convention(c) (NativeView) -> Void =
    fn(libwebkit, "webkit_web_view_go_forward")
private nonisolated(unsafe) let webkit_web_view_reload: @convention(c) (NativeView) -> Void =
    fn(libwebkit, "webkit_web_view_reload")
private nonisolated(unsafe) let webkit_web_view_stop_loading: @convention(c) (NativeView) -> Void =
    fn(libwebkit, "webkit_web_view_stop_loading")
private nonisolated(unsafe) let webkit_web_view_can_go_back: @convention(c) (NativeView) -> Int32 =
    fn(libwebkit, "webkit_web_view_can_go_back")
private nonisolated(unsafe) let webkit_web_view_can_go_forward: @convention(c) (NativeView) -> Int32 =
    fn(libwebkit, "webkit_web_view_can_go_forward")
private nonisolated(unsafe) let webkit_web_view_get_title: @convention(c) (NativeView) -> UnsafePointer<CChar>? =
    fn(libwebkit, "webkit_web_view_get_title")
private nonisolated(unsafe) let webkit_web_view_get_uri: @convention(c) (NativeView) -> UnsafePointer<CChar>? =
    fn(libwebkit, "webkit_web_view_get_uri")
private nonisolated(unsafe) let webkit_web_view_get_estimated_load_progress: @convention(c) (NativeView) -> Double =
    fn(libwebkit, "webkit_web_view_get_estimated_load_progress")
private nonisolated(unsafe) let webkit_web_view_get_user_content_manager: @convention(c) (NativeView) -> NativeView =
    fn(libwebkit, "webkit_web_view_get_user_content_manager")

// Policy decisions.
private nonisolated(unsafe) let webkit_policy_decision_use: @convention(c) (UnsafeMutableRawPointer) -> Void =
    fn(libwebkit, "webkit_policy_decision_use")
private nonisolated(unsafe) let webkit_policy_decision_ignore: @convention(c) (UnsafeMutableRawPointer) -> Void =
    fn(libwebkit, "webkit_policy_decision_ignore")
private nonisolated(unsafe) let webkit_navigation_policy_decision_get_navigation_action: @convention(c) (UnsafeMutableRawPointer) -> UnsafeMutableRawPointer? =
    fn(libwebkit, "webkit_navigation_policy_decision_get_navigation_action")
private nonisolated(unsafe) let webkit_navigation_action_get_request: @convention(c) (UnsafeMutableRawPointer) -> UnsafeMutableRawPointer? =
    fn(libwebkit, "webkit_navigation_action_get_request")
private nonisolated(unsafe) let webkit_uri_request_get_uri: @convention(c) (UnsafeMutableRawPointer) -> UnsafePointer<CChar>? =
    fn(libwebkit, "webkit_uri_request_get_uri")

// The message channel and the shim that renames it.
private nonisolated(unsafe) let webkit_user_content_manager_register_script_message_handler: @convention(c) (NativeView, UnsafePointer<CChar>) -> Int32 =
    fn(libwebkit, "webkit_user_content_manager_register_script_message_handler")
private nonisolated(unsafe) let webkit_user_content_manager_add_script: @convention(c) (NativeView, UnsafeMutableRawPointer) -> Void =
    fn(libwebkit, "webkit_user_content_manager_add_script")
private nonisolated(unsafe) let webkit_user_script_new: @convention(c) (UnsafePointer<CChar>, Int32, Int32, UnsafeMutableRawPointer?, UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer =
    fn(libwebkit, "webkit_user_script_new")
private nonisolated(unsafe) let webkit_javascript_result_get_js_value: @convention(c) (UnsafeMutableRawPointer) -> UnsafeMutableRawPointer? =
    fn(libwebkit, "webkit_javascript_result_get_js_value")
private nonisolated(unsafe) let jsc_value_to_string: @convention(c) (UnsafeMutableRawPointer) -> UnsafeMutablePointer<CChar>? =
    fn(libjsc, "jsc_value_to_string")

/// 2.40 replaced run_javascript with evaluate_javascript; only one is called.
private nonisolated(unsafe) let webkit_web_view_evaluate_javascript: @convention(c) (NativeView, UnsafePointer<CChar>, Int, UnsafePointer<CChar>?, UnsafePointer<CChar>?, UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, UnsafeMutableRawPointer?) -> Void =
    fn(libwebkit, "webkit_web_view_evaluate_javascript")
private nonisolated(unsafe) let webkit_web_view_run_javascript: @convention(c) (NativeView, UnsafePointer<CChar>, UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, UnsafeMutableRawPointer?) -> Void =
    fn(libwebkit, "webkit_web_view_run_javascript")

// WebKitLoadEvent
private let WEBKIT_LOAD_STARTED: Int32 = 0
private let WEBKIT_LOAD_FINISHED: Int32 = 3
// WebKitPolicyDecisionType
private let WEBKIT_POLICY_DECISION_TYPE_NAVIGATION_ACTION: Int32 = 0

// MARK: - Per-view state

/// @MainActor: GTK signal callbacks run on the thread owning the main loop,
/// which is the thread the engine renders on.
@MainActor
private final class LinuxWebProxy {
    weak var page: WebPage?
    let backing = WebViewBacking()
    var view: NativeView?
    init() {}
}

private func proxy(from pointer: UnsafeMutableRawPointer) -> LinuxWebProxy {
    Unmanaged<LinuxWebProxy>.fromOpaque(pointer).takeUnretainedValue()
}

extension WebView {
    public func makeNative() -> NativeView {
        guard linuxWebEngineAvailable else {
            // A visible notice, expanded like a real web view so the screen does not
            // change shape depending on whether an engine is installed.
            let notice = gtk_label_new("No web engine: install libwebkit2gtk-4.1 (or 4.0).")
            gtk_widget_set_hexpand(notice, 1)
            gtk_widget_set_vexpand(notice, 1)
            return notice
        }

        let view = webkit_web_view_new()
        gtk_widget_set_hexpand(view, 1)
        gtk_widget_set_vexpand(view, 1)

        let p = LinuxWebProxy()
        p.view = view
        let ptr = Unmanaged.passRetained(p).toOpaque()
        g_object_set_data_full(view, "omni_web_proxy", ptr) { released in
            if let released { Unmanaged<LinuxWebProxy>.fromOpaque(released).release() }
        }

        // window.omni.postMessage, over WebKit's own channel.
        let manager = webkit_web_view_get_user_content_manager(view)
        _ = webkit_user_content_manager_register_script_message_handler(manager, "omni")
        let shim = """
            window.omni = window.omni || {};
            window.omni.postMessage = function (value) {
                window.webkit.messageHandlers.omni.postMessage(String(value));
            };
            """
        // WEBKIT_USER_CONTENT_INJECT_ALL_FRAMES, WEBKIT_USER_SCRIPT_INJECT_AT_DOCUMENT_START
        webkit_user_content_manager_add_script(manager, webkit_user_script_new(shim, 0, 0, nil, nil))

        connectSignals(view: view, manager: manager, ptr: ptr)
        return view
    }

    public func updateNative(_ view: NativeView) {
        guard linuxWebEngineAvailable, let ptr = g_object_get_data(view, "omni_web_proxy") else {
            // Drained and dropped: nothing here can run them, and draining keeps the node
            // observing the page.
            _ = page?.drainCommands()
            page?.report(error: "No web engine: install libwebkit2gtk-4.1 (or 4.0).")
            return
        }
        let p = proxy(from: ptr)
        p.page = page

        guard let page else {
            if let url = staticURL, p.backing.lastRequested != url {
                p.backing.lastRequested = url
                webkit_web_view_load_uri(view, url.absoluteString)
            }
            return
        }

        for command in page.drainCommands() {
            switch command {
            case .load(let url):
                webkit_web_view_load_uri(view, url.absoluteString)
            case .loadHTML(let html, let baseURL):
                if let baseURL {
                    baseURL.absoluteString.withCString { webkit_web_view_load_html(view, html, $0) }
                } else {
                    webkit_web_view_load_html(view, html, nil)
                }
            case .goBack:    webkit_web_view_go_back(view)
            case .goForward: webkit_web_view_go_forward(view)
            case .reload:    webkit_web_view_reload(view)
            case .stop:      webkit_web_view_stop_loading(view)
            case .evaluate(let source):
                if dlsym(libwebkit, "webkit_web_view_evaluate_javascript") != nil {
                    webkit_web_view_evaluate_javascript(view, source, -1, nil, nil, nil, nil, nil)
                } else {
                    webkit_web_view_run_javascript(view, source, nil, nil, nil)
                }
            }
        }
    }

    /// Connected unswapped; user data last. bindLinuxEvent's swapped trick only
    /// works for signals that take no arguments and return nothing.
    private func connectSignals(view: NativeView, manager: NativeView, ptr: UnsafeMutableRawPointer) {
        // Returning 1 says the handler settled it.
        let onPolicy: @convention(c) (NativeView, UnsafeMutableRawPointer, Int32, UnsafeMutableRawPointer) -> Int32 = { _, decision, type, userData in
            guard type == WEBKIT_POLICY_DECISION_TYPE_NAVIGATION_ACTION else { return 0 }
            return MainActor.assumeIsolated {
                let p = proxy(from: userData)
                guard let page = p.page,
                      let action = webkit_navigation_policy_decision_get_navigation_action(decision),
                      let request = webkit_navigation_action_get_request(action),
                      let uri = webkit_uri_request_get_uri(request),
                      let url = URL(string: String(cString: uri)) else { return 0 }

                if page.policy(for: url) == .cancel {
                    webkit_policy_decision_ignore(decision)
                    return 1
                }
                webkit_policy_decision_use(decision)
                return 1
            }
        }
        g_signal_connect_data(view, "decide-policy",
                              unsafeBitCast(onPolicy, to: UnsafeMutableRawPointer.self), ptr, nil, 0)

        let onLoadChanged: @convention(c) (NativeView, Int32, UnsafeMutableRawPointer) -> Void = { webView, event, userData in
            MainActor.assumeIsolated {
                let p = proxy(from: userData)
                guard let page = p.page else { return }
                if event == WEBKIT_LOAD_STARTED {
                    page.report(isLoading: true)
                    page.report(error: nil)
                } else if event == WEBKIT_LOAD_FINISHED {
                    page.report(isLoading: false)
                }
                refresh(webView, into: page)
            }
        }
        g_signal_connect_data(view, "load-changed",
                              unsafeBitCast(onLoadChanged, to: UnsafeMutableRawPointer.self), ptr, nil, 0)

        // (view, load_event, failing_uri, GError*, user_data) -> gboolean.
        // Returning 0 lets WebKit show its own error page.
        let onLoadFailed: @convention(c) (NativeView, Int32, UnsafePointer<CChar>?, UnsafeMutableRawPointer?, UnsafeMutableRawPointer) -> Int32 = { _, _, failingURI, _, userData in
            MainActor.assumeIsolated {
                let p = proxy(from: userData)
                p.page?.report(isLoading: false)
                let uri = failingURI.map { String(cString: $0) } ?? "the page"
                p.page?.report(error: "Could not load \(uri).")
            }
            return 0
        }
        g_signal_connect_data(view, "load-failed",
                              unsafeBitCast(onLoadFailed, to: UnsafeMutableRawPointer.self), ptr, nil, 0)

        // notify:: fires per property; all three read the same getters.
        let onNotify: @convention(c) (NativeView, UnsafeMutableRawPointer, UnsafeMutableRawPointer) -> Void = { webView, _, userData in
            MainActor.assumeIsolated {
                guard let page = proxy(from: userData).page else { return }
                refresh(webView, into: page)
            }
        }
        for property in ["notify::title", "notify::uri", "notify::estimated-load-progress"] {
            g_signal_connect_data(view, property,
                                  unsafeBitCast(onNotify, to: UnsafeMutableRawPointer.self), ptr, nil, 0)
        }

        let onMessage: @convention(c) (NativeView, UnsafeMutableRawPointer, UnsafeMutableRawPointer) -> Void = { _, result, userData in
            MainActor.assumeIsolated {
                guard let page = proxy(from: userData).page,
                      let value = webkit_javascript_result_get_js_value(result),
                      let text = jsc_value_to_string(value) else { return }
                defer { g_free(text) }
                page.deliver(message: String(cString: text))
            }
        }
        g_signal_connect_data(manager, "script-message-received::omni",
                              unsafeBitCast(onMessage, to: UnsafeMutableRawPointer.self), ptr, nil, 0)
    }
}

/// Reads everything observable at once: WebKitGTK reports through property
/// notifications, and pulling all of them is cheaper than one handler each.
@MainActor
private func refresh(_ view: NativeView, into page: WebPage) {
    page.report(title: webkit_web_view_get_title(view).map { String(cString: $0) } ?? "")
    page.report(url: webkit_web_view_get_uri(view).flatMap { URL(string: String(cString: $0)) })
    page.report(progress: webkit_web_view_get_estimated_load_progress(view))
    page.report(canGoBack: webkit_web_view_can_go_back(view) != 0)
    page.report(canGoForward: webkit_web_view_can_go_forward(view) != 0)
}
#endif
