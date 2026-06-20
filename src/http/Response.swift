
import Foundation

public final class Response: @unchecked Sendable {
    public let status: Int
    public let statusText: String
    public let headers: Headers
    /// The final URL, after any redirects were followed.
    public let url: URL
    public let redirected: Bool

    private let lock = NSLock()
    private var data: Data
    private var consumed = false

    public init(data: Data = Data(), status: Int = 200, statusText: String? = nil,
                headers: Headers = Headers(), url: URL, redirected: Bool = false) {
        self.data = data
        self.status = status
        self.statusText = statusText ?? Response.defaultStatusText(status)
        self.headers = headers
        self.url = url
        self.redirected = redirected
    }

    /// 200-299. This; not a thrown error; is how a caller learns a request failed.
    public var ok: Bool { (200...299).contains(status) }

    /// Bodies are read once, as in the spec. A second read is a bug, and
    /// returning empty data would hide it.
    public var bodyUsed: Bool {
        lock.lock(); defer { lock.unlock() }
        return consumed
    }

    private func take() throws -> Data {
        lock.lock(); defer { lock.unlock() }
        guard !consumed else { throw FetchError.bodyAlreadyConsumed }
        consumed = true
        return data
    }

    public func bytes() throws -> Data { try take() }

    public func text() throws -> String {
        String(decoding: try take(), as: UTF8.self)
    }

    public func json<T: Decodable>(_ type: T.Type = T.self) throws -> T {
        let body = try take()
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            return try decoder.decode(T.self, from: body)
        } catch let error as DecodingError {
            throw FetchError.invalidArgument(Response.describe(error))
        }
    }

    private static func describe(_ error: DecodingError) -> String {
        let field = { (c: DecodingError.Context) in c.codingPath.map(\.stringValue).joined(separator: ".") }
        switch error {
        case .keyNotFound(let key, let context):
            let parent = field(context)
            return "missing field \(parent.isEmpty ? key.stringValue : "\(parent).\(key.stringValue)")"
        case .typeMismatch(let type, let context): return "field \(field(context)) was not \(type)"
        case .valueNotFound(let type, let context): return "field \(field(context)) was null but \(type) is required"
        case .dataCorrupted(let context):
            let path = field(context)
            return path.isEmpty ? "body was not valid JSON" : "field \(path) was malformed"
        @unknown default: return String(describing: error)
        }
    }

    private static func defaultStatusText(_ status: Int) -> String {
        switch status {
        case 200: return "OK"
        case 201: return "Created"
        case 202: return "Accepted"
        case 204: return "No Content"
        case 301: return "Moved Permanently"
        case 302: return "Found"
        case 304: return "Not Modified"
        case 400: return "Bad Request"
        case 401: return "Unauthorized"
        case 403: return "Forbidden"
        case 404: return "Not Found"
        case 409: return "Conflict"
        case 413: return "Payload Too Large"
        case 415: return "Unsupported Media Type"
        case 422: return "Unprocessable Content"
        case 429: return "Too Many Requests"
        case 500: return "Internal Server Error"
        case 502: return "Bad Gateway"
        case 503: return "Service Unavailable"
        case 504: return "Gateway Timeout"
        default: return ""
        }
    }
}
