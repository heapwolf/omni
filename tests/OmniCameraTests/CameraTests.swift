import XCTest
import Foundation
@testable import OmniCamera

final class CameraValueTests: XCTestCase {
    func testCaptureDefaultsAreSaneForDocumentUpload() {
        let options = CaptureOptions()
        XCTAssertEqual(options.format, .jpeg)
        XCTAssertEqual(options.quality, 0.8)
        // Full sensor resolution is several megabytes, no more legible, and
        // going over a phone network.
        XCTAssertEqual(options.maxDimension, 2048)
        if case .back = options.facing {} else { XCTFail("documents are shot with the back camera") }
    }

    func testMimeTypesMatchTheFormats() {
        XCTAssertEqual(ImageFormat.jpeg.mimeType, "image/jpeg")
        XCTAssertEqual(ImageFormat.png.mimeType, "image/png")
        XCTAssertEqual(ImageFormat.heic.mimeType, "image/heic")
    }

    /// The distinction the enum exists to make: one of these is worth a prompt,
    /// the other needs a link to Settings.
    func testDeniedAndNotDeterminedAreDistinct() {
        XCTAssertNotEqual(CameraAuthorization.denied, .notDetermined)
        XCTAssertNotEqual(CameraAuthorization.restricted, .denied)
        XCTAssertNotEqual(CameraAuthorization.unavailable, .denied)
    }

    func testCancellationIsDistinctFromFailure() {
        XCTAssertNotEqual(CameraError.cancelled, CameraError.noCameraAvailable)
        XCTAssertNotEqual(CameraError.cancelled, CameraError.notAuthorized(.denied))
    }

    func testNotAuthorizedCarriesTheState() {
        guard case .notAuthorized(let state) = CameraError.notAuthorized(.restricted) else {
            return XCTFail("expected .notAuthorized")
        }
        XCTAssertEqual(state, .restricted, "the caller needs the state to choose what to show")
    }

    func testCapturedImageKeepsItsDimensions() {
        let image = CapturedImage(data: Data([0xFF, 0xD8]), format: .jpeg, width: 1536, height: 2048)
        XCTAssertEqual(image.width, 1536)
        XCTAssertEqual(image.height, 2048)
        XCTAssertEqual(image.format.mimeType, "image/jpeg")
    }
}

/// A backend with no implementation must fail, not return an empty image. A KYC
/// upload that silently sends nothing is worse than one that does not start.
final class UnimplementedBackendTests: XCTestCase {
    private struct Unimplemented: CameraCapture {
        var authorization: CameraAuthorization { get async { .unavailable } }
        func requestAuthorization() async -> CameraAuthorization { .unavailable }
        func capture(_ options: CaptureOptions) async throws -> CapturedImage {
            throw CameraError.notImplemented("test")
        }
        func pickImage() async throws -> CapturedImage {
            throw CameraError.notImplemented("test")
        }
    }

    func testCaptureThrowsRatherThanReturningEmpty() async {
        do {
            _ = try await Unimplemented().capture()
            XCTFail("an unimplemented backend must throw")
        } catch let error as CameraError {
            guard case .notImplemented = error else {
                return XCTFail("expected .notImplemented, got \(error)")
            }
        } catch { XCTFail("unexpected error type") }
    }

    func testConvenienceCaptureUsesDefaults() async {
        // Exercises the protocol extension overload, which is otherwise untested.
        do { _ = try await Unimplemented().capture() } catch {}
    }
}

/// The resize arithmetic, shared so every backend crops identically. Pure
/// maths, so it is testable without a device.
final class TargetSizeTests: XCTestCase {
    private func options(_ max: Int?) -> CaptureOptions {
        CaptureOptions(maxDimension: max)
    }

    func testNoLimitLeavesTheSourceAlone() {
        let size = options(nil).targetSize(for: (width: 4032, height: 3024))
        XCTAssertEqual(size.width, 4032)
        XCTAssertEqual(size.height, 3024)
    }

    func testLandscapeCapsTheWidth() {
        let size = options(2048).targetSize(for: (width: 4032, height: 3024))
        XCTAssertEqual(size.width, 2048)
        XCTAssertEqual(size.height, 1536, "aspect ratio must be preserved")
    }

    /// The rule that makes portrait and landscape come out comparably sized:
    /// the longest edge is what is capped, whichever edge that is.
    func testPortraitCapsTheHeight() {
        let size = options(2048).targetSize(for: (width: 3024, height: 4032))
        XCTAssertEqual(size.height, 2048)
        XCTAssertEqual(size.width, 1536)
    }

    func testSmallerThanTheCapIsNotScaledUp() {
        let size = options(2048).targetSize(for: (width: 800, height: 600))
        XCTAssertEqual(size.width, 800, "scaling up costs bytes and adds no detail")
        XCTAssertEqual(size.height, 600)
    }

    func testExactlyTheCapIsUnchanged() {
        let size = options(2048).targetSize(for: (width: 2048, height: 1536))
        XCTAssertEqual(size.width, 2048)
        XCTAssertEqual(size.height, 1536)
    }

    func testSquareStaysSquare() {
        let size = options(1000).targetSize(for: (width: 3000, height: 3000))
        XCTAssertEqual(size.width, 1000)
        XCTAssertEqual(size.height, 1000)
    }

    /// An extreme aspect ratio must not scale its short edge to zero; a
    /// zero-height image does not encode.
    func testExtremePanoramaKeepsAtLeastOnePixel() {
        let size = options(100).targetSize(for: (width: 20_000, height: 60))
        XCTAssertEqual(size.width, 100)
        XCTAssertGreaterThanOrEqual(size.height, 1, "short edge must never round to zero")
    }

    func testZeroOrNegativeLimitIsTreatedAsNoLimit() {
        XCTAssertEqual(options(0).targetSize(for: (width: 400, height: 300)).width, 400)
        XCTAssertEqual(options(-5).targetSize(for: (width: 400, height: 300)).width, 400)
    }

    func testAspectRatioSurvivesRounding() {
        let source = (width: 4000, height: 2251)
        let size = options(1920).targetSize(for: source)
        let sourceRatio = Double(source.width) / Double(source.height)
        let targetRatio = Double(size.width) / Double(size.height)
        XCTAssertEqual(sourceRatio, targetRatio, accuracy: 0.01)
    }
}
