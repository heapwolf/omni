// iOS: App Attest (DeviceCheck). Each attestation makes a new key in the
// Secure Enclave; Apple's servers vouch for it. Needs the App Attest
// entitlement, from the provisioning profile. Not on the simulator.

#if os(iOS)
import Foundation
import CryptoKit
import DeviceCheck

func makePlatformAttester() -> any DeviceAttester { AppAttester() }

public struct AppAttester: DeviceAttester {
    public init() {}

    public func attest(_ message: Data) async throws -> Attestation? {
        let service = DCAppAttestService.shared
        guard service.isSupported else { return nil }
        let keyID = try await service.generateKey()
        let hash = Data(SHA256.hash(data: message))
        let object = try await service.attestKey(keyID, clientDataHash: hash)
        return Attestation(kind: .apple, object: object, keyID: Data(base64Encoded: keyID))
    }
}
#endif
