// src/lib/components/android/Divider+Android.swift
#if os(Android)
import Foundation
import CAndroid

extension Divider {
    @MainActor public func makeNative() -> NativeView {
        let env = OmniAndroid.env

        // A plain View with a background colour is the idiomatic Android
        // separator; there is no dedicated divider widget.
        let view = OmniAndroid.createView(env, "android/view/View")

        // Approximates android.R.color.darker_gray.
        omni_jni_set_background_color(env, view, 255, 170, 170, 170)

        let thickness: Int32 = 1
        omni_jni_set_layout_params(env, view,
                                   resolvedIsVertical ? thickness : Int32(MATCH_PARENT),
                                   resolvedIsVertical ? Int32(MATCH_PARENT) : thickness)

        // Spanning is a claim on the cross axis: a stack that hands its
        // children WRAP_CONTENT would otherwise leave the rule 1px long.
        AndroidExpansion.claim(view, horizontal: !resolvedIsVertical, vertical: resolvedIsVertical)
        return view
    }

    @MainActor public func updateNative(_ view: NativeView) {
        // Nothing varies at runtime; thickness and colour are set on creation.
    }
}
#endif
