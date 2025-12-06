// Apple: WKWebView. Coordinator per view, kept in a registry keyed on the view.

#if os(macOS) || os(iOS)
import Foundation
import WebKit

#if os(macOS)
import AppKit
#else
import UIKit
#endif

@MainActor private var appleWebRegistry: [ObjectIdentifier: AppleWebCoordinator] = [:]

extension WebView {
    @MainActor public func makeNative() -> NativeView {
        let configuration = WKWebViewConfiguration()

        // window.omni.postMessage, over WebKit's own channel.
        let shim = WKUserScript(
            source: """
                window.omni = window.omni || {};
                window.omni.postMessage = function (value) {
                    window.webkit.messageHandlers.omni.postMessage(String(value));
                };
                """,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false)
        configuration.userContentController.addUserScript(shim)

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.translatesAutoresizingMaskIntoConstraints = false
        // Fills what it's given, as SwiftUI's does: it has no size of its own,
        // and at the default hugging a ZStack placed it at zero.
        webView.setContentHuggingPriority(.init(rawValue: 1), for: .horizontal)
        webView.setContentHuggingPriority(.init(rawValue: 1), for: .vertical)

        let coordinator = AppleWebCoordinator(webView)
        appleWebRegistry[ObjectIdentifier(webView)] = coordinator
        webView.navigationDelegate = coordinator

        // Weak: WKUserContentController retains its handler, and the coordinator owns
        // the web view.
        configuration.userContentController.add(WeakScriptMessageProxy(coordinator), name: "omni")

        return webView
    }

    @MainActor public func unmountNative(_ view: NativeView) {
        guard let webView = view as? WKWebView else { return }
        // Observers first: KVO holds the coordinator unowned.
        appleWebRegistry[ObjectIdentifier(webView)]?.stopObserving()
        // Stops loading and releases the message handler.
        webView.stopLoading()
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "omni")
        appleWebRegistry.removeValue(forKey: ObjectIdentifier(webView))
    }

    @MainActor public func updateNative(_ view: NativeView) {
        // Before the guard, never after: see WebPage.observe().
        page?.observe()

        guard let webView = view as? WKWebView,
              let coordinator = appleWebRegistry[ObjectIdentifier(webView)] else { return }

        coordinator.page = page

        if let page {
            for command in page.drainCommands() {
                switch command {
                case .load(let url):
                    webView.load(URLRequest(url: url))
                case .loadHTML(let html, let baseURL):
                    webView.loadHTMLString(html, baseURL: baseURL)
                case .goBack:    webView.goBack()
                case .goForward: webView.goForward()
                case .reload:    webView.reload()
                case .stop:      webView.stopLoading()
                case .evaluate(let source):
                    webView.evaluateJavaScript(source, completionHandler: nil)
                }
            }
            coordinator.syncObservedState()
        } else if let url = staticURL, coordinator.backing.lastRequested != url {
            coordinator.backing.lastRequested = url
            webView.load(URLRequest(url: url))
        }
    }
}

/// Bridges WebKit's delegates and KVO to WebPage. @MainActor on the class:
/// WebKit's delegates and these KVO callbacks are all main-thread.
@MainActor
final class AppleWebCoordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
    let backing = WebViewBacking()
    weak var page: WebPage?
    private let webView: WKWebView
    private var isObserving = false

    /// String keys: a key-path literal is only Sendable at its own call site.
    private static let observedKeys = ["title", "estimatedProgress", "canGoBack", "canGoForward", "URL"]

    init(_ webView: WKWebView) {
        self.webView = webView
        super.init()
        for key in Self.observedKeys {
            webView.addObserver(self, forKeyPath: key, options: [.new], context: nil)
        }
        isObserving = true
    }

    /// Any change pulls all five; the reports are equality-guarded. nonisolated
    /// because NSObject's method is, and KVO here is delivered on the main thread.
    nonisolated override func observeValue(forKeyPath keyPath: String?, of object: Any?,
                                           change: [NSKeyValueChangeKey: Any]?,
                                           context: UnsafeMutableRawPointer?) {
        MainActor.assumeIsolated { syncObservedState() }
    }

    /// Must run before release: KVO holds the observer unowned.
    func stopObserving() {
        guard isObserving else { return }
        isObserving = false
        for key in Self.observedKeys {
            webView.removeObserver(self, forKeyPath: key)
        }
    }

    /// Pulls everything across once; the observations only fire on change.
    func syncObservedState() {
        guard let page else { return }
        page.report(title: webView.title ?? "")
        page.report(url: webView.url)
        page.report(progress: webView.estimatedProgress)
        page.report(canGoBack: webView.canGoBack)
        page.report(canGoForward: webView.canGoForward)
        page.report(isLoading: webView.isLoading)
    }

    // MARK: - Navigation

    /// Async form: the completion handler's attributes have moved between SDKs.
    func webView(_ webView: WKWebView,
                 decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        guard let url = navigationAction.request.url, let page else { return .allow }
        return page.policy(for: url) == .allow ? .allow : .cancel
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        page?.report(isLoading: true)
        page?.report(error: nil)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        page?.report(isLoading: false)
        page?.report(url: webView.url)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        fail(error)
    }

    func webView(_ webView: WKWebView,
                 didFailProvisionalNavigation navigation: WKNavigation!,
                 withError error: Error) {
        fail(error)
    }

    /// A cancelled navigation is decidePolicy returning .cancel, not a failure.
    private func fail(_ error: Error) {
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled { return }
        page?.report(isLoading: false)
        page?.report(error: error.localizedDescription)
    }

    // MARK: - Messages

    func userContentController(_ controller: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        page?.deliver(message: String(describing: message.body))
    }
}

/// Breaks the controller → handler → web view → coordinator cycle.
@MainActor
private final class WeakScriptMessageProxy: NSObject, WKScriptMessageHandler {
    private weak var target: AppleWebCoordinator?
    init(_ target: AppleWebCoordinator) { self.target = target }

    func userContentController(_ controller: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        target?.userContentController(controller, didReceive: message)
    }
}
#endif
