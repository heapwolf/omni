import XCTest
import Foundation
@testable import OmniKeychain
#if canImport(CryptoKit)
import CryptoKit
#endif

/// Answers from memory, remembering how each item was to be kept.
final class MemoryKeychainStore: KeychainStore, @unchecked Sendable {
    private let lock = NSLock()
    private var items: [String: (Data, Accessibility)] = [:]
    /// Thrown by every get, to stand for a phone not yet unlocked since boot.
    var failure: KeychainError?

    func set(_ data: Data, for key: String, accessibility: Accessibility) throws {
        lock.withLock { items[key] = (data, accessibility) }
    }

    func get(_ key: String) throws -> Data? {
        try lock.withLock {
            if let failure { throw failure }
            return items[key]?.0
        }
    }

    func delete(_ key: String) throws {
        try lock.withLock {
            guard items.removeValue(forKey: key) != nil else { throw KeychainError.notFound }
        }
    }

    func accessibility(_ key: String) -> Accessibility? { lock.withLock { items[key]?.1 } }
    var count: Int { lock.withLock { items.count } }
}

final class SHA256Tests: XCTestCase {
    private func hex(_ data: Data) -> String { data.map { String(format: "%02x", $0) }.joined() }

    /// FIPS 180-4's own examples.
    func testTheStandardsVectors() {
        XCTAssertEqual(hex(SoftwareSHA256.hash(Data("abc".utf8))),
                       "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        XCTAssertEqual(hex(SoftwareSHA256.hash(Data())),
                       "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
        XCTAssertEqual(hex(SoftwareSHA256.hash(Data("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq".utf8))),
                       "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1")
    }

    #if canImport(CryptoKit)
    /// Every length around the padding's edges, against CryptoKit.
    func testAgreesWithCryptoKit() {
        for length in [0, 1, 54, 55, 56, 57, 63, 64, 65, 119, 120, 128, 1000] {
            let data = Data((0..<length).map { UInt8(truncatingIfNeeded: $0 &* 31 &+ 7) })
            XCTAssertEqual(SoftwareSHA256.hash(data), Data(CryptoKit.SHA256.hash(data: data)), "length \(length)")
        }
        XCTAssertEqual(DeviceKeys.sha256(Data("abc".utf8)), SoftwareSHA256.hash(Data("abc".utf8)))
    }
    #endif
}

#if canImport(Darwin)
final class AppleDeviceKeyStoreTests: XCTestCase {
    private var keychain: MemoryKeychainStore!
    private var keys: AppleDeviceKeyStore!

    override func setUp() {
        super.setUp()
        keychain = MemoryKeychainStore()
        keys = AppleDeviceKeyStore(keychain: keychain, secureEnclave: false)
    }

    func testThePublicKeyIsX963Uncompressed() throws {
        let key = try keys.publicKey("device")
        XCTAssertEqual(key.count, 65)
        XCTAssertEqual(key.first, 0x04)
        XCTAssertNoThrow(try P256.Signing.PublicKey(x963Representation: key))
    }

    func testASignatureVerifiesWithThePublicKey() throws {
        let message = Data("example-sign-in-v1\nodch_challenge".utf8)
        let signature = try keys.sign(message, with: "device")
        let publicKey = try P256.Signing.PublicKey(x963Representation: try keys.publicKey("device"))
        let parsed = try P256.Signing.ECDSASignature(derRepresentation: signature)
        XCTAssertTrue(publicKey.isValidSignature(parsed, for: message))
        XCTAssertFalse(publicKey.isValidSignature(parsed, for: Data("something else".utf8)))
    }

    /// The message is hashed with SHA-256 by the signer, as a server verifying
    /// "ECDSA-SHA256 over the message" expects.
    func testTheSignatureIsOverTheMessagesSHA256() throws {
        let message = Data("example-refresh-v1\nabc".utf8)
        let signature = try P256.Signing.ECDSASignature(derRepresentation: try keys.sign(message, with: "device"))
        let publicKey = try P256.Signing.PublicKey(x963Representation: try keys.publicKey("device"))
        XCTAssertTrue(publicKey.isValidSignature(signature, for: CryptoKit.SHA256.hash(data: message)))
    }

    func testTheKeyOutlivesTheStoreThatMadeIt() throws {
        let first = try keys.publicKey("device")
        let again = AppleDeviceKeyStore(keychain: keychain, secureEnclave: false)
        XCTAssertEqual(try again.publicKey("device"), first)
    }

    /// Never restored to another phone, and readable while locked.
    func testItIsKeptThisDeviceOnlyAfterFirstUnlock() throws {
        _ = try keys.publicKey("device")
        XCTAssertEqual(keychain.accessibility("omni.devicekey.device"), .afterFirstUnlockThisDeviceOnly)
    }

    func testTagsAreSeparateKeys() throws {
        XCTAssertNotEqual(try keys.publicKey("one"), try keys.publicKey("two"))
    }

    func testDeletingMakesANewKeyNextTime() throws {
        let first = try keys.publicKey("device")
        try keys.delete("device")
        XCTAssertNotEqual(try keys.publicKey("device"), first)
        try keys.delete("device")
        XCTAssertThrowsError(try keys.delete("device")) { XCTAssertEqual($0 as? KeychainError, .notFound) }
    }

    /// A locked phone's refusal is not "no key": making one would be a new
    /// device, and a new email code, for nothing.
    func testAFailedReadIsThrownNotReplaced() throws {
        let first = try keys.publicKey("device")
        keychain.failure = .denied("locked")
        XCTAssertThrowsError(try keys.publicKey("device")) { XCTAssertEqual($0 as? KeychainError, .denied("locked")) }
        keychain.failure = nil
        XCTAssertEqual(try keys.publicKey("device"), first)
    }

    func testWhatCannotBeReadAsAKeyIsReplaced() throws {
        try keychain.set(Data([9, 9, 9]), for: "omni.devicekey.device", accessibility: .whenUnlocked)
        XCTAssertEqual(try keys.publicKey("device").count, 65)
    }

    func testFirstUsesAtOnceMakeOneKey() async throws {
        let keys = self.keys!
        let found = try await withThrowingTaskGroup(of: Data.self) { group in
            for _ in 0..<16 { group.addTask { try keys.publicKey("device") } }
            return try await group.reduce(into: Set<Data>()) { $0.insert($1) }
        }
        XCTAssertEqual(found.count, 1)
        XCTAssertEqual(keychain.count, 1)
    }

    /// The real enclave, where the machine has one and lets a test use it.
    func testTheSecureEnclaveWhereThereIsOne() throws {
        guard SecureEnclave.isAvailable else { throw XCTSkip("no Secure Enclave here") }
        let keys = AppleDeviceKeyStore(keychain: keychain, secureEnclave: true)
        let message = Data("example-new-device-v1\npending".utf8)
        let publicKey = try P256.Signing.PublicKey(x963Representation: try keys.publicKey("enclave"))
        let signature = try P256.Signing.ECDSASignature(derRepresentation: try keys.sign(message, with: "enclave"))
        XCTAssertTrue(publicKey.isValidSignature(signature, for: message))
        // 1: kept as an enclave key's handle, not the software fallback's.
        XCTAssertEqual(try keychain.get("omni.devicekey.enclave")?.first, 1, "the enclave refused; the fallback was used")
    }
}
#endif
