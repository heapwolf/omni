#if os(Android)
import Foundation
import CAndroid

extension Image {
    @MainActor public func makeNative() -> NativeView {
        let env = OmniAndroid.env
        return OmniAndroid.createView(env, "android/widget/ImageView")
    }

    @MainActor public func updateNative(_ view: NativeView) {
        let env = OmniAndroid.env

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
