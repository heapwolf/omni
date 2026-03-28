#if os(Android)
import Foundation
import CAndroid

@MainActor private var textEditorHandlerRegistry: [UnsafeMutableRawPointer: EventHandlerString] = [:]

extension TextEditor {
    @MainActor public func makeNative() -> NativeView {
        let env = OmniAndroid.env

        // On Android, a TextEditor is an EditText configured for multi-line
        let view = OmniAndroid.createView(env, "android/widget/EditText")

        // Set up multi-line properties (Gravity.TOP prevents text from centering vertically)
        omni_jni_set_multiline(env, view)
        omni_jni_set_gravity(env, view, 48) // 48 = GRAVITY_TOP
        omni_jni_call_void_method_int(env, view, "setMinLines", 4)
        AndroidExpansion.claim(view, horizontal: true, vertical: false)

        return view
    }

    @MainActor public func unmountNative(_ view: NativeView) {
        omni_jni_detach_text_field(OmniAndroid.env, view)
        textEditorHandlerRegistry.removeValue(forKey: view)
    }

    @MainActor public func updateNative(_ view: NativeView) {
        let binding = text
        syncTextField(view, to: binding.wrappedValue, handlers: &textEditorHandlerRegistry) { newText in
            binding.wrappedValue = newText
        }
    }
}
#endif
