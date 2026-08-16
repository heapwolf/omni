
#if os(Linux)
import Foundation

func makePlatformCamera() -> any CameraCapture { LinuxCamera() }

public struct LinuxCamera: CameraCapture {
    private static let reason = "The Linux camera backend is not implemented yet (no standard capture UI)."

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
