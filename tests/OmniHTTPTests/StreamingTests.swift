import XCTest
import Foundation
@testable import OmniHTTP
#if canImport(Network)
import Network
#endif

final class ServerSentEventParserTests: XCTestCase {
    func testAnEventEndsAtABlankLine() {
        var parser = ServerSentEventParser()
        XCTAssertEqual(parser.feed(Data("data: hello\n".utf8)), [])
        XCTAssertEqual(parser.feed(Data("\n".utf8)), [ServerSentEvent(data: "hello")])
    }

    func testFieldsLinesAndComments() {
        var parser = ServerSentEventParser()
        let events = parser.feed(Data(": a comment\nevent: notification_unread_update\nid: 7\ndata: {\"a\":1}\ndata: second\n\n".utf8))
        XCTAssertEqual(events, [ServerSentEvent(event: "notification_unread_update", data: "{\"a\":1}\nsecond", id: "7")])
    }

    func testChunksSplitAnywhereEvenInsideACharacter() {
        let whole = Data("data: ₦1,580\r\n\r\ndata: next\r\n\r\n".utf8)
        var parser = ServerSentEventParser()
        var events: [ServerSentEvent] = []
        for byte in whole { events += parser.feed(Data([byte])) }
        XCTAssertEqual(events, [ServerSentEvent(data: "₦1,580"), ServerSentEvent(data: "next")])
    }

    func testAnEventWithoutDataIsNotDispatched() {
        var parser = ServerSentEventParser()
        XCTAssertEqual(parser.feed(Data("event: ping\n\n".utf8)), [])
        XCTAssertEqual(parser.feed(Data("data:no-space\n\n".utf8)), [ServerSentEvent(data: "no-space")])
    }
}

#if canImport(Network)
/// A real server on a local port: the head, then events a little apart, so
/// the test sees them arrive before the response ends.
final class StreamingTransportTests: XCTestCase {
    func testEventsArriveAsTheyAreSent() async throws {
        let server = try LocalSSEServer(events: ["first", "second", "third"], gap: 0.2)
        defer { server.stop() }
        let port = try await server.start()

        let started = Date()
        let (response, events) = try await serverSentEvents("http://127.0.0.1:\(port)/stream")
        XCTAssertEqual(response.status, 200)
        XCTAssertEqual(response.headers.get("content-type"), "text/event-stream")

        var seen: [(String, TimeInterval)] = []
        for try await event in events { seen.append((event.data, Date().timeIntervalSince(started))) }
        XCTAssertEqual(seen.map(\.0), ["first", "second", "third"])
        XCTAssertLessThan(seen[0].1, seen[2].1 - 0.25, "the first event waited for the last: not streamed")
    }

    func testANon2xxIsReadBeforeAnyEvent() async throws {
        let server = try LocalSSEServer(events: [], gap: 0, status: "401 Unauthorized")
        defer { server.stop() }
        let port = try await server.start()
        let (response, _) = try await serverSentEvents("http://127.0.0.1:\(port)/stream")
        XCTAssertEqual(response.status, 401)
        XCTAssertFalse(response.ok)
    }
}

/// Just enough HTTP/1.1 to serve one event stream per connection.
final class LocalSSEServer: @unchecked Sendable {
    private let listener: NWListener
    private let events: [String]
    private let gap: TimeInterval
    private let status: String
    private let queue = DispatchQueue(label: "sse-server")

    init(events: [String], gap: TimeInterval, status: String = "200 OK") throws {
        self.listener = try NWListener(using: .tcp, on: .any)
        self.events = events
        self.gap = gap
        self.status = status
    }

    func start() async throws -> UInt16 {
        listener.newConnectionHandler = { [weak self] connection in self?.serve(connection) }
        return try await withCheckedThrowingContinuation { continuation in
            listener.stateUpdateHandler = { [listener] state in
                switch state {
                case .ready: continuation.resume(returning: listener.port?.rawValue ?? 0)
                case .failed(let error): continuation.resume(throwing: error)
                default: break
                }
            }
            listener.start(queue: queue)
        }
    }

    func stop() { listener.cancel() }

    private func serve(_ connection: NWConnection) {
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [self] _, _, _, _ in
            let head = "HTTP/1.1 \(status)\r\ncontent-type: text/event-stream\r\ncache-control: no-cache\r\nconnection: close\r\n\r\n"
            connection.send(content: Data(head.utf8), completion: .contentProcessed { _ in })
            for (index, event) in events.enumerated() {
                queue.asyncAfter(deadline: .now() + gap * Double(index + 1)) {
                    connection.send(content: Data("data: \(event)\n\n".utf8), completion: .contentProcessed { _ in })
                }
            }
            queue.asyncAfter(deadline: .now() + gap * Double(events.count + 1) + 0.05) {
                connection.send(content: nil, isComplete: true, completion: .contentProcessed { _ in connection.cancel() })
            }
        }
    }
}
#endif
