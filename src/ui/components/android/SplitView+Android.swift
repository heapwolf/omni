#if os(Android)
import Foundation
import CAndroid

extension SplitView {
    @MainActor public func makeNative() -> NativeView {
        let env = OmniAndroid.env

        let view = OmniAndroid.createView(env, "android/widget/LinearLayout")

        // 0 = HORIZONTAL (side-by-side), 1 = VERTICAL (top-to-bottom)
        omni_jni_call_void_method_int(env, view, "setOrientation", isVertical ? 0 : 1)

        return view
    }

    @MainActor public func updateNative(_ view: NativeView) {
        let env = OmniAndroid.env
        omni_jni_call_void_method_int(env, view, "setOrientation", isVertical ? 0 : 1)
    }

    @MainActor public func insertChild(_ child: NativeView, into parent: NativeView) {
        let env = OmniAndroid.env

        omni_jni_add_view(env, parent, child)

        // Apply layout weights so the panes divide the space equally (mimicking iOS fillEqually)
        // Note: -1 translates to MATCH_PARENT in Android
        if isVertical {
            // Side-by-side: width = 0, height = MATCH_PARENT, weight = 1.0
            omni_jni_set_linear_layout_params(env, child, 0, -1, 1.0)
        } else {
            // Top-to-bottom: width = MATCH_PARENT, height = 0, weight = 1.0
            omni_jni_set_linear_layout_params(env, child, -1, 0, 1.0)
        }
    }
}
#endif
