
#if os(Android)
import Foundation
import CAndroid

func makePlatformDeviceKeys() -> any DeviceKeyStore { AndroidDeviceKeyStore() }

func platformSHA256(_ data: Data) -> Data { SoftwareSHA256.hash(data) }

/// The Android Keystore: an EC key made there (StrongBox where the phone has
/// it), so its private half never reaches this process. OmniDeviceKey.java.
public struct AndroidDeviceKeyStore: DeviceKeyStore {
    public init() {}

    private func context() throws -> (env: UnsafeMutablePointer<JNIEnv?>, activity: jobject) {
        guard let env = omni_get_env(), let activity = omni_jni_activity() else {
            throw KeychainError.unavailable("No Android context — omni_jni_init has not run.")
        }
        return (env, activity)
    }

    public func publicKey(_ tag: String) throws -> Data {
        let (env, activity) = try context()
        var length: Int32 = 0
        guard let buffer = omni_jni_device_key_public(env, activity, tag, &length) else {
            throw KeychainError.platform(code: 0, message: "The Android Keystore could not make or read the device key \"\(tag)\".")
        }
        defer { free(buffer) }
        return Data(bytes: buffer, count: Int(length))
    }

    public func sign(_ message: Data, with tag: String) throws -> Data {
        let (env, activity) = try context()
        var length: Int32 = 0
        let buffer = message.withUnsafeBytes { raw in
            omni_jni_device_key_sign(env, activity, tag, raw.bindMemory(to: UInt8.self).baseAddress,
                                     Int32(message.count), &length)
        }
        guard let buffer else {
            throw KeychainError.platform(code: 0, message: "The Android Keystore could not sign with the device key \"\(tag)\".")
        }
        defer { free(buffer) }
        return Data(bytes: buffer, count: Int(length))
    }

    public func delete(_ tag: String) throws {
        let (env, activity) = try context()
        guard omni_jni_device_key_delete(env, activity, tag) == 1 else {
            throw KeychainError.notFound
        }
    }
}
#endif
