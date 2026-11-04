// src/ui/AppleSignIn.swift
// Sign in with Apple: the system's own sheet (ASAuthorizationController), on
// iOS and macOS. It hands back Apple's identity token, a JWT for the app's
// server to check against Apple's keys, and the person's name and email the
// first time they share them. Nowhere else: Android has no Apple account to
// sign in with, so `isAvailable` is false there and the app offers others.
//
// Needs the com.apple.developer.applesignin entitlement: the App ID's Sign in
// with Apple capability, through the provisioning profile, on a device; omni
// gives it to Simulator builds when omni.json says "signInWithApple": true.

import Foundation
#if os(iOS) || os(macOS)
import AuthenticationServices
#endif
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

@MainActor public enum AppleSignIn {
    public struct Credential: Sendable, Equatable {
        /// Apple's identity token (a JWT). Its `nonce` claim is the nonce asked with.
        public let identityToken: String
        /// Single use, five minutes: the server can exchange it with Apple for
        /// a refresh token (to revoke when the account is deleted).
        public let authorizationCode: String?
        /// Apple's stable id for this person and this app's team.
        public let user: String
        /// Only the first time the person signs in to the app; nil after.
        public let givenName: String?
        public let familyName: String?
        public let email: String?

        public init(identityToken: String, authorizationCode: String?, user: String,
                    givenName: String? = nil, familyName: String? = nil, email: String? = nil) {
            self.identityToken = identityToken
            self.authorizationCode = authorizationCode
            self.user = user
            self.givenName = givenName
            self.familyName = familyName
            self.email = email
        }
    }

    public enum Failure: Error, Equatable {
        /// No Sign in with Apple here (Android, Linux, Windows).
        case unsupported
        /// Another is open.
        case busy
        /// Apple refused, or the app lacks the entitlement. Its description, for logs.
        case failed(String)
    }

    /// Whether this platform has Sign in with Apple.
    public static var isAvailable: Bool {
        #if os(iOS) || os(macOS)
        true
        #else
        false
        #endif
    }

    /// Shows Apple's sheet and waits: the credential, or nil when the person
    /// closes it. `nonce` comes back in the token's `nonce` claim, as given:
    /// the server's way to know the token is for this sign-in.
    public static func request(nonce: String, name: Bool = true, email: Bool = true) async throws -> Credential? {
        guard isAvailable else { throw Failure.unsupported }
        guard pending == nil else { throw Failure.busy }
        return try await withCheckedThrowingContinuation { continuation in
            pending = continuation
            start(nonce: nonce, name: name, email: email)
        }
    }

    static var pending: CheckedContinuation<Credential?, any Error>?

    static func finish(_ result: Result<Credential?, any Error>) {
        guard let done = pending else { return }
        pending = nil
        #if os(iOS) || os(macOS)
        controller = nil
        #endif
        done.resume(with: result)
    }

    #if os(iOS) || os(macOS)
    static var controller: ASAuthorizationController?
    static let delegate = Delegate()

    static func start(nonce: String, name: Bool, email: Bool) {
        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = (name ? [.fullName] : []) + (email ? [.email] : [])
        request.nonce = nonce
        let made = ASAuthorizationController(authorizationRequests: [request])
        made.delegate = delegate
        made.presentationContextProvider = delegate
        controller = made
        made.performRequests()
    }

    /// What Apple's sheet gave, as a credential; nil if it isn't one.
    nonisolated static func credential(_ authorization: ASAuthorization) -> Credential? {
        guard let apple = authorization.credential as? ASAuthorizationAppleIDCredential,
              let token = apple.identityToken.flatMap({ String(data: $0, encoding: .utf8) }) else { return nil }
        return Credential(identityToken: token,
                          authorizationCode: apple.authorizationCode.flatMap { String(data: $0, encoding: .utf8) },
                          user: apple.user, givenName: apple.fullName?.givenName, familyName: apple.fullName?.familyName,
                          email: apple.email)
    }

    final class Delegate: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
        func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
            let made = AppleSignIn.credential(authorization)
            MainActor.assumeIsolated {
                if let made { AppleSignIn.finish(.success(made)) }
                else { AppleSignIn.finish(.failure(Failure.failed("no identity token"))) }
            }
        }

        func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: any Error) {
            let cancelled = (error as? ASAuthorizationError)?.code == .canceled
            let description = String(describing: error)
            MainActor.assumeIsolated {
                AppleSignIn.finish(cancelled ? .success(nil) : .failure(Failure.failed(description)))
            }
        }

        func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
            MainActor.assumeIsolated {
                #if os(iOS)
                UIApplication.shared.connectedScenes
                    .compactMap { ($0 as? UIWindowScene)?.windows.first { $0.isKeyWindow } }.first ?? ASPresentationAnchor()
                #else
                NSApp.keyWindow ?? NSApp.windows.first ?? ASPresentationAnchor()
                #endif
            }
        }
    }
    #else
    static func start(nonce: String, name: Bool, email: Bool) {
        finish(.failure(Failure.unsupported))
    }
    #endif
}
