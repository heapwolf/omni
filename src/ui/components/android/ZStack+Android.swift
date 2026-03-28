#if os(Android)
import Foundation
import CAndroid

extension ZStack {
    @MainActor public func makeNative() -> NativeView {
        let env = OmniAndroid.env
        // FrameLayout stacks children.
        return OmniAndroid.createView(env, "android/widget/FrameLayout")
    }

    @MainActor public func updateNative(_ view: NativeView) {
        // Armed here, not insertChild: the outgoing view must still be attached.
        if isNavigationContainer, let direction = Transaction.navigationTransition {
            omni_jni_begin_navigation_transition(OmniAndroid.env, view,
                                                 direction == .push ? 1 : 0, 350)
            Transaction.navigationTransition = nil
        }
    }

    // Otherwise ZStack takes NativeComponent's default.
    @MainActor public func insertChild(_ child: NativeView, into parent: NativeView) {
        OmniAndroid.addChild(child, to: parent)

        omni_jni_resolve_child_size(OmniAndroid.env, child,
                                     AndroidExpansion.wants(child, horizontal: true) ? 1 : 0,
                                     AndroidExpansion.wants(child, horizontal: false) ? 1 : 0)

        AndroidExpansion.carry(from: child, to: parent)

        omni_jni_set_child_gravity(OmniAndroid.env, child, alignment.androidGravity)
    }
}
#endif
