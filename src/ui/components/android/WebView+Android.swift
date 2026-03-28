
#if os(Android)
import Foundation
import CAndroid

@MainActor private var androidWebRegistry: [UnsafeMutableRawPointer: WebEventHandler] = [:]

/// Carries the page across the JNI boundary. @MainActor for the same reason
/// every EventHandler is: invoked from Java on the Android UI thread.
@MainActor
final class WebEventHandler {
    /// Weak: the screen owns the page, and the registry outlives any one render.
    weak var page: WebPage?
    let backing = WebViewBacking()
    init() {}
}

/// Mirrors the constants in OmniWebView.java.
private enum WebEventKind: Int32 {
    case title = 0, started = 1, finished = 2, error = 3, message = 4
}

extension WebView {
    @MainActor public func makeNative() -> NativeView {
        let env = OmniAndroid.env
        let view = OmniAndroid.createView(env, "com/omni/OmniWebView")

        // Claims both axes.
        AndroidExpansion.claim(view, horizontal: true, vertical: true)

        let handler = WebEventHandler()
        androidWebRegistry[view] = handler
        omni_jni_web_attach(env, view, UnsafeMutableRawPointer(Unmanaged.passUnretained(handler).toOpaque()))
        return view
    }

    @MainActor public func unmountNative(_ view: NativeView) {
        // Null first: Java checks this pointer against zero on every callback.
        omni_jni_web_attach(OmniAndroid.env, view, nil)
        omni_jni_call_void_method(OmniAndroid.env, view, "stopLoading")
        androidWebRegistry.removeValue(forKey: view)
    }

    @MainActor public func updateNative(_ view: NativeView) {
        let env = OmniAndroid.env
        // Before the guard: see WebPage.observe().
        page?.observe()
        guard let handler = androidWebRegistry[view] else { return }
        handler.page = page

        guard let page else {
            // The WebView(url:) form: load once, not per render.
            if let url = staticURL, handler.backing.lastRequested != url {
                handler.backing.lastRequested = url
                omni_jni_call_void_method_string(env, view, "loadUrl", url.absoluteString)
            }
            return
        }

        for command in page.drainCommands() {
            switch command {
            case .load(let url):
                omni_jni_call_void_method_string(env, view, "loadUrl", url.absoluteString)
            case .loadHTML(let html, let baseURL):
                if let baseURL {
                    baseURL.absoluteString.withCString { base in
                        omni_jni_web_load_html(env, view, html, base)
                    }
                } else {
                    omni_jni_web_load_html(env, view, html, nil)
                }
            case .goBack:    omni_jni_call_void_method(env, view, "goBack")
            case .goForward: omni_jni_call_void_method(env, view, "goForward")
            case .reload:    omni_jni_call_void_method(env, view, "reload")
            case .stop:      omni_jni_call_void_method(env, view, "stopLoading")
            case .evaluate(let source):
                omni_jni_call_void_method_string(env, view, "evaluate", source)
            }
        }
    }
}

// Declared here, not in Events+Android.swift: the pointer is a
// WebEventHandler, and the generic dispatchers take an EventHandlerString.

@_cdecl("omni_swift_web_policy")
public func omni_swift_web_policy(_ ptr: UnsafeMutableRawPointer,
                                  _ url: UnsafePointer<CChar>?) -> Int32 {
    let handler = Unmanaged<WebEventHandler>.fromOpaque(ptr).takeUnretainedValue()
    guard let url else { return 0 }
    let text = String(cString: url)
    return MainActor.assumeIsolated {
        guard let page = handler.page, let parsed = URL(string: text) else { return 0 }
        // 1 cancels, matching shouldOverrideUrlLoading.
        return page.policy(for: parsed) == .cancel ? 1 : 0
    }
}

@_cdecl("omni_swift_web_event")
public func omni_swift_web_event(_ ptr: UnsafeMutableRawPointer,
                                 _ kind: Int32,
                                 _ value: UnsafePointer<CChar>?) {
    let handler = Unmanaged<WebEventHandler>.fromOpaque(ptr).takeUnretainedValue()
    let text = value.map { String(cString: $0) } ?? ""
    MainActor.assumeIsolated {
        guard let page = handler.page, let kind = WebEventKind(rawValue: kind) else { return }
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

@_cdecl("omni_swift_web_state")
public func omni_swift_web_state(_ ptr: UnsafeMutableRawPointer,
                                 _ progress: Int32,
                                 _ canGoBack: Int32,
                                 _ canGoForward: Int32) {
    let handler = Unmanaged<WebEventHandler>.fromOpaque(ptr).takeUnretainedValue()
    MainActor.assumeIsolated {
        guard let page = handler.page else { return }
        // Android reports 0–100; the page exposes 0–1.
        page.report(progress: Double(progress) / 100.0)
        page.report(canGoBack: canGoBack != 0)
        page.report(canGoForward: canGoForward != 0)
    }
}
#endif
