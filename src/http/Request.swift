
import Foundation

public enum RedirectMode: String, Sendable { case follow, error, manual }

public struct RequestInit: Sendable {
    public var method: String
    public var headers: Headers
    public var body: Data?
    public var signal: AbortSignal?
    public var redirect: RedirectMode
    /// Not in the spec, which leaves timeouts to AbortSignal.timeout(). Kept
    /// because a mobile client without a default timeout will eventually hang.
    public var timeout: TimeInterval

    public init(method: String = "GET", headers: Headers = Headers(), body: Data? = nil,
                signal: AbortSignal? = nil, redirect: RedirectMode = .follow,
                timeout: TimeInterval = 30) {
        self.method = method
        self.headers = headers
        self.body = body
        self.signal = signal
        self.redirect = redirect
        self.timeout = timeout
    }

    public static func json<T: Encodable>(_ method: String, _ value: T,
                                          headers: Headers = Headers()) throws -> RequestInit {
        var headers = headers
        if !headers.has("content-type") { headers.set("content-type", "application/json") }
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            return RequestInit(method: method, headers: headers, body: try encoder.encode(value))
        } catch {
            throw FetchError.invalidArgument("Body could not be encoded as JSON: \(error)")
        }
    }
}

public struct Request: Sendable {
    public let url: URL
    public let method: String
    public var headers: Headers
    public let body: Data?
    public let signal: AbortSignal?
    public let redirect: RedirectMode
    public let timeout: TimeInterval

    public init(url: URL, options: RequestInit = RequestInit()) {
        self.url = url
        // Spec normalises a method to uppercase when it is a known one.
        self.method = options.method.uppercased()
        self.headers = options.headers
        self.body = options.body
        self.signal = options.signal
        self.redirect = options.redirect
        self.timeout = options.timeout
    }

    public init(_ url: String, options: RequestInit = RequestInit()) throws {
        guard let parsed = URL(string: url), parsed.scheme != nil else {
            throw FetchError.invalidArgument("Not an absolute URL: \(url.debugDescription)")
        }
        self.init(url: parsed, options: options)
    }
}
