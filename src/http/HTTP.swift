
import Foundation

// URLSession is in a separate module off Apple platforms.
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// MARK: - What goes out

public struct HTTPRequest: Sendable {
    public var url: URL
    public var method: String
    /// Ordered, duplicates allowed: Set-Cookie and Vary need both.
    public var headers: [(name: String, value: String)]
    public var body: Data?
    public var timeout: TimeInterval

    public init(url: URL, method: String = "GET",
                headers: [(name: String, value: String)] = [],
                body: Data? = nil, timeout: TimeInterval = 60) {
        self.url = url
        self.method = method
        self.headers = headers
        self.body = body
        self.timeout = timeout
    }
}

// MARK: - What comes back

public struct HTTPResponse: Sendable {
    public let status: Int
    public let headers: [(name: String, value: String)]
    public let body: Data
    /// Where the response came from, after redirects.
    public let url: URL
    public let redirected: Bool

    public init(status: Int, headers: [(name: String, value: String)],
                body: Data, url: URL, redirected: Bool) {
        self.status = status
        self.headers = headers
        self.body = body
        self.url = url
        self.redirected = redirected
    }
}

// Transport failures only; a 404 is a valid HTTPResponse.

public enum HTTPError: Error, Sendable, Equatable {
    case timedOut
    case cancelled
    /// The transport failed. The message is already diagnosed where the
    /// platform allows it; see PlatformDiagnostics.
    case transport(String)
    /// A response arrived but was not HTTP.
    case notHTTP
}

// MARK: - The seam

public protocol HTTPClient: Sendable {
    func send(_ request: HTTPRequest) async throws -> HTTPResponse
}

public final class URLSessionHTTPClient: HTTPClient, @unchecked Sendable {
    private let session: URLSession

    public init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.ephemeral
            // waitsForConnectivity is Apple-only; off-Apple it is read-only, and
            // a request should fail rather than sit waiting for a network.
            #if canImport(Darwin)
            config.waitsForConnectivity = false
            #endif
            self.session = URLSession(configuration: config)
        }
    }

    public func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        try Task.checkCancellation()

        var urlRequest = URLRequest(url: request.url)
        urlRequest.httpMethod = request.method
        urlRequest.httpBody = request.body
        urlRequest.timeoutInterval = request.timeout
        for header in request.headers {
            urlRequest.addValue(header.value, forHTTPHeaderField: header.name)
        }

        do {
            let (data, response) = try await session.data(for: urlRequest)
            guard let http = response as? HTTPURLResponse else { throw HTTPError.notHTTP }

            var headers: [(name: String, value: String)] = []
            for (key, value) in http.allHeaderFields {
                if let name = key as? String, let value = value as? String {
                    headers.append((name: name, value: value))
                }
            }

            let finalURL = http.url ?? request.url
            return HTTPResponse(status: http.statusCode, headers: headers, body: data,
                                url: finalURL, redirected: finalURL != request.url)
        } catch let error as HTTPError {
            throw error
        } catch is CancellationError {
            throw HTTPError.cancelled
        } catch {
            throw PlatformDiagnostics.diagnose(error, url: request.url)
        }
    }
}
