#if os(Android)
import Foundation
import CAndroid

@MainActor private var swipeHandlerRegistry: [UnsafeMutableRawPointer: [EventHandlerVoid]] = [:]

extension NativeSwipeModifierView {
    @MainActor public func makeNative() -> NativeView {
        let env = OmniAndroid.env

        // Notice it uses the custom class we just defined in Java!
        let view = OmniAndroid.createView(env, "com/omni/OmniEventBridge$OmniSwipeLayout")
        swipeHandlerRegistry[view] = []
        return view
    }

    @MainActor public func updateNative(_ view: NativeView) {
        let env = OmniAndroid.env

        // Wrap closures to survive crossing the C-boundary
        let leftHandler = EventHandlerVoid(onSwipeLeft)
        let rightHandler = EventHandlerVoid(onSwipeRight)

        swipeHandlerRegistry[view] = [leftHandler, rightHandler]

        let leftPtr = UnsafeMutableRawPointer(Unmanaged.passUnretained(leftHandler).toOpaque())
        let rightPtr = UnsafeMutableRawPointer(Unmanaged.passUnretained(rightHandler).toOpaque())

        omni_jni_attach_swipe_gestures(env, view, leftPtr, rightPtr)
    }

}
#endif
