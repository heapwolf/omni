// CameraX is a Gradle dependency this build cannot resolve.

#if os(Android)
import Foundation
import CAndroid

func makePlatformCamera() -> any CameraCapture { AndroidCamera() }

public struct AndroidCamera: CameraCapture {
    public init() {}

    public var authorization: CameraAuthorization {
        get async { await AndroidCameraBridge.authorization() }
    }

    public func requestAuthorization() async -> CameraAuthorization {
        await AndroidCameraBridge.requestAuthorization()
    }

    public func capture(_ options: CaptureOptions) async throws -> CapturedImage {
        try await AndroidCameraBridge.capture(options)
    }

    public func pickImage() async throws -> CapturedImage {
        try await AndroidCameraBridge.pickImage()
    }
}

@MainActor
private enum AndroidCameraBridge {
    private static func trace(_ message: String) {
        omni_jni_log("OmniCamera", message)
    }

    private static let permission = "android.permission.CAMERA"
    private static let requestCodePermission: Int32 = 41001
    private static let requestCodeCapture: Int32 = 41002
    private static let requestCodePick: Int32 = 41003

    static func authorization() -> CameraAuthorization {
        guard let env = omni_get_env(), let activity = omni_jni_activity() else { return .unavailable }
        return omni_jni_check_self_permission(env, activity, permission) == 0 ? .authorized : .notDetermined
    }

    static func requestAuthorization() async -> CameraAuthorization {
        let current = authorization()
        trace("requestAuthorization: current = \(current)")
        guard current == .notDetermined else { return current }
        guard let env = omni_get_env(), let activity = omni_jni_activity() else {
            trace("requestAuthorization: NO env or activity")
            return .unavailable
        }
        trace("requestAuthorization: prompting")

        return await withCheckedContinuation { (continuation: CheckedContinuation<CameraAuthorization, Never>) in
            let handler = CameraPermissionHandler { granted in
                continuation.resume(returning: granted ? .authorized : .denied)
            }
            let ptr = Unmanaged.passRetained(handler).toOpaque()
            omni_jni_request_permission(env, activity, permission, requestCodePermission, ptr)
        }
    }

    static func capture(_ options: CaptureOptions) async throws -> CapturedImage {
        trace("capture: entered")
        let state = await requestAuthorization()
        trace("capture: authorization = \(state)")
        guard state == .authorized else { throw CameraError.notAuthorized(state) }
        guard let env = omni_get_env(), let activity = omni_jni_activity() else {
            trace("capture: NO env or activity")
            throw CameraError.platform("No activity to present from.")
        }
        guard let cCacheDir = omni_jni_cache_dir(env, activity) else {
            trace("capture: NO cache dir")
            throw CameraError.platform("Could not find a writable directory.")
        }
        let cacheDir = String(cString: cCacheDir)
        free(cCacheDir)

        let outputPath = cacheDir + "/omni-capture-\(UUID().uuidString).jpg"
        defer { try? FileManager.default.removeItem(atPath: outputPath) }

        trace("capture: launching, output = \(outputPath)")
        let result = await awaitActivityResult { ptr in
            let started = omni_jni_launch_camera_capture(
                env, activity, outputPath, requestCodeCapture,
                options.facing == .front ? 1 : 0, ptr) == 1
            trace("capture: launch returned \(started)")
            return started
        }
        trace("capture: result launched=\(result.launched) ok=\(result.ok)")
        guard result.launched else {
            throw CameraError.noCameraAvailable
        }
        guard result.ok else { throw CameraError.cancelled }

        guard let data = FileManager.default.contents(atPath: outputPath) else {
            throw CameraError.platform("The camera app did not write an image.")
        }
        return try AndroidImageEncoder.encode(data, options: options)
    }

