// iOS and macOS: a Secure Enclave key whose use needs the current biometric set
// (.biometryCurrentSet), so adding a face or finger makes it unusable. Its handle is kept in
// the keychain this-device-only, with the biometric set's state at creation: a different state
// at signing reads as `.invalidated` rather than as a failed prompt. No enclave (the simulator,
// a VM), or no biometric enrolled: `.none`, and no key.

#if canImport(Darwin)
import Foundation
import CryptoKit
import LocalAuthentication
import Security

func makePlatformApprovalKeys() -> any ApprovalKeyStore { AppleApprovalKeyStore() }

public struct AppleApprovalKeyStore: ApprovalKeyStore {
    private let keychain: any KeychainStore

    public init(keychain: any KeychainStore = Keychain.default) {
        self.keychain = keychain
    }

    private func item(_ tag: String) -> String { "omni.approvalkey.\(tag)" }

    public var biometry: Biometry {
        guard SecureEnclave.isAvailable else { return .none }
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else { return .none }
        switch context.biometryType {
        case .faceID: return .faceID
        case .touchID: return .touchID
        case .opticID: return .opticID
        default: return .none
        }
    }

    public func hasKey(_ tag: String) -> Bool {
        ((try? keychain.get(item(tag))) ?? nil) != nil
    }

    public func create(_ tag: String) throws -> Data {
        guard biometry != .none else { throw ApprovalKeyError.unavailable("No Secure Enclave or no biometric enrolled.") }
        var problem: Unmanaged<CFError>?
        guard let access = SecAccessControlCreateWithFlags(nil, kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly,
                                                           [.privateKeyUsage, .biometryCurrentSet], &problem) else {
            throw ApprovalKeyError.failed("Access control: \(problem?.takeRetainedValue().localizedDescription ?? "?")")
        }
        let key: SecureEnclave.P256.Signing.PrivateKey
        do {
            key = try SecureEnclave.P256.Signing.PrivateKey(accessControl: access)
        } catch {
            throw ApprovalKeyError.failed("The Secure Enclave refused the key: \(error)")
        }
        try keychain.set(Self.encode(key.dataRepresentation, state: Self.biometricState()), for: item(tag),
                         accessibility: .whenUnlockedThisDeviceOnly)
        return key.publicKey.x963Representation
    }

    public func signBlocking(_ message: Data, with tag: String, prompt: ApprovalPrompt) throws -> Data {
        guard let stored = try keychain.get(item(tag)) else { throw ApprovalKeyError.notFound }
        guard let (handle, state) = Self.decode(stored) else { throw ApprovalKeyError.invalidated }
        guard biometry != .none else { throw ApprovalKeyError.unavailable("No biometric enrolled.") }
        if let state, state != Self.biometricState() { throw ApprovalKeyError.invalidated }
        let context = LAContext()
        context.localizedReason = prompt.reason
        do {
            let key = try SecureEnclave.P256.Signing.PrivateKey(dataRepresentation: handle, authenticationContext: context)
            return try key.signature(for: message).derRepresentation
        } catch {
            throw Self.mapped(error)
        }
    }

    public func delete(_ tag: String) throws {
        do { try keychain.delete(item(tag)) } catch KeychainError.notFound { throw ApprovalKeyError.notFound }
    }

    // MARK: Storage

    /// The enrolled biometric set's state, opaque; nil where the platform gives none.
    private static func biometricState() -> Data? {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else { return nil }
        if #available(iOS 18.0, macOS 15.0, *) { return context.domainState.biometry.stateHash }
        return context.evaluatedPolicyDomainState
    }

    /// Version 1: the state's length (2 bytes), the state, then the enclave handle.
    static func encode(_ handle: Data, state: Data?) -> Data {
        let state = state ?? Data()
        return Data([1, UInt8(state.count >> 8), UInt8(state.count & 0xFF)]) + state + handle
    }

    static func decode(_ stored: Data) -> (handle: Data, state: Data?)? {
        let bytes = [UInt8](stored)
        guard bytes.count > 3, bytes[0] == 1 else { return nil }
        let length = Int(bytes[1]) << 8 | Int(bytes[2])
        guard bytes.count > 3 + length else { return nil }
        let state = Data(bytes[3..<(3 + length)])
        return (Data(bytes[(3 + length)...]), state.isEmpty ? nil : state)
    }

    /// The person's cancel, the system's, or the app's are `.cancelled`; the rest fail.
    private static func mapped(_ error: any Error) -> ApprovalKeyError {
        let ns = error as NSError
        let cancels: Set<Int> = [LAError.userCancel.rawValue, LAError.systemCancel.rawValue, LAError.appCancel.rawValue,
                                 Int(errSecUserCanceled)]
        if cancels.contains(ns.code) || (ns.userInfo[NSUnderlyingErrorKey] as? NSError).map({ cancels.contains($0.code) }) == true {
            return .cancelled
        }
        if ns.code == LAError.biometryLockout.rawValue { return .unavailable("Too many tries. Unlock the phone with its passcode first.") }
        return .failed("Signing with the approval key failed: \(error)")
    }
}
#endif
