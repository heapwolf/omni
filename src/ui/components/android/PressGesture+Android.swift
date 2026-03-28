// src/lib/components/android/PressGesture+Android.swift
#if os(Android)
import Foundation
import CAndroid

/// Each press view's handler. OmniEventBridge.attachOnPress sends 1 when the
/// touch goes down or comes back inside, 0 when it leaves or is cancelled (a
/// scroll took it), and 2 for a release inside. Kept for the view's life, as
/// tap handlers are: a view removed mid-touch is still sent ACTION_CANCEL.
@MainActor private var pressHandlers: [UnsafeMutableRawPointer: EventHandlerInt] = [:]

extension PressGestureView {
    @MainActor public func makeNative() -> NativeView {
        OmniAndroid.makeContainer()
    }

    @MainActor public func updateNative(_ view: NativeView) {
        let onPressChange = self.onPressChange
        let action = self.action
        let respond: (Int) -> Void = { phase in
            onPressChange(phase == 1)
            if phase == 2 { action() }
        }
        if let existing = pressHandlers[view] {
            // Bound already: point the live listener at the newest closures.
            existing.action = respond
            return
        }
        let handler = EventHandlerInt(respond)
        pressHandlers[view] = handler
        omni_jni_set_on_press(OmniAndroid.env, view, Unmanaged.passUnretained(handler).toOpaque())
    }

    @MainActor public func insertChild(_ child: NativeView, into parent: NativeView) {
        OmniAndroid.addChild(child, to: parent)
    }
}
#endif
