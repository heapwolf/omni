import Foundation
@testable import OmniHTTP

/// The whole test double. One method, because Transport has one method; no
/// URLProtocol subclass, no local server, no ports, no waiting.
final class StubTransport: Transport, @unchecked Sendable {
    private let lock = NSLock()
    private var replies: [Result<Response, any Error>]
    private var recorded: [Request] = []
    /// Called before replying, so a test can abort mid-flight.
    var beforeReply: (@Sendable (Request) -> Void)?

    init(_ replies: [Result<Response, any Error>]) { self.replies = replies }

    convenience init(status: Int, body: String = "", headers: Headers = Headers(),
                     url: String = "https://api.example.com/") {
        self.init([.success(Response(data: Data(body.utf8), status: status, headers: headers,
                                     url: URL(string: url)!))])
    }

    convenience init(failing error: any Error) { self.init([.failure(error)]) }

    var sent: [Request] { lock.lock(); defer { lock.unlock() }; return recorded }
    var lastRequest: Request? { sent.last }
    var callCount: Int { sent.count }

    /// Synchronous on purpose: Swift 6 makes NSLock.unlock unavailable from an
    /// async context, and holding a lock across a suspension is the reason.
    private func record(_ request: Request) -> Result<Response, any Error> {
        lock.lock()
        defer { lock.unlock() }
        recorded.append(request)
        return replies.count > 1 ? replies.removeFirst() : replies[0]
    }

    func send(_ request: Request) async throws -> Response {
        let reply = record(request)

        beforeReply?(request)
        if request.signal?.aborted == true { throw FetchError.aborted }
        return try reply.get()
    }
}
