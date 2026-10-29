#if os(Android)
import Foundation
import CAndroid

extension Spacer {
    @MainActor public func makeNative() -> NativeView {
        let env = OmniAndroid.env
        let view = OmniAndroid.createView(env, "com/omni/OmniEventBridge$OmniSpacer")

        AndroidExpansion.markSpacer(view)
        AndroidExpansion.claim(view, horizontal: true, vertical: true)

        if let min = minLength {
            omni_jni_set_layout_params(env, view, Int32(min), Int32(min))
            // What it measures at, when not given an exact size.
            omni_jni_set_minimum_size(env, view, Float(min), Float(min))
        }
        return view
    }

    @MainActor public func updateNative(_ view: NativeView) {
        // Everything a Spacer has is fixed at construction.
    }
}
#endif
