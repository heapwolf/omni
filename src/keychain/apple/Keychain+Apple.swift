// iOS and macOS: Security.framework.

#if canImport(Darwin)
import Foundation
import Security

func makePlatformStore() -> any KeychainStore { AppleKeychainStore() }

public struct AppleKeychainStore: KeychainStore {
    /// Namespaces every item, so two apps sharing a device (or a test and the
    /// app) never collide.
    private let service: String

    public init(service: String = Bundle.main.bundleIdentifier ?? "omni") {
        self.service = service
    }

    private func query(_ key: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: key]
    }

    private func protection(_ accessibility: Accessibility) -> CFString {
        switch accessibility {
        case .whenUnlocked: return kSecAttrAccessibleWhenUnlocked
        case .afterFirstUnlock: return kSecAttrAccessibleAfterFirstUnlock
        case .whenUnlockedThisDeviceOnly: return kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        case .afterFirstUnlockThisDeviceOnly: return kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        }
    }

    public func set(_ data: Data, for key: String, accessibility: Accessibility) throws {
        SecItemDelete(query(key) as CFDictionary)

        var attributes = query(key)
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = protection(accessibility)

        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else { throw Self.error(status) }
    }

    public func get(_ key: String) throws -> Data? {
        var attributes = query(key)
        attributes[kSecReturnData as String] = true
        attributes[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(attributes as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw Self.error(status) }
        return item as? Data
    }

    public func delete(_ key: String) throws {
        let status = SecItemDelete(query(key) as CFDictionary)
        if status == errSecItemNotFound { throw KeychainError.notFound }
        guard status == errSecSuccess else { throw Self.error(status) }
    }

    private static func error(_ status: OSStatus) -> KeychainError {
        let message = SecCopyErrorMessageString(status, nil) as String?
            ?? "OSStatus \(status)"
        switch status {
        case errSecInteractionNotAllowed:
            return .denied("The device is locked, or the item's accessibility class forbids access right now. \(message)")
        case errSecMissingEntitlement:
            return .denied("Missing keychain entitlement. Add a keychain-access-group matching the app's bundle id. \(message)")
        default:
            return .platform(code: Int(status), message: message)
        }
    }
}
#endif
