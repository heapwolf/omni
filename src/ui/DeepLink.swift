// A cold launch delivers the URL before the first render, so it is held.

import Foundation

@MainActor
public enum DeepLink {
    private static var handler: ((URL) -> Void)?
    private static var pending: URL?

    /// Safe before the app has rendered. A link that finishes an open
    /// WebAuthentication goes there, not to the app.
    public static func receive(_ url: URL) {
        if WebAuthentication.take(url) { return }
        if let handler {
            handler(url)
        } else {
            pending = url
        }
    }

    /// Installed after the first render. Delivers anything held.
    static func install(_ handler: ((URL) -> Void)?) {
        self.handler = handler
        if let handler, let held = pending {
            pending = nil
            handler(held)
        }
    }

    /// For tests: this is process state.
    static func reset() {
        handler = nil
        pending = nil
    }

    /// Linux and Windows pass the link in argv; there is no callback.
    static func launchURL(in arguments: [String]) -> URL? {
        for argument in arguments.dropFirst() {
            guard let url = URL(string: argument), let scheme = url.scheme, !scheme.isEmpty,
                  argument.contains(":") else { continue }
            return url
        }
        return nil
    }
}

#if os(Android)
/// Called from OmniEventBridge.deliverIntent.
@_cdecl("omni_swift_deep_link")
public func omni_swift_deep_link(_ url: UnsafePointer<CChar>?) {
    guard let url else { return }
    let text = String(cString: url)
    MainActor.assumeIsolated {
        guard let parsed = URL(string: text) else { return }
        DeepLink.receive(parsed)
    }
}
#endif
