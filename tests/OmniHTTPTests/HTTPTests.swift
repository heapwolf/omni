import XCTest
import Foundation
@testable import OmniHTTP

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// A client that returns what it was told to, so the tests above the transport
/// need no local server and no ports.
private struct StubClient: HTTPClient {
    let result: Result<HTTPResponse, HTTPError>
    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        switch result {
        case .success(let response): return response
        case .failure(let error): throw error
        }
    }
}

final class HTTPRequestTests: XCTestCase {
    func testDefaultsAreGETWithNoBody() {
        let request = HTTPRequest(url: URL(string: "https://example.com")!)
        XCTAssertEqual(request.method, "GET")
        XCTAssertNil(request.body)
        XCTAssertEqual(request.timeout, 60)
        XCTAssertTrue(request.headers.isEmpty)
    }

    func testHeadersKeepOrderAndAllowDuplicates() {
        let request = HTTPRequest(
            url: URL(string: "https://example.com")!,
            headers: [("set-cookie", "a=1"), ("set-cookie", "b=2"), ("accept", "*/*")])
        XCTAssertEqual(request.headers.count, 3)
        XCTAssertEqual(request.headers.map(\.value), ["a=1", "b=2", "*/*"])
    }
}

final class HTTPResponseTests: XCTestCase {
    /// The rule that makes this a transport and not a client library: a status
    /// is data, never an error.
    func testNon2xxIsAResponseNotAnError() async throws {
        let url = URL(string: "https://example.com")!
        for status in [404, 418, 500] {
            let client = StubClient(result: .success(
                HTTPResponse(status: status, headers: [], body: Data(), url: url, redirected: false)))
            let response = try await client.send(HTTPRequest(url: url))
            XCTAssertEqual(response.status, status)
        }
    }

    func testRedirectIsReportedNotEnforced() async throws {
        let from = URL(string: "https://example.com/a")!
        let to = URL(string: "https://example.com/b")!
        let client = StubClient(result: .success(
            HTTPResponse(status: 200, headers: [], body: Data(), url: to, redirected: true)))
        let response = try await client.send(HTTPRequest(url: from))
        // The transport reports it; policy is a decision for the layer above.
        XCTAssertTrue(response.redirected)
        XCTAssertEqual(response.url, to)
    }
}
