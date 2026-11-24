// src/ui/components/windows/WebView+Windows.swift
//
// WebView2 (src/bridge/windows/CWinWebView.cxx), hosted as a control: its
// host window is made once the view is in a window, placed by the layout,
// and the page's commands wait until then.

#if os(Windows)
import Foundation
import WinSDK
import CWindows

@MainActor
final class WinWebHost: WinControl {
    weak var page: WebPage?
    var pending: [WebPage.Command] = []
    var lastRequested: URL?
    var reportedUnavailable = false

    static var byHost: [HWND: WinWebHost] = [:]

    override func makeWindow(parent: HWND) -> HWND? {
        guard let raw = omni_win_create_webview(UnsafeMutableRawPointer(parent), 0, 0, 1, 1) else { return nil }
        let host = raw.assumingMemoryBound(to: HWND__.self)
        WinWebHost.byHost[host] = self
        return host
    }

    override var wantsSubclass: Bool { false }

    override func created() {
        run(pending)
        pending.removeAll()
    }

    func run(_ commands: [WebPage.Command]) {
        guard let hwnd else {
            pending += commands
            return
        }
        let view = UnsafeMutableRawPointer(hwnd)
        for command in commands {
            switch command {
            case .load(let url): omni_win_web_load(view, url.absoluteString)
            // NavigateToString takes no base URL: WebView2 gives the content an
            // opaque origin and offers no way to name one.
            case .loadHTML(let html, _): omni_win_web_load_html(view, html)
            case .goBack: omni_win_web_go_back(view)
            case .goForward: omni_win_web_go_forward(view)
            case .reload: omni_win_web_reload(view)
            case .stop: omni_win_web_stop(view)
            case .evaluate(let source): omni_win_web_evaluate(view, source)
            }
        }
    }

    override func sized() {
        guard let hwnd, let view, let surface else { return }
        let f = contentRect(in: view.windowFrame)
        let s = surface.scale
        omni_win_web_set_bounds(UnsafeMutableRawPointer(hwnd), Int32((f.x * s).rounded()), Int32((f.y * s).rounded()),
                                Int32((f.width * s).rounded()), Int32((f.height * s).rounded()))
    }

    override func destroy() {
        guard let hwnd else { return }
        WinWebHost.byHost[hwnd] = nil
        // WebView2 keeps a browser process per controller: let it go.
        omni_win_web_destroy(UnsafeMutableRawPointer(hwnd))
        super.destroy()
    }
}

extension WebView {
    @MainActor public func makeNative() -> NativeView {
        let native = WinView.make("WebView", layout: .leaf)
        let v = winView(native)
        v.hexpand = true
        v.vexpand = true
        v.measure = { _ in WinSize(width: 100, height: 100) }
        v.control = WinWebHost()
        return native
    }

    @MainActor public func updateNative(_ view: NativeView) {
        guard let host = winView(view).control as? WinWebHost else { return }
        // Before the guard, never after: see WebPage.observe().
        page?.observe()
        host.page = page

        if omni_win_web_available() == 0, !host.reportedUnavailable {
            host.reportedUnavailable = true
            page?.report(error: """
                No web engine. WebView2 needs its runtime (Windows 11 has it) and an \
                app built with its SDK.
                """)
        }

        guard let page else {
            if let url = staticURL, host.lastRequested != url {
                host.lastRequested = url
                host.run([.load(url)])
            }
            return
        }
        host.run(page.drainCommands())
    }
}

// WebView2's handlers are raised on the thread owning the message loop, which
// is the thread the engine renders on.

/// By the host window's address: a pointer isn't Sendable, its value is.
@MainActor private func page(for address: UInt) -> WebPage? {
    guard let raw = UnsafeMutableRawPointer(bitPattern: address) else { return nil }
    return WinWebHost.byHost[raw.assumingMemoryBound(to: HWND__.self)]?.page
}

/// Mirrors the constants in CWinWebView.cxx.
private enum WindowsWebEvent: Int32 {
    case title = 0, started = 1, finished = 2, error = 3, message = 4
}

@_cdecl("omni_swift_win_web_policy")
public func omni_swift_win_web_policy(_ hwnd: UnsafeMutableRawPointer,
                                      _ url: UnsafePointer<CChar>?) -> Int32 {
    guard let url else { return 0 }
    let text = String(cString: url)
    let address = UInt(bitPattern: hwnd)
    return MainActor.assumeIsolated {
        guard let page = page(for: address), let parsed = URL(string: text) else { return 0 }
        return page.policy(for: parsed) == .cancel ? 1 : 0
    }
}

@_cdecl("omni_swift_win_web_event")
public func omni_swift_win_web_event(_ hwnd: UnsafeMutableRawPointer,
                                     _ kind: Int32,
                                     _ value: UnsafePointer<CChar>?) {
    let text = value.map { String(cString: $0) } ?? ""
    let address = UInt(bitPattern: hwnd)
    MainActor.assumeIsolated {
        guard let page = page(for: address), let kind = WindowsWebEvent(rawValue: kind) else { return }
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
    let address = UInt(bitPattern: hwnd)
    MainActor.assumeIsolated {
        guard let page = page(for: address) else { return }
        page.report(progress: progress)
        page.report(canGoBack: canGoBack != 0)
        page.report(canGoForward: canGoForward != 0)
    }
}
#endif