    static func pickImage() async throws -> CapturedImage {
        guard let env = omni_get_env(), let activity = omni_jni_activity() else {
            throw CameraError.platform("No activity to present from.")
        }

        let result = await awaitActivityResult { ptr in
            omni_jni_launch_image_pick(env, activity, requestCodePick, ptr)
            return true
        }
        guard result.launched else {
            throw CameraError.platform("No app on this device can pick an image.")
        }
        guard result.ok, let uri = result.uri else { throw CameraError.cancelled }

        var length: Int32 = 0
        guard let buffer = omni_jni_read_uri(env, activity, uri, &length) else {
            throw CameraError.platform("Could not read the chosen image.")
        }
        let data = Data(bytes: buffer, count: Int(length))
        free(buffer)

        return try AndroidImageEncoder.encode(data, options: CaptureOptions())
    }

    private static func awaitActivityResult(
        launch: (UnsafeMutableRawPointer) -> Bool
    ) async -> (launched: Bool, ok: Bool, uri: String?) {
        await withCheckedContinuation { continuation in
            let handler = CameraActivityResultHandler { ok, uri in
                continuation.resume(returning: (true, ok, uri))
            }
            let ptr = Unmanaged.passRetained(handler).toOpaque()
            if !launch(ptr) {
                Unmanaged<CameraActivityResultHandler>.fromOpaque(ptr).release()
                continuation.resume(returning: (false, false, nil))
            }
        }
    }
}

// MARK: - JNI dispatch

/// Fires at most once or twice a session, so it is simplest to leave
/// retained; see the note where it is created.
@MainActor
private final class CameraPermissionHandler {
    let action: (Bool) -> Void
    init(_ action: @escaping (Bool) -> Void) { self.action = action }
}

@MainActor
private final class CameraActivityResultHandler {
    let action: (Bool, String?) -> Void
    init(_ action: @escaping (Bool, String?) -> Void) { self.action = action }
}

@_cdecl("omni_camera_dispatch_permission_result")
func omni_camera_dispatch_permission_result(_ ptr: UnsafeMutableRawPointer, _ granted: Int32) {
    let handler = Unmanaged<CameraPermissionHandler>.fromOpaque(ptr).takeUnretainedValue()
    MainActor.assumeIsolated { handler.action(granted != 0) }
}

@_cdecl("omni_camera_dispatch_activity_result")
func omni_camera_dispatch_activity_result(
    _ ptr: UnsafeMutableRawPointer, _ ok: Int32, _ uri: UnsafePointer<CChar>?
) {
    let str = uri.map { String(cString: $0) }
    let handler = Unmanaged<CameraActivityResultHandler>.fromOpaque(ptr).takeRetainedValue()
    MainActor.assumeIsolated { handler.action(ok != 0, str) }
}

// MARK: - Resizing and encoding

private enum AndroidImageEncoder {
    static func encode(_ data: Data, options: CaptureOptions) throws -> CapturedImage {
        guard let env = omni_get_env() else {
            throw CameraError.platform("No JNI environment.")
        }

        let produced: ImageFormat
        switch options.format {
        case .png: produced = .png
        case .jpeg, .heic: produced = .jpeg
        }
        let formatName = produced == .png ? "png" : "jpeg"

        let sourceBytes = [UInt8](data)
        var encodedLength: Int32 = 0
        guard let encodedPtr = sourceBytes.withUnsafeBufferPointer({ source in
            omni_jni_encode_image(env, source.baseAddress, Int32(source.count),
                                  Int32(options.maxDimension ?? -1), formatName,
                                  options.quality, &encodedLength)
        }) else {
            throw CameraError.platform("Could not encode the image.")
        }
        let encodedBytes = [UInt8](UnsafeBufferPointer(start: encodedPtr, count: Int(encodedLength)))
        free(encodedPtr)

        var width: Int32 = 0
        var height: Int32 = 0
        encodedBytes.withUnsafeBufferPointer { encoded in
            omni_jni_image_dimensions(env, encoded.baseAddress, Int32(encoded.count), &width, &height)
        }

        return CapturedImage(data: Data(encodedBytes), format: produced,
                             width: Int(width), height: Int(height))
    }
}
#endif
