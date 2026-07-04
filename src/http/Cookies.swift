import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// Cookies, kept by the app rather than the platform. URLSession, curl and
// WinHTTP each keep (or don't keep) cookies their own way, and none of them can
// be handed a cookie from somewhere else, such as a web view's sign-in. A
// CookieJar is the one store: CookieTransport sends what it holds and keeps
// what servers set, on every platform alike, and an app can save it, restore
// it, add to it and clear it.

/// One cookie, as much of it as a client needs.
public struct Cookie: Sendable, Equatable, Codable {
    public var name: String
    public var value: String
    /// The host it is sent to; also its subdomains when `includesSubdomains`.
    public var domain: String
    public var includesSubdomains: Bool
    public var path: String
    public var expires: Date?
    public var secure: Bool

    public init(name: String, value: String, domain: String, includesSubdomains: Bool = false,
                path: String = "/", expires: Date? = nil, secure: Bool = false) {
        self.name = name
        self.value = value
        self.domain = domain.lowercased()
        self.includesSubdomains = includesSubdomains
        self.path = path
        self.expires = expires
        self.secure = secure
    }

    func isExpired(at now: Date) -> Bool { expires.map { $0 <= now } ?? false }

    func matches(_ url: URL, at now: Date) -> Bool {
        guard !isExpired(at: now), let host = url.host?.lowercased() else { return false }
        if secure && url.scheme?.lowercased() != "https" { return false }
        let hostMatches = host == domain || (includesSubdomains && host.hasSuffix("." + domain))
        let requestPath = url.path.isEmpty ? "/" : url.path
        let pathMatches = requestPath == path || requestPath.hasPrefix(path.hasSuffix("/") ? path : path + "/")
        return hostMatches && pathMatches
    }

    /// One Set-Cookie value, from `url`'s response (RFC 6265, the parts that
    /// matter to a client). nil when it is not a cookie.
    public init?(setCookie header: String, from url: URL, now: Date = Date()) {
        let parts = header.split(separator: ";", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        guard let pair = parts.first, let equals = pair.firstIndex(of: "="), let host = url.host else { return nil }
        let name = String(pair[..<equals]).trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return nil }
        var cookie = Cookie(name: name, value: String(pair[pair.index(after: equals)...]), domain: host)

        // The default path: the request's directory.
        let requestPath = url.path.isEmpty ? "/" : url.path
        cookie.path = requestPath.contains("/") && requestPath != "/"
            ? String(requestPath[..<requestPath.lastIndex(of: "/")!]).nonEmpty ?? "/"
            : "/"

        for attribute in parts.dropFirst() {
            let pieces = attribute.split(separator: "=", maxSplits: 1).map { String($0).trimmingCharacters(in: .whitespaces) }
            let key = pieces[0].lowercased()
            let value = pieces.count > 1 ? pieces[1] : ""
            switch key {
            case "domain" where !value.isEmpty:
                cookie.domain = (value.hasPrefix(".") ? String(value.dropFirst()) : value).lowercased()
                cookie.includesSubdomains = true
            case "path" where value.hasPrefix("/"):
                cookie.path = value
            case "max-age":
                if let seconds = Double(value) { cookie.expires = now.addingTimeInterval(seconds) }
            case "expires" where cookie.expires == nil:
                cookie.expires = Self.httpDate(value)
            case "secure":
                cookie.secure = true
            default:
                break
            }
        }
        self = cookie
    }

