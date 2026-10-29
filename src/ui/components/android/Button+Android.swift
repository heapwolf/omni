// src/lib/components/android/Button+Android.swift
#if os(Android)
import Foundation
import CAndroid


@MainActor private var clickHandlers: [UnsafeMutableRawPointer: EventHandlerVoid] = [:]

extension SystemButtonPrimitive {
    @MainActor
    public func makeNative() -> NativeView {
        let env = OmniAndroid.env
        let view = OmniAndroid.createView(env, "android/widget/Button")

        omni_jni_call_void_method_int(env, view, "setBackgroundResource", 0)

        omni_jni_call_void_method_int(env, view, "setMinWidth", 0)
        omni_jni_call_void_method_int(env, view, "setMinHeight", 0)

        OmniAndroid.setTextColor(view, .primaryText)

        return view
    }

    @MainActor
    public func updateNative(_ view: NativeView) {
        let env = OmniAndroid.env

        omni_jni_call_void_method_string(env, view, "setText", title)

        if let color = foregroundColor {
            let c = color.rgbaComponents
            omni_jni_set_text_color(env, view,
                Int32(c.a * 255), Int32(c.r * 255), Int32(c.g * 255), Int32(c.b * 255))
        }

        if let existing = clickHandlers[view] {
            // Bound already: point the live listener at the newest closure.
            existing.action = action
            return
        }

        let handler = EventHandlerVoid(action)
        clickHandlers[view] = handler
        omni_jni_set_on_click(env, view, Unmanaged.passUnretained(handler).toOpaque())
    }
}
#endif
