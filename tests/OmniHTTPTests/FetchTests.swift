import XCTest
@testable import OmniHTTP

/// https://fetch.spec.whatwg.org/#fetch-method
final class FetchTests: XCTestCase {
    let url = URL(string: "https://api.example.com/accounts")!

    // MARK: the rule everything else depends on

    func testAnErrorStatusResolvesRatherThanThrowing() async throws {
        for status in [400, 401, 403, 404, 409, 418, 422, 429, 500, 502, 503, 504] {
            let response = try await fetch(url, using: StubTransport(status: status, body: "{}"))
            XCTAssertEqual(response.status, status)
            XCTAssertFalse(response.ok, "\(status) must resolve with ok == false, not throw")
        }
    }

    func testOkIsExactlyTwoHundredToTwoNinetyNine() async throws {
        let cases: [(Int, Bool)] = [(100, false), (199, false), (200, true), (204, true),
                                    (299, true), (300, false), (301, false), (599, false)]
        for (status, expected) in cases {
            let response = try await fetch(url, using: StubTransport(status: status))
            XCTAssertEqual(response.ok, expected, "status \(status)")
        }
    }

    func testOnlyNetworkFailuresThrow() async {
        do {
            _ = try await fetch(url, using: StubTransport(failing: FetchError.network("connection refused")))
            XCTFail("a network failure must throw")
        } catch let error as FetchError {
            XCTAssertEqual(error, .network("connection refused"))
            XCTAssertTrue(error.isRetryable)
        } catch { XCTFail("wrong error type: \(error)") }
    }

    // MARK: building the request

    func testMethodIsUppercased() async throws {
        for (given, expected) in [("get", "GET"), ("post", "POST"), ("PaTcH", "PATCH"), ("DELETE", "DELETE")] {
            let stub = StubTransport(status: 200)
            _ = try await fetch(url, RequestInit(method: given), using: stub)
            XCTAssertEqual(stub.lastRequest?.method, expected)
        }
    }

    func testDefaultsAreGetWithNoBody() async throws {
        let stub = StubTransport(status: 200)
        _ = try await fetch(url, using: stub)
        XCTAssertEqual(stub.lastRequest?.method, "GET")
        XCTAssertNil(stub.lastRequest?.body)
        XCTAssertTrue(stub.lastRequest?.headers.isEmpty ?? false)
    }

    func testHeadersReachTheTransportUnchanged() async throws {
        let stub = StubTransport(status: 200)
        var headers = Headers()
        headers.set("accept", "application/json")
        headers.append("x-trace", "a")
        headers.append("x-trace", "b")
        _ = try await fetch(url, RequestInit(headers: headers), using: stub)

        XCTAssertEqual(stub.lastRequest?.headers.get("Accept"), "application/json")
        XCTAssertEqual(stub.lastRequest?.headers.get("x-trace"), "a, b")
    }

    func testUrlIsPreservedExactlyIncludingQueryAndPort() async throws {
        let stub = StubTransport(status: 200)
        let target = "https://api.example.com:8443/v1/accounts?page=2&limit=5"
        _ = try await fetch(target, using: stub)

        XCTAssertEqual(stub.lastRequest?.url.absoluteString, target)
        XCTAssertEqual(stub.lastRequest?.url.port, 8443)
        XCTAssertEqual(stub.lastRequest?.url.query, "page=2&limit=5")
    }

    func testJsonInitSetsContentTypeAndEncodes() async throws {
        struct Payload: Encodable, Sendable { let ownerEmail: String; let amountMinor: Int }
        let stub = StubTransport(status: 201)
        let options = try RequestInit.json("POST", Payload(ownerEmail: "a@b.co", amountMinor: 50))
        _ = try await fetch(url, options, using: stub)

        XCTAssertEqual(stub.lastRequest?.headers.get("content-type"), "application/json")
        let body = try XCTUnwrap(stub.lastRequest?.body)
        let decoded = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        XCTAssertEqual(decoded?["amountMinor"] as? Int, 50)
        XCTAssertEqual(decoded?["ownerEmail"] as? String, "a@b.co")
    }

    func testJsonInitDoesNotOverrideAnExplicitContentType() async throws {
        struct Payload: Encodable, Sendable { let a: Int }
        let options = try RequestInit.json("POST", Payload(a: 1),
                                           headers: ["content-type": "application/merge-patch+json"])
        XCTAssertEqual(options.headers.get("content-type"), "application/merge-patch+json")
    }

    func testAnUnencodableBodyFailsWhereItIsWritten() {
        struct Bad: Encodable, Sendable {
            func encode(to encoder: any Encoder) throws {
                throw FetchError.invalidArgument("nope")
            }
        }
        XCTAssertThrowsError(try RequestInit.json("POST", Bad())) { error in
            guard case .invalidArgument = error as? FetchError ?? .timedOut else {
                return XCTFail("wrong error: \(error)")
            }
        }
    }

    func testRelativeOrSchemelessUrlsAreRefusedUpFront() async {
        for bad in ["/accounts", "api.example.com", "", "   "] {
            do {
                _ = try await fetch(bad, using: StubTransport(status: 200))
                XCTFail("\(bad.debugDescription) should not be accepted")
            } catch let error as FetchError {
                guard case .invalidArgument = error else {
                    return XCTFail("wrong error for \(bad.debugDescription): \(error)")
                }
            } catch { XCTFail("wrong error type") }
        }
    }

    // MARK: abort

    func testAnAlreadyAbortedSignalStopsTheRequest() async {
        do {
            _ = try await fetch(url, RequestInit(signal: .aborted()), using: StubTransport(status: 200))
            XCTFail("expected abort")
        } catch let error as FetchError {
            XCTAssertEqual(error, .aborted)
            XCTAssertFalse(error.isRetryable, "an abort was deliberate; retrying it is wrong")
        } catch { XCTFail("wrong error type") }
    }

    func testAbortingMidFlightStopsTheRequest() async {
        let controller = AbortController()
        let stub = StubTransport(status: 200)
        stub.beforeReply = { _ in controller.abort() }

        do {
            _ = try await fetch(url, RequestInit(signal: controller.signal), using: stub)
            XCTFail("expected abort")
        } catch let error as FetchError {
            XCTAssertEqual(error, .aborted)
        } catch { XCTFail("wrong error type") }
    }

    func testARequestThatWasNotAbortedIsUnaffected() async throws {
        let controller = AbortController()
        let response = try await fetch(url, RequestInit(signal: controller.signal),
                                       using: StubTransport(status: 200, body: "fine"))
        XCTAssertTrue(response.ok)
        XCTAssertEqual(try response.text(), "fine")
    }

    // MARK: concurrency

    func testManyConcurrentFetchesAllComplete() async throws {
        let stub = StubTransport(status: 200, body: "ok")
        // Hoisted out of the closure: XCTestCase is not Sendable, so capturing
        // self in a task group is a data race Swift 6 refuses to compile.
        let target = url
        try await withThrowingTaskGroup(of: Int.self) { group in
            for _ in 0..<50 {
                group.addTask { try await fetch(target, using: stub).status }
            }
            var completed = 0
            for try await status in group {
                XCTAssertEqual(status, 200)
                completed += 1
            }
            XCTAssertEqual(completed, 50)
        }
        XCTAssertEqual(stub.callCount, 50, "every request must reach the transport exactly once")
    }
}
