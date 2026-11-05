#if os(Android)
import Foundation
import CAndroid

/// The bytes each view last got: the same again don't cross JNI again. A swipe renders the
/// view on every frame, and a video is hundreds of kilobytes.
@MainActor private var videoShown: [UnsafeMutableRawPointer: Data] = [:]
/// Each view's end handler: Java keeps its pointer, so it lives here till the view goes.
@MainActor private var videoEnds: [UnsafeMutableRawPointer: EventHandlerVoid] = [:]

/// Mirrors the constants in OmniVideoView.java.
private extension Video.Playback {
    var code: Int32 {
        switch self {
        case .atStart: 0
        case .playing: 1
        case .paused: 2
        }
    }
}

extension Video {
    @MainActor public func makeNative() -> NativeView {
        let view = OmniAndroid.createView(OmniAndroid.env, "com/omni/OmniVideoView")
        // Resizable, it takes the space offered, as a resizable Image does.
        if isResizable { AndroidExpansion.claim(view, horizontal: true, vertical: true) }
        return view
    }

    @MainActor public func updateNative(_ view: NativeView) {
        let env = OmniAndroid.env
        omni_jni_call_void_method_bool(env, view, "setFill", isResizable && contentMode == .fill ? 1 : 0)
        if videoShown[view] != data {
            videoShown[view] = data
            [UInt8](data).withUnsafeBufferPointer { buffer in
                omni_jni_set_video_bytes(env, view, buffer.baseAddress, Int32(buffer.count))
            }
        }
        omni_jni_call_void_method_int(env, view, "setEndLead", Int32((endLead * 1000).rounded()))
        omni_jni_call_void_method_int(env, view, "setPlayback", playback.code)
        if let onEnd {
            if let handler = videoEnds[view] {
                handler.action = onEnd
            } else {
                let handler = EventHandlerVoid(onEnd)
                videoEnds[view] = handler
                omni_jni_video_set_end(env, view, Unmanaged.passUnretained(handler).toOpaque())
            }
        } else if videoEnds.removeValue(forKey: view) != nil {
            omni_jni_video_set_end(env, view, nil)
        }
    }

    @MainActor public func unmountNative(_ view: NativeView) {
        omni_jni_call_void_method(OmniAndroid.env, view, "release")
        videoShown.removeValue(forKey: view)
        videoEnds.removeValue(forKey: view)
    }
}
#endif
