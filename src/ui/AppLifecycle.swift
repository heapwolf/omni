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

    /// Whether the keyboard covers the app's root, instead of the root moving
    /// up out of its way (the default, so a form's field and button stay in
    /// view). Sheets are unaffected: they always move. Set by views marked
    /// `keyboardCoversContent(_:)`: true while any of them asks for it.
    public static var coversContent: Bool { !covering.isEmpty }

    /// The views asking for it, by the id each keeps.
    private static var covering: Set<UUID> = []

    /// iOS's root, told when it changes (Engine's OmniSceneDelegate).
    static var onCoversContentChange: ((Bool) -> Void)?

    static func cover(_ on: Bool, for view: UUID) {
        let was = coversContent
        if on { covering.insert(view) } else { covering.remove(view) }
        guard coversContent != was else { return }
        #if os(iOS)
        onCoversContentChange?(coversContent)
        #elseif os(Android)
        omni_jni_set_keyboard_covers(OmniAndroid.getEnv(), coversContent ? 1 : 0)
        #endif
    }
}

/// See `View.keyboardCoversContent(_:)`.
public struct KeyboardCoverView<Content: View>: View {
    let content: Content
    let covers: Bool
    @State private var id = UUID()

    public var body: some View {
        let id = self.id, covers = self.covers
        return content
            .onAppear { Keyboard.cover(covers, for: id) }
            .onChange(of: covers) { Keyboard.cover($0, for: id) }
            .onDisappear { Keyboard.cover(false, for: id) }
    }
}

public extension View {
    /// While `covers` and this view is on screen, the keyboard covers the
    /// app instead of the app moving up out of its way: for a screen whose
    /// bottom is a tab bar, which shouldn't ride up on the keyboard, and whose
    /// fields are near the top. iOS and Android; elsewhere nothing moves.
    func keyboardCoversContent(_ covers: Bool = true) -> some View {
        KeyboardCoverView(content: self, covers: covers)
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

/// Called as the window's insets change: the bars' heights, in points. A
/// screen drawing under the status bar (.ignoresSafeArea) reads it to keep
/// clear of it, as on iOS.
@_cdecl("omni_swift_safe_area")
public func omni_swift_safe_area(_ top: Float, _ bottom: Float) {
    MainActor.assumeIsolated {
        let insets = SafeArea(top: Double(top), bottom: Double(bottom))
        guard insets.top != Engine.safeArea.top || insets.bottom != Engine.safeArea.bottom else { return }
        Engine.safeArea = insets
        if let root = Engine.root { Engine.render(root) }
    }
}

/// Called from MainActivity's dispatchTouchEvent, for each finger going down.
@_cdecl("omni_swift_user_activity")
public func omni_swift_user_activity() {
    MainActor.assumeIsolated { Interactions.noteActivity() }
}
#endif
