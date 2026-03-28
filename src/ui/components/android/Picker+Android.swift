#if os(Android)
import Foundation
import CAndroid

@MainActor private var pickerHandlerRegistry: [UnsafeMutableRawPointer: EventHandlerInt] = [:]

extension NativePicker {
    @MainActor public func makeNative() -> NativeView {
        let env = OmniAndroid.env

        let view = OmniAndroid.createView(env, "android/widget/Spinner")

        // Populate options immediately
        let labelsStr = options.map { $0.label }.joined(separator: "|||")
        omni_jni_set_spinner_options(env, view, labelsStr)
        AndroidExpansion.claim(view, horizontal: true, vertical: false)

        return view
    }

    @MainActor public func updateNative(_ view: NativeView) {
        let env = OmniAndroid.env

        // 1. Sync Selection Index
        let currentSelection = selection.wrappedValue
        let selectedIndex = options.firstIndex(where: { $0.tag == currentSelection }) ?? 0
        omni_jni_call_void_method_int(env, view, "setSelection", Int32(selectedIndex))

        // 2. Attach Selection Listener
        if pickerHandlerRegistry[view] == nil {
            let binding = selection
            let opts = options // capture locally

            let handler = EventHandlerInt { idx in
                if idx >= 0 && idx < opts.count {
                    binding.wrappedValue = opts[idx].tag
                }
            }
            pickerHandlerRegistry[view] = handler

            let ptr = UnsafeMutableRawPointer(Unmanaged.passUnretained(handler).toOpaque())
            // (You previously defined attachOnItemSelected in Events+Android.java)
            omni_jni_attach_on_item_selected(env, view, ptr)
        }
    }
}
#endif
