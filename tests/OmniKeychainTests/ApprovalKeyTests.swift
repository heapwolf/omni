import XCTest
import Foundation
@testable import OmniKeychain

/// The approval key's seam and what can run without a Secure Enclave or a face: the stored
/// format, the platforms without one, and the async form. Prompting needs a phone.
final class ApprovalKeyTests: XCTestCase {
    /// Signs at once; records the thread it ran on.
    final class Recorder: ApprovalKeyStore, @unchecked Sendable {
        var ranOnMain: Bool?
        var biometry: Biometry { .faceID }
        func hasKey(_ tag: String) -> Bool { true }
        func create(_ tag: String) throws -> Data { Data([4]) }
        func signBlocking(_ message: Data, with tag: String, prompt: ApprovalPrompt) throws -> Data {
            ranOnMain = Thread.isMainThread
            if prompt.reason == "cancel" { throw ApprovalKeyError.cancelled }
            return message + Data(prompt.reason.utf8)
        }
        func delete(_ tag: String) throws {}
    }

    func testTheAsyncFormSignsOffTheMainThreadAndPassesErrorsOn() async throws {
        let store = Recorder()
        let signed = try await store.sign(Data("a".utf8), with: "t", prompt: ApprovalPrompt(reason: "b", cancel: "PIN"))
        XCTAssertEqual(signed, Data("ab".utf8))
        XCTAssertEqual(store.ranOnMain, false, "the prompt waits for the person, so never on the main thread")
        do {
            _ = try await store.sign(Data(), with: "t", prompt: ApprovalPrompt(reason: "cancel", cancel: "PIN"))
            XCTFail("a cancel signed")
        } catch let error as ApprovalKeyError {
            XCTAssertEqual(error, .cancelled)
        }
    }

    func testWithoutBiometricsThereIsNoKey() {
        let none = NoApprovalKeyStore()
        XCTAssertEqual(none.biometry, .none)
        XCTAssertFalse(none.hasKey("t"))
        XCTAssertThrowsError(try none.create("t"))
        XCTAssertThrowsError(try none.signBlocking(Data(), with: "t", prompt: ApprovalPrompt(reason: "r", cancel: "c"))) {
            XCTAssertEqual($0 as? ApprovalKeyError, .notFound)
        }
    }

    #if canImport(Darwin)
    func testTheStoredHandleKeepsTheBiometricState() throws {
        let handle = Data([9, 8, 7]), state = Data([1, 2])
        let decoded = try XCTUnwrap(AppleApprovalKeyStore.decode(AppleApprovalKeyStore.encode(handle, state: state)))
        XCTAssertEqual(decoded.handle, handle)
        XCTAssertEqual(decoded.state, state)
        let stateless = try XCTUnwrap(AppleApprovalKeyStore.decode(AppleApprovalKeyStore.encode(handle, state: nil)))
        XCTAssertNil(stateless.state)
        XCTAssertNil(AppleApprovalKeyStore.decode(Data([2, 0, 0, 1])), "an unknown version reads as invalidated")
        XCTAssertNil(AppleApprovalKeyStore.decode(Data([1, 0, 9, 1])), "a short one too")
    }

    func testSigningWithoutAKeyIsNotFound() {
        let store = AppleApprovalKeyStore(keychain: MemoryKeychainStore())
        XCTAssertFalse(store.hasKey("missing"))
        XCTAssertThrowsError(try store.signBlocking(Data(), with: "missing", prompt: ApprovalPrompt(reason: "r", cancel: "c"))) {
            XCTAssertEqual($0 as? ApprovalKeyError, .notFound)
        }
        XCTAssertThrowsError(try store.delete("missing")) { XCTAssertEqual($0 as? ApprovalKeyError, .notFound) }
    }
    #endif
}
