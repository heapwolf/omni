// src/ui/WebAuthentication.swift
// A partner's page (a bank link, a card payment) in the system's sign-in
// browser: ASWebAuthenticationSession on iOS and macOS, a Custom Tab on
// Android. The page runs in the browser's own process, so the app can't read
// or change it, and the browser's autofill works. The app sees only the URL
// the page finishes at, on the app's own scheme.

import Foundation
#if os(iOS) || os(macOS)
import AuthenticationServices
#endif
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#elseif os(Android)
import CAndroid
#endif

@MainActor public enum WebAuthentication {
    public enum Failure: Error, Equatable {
        /// No system browser sheet here (Linux, Windows).
        case unsupported
        /// Another is open.
        case busy
        case couldNotStart
    }

    /// Opens `url` and waits. The URL the page finishes at, whose scheme is
    /// `callbackScheme` (the app's, from omni.json's urlSchemes); nil when the
    /// person closes it first.
    public static func open(_ url: URL, callbackScheme: String) async throws -> URL? {
        guard pending == nil else { throw Failure.busy }
        return try await withCheckedThrowingContinuation { continuation in
            pending = Pending(scheme: callbackScheme.lowercased(), continuation: continuation)
            start(url, callbackScheme: callbackScheme)
        }
    }

    struct Pending {
        let scheme: String
        let continuation: CheckedContinuation<URL?, any Error>
    }

    static var pending: Pending?

    static func finish(_ result: Result<URL?, any Error>) {
        guard let done = pending else { return }
        pending = nil
        #if os(iOS) || os(macOS)
        session = nil
        #elseif os(Android)
        if let returned { AppLifecycle.removeObserver(returned) }
        returned = nil
        #endif
        done.continuation.resume(with: result)
    }

    /// A deep link that finishes the open session, if any. DeepLink asks
    /// before the app's handler sees it.
    static func take(_ url: URL) -> Bool {
        guard let pending, url.scheme?.lowercased() == pending.scheme else { return false }
        finish(.success(url))
        return true
    }

    #if os(iOS) || os(macOS)
    static var session: ASWebAuthenticationSession?
    static let anchor = Anchor()

    final class Anchor: NSObject, ASWebAuthenticationPresentationContextProviding {
        func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
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

    static func start(_ url: URL, callbackScheme: String) {
        let made = ASWebAuthenticationSession(url: url, callbackURLScheme: callbackScheme) { callback, error in
            MainActor.assumeIsolated {
                if let error = error as? ASWebAuthenticationSessionError, error.code == .canceledLogin {
                    finish(.success(nil))
                } else if let error {
                    finish(.failure(error))
                } else {
                    finish(.success(callback))
                }
            }
        }
        made.presentationContextProvider = anchor
        // Shares the browser's cookies, so a partner's saved sign-in works.
        made.prefersEphemeralWebBrowserSession = false
        session = made
        if !made.start() { finish(.failure(Failure.couldNotStart)) }
    }
    #elseif os(Android)
    static var returned: AppLifecycle.ObserverID?

    /// A Custom Tab gives no word when it's closed: back in the foreground
    /// with no deep link soon after means it was.
    static func start(_ url: URL, callbackScheme: String) {
        var left = false
        returned = AppLifecycle.addObserver { phase in
            if phase == .background { left = true; return }
            guard left else { return }
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 800_000_000)
                if WebAuthentication.pending != nil { finish(.success(nil)) }
            }
        }
        omni_jni_send_text(OmniAndroid.env, "openCustomTab", url.absoluteString)
    }
    #else
    static func start(_ url: URL, callbackScheme: String) {
        finish(.failure(Failure.unsupported))
    }
    #endif
}
