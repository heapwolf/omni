// src/lib/android/VStack+Android.swift
#if os(Android)
import Foundation
import CAndroid

extension VStack {
    @MainActor public func makeNative() -> NativeView {
        let env = OmniAndroid.env
        return OmniAndroid.createView(env, "android/widget/LinearLayout")
    }

    @MainActor public func updateNative(_ view: NativeView) {
        let env = OmniAndroid.env

        // 1. Set Orientation to VERTICAL (1)
        // (Utilizing the generic method_int caller we already have in JNIBridge)
        omni_jni_call_void_method_int(env, view, "setOrientation", 1)

        // 2. Set Cross-Axis Alignment (Gravity)
        let gravity: Int32
        switch alignment {
        case .leading: gravity = 3 // GRAVITY_LEFT
        case .center: gravity = 1 // GRAVITY_CENTER_HORIZONTAL
        case .trailing: gravity = 5 // GRAVITY_RIGHT
        }
        omni_jni_set_gravity(env, view, gravity)

        // 3. Set Spacing (Gap between children)
        if resolvedSpacing > 0 {
            omni_jni_set_linear_layout_spacing(env, view, Int32(resolvedSpacing))
        }
    }

    @MainActor public func insertChild(_ child: NativeView, into parent: NativeView) {
        let env = OmniAndroid.env

        omni_jni_add_view(env, parent, child)

        AndroidExpansion.narrowSpacer(child, toVertical: true)
        omni_jni_set_stack_child(env, child, 1,
                                 AndroidExpansion.wants(child, horizontal: true) ? 1 : 0,
                                 AndroidExpansion.wants(child, horizontal: false) ? 1 : 0)
        AndroidExpansion.carry(from: child, to: parent)
    }
}
#endif