    private static func httpDate(_ text: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        for format in ["EEE, dd MMM yyyy HH:mm:ss zzz", "EEEE, dd-MMM-yy HH:mm:ss zzz", "EEE MMM d HH:mm:ss yyyy"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: text) { return date }
        }
        return nil
    }

    /// Set-Cookie values, from headers that may have folded several into one
    /// (Apple's do, comma-joined). A comma splits two cookies only when what
    /// follows it is `name=`, so an Expires date's comma does not.
    public static func split(_ headers: [String]) -> [String] {
        headers.flatMap { header -> [String] in
            var results: [String] = []
            var current = ""
            var index = header.startIndex
            while index < header.endIndex {
                let character = header[index]
                if character == ",", startsCookie(header[header.index(after: index)...]) {
                    results.append(current.trimmingCharacters(in: .whitespaces))
                    current = ""
                } else {
                    current.append(character)
                }
                index = header.index(after: index)
            }
            if !current.trimmingCharacters(in: .whitespaces).isEmpty {
                results.append(current.trimmingCharacters(in: .whitespaces))
            }
            return results
        }
    }

    private static func startsCookie(_ rest: Substring) -> Bool {
        let trimmed = rest.drop { $0 == " " }
        guard let equals = trimmed.firstIndex(of: "=") else { return false }
        let name = trimmed[..<equals]
        return !name.isEmpty && !name.contains(where: { $0 == ";" || $0 == "," || $0 == " " })
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}

/// The cookies an app holds. Thread-safe; share one per signed-in account.
public final class CookieJar: @unchecked Sendable {
    private let lock = NSLock()
    private var cookies: [Cookie] = []
    /// Called after every change, with everything held: where an app saves it.
    public var onChange: (@Sendable ([Cookie]) -> Void)?

    public init(_ cookies: [Cookie] = []) {
        self.cookies = cookies
    }

    public var all: [Cookie] { lock.withLock { cookies } }

    /// Adds, or replaces the one with the same name, domain and path. An
    /// expired one removes it, as a server deletes a cookie.
    public func set(_ cookie: Cookie, now: Date = Date()) {
        let snapshot = lock.withLock { () -> [Cookie] in
            cookies.removeAll { $0.name == cookie.name && $0.domain == cookie.domain && $0.path == cookie.path }
            if !cookie.isExpired(at: now) { cookies.append(cookie) }
            return cookies
        }
        onChange?(snapshot)
    }

    /// What servers set on `url`'s response.
    public func store(setCookies headers: [String], from url: URL, now: Date = Date()) {
        for header in Cookie.split(headers) {
            if let cookie = Cookie(setCookie: header, from: url, now: now) { set(cookie, now: now) }
        }
    }

    /// The Cookie header for `url`, or nil with nothing to send. Longer paths
    /// first, as RFC 6265 orders them.
    public func header(for url: URL, now: Date = Date()) -> String? {
        let matching = lock.withLock { cookies.filter { $0.matches(url, at: now) } }
            .sorted { $0.path.count > $1.path.count }
        guard !matching.isEmpty else { return nil }
        return matching.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
    }

    public func value(_ name: String, for url: URL, now: Date = Date()) -> String? {
        lock.withLock { cookies.first { $0.name == name && $0.matches(url, at: now) }?.value }
    }

    public func removeAll() {
        lock.withLock { cookies.removeAll() }
        onChange?([])
    }
}

/// A transport that sends `jar`'s cookies and keeps what the server sets. The
/// platform's own cookie handling is switched off underneath, so the jar is
/// the only store and nothing is sent that the app did not choose.
public struct CookieTransport: Transport {
    public let jar: CookieJar
    private let base: any Transport

    public init(jar: CookieJar, base: (any Transport)? = nil) {
        self.jar = jar
        self.base = base ?? Self.cookieless
    }

    public func send(_ request: Request) async throws -> Response {
        var request = request
        if let header = jar.header(for: request.url) { request.headers.set("cookie", header) }
        let response = try await base.send(request)
        jar.store(setCookies: response.headers.getSetCookie(), from: response.url)
        return response
    }

    /// The default transport, with the session's cookie store taken away.
    private static let cookieless: any Transport = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        #if canImport(Darwin)
        configuration.waitsForConnectivity = false
        #endif
        return HTTPClientTransport(client: URLSessionHTTPClient(session: URLSession(configuration: configuration)))
    }()
}
