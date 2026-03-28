#if os(Android)
import Foundation
import CAndroid

extension ProgressView {
    @MainActor public func makeNative() -> NativeView {
        let env = OmniAndroid.env

        // ProgressBar's horizontal style can only be chosen through a styled
        // constructor, which the JNI bridge does not expose yet — so a
        // determinate ProgressView renders as a determinate *circular* bar
        // here rather than a horizontal one.
        let view = OmniAndroid.createView(env, "android/widget/ProgressBar")
        omni_jni_call_void_method_bool(env, view, "setIndeterminate", fraction == nil ? 1 : 0)
        if fraction != nil {
            omni_jni_call_void_method_int(env, view, "setMax", 1000)
        }
        return view
    }

    @MainActor public func updateNative(_ view: NativeView) {
        guard let fraction else { return }
        omni_jni_call_void_method_int(OmniAndroid.env, view, "setProgress", Int32(fraction * 1000))
    }
}
#endif
