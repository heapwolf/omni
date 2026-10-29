#if os(Android)
import Foundation
import CAndroid

@MainActor private var secureFieldHandlerRegistry: [UnsafeMutableRawPointer: EventHandlerString] = [:]

extension SecureField {
    @MainActor public func makeNative() -> NativeView {
        let env = OmniAndroid.env

        let view = OmniAndroid.createView(env, "android/widget/EditText")
        OmniAndroid.makePlainField(view)

        // 1. Set Placeholder (called "Hint" in Android)
        // Reusing the generic call_void_method_string from our bridge
        omni_jni_call_void_method_string(env, view, "setHint", title)

        // 2. Set to Secure/Password mode
        omni_jni_set_secure_text(env, view)
        AndroidExpansion.claim(view, horizontal: true, vertical: false)

        return view
    }

    @MainActor public func unmountNative(_ view: NativeView) {
        omni_jni_detach_text_field(OmniAndroid.env, view)
        secureFieldHandlerRegistry.removeValue(forKey: view)
    }

    @MainActor public func updateNative(_ view: NativeView) {
        let binding = text
        syncTextField(view, to: binding.wrappedValue, handlers: &secureFieldHandlerRegistry) { newText in
            binding.wrappedValue = newText
        }
    }
}
#endif
