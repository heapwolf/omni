
#if os(Windows)
import Foundation

func makePlatformCamera() -> any CameraCapture { WindowsCamera() }

public struct WindowsCamera: CameraCapture {
    private static let reason = "The Windows camera backend is not implemented yet (MediaCapture via CWindows)."

    public init() {}
    public var authorization: CameraAuthorization { get async { .unavailable } }
    public func requestAuthorization() async -> CameraAuthorization { .unavailable }
    public func capture(_ options: CaptureOptions) async throws -> CapturedImage {
        throw CameraError.notImplemented(Self.reason)
    }
    public func pickImage() async throws -> CapturedImage {
        throw CameraError.notImplemented(Self.reason)
    }
}
#endif
