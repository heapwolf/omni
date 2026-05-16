import XCTest
@testable import OmniUI

/// A deep link on the open session's scheme finishes it; the app never sees it.
@MainActor
final class WebAuthenticationTests: XCTestCase {
    override func tearDown() {
        DeepLink.reset()
        WebAuthentication.pending = nil
        super.tearDown()
    }

    func testTheSessionsLinkFinishesItAndOthersGoToTheApp() async throws {
        var seen: [URL] = []
        DeepLink.install { seen.append($0) }
        let result: URL? = try await withCheckedThrowingContinuation { continuation in
            WebAuthentication.pending = .init(scheme: "example", continuation: continuation)
            DeepLink.receive(URL(string: "https://example.com/other")!)
            DeepLink.receive(URL(string: "OneDosh://plaid/done?public_token=p1")!)
        }
        XCTAssertEqual(result?.absoluteString, "OneDosh://plaid/done?public_token=p1")
        XCTAssertEqual(seen.map(\.absoluteString), ["https://example.com/other"])
        XCTAssertNil(WebAuthentication.pending)
        // Nothing open: the app gets it.
        DeepLink.receive(URL(string: "example://card-activation")!)
        XCTAssertEqual(seen.count, 2)
    }

    func testOneAtATime() async throws {
        let first = Task { try await withCheckedThrowingContinuation { (c: CheckedContinuation<URL?, any Error>) in
            WebAuthentication.pending = .init(scheme: "example", continuation: c)
        } }
        await Task.yield()
        do {
            _ = try await WebAuthentication.open(URL(string: "https://example.com")!, callbackScheme: "example")
            XCTFail("a second session opened")
        } catch let error as WebAuthentication.Failure {
            XCTAssertEqual(error, .busy)
        }
        WebAuthentication.finish(.success(nil))
        let closed = try await first.value
        XCTAssertNil(closed)
    }
}
