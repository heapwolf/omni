// One API, four backends, no view engine. Scope is small secrets: tokens,
// keys, a PIN hash. Not files or caches.

import Foundation

// MARK: - When a secret may be read

public enum Accessibility: Sendable {
    /// Readable whenever the device is unlocked. The default.
    case whenUnlocked
    /// Readable after the first unlock following a boot, including while locked.
    case afterFirstUnlock
    /// Readable only while unlocked, never restored to a new device, and removed
    /// if the user disables their passcode.
    case whenUnlockedThisDeviceOnly
    /// Readable after the first unlock following a boot, including while
    /// locked, and never restored to a new device: what a session's tokens
    /// want, so a refresh still runs under the lock screen and a backup
    /// carries no session to another phone.
    case afterFirstUnlockThisDeviceOnly
}

// MARK: - How it fails

public enum KeychainError: Error, Sendable, Equatable {
    /// No item under that key. Distinct from a stored empty value.
    case notFound
    /// The platform refused: locked device, missing entitlement, or policy.
    case denied(String)
    /// No secure store on this platform or configuration.
    case unavailable(String)
    /// Anything else the platform reported.
    case platform(code: Int, message: String)
}

// MARK: - The seam

public protocol KeychainStore: Sendable {
    /// Writes, replacing any existing value for the key.
    func set(_ data: Data, for key: String, accessibility: Accessibility) throws
    /// Reads, or nil when absent. Absence is not an error.
    func get(_ key: String) throws -> Data?
    /// Removes. Throws .notFound when there was nothing to remove.
    func delete(_ key: String) throws
}

public extension KeychainStore {
    func set(_ data: Data, for key: String) throws {
        try set(data, for: key, accessibility: .whenUnlocked)
    }

    /// UTF-8 convenience.
    func setString(_ value: String, for key: String,
                   accessibility: Accessibility = .whenUnlocked) throws {
        try set(Data(value.utf8), for: key, accessibility: accessibility)
    }

    func getString(_ key: String) throws -> String? {
        try get(key).flatMap { String(data: $0, encoding: .utf8) }
    }
}

// MARK: - The one every app uses

public enum Keychain {
    /// The platform's store. A let, not a var: a swappable global is a data race
    /// and lets one test change another's behaviour.
    public static let `default`: any KeychainStore = makePlatformStore()
}
