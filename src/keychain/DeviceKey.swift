// A signing key that never leaves the phone: P-256, made in the secure
// hardware where there is some (Secure Enclave, Android Keystore with
// StrongBox where present), named by a tag, made on first use. What it signs
// proves a request came from this device; the private half is never read.
//
// No prompt, and usable while the phone is locked: it is for proving the
// device, not the person. A key that needs Face ID belongs elsewhere.

import Foundation

// MARK: - The seam

public protocol DeviceKeyStore: Sendable {
    /// The public half, x9.63 uncompressed: 65 bytes, 0x04 ‖ x ‖ y. Makes the
    /// key first if there is none under `tag`.
    func publicKey(_ tag: String) throws -> Data
    /// ECDSA over SHA-256 of `message` (hashed here, not by the caller), DER.
    /// Makes the key first if there is none under `tag`.
    func sign(_ message: Data, with tag: String) throws -> Data
    /// Removes. Throws .notFound when there was nothing to remove.
    func delete(_ tag: String) throws
}

// MARK: - The one every app uses

public enum DeviceKeys {
    /// The platform's keys. A let, for the reason Keychain.default is one.
    public static let `default`: any DeviceKeyStore = makePlatformDeviceKeys()

    /// SHA-256, for what a caller signs a digest of. Here because a key's
    /// users need it on every platform, and only Apple's has CryptoKit.
    public static func sha256(_ data: Data) -> Data {
        platformSHA256(data)
    }
}
