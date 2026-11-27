// Push notifications: this device's token, for the app's server to send to. Nothing more: a
// notification shows on its own, and a tap opens the app.
//
// iOS: APNs, the system's own. Android: Google Play services' push, with no Google library:
// platform APIs only (src/ui/android/OmniPush.java), built into the manifest when omni.json has
// `push`. Elsewhere: unavailable.

import Foundation

/// A device's push token, as the server needs it to send.
public struct PushToken: Sendable, Equatable {
    public let token: String
    /// "apns" or "fcm": which service the server sends through.
    public let provider: String
    /// APNs: "sandbox" for a development build, "production" for TestFlight and the App Store.
    /// nil for FCM, which has one.
    public let environment: String?

    public init(token: String, provider: String, environment: String?) {
        self.token = token
        self.provider = provider
        self.environment = environment
    }
}

public enum PushError: Error, Equatable {
    /// The customer said no, or turned notifications off in Settings.
    case denied
    /// Never asked, and `prompting` was false.
    case notAsked
    /// This device can't take pushes now (no Play services, no network, not configured), and why.
    case unavailable(String)
}

public enum Push {
    /// This device's token. With `prompting`, asks to notify if the customer hasn't been asked;
    /// the system remembers the answer, and never asks twice. Without it, a token only if they've
    /// already said yes: safe to call at every launch, to keep the server's token fresh.
    public static func register(prompting: Bool) async throws -> PushToken {
        try await platformRegister(prompting: prompting)
    }
}
