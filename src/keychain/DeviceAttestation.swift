// Proof for a server that the app is ours, unmodified, on a genuine device:
// Apple's App Attest on iOS, Google's Play Integrity on Android. Elsewhere,
// and on simulators, there is none. The server checks it with Apple's root
// CA, or by asking Google to decode it.

import Foundation

public struct Attestation: Sendable, Equatable {
    public enum Kind: String, Sendable { case apple, google }

    public let kind: Kind
    /// apple: the attestation object (CBOR).
    public let object: Data?
    /// apple: the new App Attest key's id (SHA-256 of its public key).
    public let keyID: Data?
    /// google: the integrity token.
    public let token: String?

    public init(kind: Kind, object: Data? = nil, keyID: Data? = nil, token: String? = nil) {
        self.kind = kind
        self.object = object
        self.keyID = keyID
        self.token = token
    }
}

public protocol DeviceAttester: Sendable {
    /// An attestation bound to `message`. App Attest's client data hash is
    /// SHA-256 of it; Play Integrity's request hash is that, base64url.
    /// Nil where the platform has none.
    func attest(_ message: Data) async throws -> Attestation?
}

public enum DeviceAttesters {
    /// The platform's.
    public static let `default`: any DeviceAttester = makePlatformAttester()
}

/// Where there's no attestation.
public struct NoAttester: DeviceAttester {
    public init() {}
    public func attest(_ message: Data) async throws -> Attestation? { nil }
}

#if !os(iOS) && !os(Android)
func makePlatformAttester() -> any DeviceAttester { NoAttester() }
#endif
