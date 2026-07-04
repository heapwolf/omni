// Streaming responses: the status and headers as soon as they arrive, then the
// body as it comes, rather than all at once. On top of that, server-sent
// events (the text/event-stream format WHATWG's EventSource reads).
//
// Built on URLSession's data delegate, not URLSession.bytes(for:): the async
// bytes API is Apple-only, and the delegate is what swift-corelibs-foundation
// implements on Android, Linux and Windows too.

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// MARK: - A streaming response

/// What a stream says first, then its body as it arrives. The body ends when
/// the server closes it, and throws if the connection fails; cancelling the
/// task iterating it closes the connection.
public struct StreamingResponse: Sendable {
    public let status: Int
    public let headers: Headers
    public let url: URL
    public let body: AsyncThrowingStream<Data, any Error>

    public init(status: Int, headers: Headers, url: URL, body: AsyncThrowingStream<Data, any Error>) {
        self.status = status
        self.headers = headers
        self.url = url
        self.body = body
    }

    public var ok: Bool { (200...299).contains(status) }
}

/// A Transport that can also stream. The default one does; a test double can.
public protocol StreamingTransport: Transport {
    func stream(_ request: Request) async throws -> StreamingResponse
}

public let defaultStreamingTransport: any StreamingTransport = HTTPClientTransport()

/// fetch(), but the body arrives as it comes. A stream has no timeout of its
/// own: `options.timeout` is how long to wait for the response to begin.
public func fetchStream(_ url: String, _ options: RequestInit = RequestInit(),
                        using transport: (any StreamingTransport)? = nil) async throws -> StreamingResponse {
    try await (transport ?? defaultStreamingTransport).stream(try Request(url, options: options))
}

extension HTTPClientTransport: StreamingTransport {
    public func stream(_ request: Request) async throws -> StreamingResponse {
        if request.signal?.aborted == true { throw FetchError.aborted }
        do {
            return try await URLSessionStreamer.stream(request)
        } catch let error as HTTPError {
            switch error {
            case .timedOut: throw FetchError.timedOut
            case .cancelled: throw FetchError.aborted
            case .notHTTP: throw FetchError.network("Response was not HTTP")
            case .transport(let message): throw FetchError.network(message)
            }
        } catch is CancellationError {
            throw FetchError.aborted
        }
    }
}

/// One URLSession and data task per stream, driven by its delegate.
enum URLSessionStreamer {
    static func stream(_ request: Request) async throws -> StreamingResponse {
        let delegate = StreamDelegate()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = request.timeout
        // A stream is quiet for as long as it likes once it has started.
        configuration.timeoutIntervalForResource = 7 * 24 * 3600
        let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)

        var urlRequest = URLRequest(url: request.url)
        urlRequest.httpMethod = request.method
        urlRequest.httpBody = request.body
        for (name, value) in request.headers.entries { urlRequest.addValue(value, forHTTPHeaderField: name) }

        let task = session.dataTask(with: urlRequest)
        let body = AsyncThrowingStream<Data, any Error> { continuation in
            delegate.attach(continuation)
            continuation.onTermination = { _ in
                task.cancel()
                session.finishTasksAndInvalidate()
            }
        }
        request.signal?.onAbort { task.cancel() }

        let head: HTTPURLResponse = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                delegate.waitForHead(continuation)
                task.resume()
            }
        } onCancel: {
            task.cancel()
        }

        var headers = Headers()
        for (key, value) in head.allHeaderFields {
            if let name = key as? String, let value = value as? String { headers.append(name, value) }
        }
        return StreamingResponse(status: head.statusCode, headers: headers, url: head.url ?? request.url, body: body)
    }
}

