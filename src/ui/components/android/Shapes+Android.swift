#if os(Android)
import Foundation
import CAndroid

extension ClipModifierView {
    @MainActor public func makeNative() -> NativeView {
        let env = OmniAndroid.env
        // FrameLayout serves as an excellent clipping container
        return OmniAndroid.createView(env, "android/widget/FrameLayout")
    }

    @MainActor public func updateNative(_ view: NativeView) {
        let env = OmniAndroid.env
        // Pass radius and boolean (1/0) to the Java bridge
        omni_jni_set_clip_radius(env, view, Float(radius), isCircular ? 1 : 0)
    }

}
#endif
