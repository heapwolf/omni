#if os(Android)
import Foundation
import CAndroid

extension Image {
    @MainActor public func makeNative() -> NativeView {
        let env = OmniAndroid.env
        let view = OmniAndroid.createView(env, "android/widget/ImageView")
        // Resizable, it takes the space offered, as iOS's low hugging does, rather
        // than its picture's own size: a card's artwork drew small in its frame.
        if isResizable { AndroidExpansion.claim(view, horizontal: true, vertical: true) }
        return view
    }

    @MainActor public func updateNative(_ view: NativeView) {
        let env = OmniAndroid.env
        omni_jni_set_image_scale(env, view, isResizable && contentMode == .fill ? 1 : 0)

        if let data {
            let bytes = [UInt8](data)
            bytes.withUnsafeBufferPointer { buffer in
                omni_jni_set_image_bytes(env, view, buffer.baseAddress, Int32(buffer.count))
            }
        } else {
            // Pass isSystem as a C-compatible integer (1 = true, 0 = false)
            omni_jni_set_image(env, view, name, isSystem ? 1 : 0)
        }
    }
}
#endif
