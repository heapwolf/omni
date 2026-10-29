#if os(Android)
import Foundation
import CAndroid

extension HStack {
    @MainActor public func makeNative() -> NativeView {
        let env = OmniAndroid.env
        let view = OmniAndroid.createView(env, "android/widget/LinearLayout")

        // 0 = HORIZONTAL. Set once during creation to avoid JNI overhead during updates.
        omni_jni_call_void_method_int(env, view, "setOrientation", 0)

        return view
    }

    @MainActor public func updateNative(_ view: NativeView) {
        let env = OmniAndroid.env

        // Apply Alignment
        let gravity: Int32
        switch alignment {
        case .top: gravity = 48    // GRAVITY_TOP
        case .center: gravity = 16 // GRAVITY_CENTER_VERTICAL
        case .bottom: gravity = 80 // GRAVITY_BOTTOM
        }
        omni_jni_set_gravity(env, view, gravity)

        // Apply Spacing (Utilizes the exact same JNI bridge we built for VStack!)
        if resolvedSpacing > 0 {
            omni_jni_set_linear_layout_spacing(env, view, Int32(resolvedSpacing))
        }
    }

    @MainActor public func insertChild(_ child: NativeView, into parent: NativeView) {
        let env = OmniAndroid.env
        omni_jni_add_view(env, parent, child)

        AndroidExpansion.narrowSpacer(child, toVertical: false)
        omni_jni_set_stack_child(env, child, 0,
                                 AndroidExpansion.wants(child, horizontal: false) ? 1 : 0,
                                 AndroidExpansion.wants(child, horizontal: true) ? 1 : 0)
        AndroidExpansion.settle(child, vertical: false)
        AndroidExpansion.carry(from: child, to: parent)
    }
}
#endif
