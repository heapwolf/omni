// A P-256 key in secure hardware. Each signature needs the biometric.
// A new face or finger breaks the key. No hardware or biometric: no key.

import Foundation

// MARK: - Seam

public enum Biometry: String, Sendable, Equatable {
    /// Use the PIN.
    case none
    case faceID, touchID, opticID
    /// Android's strong biometric.
    case biometric
}

public enum ApprovalKeyError: Error, Sendable, Equatable {
    case cancelled
    /// The biometric set changed. Make a new key.
    case invalidated
    case notFound
    case unavailable(String)
    case failed(String)
}

/// The prompt's text.
public struct ApprovalPrompt: Sendable, Equatable {
    public var reason: String
    /// Android's cancel button.
    public var cancel: String

    public init(reason: String, cancel: String) {
        self.reason = reason
        self.cancel = cancel
    }
}

public protocol ApprovalKeyStore: Sendable {
    /// No prompt.
    var biometry: Biometry { get }
    func hasKey(_ tag: String) -> Bool
    /// Replaces any key. Returns the public key, x9.63. No prompt.
    func create(_ tag: String) throws -> Data
    /// Prompts, then signs: ECDSA, SHA-256, DER. Blocks.
    func signBlocking(_ message: Data, with tag: String, prompt: ApprovalPrompt) throws -> Data
    func delete(_ tag: String) throws
}

public extension ApprovalKeyStore {
    /// signBlocking on its own thread.
    func sign(_ message: Data, with tag: String, prompt: ApprovalPrompt) async throws -> Data {
        try await withCheckedThrowingContinuation { done in
            let thread = Thread {
                done.resume(with: Result { try self.signBlocking(message, with: tag, prompt: prompt) })
            }
            thread.start()
        }
    }
}

// MARK: - Default

public enum ApprovalKeys {
    public static let `default`: any ApprovalKeyStore = makePlatformApprovalKeys()
}

/// PIN only.
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
