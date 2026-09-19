
#if os(Windows)
import Foundation

func makePlatformStore() -> any KeychainStore { WindowsCredentialStore() }

public struct WindowsCredentialStore: KeychainStore {
    private static let notImplemented = KeychainError.unavailable(
        "The Windows credential backend is not implemented yet (needs DPAPI via CWindows).")

    public init() {}
    public func set(_ data: Data, for key: String, accessibility: Accessibility) throws {
        throw Self.notImplemented
    }
    public func get(_ key: String) throws -> Data? { throw Self.notImplemented }
    public func delete(_ key: String) throws { throw Self.notImplemented }
}
#endif
