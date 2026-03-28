#if os(Android)
import Foundation
import CAndroid

@MainActor private var scrollStateRegistry: [UnsafeMutableRawPointer: AndroidScrollState] = [:]

@MainActor private final class AndroidScrollState {
    let handler = EventHandlerFloat2 { _, _ in }
    var lastReported: Double = 0
}

extension ScrollView {
    @MainActor public func makeNative() -> NativeView {
        let env = OmniAndroid.env

        let className = axis == .horizontal ? "android/widget/HorizontalScrollView" : "android/widget/ScrollView"
        let view = OmniAndroid.createView(env, className)

        // Remove scrollbars for cleaner UI (matching SwiftUI default behavior).
        // These setters take a boolean, so they need the (Z)V bridge.
        omni_jni_call_void_method_bool(
            env, view,
            axis == .horizontal ? "setHorizontalScrollBarEnabled" : "setVerticalScrollBarEnabled",
            0)

        // A scroll view takes the space it is offered rather than the space its
        // content happens to need, or everything after it is pushed off screen.
        AndroidExpansion.claim(view, horizontal: true, vertical: true)
        return view
    }

    @MainActor public func unmountNative(_ view: NativeView) {
        scrollStateRegistry.removeValue(forKey: view)
    }

    @MainActor public func updateNative(_ view: NativeView) {
        let env = OmniAndroid.env
        let currentOffset = offset
        let horizontal = axis == .horizontal

        let state: AndroidScrollState
        if let existing = scrollStateRegistry[view] {
            state = existing
        } else {
            state = AndroidScrollState()
            scrollStateRegistry[view] = state
            let ptr = UnsafeMutableRawPointer(Unmanaged.passUnretained(state.handler).toOpaque())
            omni_jni_attach_on_scroll_change(env, view, ptr)
        }

        state.handler.action = { x, y in
            let value = Double(horizontal ? x : y)
            state.lastReported = value
            currentOffset?.wrappedValue = value
        }

        if let target = currentOffset?.wrappedValue, abs(target - state.lastReported) > 1 {
            state.lastReported = target
            if horizontal {
                omni_jni_scroll_to(env, view, Int32(target), 0)
            } else {
                omni_jni_scroll_to(env, view, 0, Int32(target))
            }
        }
    }

}
#endif
