#if os(Android)
import Foundation
import CAndroid

// Keeps event handler objects alive by binding them to the lifecycle of the NativeView (jobject pointer)
@MainActor private var frameHandlerRegistry: [UnsafeMutableRawPointer: [Any]] = [:]

extension Frame {
    @MainActor public func makeNative() -> NativeView {
        let env = OmniAndroid.env

        // FrameLayout is the closest Android equivalent to a Z-stacking bounding box
        let view = OmniAndroid.createView(env, "android/widget/FrameLayout")
        frameHandlerRegistry[view] = []
        return view
    }

    @MainActor public func updateNative(_ view: NativeView) {
        let env = OmniAndroid.env

        // 1. Apply Layout Constraints. An unset axis is left as the parent
        // generated it; see ModifierView.
        omni_jni_set_layout_params(env, view,
                                   width.map { Int32($0) } ?? Int32(OMNI_LAYOUT_KEEP),
                                   height.map { Int32($0) } ?? Int32(OMNI_LAYOUT_KEEP))
        AndroidExpansion.pin(view, width: width != nil, height: height != nil)

        // 2. Map Gestures & Retain Handlers
        var retainArray: [Any] = []
        var tapPtr, tapLocPtr, dragPtr, scrollPtr: UnsafeMutableRawPointer?

        if let onTap = onTap {
            let handler = EventHandlerVoid(onTap)
            retainArray.append(handler)
            tapPtr = UnsafeMutableRawPointer(Unmanaged.passUnretained(handler).toOpaque())
        }

        if let onTapLoc = onTapLocation {
            let handler = EventHandlerFloat2({ x, y in onTapLoc(Double(x), Double(y)) })
            retainArray.append(handler)
            tapLocPtr = UnsafeMutableRawPointer(Unmanaged.passUnretained(handler).toOpaque())
        }

        if let onDrag = onDrag {
            // Android GestureDetector passes delta distances; Apple sets translation to zero each tick.
            // These map perfectly to each other contextually.
            let handler = EventHandlerFloat2({ dx, dy in onDrag(Double(dx), Double(dy)) })
            retainArray.append(handler)
            dragPtr = UnsafeMutableRawPointer(Unmanaged.passUnretained(handler).toOpaque())
        }

        if let onScroll = onScroll {
            let handler = EventHandlerFloat2({ dx, dy in onScroll(Double(dx), Double(dy)) })
            retainArray.append(handler)
            scrollPtr = UnsafeMutableRawPointer(Unmanaged.passUnretained(handler).toOpaque())
        }

        // Attach all gestures atomically via JNI
        omni_jni_attach_frame_gestures(env, view, tapPtr, tapLocPtr, dragPtr, scrollPtr)

        // Keep handlers alive in Swift memory
        frameHandlerRegistry[view] = retainArray
    }

}
#endif
