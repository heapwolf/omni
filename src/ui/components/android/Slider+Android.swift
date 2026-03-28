#if os(Android)
import Foundation
import CAndroid

@MainActor private var sliderHandlerRegistry: [UnsafeMutableRawPointer: EventHandlerFloat] = [:]

extension Slider {
    @MainActor public func makeNative() -> NativeView {
        let env = OmniAndroid.env

        let view = OmniAndroid.createView(env, "android/widget/SeekBar")

        // Increase resolution of the Android integer-based SeekBar to 10,000 steps
        // (We already have omni_jni_call_void_method_int from JNIBridge.c)
        omni_jni_call_void_method_int(env, view, "setMax", 10000)
        AndroidExpansion.claim(view, horizontal: true, vertical: false)

        return view
    }

    @MainActor public func updateNative(_ view: NativeView) {
        let env = OmniAndroid.env

        let binding = value
        let minVal = range.lowerBound
        let maxVal = range.upperBound
        let current = binding.wrappedValue

        // Map Swift Double to Android 0-10,000 integer range
        let progress = Int32(max(0, min(10000, ((current - minVal) / (maxVal - minVal)) * 10000)))
        omni_jni_call_void_method_int(env, view, "setProgress", progress)

        // Attach Listener
        if sliderHandlerRegistry[view] == nil {
            let handler = EventHandlerFloat { prog in
                // Map Android 0-10,000 integer back to Swift Double
                let scaledValue = minVal + (Double(prog) / 10000.0) * (maxVal - minVal)
                binding.wrappedValue = scaledValue
            }
            sliderHandlerRegistry[view] = handler

            let ptr = UnsafeMutableRawPointer(Unmanaged.passUnretained(handler).toOpaque())
            // This C-method was provided in your JNIBridge code earlier!
            omni_jni_attach_on_seek_bar_change(env, view, ptr)
        }
    }
}
#endif
