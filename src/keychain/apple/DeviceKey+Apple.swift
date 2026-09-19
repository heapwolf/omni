// iOS and macOS: CryptoKit. The Secure Enclave where there is one; its key's
// dataRepresentation is a handle only that enclave can use, kept in the
// keychain this-device-only. Without one (the simulator, an Intel Mac, a VM),
// a software key, kept the same way: the threat model's "a keychain key where
// there's none".

#if canImport(Darwin)
import Foundation
import CryptoKit
import Security

func makePlatformDeviceKeys() -> any DeviceKeyStore { AppleDeviceKeyStore() }

func platformSHA256(_ data: Data) -> Data { Data(SHA256.hash(data: data)) }

public struct AppleDeviceKeyStore: DeviceKeyStore {
    private let keychain: any KeychainStore
    private let secureEnclave: Bool

    /// `secureEnclave: false` makes software keys even where the enclave is
    /// there: for tests, which can't reach it from a test runner.
    public init(keychain: any KeychainStore = Keychain.default,
                secureEnclave: Bool = SecureEnclave.isAvailable) {
        self.keychain = keychain
        self.secureEnclave = secureEnclave
    }

    /// The first byte of what's stored: which kind of key the rest is.
    private enum Kind: UInt8 {
        case secureEnclave = 1
        case software = 2
    }

    private enum Key {
        case secureEnclave(SecureEnclave.P256.Signing.PrivateKey)
        case software(P256.Signing.PrivateKey)

        var publicKey: P256.Signing.PublicKey {
            switch self {
            case .secureEnclave(let key): return key.publicKey
            case .software(let key): return key.publicKey
            }
        }

        func signature(for message: Data) throws -> P256.Signing.ECDSASignature {
            switch self {
            case .secureEnclave(let key): return try key.signature(for: message)
            case .software(let key): return try key.signature(for: message)
            }
        }
    }

    /// One load-or-make at a time, or two first uses at once would each make
    /// a key and one would overwrite the other's.
    private static let lock = NSLock()

    private func item(_ tag: String) -> String { "omni.devicekey.\(tag)" }

    public func publicKey(_ tag: String) throws -> Data {
        try key(tag).publicKey.x963Representation
    }

    public func sign(_ message: Data, with tag: String) throws -> Data {
        do {
            return try key(tag).signature(for: message).derRepresentation
        } catch let error as KeychainError {
            throw error
        } catch {
            throw KeychainError.platform(code: 0, message: "Signing with the device key failed: \(error)")
        }
    }

    public func delete(_ tag: String) throws {
        try Self.lock.withLock { try keychain.delete(item(tag)) }
    }

    private func key(_ tag: String) throws -> Key {
        try Self.lock.withLock {
            // A read that fails (a locked phone before its first unlock) is
            // thrown, never taken for "no key": a new key is a new device.
            if let stored = try keychain.get(item(tag)), let key = Self.decode(stored) {
                return key
            }
            // Nothing stored, or what is can't be used here: a new key.
            let (key, stored) = try make()
            try keychain.set(stored, for: item(tag), accessibility: .afterFirstUnlockThisDeviceOnly)
            return key
        }
    }

    private static func decode(_ stored: Data) -> Key? {
        guard let first = stored.first, let kind = Kind(rawValue: first) else { return nil }
        let rest = stored.dropFirst()
        switch kind {
        case .secureEnclave:
            return (try? SecureEnclave.P256.Signing.PrivateKey(dataRepresentation: rest)).map(Key.secureEnclave)
        case .software:
            return (try? P256.Signing.PrivateKey(rawRepresentation: rest)).map(Key.software)
        }
    }

    private func make() throws -> (Key, Data) {
        if secureEnclave {
            // Usable without a prompt, and while locked (a refresh may run
            // then); never outside this enclave.
            if let access = SecAccessControlCreateWithFlags(nil, kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
                                                            .privateKeyUsage, nil),
               let key = try? SecureEnclave.P256.Signing.PrivateKey(accessControl: access) {
                return (.secureEnclave(key), Data([Kind.secureEnclave.rawValue]) + key.dataRepresentation)
            }
            // The enclave refused (an unsigned Mac build, say): a software key
            // rather than no sign-in at all.
        }
        let key = P256.Signing.PrivateKey()
        return (.software(key), Data([Kind.software.rawValue]) + key.rawRepresentation)
    }
}
#endif
