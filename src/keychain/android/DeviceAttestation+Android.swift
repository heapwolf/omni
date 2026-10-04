// Android: Play Integrity, when the app is built with it (omni.json
// playIntegrity); else none. The token's request hash is base64url SHA-256
// of the message.

#if os(Android)
import Foundation
import CAndroid

func makePlatformAttester() -> any DeviceAttester { PlayIntegrityAttester() }

public struct PlayIntegrityAttester: DeviceAttester {
    public init() {}

    public func attest(_ message: Data) async throws -> Attestation? {
        let hash = SoftwareSHA256.hash(message).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        // Up to 40 seconds of blocking Java: a thread of its own, not the pool's.
        let token: String? = await withCheckedContinuation { done in
            let thread = Thread {
                guard let raw = omni_jni_attest_token(hash) else { return done.resume(returning: nil) }
                defer { free(raw) }
                done.resume(returning: String(cString: raw))
            }
            thread.start()
        }
        return token.map { Attestation(kind: .google, token: $0) }
    }
}
#endif
