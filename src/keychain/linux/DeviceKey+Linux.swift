
#if os(Linux)
import Foundation

func makePlatformDeviceKeys() -> any DeviceKeyStore { UnavailableDeviceKeyStore() }

func platformSHA256(_ data: Data) -> Data { SoftwareSHA256.hash(data) }

/// No secure hardware to ask, and no P-256 here without a crypto library this
/// package doesn't take. Unavailable rather than a key in a file, pretended.
public struct UnavailableDeviceKeyStore: DeviceKeyStore {
    private static let unavailable = KeychainError.unavailable(
        "Device keys are not implemented on Linux yet (needs P-256 signing, e.g. swift-crypto).")

    public init() {}
    public func publicKey(_ tag: String) throws -> Data { throw Self.unavailable }
    public func sign(_ message: Data, with tag: String) throws -> Data { throw Self.unavailable }
    public func delete(_ tag: String) throws { throw Self.unavailable }
}
#endif
