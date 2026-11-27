// Android: src/ui/android/OmniPush.java, through JNIBridge.c's omni_jni_push_token. It blocks
// (the permission prompt, a REST call, a request to Play services), so it runs on a thread of its
// own. Its answer is "token:<token>", "denied", "not-asked", or "unavailable:<why>".

#if os(Android)
import Foundation
import CAndroid

func platformRegister(prompting: Bool) async throws -> PushToken {
    let answer: String = await withCheckedContinuation { done in
        Thread {
            guard let raw = omni_jni_push_token(prompting ? 1 : 0) else {
                return done.resume(returning: "unavailable:no answer")
            }
            defer { free(raw) }
            done.resume(returning: String(cString: raw))
        }.start()
    }
    if answer.hasPrefix("token:") {
        return PushToken(token: String(answer.dropFirst("token:".count)), provider: "fcm", environment: nil)
    }
    switch answer {
    case "denied": throw PushError.denied
    case "not-asked": throw PushError.notAsked
    default: throw PushError.unavailable(String(answer.drop(while: { $0 != ":" }).dropFirst()))
    }
}
#endif