/// The data task's delegate: the head once, then each chunk, then the end.
/// Its callbacks arrive on the session's queue; the lock makes it safe.
final class StreamDelegate: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var head: CheckedContinuation<HTTPURLResponse, any Error>?
    private var body: AsyncThrowingStream<Data, any Error>.Continuation?
    /// Chunks that came before the body was attached.
    private var early: [Data] = []

    func attach(_ continuation: AsyncThrowingStream<Data, any Error>.Continuation) {
        let pending = lock.withLock { () -> [Data] in
            body = continuation
            defer { early = [] }
            return early
        }
        pending.forEach { continuation.yield($0) }
    }

    func waitForHead(_ continuation: CheckedContinuation<HTTPURLResponse, any Error>) {
        lock.withLock { head = continuation }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping @Sendable (URLSession.ResponseDisposition) -> Void) {
        let waiting = lock.withLock { () -> CheckedContinuation<HTTPURLResponse, any Error>? in
            defer { head = nil }
            return head
        }
        if let http = response as? HTTPURLResponse {
            waiting?.resume(returning: http)
            completionHandler(.allow)
        } else {
            waiting?.resume(throwing: HTTPError.notHTTP)
            completionHandler(.cancel)
        }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        let continuation = lock.withLock { () -> AsyncThrowingStream<Data, any Error>.Continuation? in
            if body == nil { early.append(data) }
            return body
        }
        continuation?.yield(data)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        let (waiting, continuation) = lock.withLock { () -> (CheckedContinuation<HTTPURLResponse, any Error>?, AsyncThrowingStream<Data, any Error>.Continuation?) in
            defer { head = nil }
            return (head, body)
        }
        let failure: (any Error)? = error.map { error in
            (error as? URLError)?.code == .cancelled ? HTTPError.cancelled
                : (error as? URLError)?.code == .timedOut ? HTTPError.timedOut
                : PlatformDiagnostics.diagnose(error, url: task.originalRequest?.url ?? URL(string: "about:blank")!)
        }
        if let waiting {
            waiting.resume(throwing: failure ?? HTTPError.notHTTP)
        }
        if let failure { continuation?.finish(throwing: failure) } else { continuation?.finish() }
        session.finishTasksAndInvalidate()
    }
}

// MARK: - Server-sent events

/// One event of a text/event-stream: its type ("message" unless named), its
/// data (lines joined with newlines), and its id if it had one.
public struct ServerSentEvent: Sendable, Equatable {
    public var event: String
    public var data: String
    public var id: String?

    public init(event: String = "message", data: String, id: String? = nil) {
        self.event = event
        self.data = data
        self.id = id
    }
}

/// The text/event-stream format, fed in whatever chunks the network gives:
/// a line may end in a chunk after it began, and a character's bytes may be
/// split. https://html.spec.whatwg.org/multipage/server-sent-events.html
public struct ServerSentEventParser: Sendable {
    private var pending: [UInt8] = []
    private var event = ""
    private var data: [String] = []
    private var id: String?
    private var sawCarriageReturn = false

    public init() {}

    /// The events `chunk` completes.
    public mutating func feed(_ chunk: Data) -> [ServerSentEvent] {
        var events: [ServerSentEvent] = []
        for byte in chunk {
            // \r\n, \r and \n all end a line; \r\n is one ending, not two.
            if sawCarriageReturn {
                sawCarriageReturn = false
                if byte == 0x0A { continue }
            }
            if byte == 0x0A || byte == 0x0D {
                sawCarriageReturn = byte == 0x0D
                if let event = line(String(decoding: pending, as: UTF8.self)) { events.append(event) }
                pending.removeAll(keepingCapacity: true)
            } else {
                pending.append(byte)
            }
        }
        return events
    }

    private mutating func line(_ line: String) -> ServerSentEvent? {
        if line.isEmpty { return dispatch() }
        if line.hasPrefix(":") { return nil }
        let field: Substring
        var value: Substring
        if let colon = line.firstIndex(of: ":") {
            field = line[..<colon]
            value = line[line.index(after: colon)...]
            if value.hasPrefix(" ") { value = value.dropFirst() }
        } else {
            field = Substring(line)
            value = ""
        }
        switch field {
        case "event": event = String(value)
        case "data": data.append(String(value))
        case "id" where !value.contains("\0"): id = String(value)
        default: break
        }
        return nil
    }

    /// A blank line: the event so far, if it had any data.
    private mutating func dispatch() -> ServerSentEvent? {
        defer {
            event = ""
            data = []
        }
        guard !data.isEmpty else { return nil }
        return ServerSentEvent(event: event.isEmpty ? "message" : event, data: data.joined(separator: "\n"), id: id)
    }
}

/// Server-sent events from `url`, as they arrive. Throws before any event if
/// the response is not a 2xx; `onOpen` hears the status first. Reconnecting is
/// the caller's: when the sequence ends, the stream has closed.
public func serverSentEvents(_ url: String, _ options: RequestInit = RequestInit(),
                             using transport: (any StreamingTransport)? = nil) async throws
    -> (response: StreamingResponse, events: AsyncThrowingStream<ServerSentEvent, any Error>) {
    var options = options
    if !options.headers.has("accept") { options.headers.set("accept", "text/event-stream") }
    let response = try await fetchStream(url, options, using: transport)
    let events = AsyncThrowingStream<ServerSentEvent, any Error> { continuation in
        let task = Task {
            var parser = ServerSentEventParser()
            do {
                for try await chunk in response.body {
                    for event in parser.feed(chunk) { continuation.yield(event) }
                }
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }
        continuation.onTermination = { _ in task.cancel() }
    }
    return (response, events)
}
