// iOS: asks with UserNotifications, then registers with APNs. The token comes to OmniUI's app
// delegate (RemoteNotifications). Its environment is the build's: a development provisioning
// profile's aps-environment is APNs' sandbox; TestFlight and the App Store embed no profile in
// the way, and are production.

#if os(iOS)
import Foundation
import UIKit
import UserNotifications
import OmniUI

func platformRegister(prompting: Bool) async throws -> PushToken {
    let center = UNUserNotificationCenter.current()
    switch await center.notificationSettings().authorizationStatus {
    case .notDetermined:
        guard prompting else { throw PushError.notAsked }
        guard (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) == true else {
            throw PushError.denied
        }
    case .denied:
        throw PushError.denied
    default:
        break
    }
    let token = try await deviceToken()
    return PushToken(token: token.map { String(format: "%02x", $0) }.joined(), provider: "apns",
                     environment: apnsEnvironment())
}

/// Registers, and waits for the delegate's answer: 30 seconds at most.
private func deviceToken() async throws -> Data {
    try await withCheckedThrowingContinuation { (done: CheckedContinuation<Data, any Error>) in
        let once = Once()
        RemoteNotifications.next { outcome in
            guard once.claim() else { return }
            switch outcome {
            case .success(let token): done.resume(returning: token)
            case .failure(let error): done.resume(throwing: PushError.unavailable(error.localizedDescription))
            }
        }
        DispatchQueue.main.async { UIApplication.shared.registerForRemoteNotifications() }
        DispatchQueue.global().asyncAfter(deadline: .now() + 30) {
            guard once.claim() else { return }
            done.resume(throwing: PushError.unavailable("APNs didn't answer."))
        }
    }
}

private final class Once: @unchecked Sendable {
    private let lock = NSLock()
    private var claimed = false
    func claim() -> Bool { lock.withLock { defer { claimed = true }; return !claimed } }
}

/// The build's APNs environment, from its embedded provisioning profile's aps-environment.
private func apnsEnvironment() -> String {
    #if targetEnvironment(simulator)
    return "sandbox"
    #else
    guard let path = Bundle.main.path(forResource: "embedded", ofType: "mobileprovision"),
          let data = FileManager.default.contents(atPath: path),
          let start = data.range(of: Data("<?xml".utf8)),
          let end = data.range(of: Data("</plist>".utf8), in: start.lowerBound..<data.endIndex),
          let plist = try? PropertyListSerialization.propertyList(from: data[start.lowerBound..<end.upperBound],
                                                                  format: nil) as? [String: Any],
          let entitlements = plist["Entitlements"] as? [String: Any],
          entitlements["aps-environment"] as? String == "development" else { return "production" }
    return "sandbox"
    #endif
}
#endif
