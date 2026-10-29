// src/ui/Appearance.swift
// Light and dark: the scheme on screen, the app's preference, and what follows
// when either changes.
//
// A colour that differs between the two is `Color(light:dark:)`. It resolves
// against `Appearance.current` when a native view takes it, so a change of
// scheme renders the whole tree again (open sheets with it, from their
// presenters): every view sets its colours afresh, CGColor-backed ones
// (borders, shadows, shapes) included, which a dynamic UIColor alone would
// leave as they were.
//
// The preference is also applied to the window, so the system's own UI (alerts,
// the keyboard, the status bar, a sheet's chrome) matches the app's.

import Foundation

#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#elseif os(Android)
import CAndroid
#endif

/// SwiftUI's ColorScheme.
public enum ColorScheme: Sendable, Equatable, CaseIterable {
    case light, dark
}

public extension EnvironmentValues {
    /// The scheme on screen. Every view renders again when it changes, so a
    /// view reading this always has the current one.
    var colorScheme: ColorScheme { Appearance.current }
}

public enum Appearance {
    /// What is on screen: the preference, else the system's.
    nonisolated(unsafe) public private(set) static var current: ColorScheme = .light
    /// The app's choice; nil follows the system.
    nonisolated(unsafe) public private(set) static var preferred: ColorScheme?

    /// Follows `scheme`, or the system with nil. Renders everything again if
    /// that changes what is on screen.
    @MainActor public static func prefer(_ scheme: ColorScheme?) {
        preferred = scheme
        applyToWindows()
        refresh()
    }

    /// A window is up: it takes the preference, and the first render, done
    /// before any window existed, is redone if the system is dark.
    @MainActor static func windowDidAppear() {
        applyToWindows()
        refresh()
    }

    /// The system's scheme changed, or a window was created.
    @MainActor static func refresh() {
        let next = preferred ?? system
        #if os(Android)
        omni_jni_set_dark_scheme(OmniAndroid.env, next == .dark ? 1 : 0)
        #endif
        guard next != current else { return }
        current = next
        if let root = Engine.root { Engine.render(root) }
    }

    /// The system's own, whatever the app prefers: a window's traits carry
    /// the override, the screen's do not.
    @MainActor static var system: ColorScheme {
        #if os(iOS)
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        let traits = scene?.screen.traitCollection ?? UIScreen.main.traitCollection
        return traits.userInterfaceStyle == .dark ? .dark : .light
        #elseif os(macOS)
        let match = NSApplication.shared.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua])
        return match == .darkAqua ? .dark : .light
        #elseif os(Android)
        return omni_jni_is_night_mode(OmniAndroid.env) != 0 ? .dark : .light
        #else
        return .light
        #endif
    }

    @MainActor private static func applyToWindows() {
        #if os(iOS)
        let style: UIUserInterfaceStyle = preferred == .dark ? .dark : preferred == .light ? .light : .unspecified
        for scene in UIApplication.shared.connectedScenes {
            (scene as? UIWindowScene)?.windows.forEach { $0.overrideUserInterfaceStyle = style }
        }
        (UIApplication.shared.delegate as? Del)?.w?.overrideUserInterfaceStyle = style
        #elseif os(macOS)
        NSApplication.shared.appearance = preferred.map { NSAppearance(named: $0 == .dark ? .darkAqua : .aqua) } ?? nil
        #endif
    }
}

public extension Color {
    /// One colour in light, another in dark.
    init(light: Color, dark: Color) {
        self = .adaptive(light: light, dark: dark)
    }

    /// This colour in the scheme on screen: an adaptive one's half, else itself.
    var resolved: Color {
        if case .adaptive(let light, let dark) = self {
            return (Appearance.current == .dark ? dark : light).resolved
        }
        return self
    }
}

public extension View {
    /// SwiftUI's: the scheme the app is shown in, nil for the system's. Applied
    /// a turn later, as a change of scheme renders everything again.
    func preferredColorScheme(_ scheme: ColorScheme?) -> Self {
        if scheme != Appearance.preferred {
            DispatchQueue.main.async { MainActor.assumeIsolated { Appearance.prefer(scheme) } }
        }
        return self
    }
}

#if os(Android)
/// The system's light or dark changed; see OmniEventBridge.RootHost.
@_cdecl("omni_swift_appearance_changed")
public func omni_swift_appearance_changed() {
    MainActor.assumeIsolated { Appearance.refresh() }
}
#endif
