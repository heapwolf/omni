// src/lib/components/android/TapGesture+Android.swift
#if os(Android)
import Foundation
import CAndroid

@MainActor private var tapHandlers: [UnsafeMutableRawPointer: EventHandlerVoid] = [:]

extension TapGestureView {
    @MainActor public func makeNative() -> NativeView {
        OmniAndroid.makeContainer()
    }

    @MainActor public func updateNative(_ view: NativeView) {
        if let existing = tapHandlers[view] {
            // Bound already: point the live listener at the newest closure.
            existing.action = action
            return
        }

        let handler = EventHandlerVoid(action)
        tapHandlers[view] = handler
        // setOnClickListener also makes the view clickable and focusable, so
        // there is nothing else to set for it to start receiving touches.
        omni_jni_set_on_click(OmniAndroid.env, view, Unmanaged.passUnretained(handler).toOpaque())
    }

    @MainActor public func insertChild(_ child: NativeView, into parent: NativeView) {
        OmniAndroid.addChild(child, to: parent)
    }
}
#endif
