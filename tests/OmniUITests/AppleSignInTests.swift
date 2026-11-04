import XCTest
@testable import OmniUI

/// One sheet at a time, and its answer reaches the one waiting.
@MainActor
final class AppleSignInTests: XCTestCase {
    override func tearDown() {
        AppleSignIn.pending = nil
        super.tearDown()
    }

    func testOneAtATimeAndTheAnswerReachesTheCaller() async throws {
        let first = Task { try await withCheckedThrowingContinuation { (c: CheckedContinuation<AppleSignIn.Credential?, any Error>) in
            AppleSignIn.pending = c
        } }
        await Task.yield()
        do {
            _ = try await AppleSignIn.request(nonce: "n")
            XCTFail("a second sheet opened")
        } catch let error as AppleSignIn.Failure {
            XCTAssertEqual(error, .busy)
        }
        let given = AppleSignIn.Credential(identityToken: "header.claims.signature", authorizationCode: "c1", user: "001.abc")
        AppleSignIn.finish(.success(given))
        let got = try await first.value
        XCTAssertEqual(got, given)
        XCTAssertNil(AppleSignIn.pending)
    }

    func testClosingTheSheetIsNil() async throws {
        let waiting = Task { try await withCheckedThrowingContinuation { (c: CheckedContinuation<AppleSignIn.Credential?, any Error>) in
            AppleSignIn.pending = c
        } }
        await Task.yield()
        AppleSignIn.finish(.success(nil))
        let got = try await waiting.value
        XCTAssertNil(got)
    }
}
