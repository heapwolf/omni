import XCTest
@testable import OmniHTTP

/// https://fetch.spec.whatwg.org/#response-class
final class ResponseTests: XCTestCase {
    let url = URL(string: "https://api.example.com/accounts")!

    private func response(_ body: String, status: Int = 200, headers: Headers = Headers()) -> Response {
        Response(data: Data(body.utf8), status: status, headers: headers, url: url)
    }

    // MARK: bodies are read once

    func testTextReadsTheBody() throws {
        XCTAssertEqual(try response("hello").text(), "hello")
    }

    func testBytesReadsTheBody() throws {
        XCTAssertEqual(try response("hello").bytes(), Data("hello".utf8))
    }

    func testJsonDecodesTypedValues() throws {
        struct Account: Decodable { let id: String; let balanceMinor: Int }
        let account: Account = try response(#"{"id":"acc_1","balanceMinor":12345}"#).json()
        XCTAssertEqual(account.id, "acc_1")
        XCTAssertEqual(account.balanceMinor, 12345)
    }

    func testJsonDecodesIso8601Dates() throws {
        struct Row: Decodable { let createdAt: Date }
        let row: Row = try response(#"{"createdAt":"2026-01-02T03:04:05Z"}"#).json()
        XCTAssertEqual(row.createdAt, Date(timeIntervalSince1970: 1_767_323_045))
    }

    func testBodyUsedFlipsAndASecondReadThrows() throws {
        let r = response("hello")
        XCTAssertFalse(r.bodyUsed)
        _ = try r.text()
        XCTAssertTrue(r.bodyUsed)
        XCTAssertThrowsError(try r.text()) { XCTAssertEqual($0 as? FetchError, .bodyAlreadyConsumed) }
    }

    func testAnyTwoBodyReadsConflictNotJustTheSameOne() throws {
        let r = response(#"{"a":1}"#)
        _ = try r.bytes()
        XCTAssertThrowsError(try r.text())

        struct A: Decodable { let a: Int }
        let r2 = response(#"{"a":1}"#)
        _ = try r2.json(A.self)
        XCTAssertThrowsError(try r2.bytes())
    }

    func testAnEmptyBodyIsStillAReadThatSucceeds() throws {
        let r = response("")
        XCTAssertEqual(try r.text(), "")
        XCTAssertTrue(r.bodyUsed)
    }

    // MARK: decoding failures name the field

    func testMissingFieldIsNamed() throws {
        struct Account: Decodable { let id: String; let balanceMinor: Int }
        XCTAssertThrowsError(try response(#"{"id":"acc_1"}"#).json(Account.self)) { error in
            guard case .invalidArgument(let detail) = error as? FetchError ?? .timedOut else {
                return XCTFail("wrong error: \(error)")
            }
            XCTAssertTrue(detail.contains("balanceMinor"), "unhelpful: \(detail)")
            XCTAssertTrue(detail.contains("missing"), "should say what was wrong: \(detail)")
        }
    }

    func testWrongTypeIsNamed() throws {
        struct Account: Decodable { let balanceMinor: Int }
        XCTAssertThrowsError(try response(#"{"balanceMinor":"lots"}"#).json(Account.self)) { error in
            guard case .invalidArgument(let detail) = error as? FetchError ?? .timedOut else {
                return XCTFail("wrong error: \(error)")
            }
            XCTAssertTrue(detail.contains("balanceMinor"), "unhelpful: \(detail)")
        }
    }

    func testNestedFieldPathIsNamed() throws {
        struct Inner: Decodable { let amount: Int }
        struct Outer: Decodable { let inner: Inner }
        XCTAssertThrowsError(try response(#"{"inner":{}}"#).json(Outer.self)) { error in
            guard case .invalidArgument(let detail) = error as? FetchError ?? .timedOut else {
                return XCTFail("wrong error: \(error)")
            }
            XCTAssertTrue(detail.contains("inner.amount"), "should give the path: \(detail)")
        }
    }

    func testMalformedJsonSaysSo() throws {
        struct A: Decodable { let a: Int }
        XCTAssertThrowsError(try response("not json at all").json(A.self)) { error in
            guard case .invalidArgument(let detail) = error as? FetchError ?? .timedOut else {
                return XCTFail("wrong error: \(error)")
            }
            XCTAssertTrue(detail.contains("JSON"), "unhelpful: \(detail)")
        }
    }

    func testAnHtmlErrorPageDoesNotDecodeAsJson() throws {
        struct A: Decodable { let a: Int }
        let r = Response(data: Data("<html>502 Bad Gateway</html>".utf8), status: 502, url: url)
        XCTAssertFalse(r.ok)
        XCTAssertEqual(r.status, 502, "the status must survive an unparseable body")
        XCTAssertThrowsError(try r.json(A.self))
    }

    // MARK: metadata

    func testStatusTextIsFilledInForKnownStatuses() {
        let known: [Int: String] = [200: "OK", 201: "Created", 204: "No Content",
                                    400: "Bad Request", 401: "Unauthorized", 404: "Not Found",
                                    409: "Conflict", 422: "Unprocessable Content",
                                    429: "Too Many Requests", 500: "Internal Server Error",
                                    502: "Bad Gateway", 503: "Service Unavailable"]
        for (status, text) in known {
            XCTAssertEqual(Response(status: status, url: url).statusText, text, "status \(status)")
        }
    }

    func testAnExplicitStatusTextWins() {
        XCTAssertEqual(Response(status: 200, statusText: "Totally Fine", url: url).statusText, "Totally Fine")
    }

    func testAnUnknownStatusHasEmptyStatusText() {
        XCTAssertEqual(Response(status: 599, url: url).statusText, "")
    }

    func testHeadersAreReadableAndCaseInsensitive() {
        let r = response("", headers: ["Content-Type": "application/json"])
        XCTAssertEqual(r.headers.get("content-type"), "application/json")
    }

    func testRedirectedDefaultsFalseAndUrlIsTheFinalOne() {
        let r = response("")
        XCTAssertFalse(r.redirected)
        XCTAssertEqual(r.url, url)
    }
}
