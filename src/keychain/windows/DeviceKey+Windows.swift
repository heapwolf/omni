
#if os(Windows)
import Foundation

func makePlatformDeviceKeys() -> any DeviceKeyStore { WindowsDeviceKeyStore() }

func platformSHA256(_ data: Data) -> Data { SoftwareSHA256.hash(data) }

public struct WindowsDeviceKeyStore: DeviceKeyStore {
    private static let notImplemented = KeychainError.unavailable(
        "Device keys are not implemented on Windows yet (needs CNG via CWindows).")

    public init() {}
    public func publicKey(_ tag: String) throws -> Data { throw Self.notImplemented }
    public func sign(_ message: Data, with tag: String) throws -> Data { throw Self.notImplemented }
    public func delete(_ tag: String) throws { throw Self.notImplemented }
}
#endif
