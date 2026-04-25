// WebView2.h ships with the WebView2 SDK, not the Windows SDK.
#pragma once
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

/// 1 when built against the SDK and the Evergreen runtime is installed.
int omni_win_web_available(void);

/// Creates the host window and starts asynchronous creation. Returns
/// immediately; commands issued before the controller arrives are queued.
void* omni_win_create_webview(void* parent_hwnd, int x, int y, int w, int h);

void omni_win_web_load(void* hwnd, const char* url);
void omni_win_web_load_html(void* hwnd, const char* html);
void omni_win_web_go_back(void* hwnd);
void omni_win_web_go_forward(void* hwnd);
void omni_win_web_reload(void* hwnd);
void omni_win_web_stop(void* hwnd);
void omni_win_web_evaluate(void* hwnd, const char* source);
/// Matches the host window to its parent's client area.
void omni_win_web_set_bounds(void* hwnd, int x, int y, int w, int h);
/// Releases the controller. WebView2 keeps a browser process per controller.
void omni_win_web_destroy(void* hwnd);

#ifdef __cplusplus
}
#endif
