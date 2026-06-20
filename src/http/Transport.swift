
import Foundation

public protocol Transport: Sendable {
    func send(_ request: Request) async throws -> Response
}

/// The default transport: WHATWG semantics over the platform's HTTP.
public struct HTTPClientTransport: Transport {
    private let client: any HTTPClient

    public init(client: any HTTPClient = URLSessionHTTPClient()) {
        self.client = client
    }

    public func send(_ request: Request) async throws -> Response {
        if request.signal?.aborted == true { throw FetchError.aborted }

        let platformRequest = HTTPRequest(
            url: request.url,
            method: request.method,
            headers: request.headers.entries.map { (name: $0.0, value: $0.1) },
            body: request.body,
            timeout: request.timeout)

        // Bridge AbortSignal onto Task cancellation, which is what the layer
        // below understands.
        let task = Task { try await client.send(platformRequest) }
        request.signal?.onAbort { task.cancel() }

        let platformResponse: HTTPResponse
        do {
            platformResponse = try await task.value
        } catch let error as HTTPError {
            throw Self.fetchError(from: error)
        } catch is CancellationError {
            throw FetchError.aborted
        }

        // Redirect policy is a Fetch decision, made here rather than below.
        if platformResponse.redirected, request.redirect == .error {
            throw FetchError.redirectNotAllowed(to: platformResponse.url.absoluteString)
        }

        var headers = Headers()
        for header in platformResponse.headers { headers.append(header.name, header.value) }

        return Response(data: platformResponse.body, status: platformResponse.status,
                        headers: headers, url: platformResponse.url,
                        redirected: platformResponse.redirected)
    }

    private static func fetchError(from error: HTTPError) -> FetchError {
        switch error {
        case .timedOut: return .timedOut
        case .cancelled: return .aborted
        case .notHTTP: return .network("Response was not HTTP")
        case .transport(let message): return .network(message)
        }
    }
}
