import Foundation

#if os(macOS) || os(iOS)
import WebKit
#endif

// The cookies a web view holds. A sign-in run in a web view ends with its
// session in a cookie, httpOnly so the page's own script cannot read it; the
// app can, from here, and carry it on with its own requests.
//
// Apple: WKWebsiteDataStore.default(), the store every WebView here uses.
// Linux (WebKitGTK's cookie manager), Windows (WebView2's CookieManager) and
// Android (CookieManager) are not written yet: `isSupported` is false there and
// both calls do nothing.

public struct WebCookie: Sendable, Equatable {
    public let name: String
    public let value: String
    public let domain: String
    public let path: String
    public let expires: Date?
    public let isSecure: Bool
    public let isHTTPOnly: Bool
}

public enum WebCookies {
    public static var isSupported: Bool {
        #if os(macOS) || os(iOS)
        return true
        #else
        return false
        #endif
    }

    /// The cookies the web views hold for `host` and its parents.
    @MainActor public static func all(for host: String) async -> [WebCookie] {
        #if os(macOS) || os(iOS)
        let host = host.lowercased()
        let cookies = await WKWebsiteDataStore.default().httpCookieStore.allCookies()
        return cookies.compactMap { cookie in
            let domain = cookie.domain.hasPrefix(".") ? String(cookie.domain.dropFirst()) : cookie.domain
            guard host == domain.lowercased() || host.hasSuffix("." + domain.lowercased()) else { return nil }
            return WebCookie(name: cookie.name, value: cookie.value, domain: domain, path: cookie.path,
                             expires: cookie.expiresDate, isSecure: cookie.isSecure, isHTTPOnly: cookie.isHTTPOnly)
        }
        #else
        return []
        #endif
    }

    /// Forgets every cookie the web views hold: a sign-out, or a sign-in that
    /// should start clean.
    @MainActor public static func removeAll() async {
        #if os(macOS) || os(iOS)
        let store = WKWebsiteDataStore.default()
        await store.removeData(ofTypes: [WKWebsiteDataTypeCookies], modifiedSince: .distantPast)
        #endif
    }
}
