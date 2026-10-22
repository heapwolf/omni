// Android: OmniApprovalKey.java.

#if os(Android)
import Foundation
import CAndroid

func makePlatformApprovalKeys() -> any ApprovalKeyStore { AndroidApprovalKeyStore() }

public struct AndroidApprovalKeyStore: ApprovalKeyStore {
    public init() {}

    private func context() throws -> (env: UnsafeMutablePointer<JNIEnv?>, activity: jobject) {
        guard let env = omni_get_env(), let activity = omni_jni_activity() else {
            throw ApprovalKeyError.unavailable("No Android context — omni_jni_init has not run.")
        }
        return (env, activity)
    }

    public var biometry: Biometry {
        guard let (env, activity) = try? context() else { return .none }
        return omni_jni_approval_biometry(env, activity) == 1 ? .biometric : .none
    }

    public func hasKey(_ tag: String) -> Bool {
        guard let (env, activity) = try? context() else { return false }
        return omni_jni_approval_key_has(env, activity, tag) == 1
    }

    public func create(_ tag: String) throws -> Data {
        guard biometry != .none else { throw ApprovalKeyError.unavailable("No strong biometric enrolled.") }
        let (env, activity) = try context()
        var length: Int32 = 0
        guard let buffer = omni_jni_approval_key_create(env, activity, tag, &length) else {
            throw ApprovalKeyError.failed("The Android Keystore could not make the approval key \"\(tag)\".")
        }
        defer { free(buffer) }
        return Data(bytes: buffer, count: Int(length))
    }

    public func signBlocking(_ message: Data, with tag: String, prompt: ApprovalPrompt) throws -> Data {
        var length: Int32 = 0, status: Int32 = 4
        let buffer = message.withUnsafeBytes { raw in
            omni_jni_approval_key_sign(tag, raw.bindMemory(to: UInt8.self).baseAddress, Int32(message.count),
                                       prompt.reason, "", prompt.cancel, &length, &status)
        }
        guard let buffer else {
            switch status {
            case 1: throw ApprovalKeyError.cancelled
            case 2: throw ApprovalKeyError.invalidated
            case 3: throw ApprovalKeyError.notFound
            default: throw ApprovalKeyError.failed("The Android Keystore could not sign with the approval key \"\(tag)\".")
            }
        }
        defer { free(buffer) }
        return Data(bytes: buffer, count: Int(length))
    }

    public func delete(_ tag: String) throws {
        let (env, activity) = try context()
        guard omni_jni_approval_key_delete(env, activity, tag) == 1 else { throw ApprovalKeyError.notFound }
    }
}
#endif
