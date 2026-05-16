#if os(macOS) || os(iOS)
import XCTest
@testable import OmniUI

// Strokes follow the shape's path. They used to be a square border clipped to
// the shape, which lost the line at every rounded corner.
final class StrokeTests: XCTestCase {

    func testEachShapeStrokesItsOwnOutline() {
        MainActor.assumeIsolated {
            XCTAssertEqual(RoundedRectangle(cornerRadius: 24).outline, .rectangle(cornerRadius: 24))
            XCTAssertEqual(Rectangle().outline, .rectangle(cornerRadius: 0))
            XCTAssertEqual(Circle().outline, .circle)
            XCTAssertEqual(Capsule().outline, .capsule)
            XCTAssertEqual(Ellipse().outline, .ellipse)
        }
    }

    // A radius past half the short side is clamped, as in SwiftUI.
    func testTheRadiusIsClampedToHalfTheShortSide() {
        let rect = CGRect(x: 0, y: 0, width: 200, height: 56)
        let clamped = OmniStrokeView.path(.rectangle(cornerRadius: 40), in: rect, inset: 0)
        let capsule = OmniStrokeView.path(.capsule, in: rect, inset: 0)
        XCTAssertEqual(clamped.boundingBoxOfPath, capsule.boundingBoxOfPath)
        XCTAssertTrue(clamped.contains(CGPoint(x: 100, y: 28)))
        XCTAssertFalse(clamped.contains(CGPoint(x: 1, y: 1)), "the corner is rounded off")
    }

    // strokeBorder stays inside the frame; stroke is centred on its edge.
    func testStrokeBorderIsInset() {
        MainActor.assumeIsolated {
            let inset = ShapeStroke(outline: .rectangle(cornerRadius: 8), color: .red, lineWidth: 2, isInset: true)
            let centred = ShapeStroke(outline: .rectangle(cornerRadius: 8), color: .red, lineWidth: 2, isInset: false)
            XCTAssertTrue(inset.isInset)
            XCTAssertFalse(centred.isInset)
            let bounds = CGRect(x: 0, y: 0, width: 100, height: 40)
            let path = OmniStrokeView.path(.rectangle(cornerRadius: 8), in: bounds.insetBy(dx: 1, dy: 1), inset: 1)
            XCTAssertEqual(path.boundingBoxOfPath, bounds.insetBy(dx: 1, dy: 1))
        }
    }

    func testAnEmptyFrameDrawsNothing() {
        XCTAssertTrue(OmniStrokeView.path(.circle, in: .zero, inset: 0).isEmpty)
    }
}
#endif
