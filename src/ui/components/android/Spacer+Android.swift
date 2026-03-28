#if os(Android)
import Foundation
import CAndroid

extension Spacer {
    @MainActor public func makeNative() -> NativeView {
        let env = OmniAndroid.env
        let view = OmniAndroid.createView(env, "android/view/View")

        AndroidExpansion.markSpacer(view)
        AndroidExpansion.claim(view, horizontal: true, vertical: true)

        if let min = minLength {
            omni_jni_set_layout_params(env, view, Int32(min), Int32(min))
        }
        return view
    }

    @MainActor public func updateNative(_ view: NativeView) {
        // Everything a Spacer has is fixed at construction.
    }
}
#endif
