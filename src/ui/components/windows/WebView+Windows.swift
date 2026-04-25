
#if os(Windows)
import Foundation
import CWindows

@MainActor
private final class WindowsWebRegistry {
    static var pages: [Int: WebPage] = [:]
    static var backings: [Int: WebViewBacking] = [:]
    /// Once per view, not per render.
    static var reportedUnavailable: Set<Int> = []
}

/// Mirrors the constants in CWinWebView.cxx.
private enum WindowsWebEvent: Int32 {
    case title = 0, started = 1, finished = 2, error = 3, message = 4
}

private func key(_ view: NativeView) -> Int { Int(bitPattern: view) }

extension WebView {
    @MainActor public func makeNative() -> NativeView {
        // Sized by the parent on its next layout pass.
        guard let view = omni_win_create_webview(nil, 0, 0, 100, 100) else {
            // CreateWindowExW failed; hand back an empty host.
            return omni_win_create_frame(nil, 100, 100)
        }
        WindowsWebRegistry.backings[key(view)] = WebViewBacking()
        return view
    }

    @MainActor public func updateNative(_ view: NativeView) {
        let handle = key(view)
        // Before the guard, never after: see WebPage.observe().
        page?.observe()
        WindowsWebRegistry.pages[handle] = page
        guard let backing = WindowsWebRegistry.backings[handle] else { return }

        if omni_win_web_available() == 0, !WindowsWebRegistry.reportedUnavailable.contains(handle) {
            WindowsWebRegistry.reportedUnavailable.insert(handle)
            page?.report(error: """
                No web engine on this machine. WebView2 needs the Evergreen \
                runtime, which is a separate install from the app.
                """)
        }

        guard let page else {
            if let url = staticURL, backing.lastRequested != url {
                backing.lastRequested = url
                omni_win_web_load(view, url.absoluteString)
            }
            return
        }

        for command in page.drainCommands() {
            switch command {
            case .load(let url):
                omni_win_web_load(view, url.absoluteString)
            case .loadHTML(let html, _):
                // NavigateToString takes no base URL: WebView2 gives the content an opaque
                // origin and offers no way to name one.
                omni_win_web_load_html(view, html)
            case .goBack:    omni_win_web_go_back(view)
            case .goForward: omni_win_web_go_forward(view)
            case .reload:    omni_win_web_reload(view)
            case .stop:      omni_win_web_stop(view)
            case .evaluate(let source):
                omni_win_web_evaluate(view, source)
            }
        }
    }

    /// WebView2 keeps a browser process per controller; this is why
    /// NativeComponent.unmountNative exists.
    @MainActor public func unmountNative(_ view: NativeView) {
        let handle = key(view)
        WindowsWebRegistry.pages.removeValue(forKey: handle)
        WindowsWebRegistry.backings.removeValue(forKey: handle)
        WindowsWebRegistry.reportedUnavailable.remove(handle)
        omni_win_web_destroy(view)
    }
}

// WebView2's handlers are raised on the thread owning the message loop, which
// is the thread the engine renders on.

@_cdecl("omni_swift_win_web_policy")
public func omni_swift_win_web_policy(_ hwnd: UnsafeMutableRawPointer,
                                      _ url: UnsafePointer<CChar>?) -> Int32 {
    guard let url else { return 0 }
    let text = String(cString: url)
    return MainActor.assumeIsolated {
        guard let page = WindowsWebRegistry.pages[Int(bitPattern: hwnd)],
              let parsed = URL(string: text) else { return 0 }
        return page.policy(for: parsed) == .cancel ? 1 : 0
    }
}

@_cdecl("omni_swift_win_web_event")
public func omni_swift_win_web_event(_ hwnd: UnsafeMutableRawPointer,
                                     _ kind: Int32,
                                     _ value: UnsafePointer<CChar>?) {
    let text = value.map { String(cString: $0) } ?? ""
    MainActor.assumeIsolated {
        guard let page = WindowsWebRegistry.pages[Int(bitPattern: hwnd)],
              let kind = WindowsWebEvent(rawValue: kind) else { return }
        switch kind {
        case .title:
            page.report(title: text)
        case .started:
            page.report(isLoading: true)
            page.report(error: nil)
            page.report(url: URL(string: text))
        case .finished:
            page.report(isLoading: false)
            page.report(url: URL(string: text))
        case .error:
            page.report(isLoading: false)
            page.report(error: text)
        case .message:
            page.deliver(message: text)
        }
    }
}

@_cdecl("omni_swift_win_web_state")
public func omni_swift_win_web_state(_ hwnd: UnsafeMutableRawPointer,
                                     _ progress: Double,
                                     _ canGoBack: Int32,
                                     _ canGoForward: Int32) {
    MainActor.assumeIsolated {
        guard let page = WindowsWebRegistry.pages[Int(bitPattern: hwnd)] else { return }
        page.report(progress: progress)
        page.report(canGoBack: canGoBack != 0)
        page.report(canGoForward: canGoForward != 0)
    }
}
#endif
