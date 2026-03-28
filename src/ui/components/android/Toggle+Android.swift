#if os(Android)
import Foundation
import CAndroid

@MainActor private var toggleHandlerRegistry: [UnsafeMutableRawPointer: EventHandlerBool] = [:]

extension Toggle {
    @MainActor public func makeNative() -> NativeView {
        let env = OmniAndroid.env
        // "android/widget/Switch" is the standard toggle on Android.
        let view = OmniAndroid.createView(env, "android/widget/Switch")
        AndroidExpansion.claim(view, horizontal: true, vertical: false)
        return view
    }

    @MainActor public func updateNative(_ view: NativeView) {
        let env = OmniAndroid.env

        let binding = isOnBinding

        // 1. Set Title (Switch inherits from TextView on Android, so we can use setText)
        omni_jni_call_void_method_string(env, view, "setText", title)

        // 2. Set State programmatically
        omni_jni_set_checked(env, view, binding.wrappedValue ? 1 : 0)

        // 3. Bind Native Change Event
        let handler = EventHandlerBool { isChecked in
            binding.wrappedValue = isChecked
        }
        toggleHandlerRegistry[view] = handler

        let ptr = UnsafeMutableRawPointer(Unmanaged.passUnretained(handler).toOpaque())
        omni_jni_attach_on_checked(env, view, ptr)
    }
}
#endif
