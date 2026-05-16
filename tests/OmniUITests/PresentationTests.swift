import XCTest
@testable import OmniUI

// .presentationDetents & co. The sheet reads them from its content's nodes;
// these hold that reading. UIKit's side (UISheetPresentationController) needs
// iOS and is checked on the simulator.
final class PresentationTests: XCTestCase {

    @MainActor
    private static func options(of view: any View) -> PresentationOptions {
        let node = Node(view)
        Engine.render(node)
        return PresentationOptions.collect(from: node)
    }

    func testDetentsAreFoundOnTheContent() {
        MainActor.assumeIsolated {
            let found = Self.options(of: Text("x").presentationDetents([.medium, .large]))
            XCTAssertEqual(found.detents, [.medium, .large])
        }
    }

    // Omni.unpackViews must not flatten the carrier away.
    func testDetentsInsideAStackAreFound() {
        MainActor.assumeIsolated {
            let found = Self.options(of: VStack { Text("x").presentationDetents([.height(200)]) })
            XCTAssertEqual(found.detents, [.height(200)])
        }
    }

    func testEachModifierContributesItsOwnValue() {
        MainActor.assumeIsolated {
            let found = Self.options(of: Text("x")
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(26)
                .interactiveDismissDisabled())
            XCTAssertEqual(found.detents, [.medium])
            XCTAssertEqual(found.dragIndicator, .visible)
            XCTAssertEqual(found.cornerRadius, 26)
            XCTAssertEqual(found.interactiveDismissDisabled, true)
        }
    }

    func testNoModifiersMeansTheSystemDefaults() {
        MainActor.assumeIsolated {
            let found = Self.options(of: Text("x"))
            XCTAssertNil(found.detents)
            XCTAssertEqual(found.orderedDetents, [.large], "a plain sheet is full height")
        }
    }

    // UIKit wants detents smallest first; a Set has no order.
    func testDetentsAreOrderedSmallestFirst() {
        let options = PresentationOptions(detents: [.large, .fraction(0.25), .medium, .height(700)])
        XCTAssertEqual(options.orderedDetents, [.fraction(0.25), .medium, .height(700), .large])
    }

    func testIdentifiersAreDistinct() {
        let detents: [PresentationDetent] = [.medium, .large, .fraction(0.3), .fraction(0.4), .height(300)]
        XCTAssertEqual(Set(detents.map(\.identifier)).count, detents.count)
    }

    // nil is "the system's radius", which must differ from never having asked.
    func testANilCornerRadiusIsRecorded() {
        MainActor.assumeIsolated {
            XCTAssertNotNil(Self.options(of: Text("x").presentationCornerRadius(nil)).cornerRadius)
            XCTAssertNil(Self.options(of: Text("x")).cornerRadius)
        }
    }
}
