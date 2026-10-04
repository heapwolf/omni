
#if os(Android)
import Foundation
import CAndroid

func makePlatformStore() -> any KeychainStore { AndroidKeystoreStore() }

public struct AndroidKeystoreStore: KeychainStore {
    public init() {}

    /// Matches OmniKeystore.aliasFor: one Keystore key per level, because the
    /// unlock restriction is a property of the key rather than of the value.
    private func level(_ accessibility: Accessibility) -> Int32 {
        switch accessibility {
        case .whenUnlocked: return 0
        case .afterFirstUnlock: return 1
        case .whenUnlockedThisDeviceOnly: return 2
        case .afterFirstUnlockThisDeviceOnly: return 3
        }
    }

    private func context() throws -> (env: UnsafeMutablePointer<JNIEnv?>, activity: jobject) {
        guard let env = omni_get_env(), let activity = omni_jni_activity() else {
            throw KeychainError.unavailable("No Android context — omni_jni_init has not run.")
        }
        return (env, activity)
    }

    public func set(_ data: Data, for key: String, accessibility: Accessibility) throws {
        let (env, activity) = try context()
        let ok = data.withUnsafeBytes { raw -> Int32 in
            omni_jni_keystore_set(env, activity, key,
                                  raw.bindMemory(to: UInt8.self).baseAddress,
                                  Int32(data.count), level(accessibility))
        }
        guard ok == 1 else {
            throw KeychainError.platform(
                code: 0,
                message: "The Android Keystore refused to store \"\(key)\". A key is invalidated by a lock-screen credential change, and an unlocked-device-required key cannot be written while locked.")
        }
    }

    public func get(_ key: String) throws -> Data? {
        let (env, activity) = try context()

        var length: Int32 = 0
        guard let buffer = omni_jni_keystore_get(env, activity, key, &length) else {
            if omni_jni_keystore_has(env, activity, key) == 1 {
                throw KeychainError.denied(
                    "\"\(key)\" is stored but could not be decrypted. Usually a locked device for an unlocked-device-required item, or a key invalidated by a lock-screen credential change.")
            }
            return nil
        }
        defer { free(buffer) }
        return Data(bytes: buffer, count: Int(length))
    }

    public func delete(_ key: String) throws {
        let (env, activity) = try context()
        guard omni_jni_keystore_delete(env, activity, key) == 1 else {
            throw KeychainError.notFound
        }
    }
}
#endif
