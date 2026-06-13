// src/ui/AppLifecycle.swift
// The app going to the background and coming back, on every platform. For
// what an app does then: locking a session, saving, flushing a queue. SwiftUI
// has scenePhase for views; this is for the code behind them, which has no
// environment to read.
import Foundation
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#elseif os(Android)
import CAndroid
#endif

@MainActor public enum AppLifecycle {
    public enum Phase: Sendable, Equatable {
        /// On screen, in use.
        case foreground
        /// Not on screen: another app is in front, the screen is off, or the
        /// app is hidden.
        case background
    }

    /// Where the app is now. The foreground until it first leaves.
    public private(set) static var phase: Phase = .foreground

    /// A registration, for removeObserver.
    public struct ObserverID: Hashable, Sendable { let raw: Int }

    private static var observers: [(id: ObserverID, handler: (Phase) -> Void)] = []
    private static var nextID = 0

    /// Calls `handler` each time the phase changes, on the main actor, until
    /// removed. Not for the phase the app starts in.
    ///   iOS      the scene entering the background and the foreground
    ///   macOS    the app hidden and shown again
    ///   Android  the activity stopped and started
    ///   Linux and Windows report nothing yet.
    @discardableResult
    public static func addObserver(_ handler: @escaping (Phase) -> Void) -> ObserverID {
        nextID += 1
        let id = ObserverID(raw: nextID)
        observers.append((id, handler))
        #if os(macOS)
        HideMonitor.install()
        #endif
        return id
    }

    public static func removeObserver(_ id: ObserverID) {
        observers.removeAll { $0.id == id }
    }

    /// From each platform's callback. A repeat is dropped: Android starts the
    /// activity at launch, which is no change.
    static func enter(_ new: Phase) {
        guard new != phase else { return }
        phase = new
        for observer in observers { observer.handler(new) }
    }

    /// Runs `work` after the app has gone to the background, with the time to
    /// finish it. iOS suspends a backgrounded app within seconds unless it asks
    /// for that time, and gives a few seconds. Elsewhere the process keeps
    /// running, and this just runs it.
    public static func finishInBackground(_ work: @escaping @MainActor () async -> Void) {
        #if os(iOS)
        var task = UIBackgroundTaskIdentifier.invalid
        task = UIApplication.shared.beginBackgroundTask { UIApplication.shared.endBackgroundTask(task) }
        Task {
            await work()
            UIApplication.shared.endBackgroundTask(task)
        }
        #else
        Task { await work() }
        #endif
    }
}

/// The on-screen keyboard.
@MainActor public enum Keyboard {
    /// Puts the keyboard away, and the field typing into it loses focus. For a
    /// screen that covers the app, a lock say: a field left focused under it
    /// would still take typing.
    public static func dismiss() {
        #if os(iOS)
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        #elseif os(macOS)
        // No NSApp without an app: a test, or a tool, has nothing to dismiss.
        guard let app = NSApp else { return }
        for window in app.windows { window.makeFirstResponder(nil) }
        #elseif os(Android)
        omni_jni_dismiss_keyboard(OmniAndroid.getEnv())
        #endif
    }
}

#if os(macOS)
/// A Mac app is in the background when it is hidden. Not when another app is
/// in front: a desktop app stays on screen behind it.
@MainActor enum HideMonitor {
    private static var installed = false

    static func install() {
        guard !installed else { return }
        installed = true
        let center = NotificationCenter.default
        center.addObserver(forName: NSApplication.didHideNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { AppLifecycle.enter(.background) }
        }
        center.addObserver(forName: NSApplication.didUnhideNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { AppLifecycle.enter(.foreground) }
        }
    }
}
#endif

#if os(Android)
/// Called from MainActivity's onStart (1) and onStop (0).
@_cdecl("omni_swift_lifecycle")
public func omni_swift_lifecycle(_ foreground: Int32) {
    MainActor.assumeIsolated { AppLifecycle.enter(foreground != 0 ? .foreground : .background) }
}

/// Called from MainActivity's dispatchTouchEvent, for each finger going down.
@_cdecl("omni_swift_user_activity")
public func omni_swift_user_activity() {
    MainActor.assumeIsolated { Interactions.noteActivity() }
}
#endif
