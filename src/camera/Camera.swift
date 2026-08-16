// Take a photo, or pick an existing one. Not video, not a preview surface,
// not a barcode scanner: different APIs and different permissions.

import Foundation

// MARK: - What comes back

public struct CapturedImage: Sendable {
    /// Encoded image bytes, in `format`.
    public let data: Data
    public let format: ImageFormat
    public let width: Int
    public let height: Int

    public init(data: Data, format: ImageFormat, width: Int, height: Int) {
        self.data = data
        self.format = format
        self.width = width
        self.height = height
    }
}

public enum ImageFormat: Sendable, Equatable {
    case jpeg, png, heic

    public var mimeType: String {
        switch self {
        case .jpeg: return "image/jpeg"
        case .png: return "image/png"
        case .heic: return "image/heic"
        }
    }
}

// MARK: - What is asked for

public enum CameraFacing: Sendable {
    case back, front
}

public struct CaptureOptions: Sendable {
    public var facing: CameraFacing
    /// Longest edge in pixels. Full sensor resolution is several megabytes and no
    /// more legible over a phone network.
    public var maxDimension: Int?
    /// 0...1, ignored by formats without lossy compression.
    public var quality: Double
    public var format: ImageFormat

    public init(facing: CameraFacing = .back, maxDimension: Int? = 2048,
                quality: Double = 0.8, format: ImageFormat = .jpeg) {
        self.facing = facing
        self.maxDimension = maxDimension
        self.quality = quality
        self.format = format
    }
}

public extension CaptureOptions {
    /// The size to encode at. Shared because it is pure arithmetic: the longest
    /// edge is capped, and an image already smaller is left alone.
    func targetSize(for source: (width: Int, height: Int)) -> (width: Int, height: Int) {
        guard let maxDimension, maxDimension > 0 else { return source }
        let longest = max(source.width, source.height)
        guard longest > maxDimension else { return source }

        let ratio = Double(maxDimension) / Double(longest)
        // Floored at 1: a wide panorama must not scale its short edge to zero.
        return (width: max(1, Int((Double(source.width) * ratio).rounded())),
                height: max(1, Int((Double(source.height) * ratio).rounded())))
    }
}

// Explicit because "not asked yet" and "denied for good" call for different
// UI.

public enum CameraAuthorization: Sendable, Equatable {
    case notDetermined
    case authorized
    /// Asking again does nothing; only Settings can change it.
    case denied
    /// Policy forbids it: parental controls, MDM.
    case restricted
    /// No camera on this device or platform.
    case unavailable
}

// MARK: - How it fails

public enum CameraError: Error, Sendable, Equatable {
    /// Not authorized. Carries the state so a caller knows whether to prompt or
    /// to send the user to Settings.
    case notAuthorized(CameraAuthorization)
    /// The user backed out. Not an error condition to report, but a caller has
    /// to be able to tell it apart from a failure.
    case cancelled
    case noCameraAvailable
    case notImplemented(String)
    case platform(String)
}

// MARK: - The seam

public protocol CameraCapture: Sendable {
    var authorization: CameraAuthorization { get async }
    /// Prompts if the state is `.notDetermined`; otherwise returns the state
    /// unchanged rather than prompting again.
    func requestAuthorization() async -> CameraAuthorization
    /// Presents the platform's capture UI. Throws `.cancelled` if dismissed.
    func capture(_ options: CaptureOptions) async throws -> CapturedImage
    /// Presents the platform's photo picker.
    func pickImage() async throws -> CapturedImage
}

public extension CameraCapture {
    func capture() async throws -> CapturedImage { try await capture(CaptureOptions()) }
}

// MARK: - The one every app uses

public enum Camera {
    public static let `default`: any CameraCapture = makePlatformCamera()
}
