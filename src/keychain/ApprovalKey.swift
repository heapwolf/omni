// A signing key that needs the person, not just the phone: P-256 in the secure hardware,
// and every signature asks for Face ID, Touch ID or the phone's strong biometric. Adding a
// face or fingerprint to the phone makes the key unusable, so whoever adds one can't approve.
// For approving payments and unlocking; DeviceKey (no prompt) proves the device.
//
// Only where there is secure hardware and an enrolled biometric. Nowhere else is there a
// software stand-in: without one, the app asks for its PIN instead.

import Foundation

// MARK: - The seam

/// What the phone can check.
public enum Biometry: String, Sendable, Equatable {
    /// No biometric enrolled, no hardware, or not allowed: use the PIN.
    case none
    case faceID, touchID, opticID
    /// Android's strong (Class 3) biometric: a fingerprint or a face, as the phone has.
    case biometric
}

public enum ApprovalKeyError: Error, Sendable, Equatable {
    /// The person dismissed the prompt, or the app went away.
    case cancelled
    /// A face or fingerprint was added or removed since the key was made. Make a new one;
    /// the server must see it enrolled again (with the PIN).
    case invalidated
    /// No key under that tag.
    case notFound
    /// No secure hardware or no biometric enrolled.
    case unavailable(String)
    case failed(String)
}

/// What the prompt says, in the app's words: omni has no strings of its own.
public struct ApprovalPrompt: Sendable, Equatable {
    /// Why it's asking, such as "Approve sending $25.00". The title on Android; under the
    /// biometric on iOS.
    public var reason: String
    /// Android's button to use the PIN instead. iOS draws its own.
    public var cancel: String

    public init(reason: String, cancel: String) {
        self.reason = reason
        self.cancel = cancel
    }
}

public protocol ApprovalKeyStore: Sendable {
    /// Asks nothing of the person.
    var biometry: Biometry { get }
    /// True if a key is stored under `tag`. It may still be invalidated: that shows when signing.
    func hasKey(_ tag: String) -> Bool
    /// Makes a new key under `tag`, replacing any there was, and returns its public half:
    /// x9.63 uncompressed, 65 bytes. No prompt.
    func create(_ tag: String) throws -> Data
    /// Asks for the biometric with `prompt` shown, then signs: ECDSA over SHA-256 of
    /// `message` (hashed here), DER. It waits for the person: never call it on the main
    /// thread. The async form below runs it on a thread of its own.
    func signBlocking(_ message: Data, with tag: String, prompt: ApprovalPrompt) throws -> Data
    func delete(_ tag: String) throws
}

public extension ApprovalKeyStore {
    /// `signBlocking` on a thread of its own: the prompt may take as long as the person does.
    func sign(_ message: Data, with tag: String, prompt: ApprovalPrompt) async throws -> Data {
        try await withCheckedThrowingContinuation { done in
            let thread = Thread {
                done.resume(with: Result { try self.signBlocking(message, with: tag, prompt: prompt) })
            }
            thread.start()
        }
    }
}

// MARK: - The one every app uses

public enum ApprovalKeys {
    /// The platform's keys.
    public static let `default`: any ApprovalKeyStore = makePlatformApprovalKeys()
}

/// No biometric approval here (Linux, Windows): every approval is the PIN.
public struct NoApprovalKeyStore: ApprovalKeyStore {
    public init() {}
    public var biometry: Biometry { .none }
    public func hasKey(_ tag: String) -> Bool { false }
    public func create(_ tag: String) throws -> Data { throw ApprovalKeyError.unavailable("No biometric approval on this platform.") }
    public func signBlocking(_ message: Data, with tag: String, prompt: ApprovalPrompt) throws -> Data {
        throw ApprovalKeyError.notFound
    }
    public func delete(_ tag: String) throws { throw ApprovalKeyError.notFound }
}
