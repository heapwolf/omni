// src/ui/OpenURL.swift
import Foundation
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#elseif os(Android)
import CAndroid
#endif

/// SwiftUI's OpenURLAction: `@Environment(\.openURL) var openURL`, then
/// `openURL(url)`. The system opens it unless a handler set with
/// `.environment(\.openURL, ...)` takes it.
public struct OpenURLAction {
    public enum Result { case handled, discarded, systemAction }

    let handler: (URL) -> Result

    public init(handler: @escaping (URL) -> Result) {
        self.handler = handler
    }

    @MainActor public func callAsFunction(_ url: URL) {
        guard case .systemAction = handler(url) else { return }
        Self.openWithSystem(url)
    }

    /// The browser, the store, the dialer: whichever app the platform picks.
    @MainActor static func openWithSystem(_ url: URL) {
        #if os(iOS)
        UIApplication.shared.open(url)
        #elseif os(macOS)
        NSWorkspace.shared.open(url)
        #elseif os(Android)
        omni_jni_send_text(OmniAndroid.env, "openURL", url.absoluteString)
        #else
        Omni.log("openURL is not supported on this platform yet: \(url)")
        #endif
    }
}

public struct OpenURLKey: EnvironmentKey {
    public static var defaultValue: OpenURLAction { OpenURLAction { _ in .systemAction } }
}

public extension EnvironmentValues {
    var openURL: OpenURLAction {
        get { self[OpenURLKey.self] }
        set { self[OpenURLKey.self] = newValue }
    }
}
