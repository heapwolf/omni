#if os(macOS)
import XCTest
import AppKit
@testable import OmniUI

// A stack puts its spacing between its children, not after the last: the
// filler omni adds at the end (a stack that wants no room still grows) took
// a gap of the stack's spacing before it, and every card ended in a band.

final class StackSpacingTests: XCTestCase {
    @MainActor private static func height(_ view: some View) -> Double {
        let node = Node(view)
        Engine.render(node)
        guard let native = node.native else { XCTFail("nothing rendered"); return 0 }
        native.layoutSubtreeIfNeeded()
        return Double(native.fittingSize.height)
    }

    func testAColumnEndsAtItsLastChild() {
        MainActor.assumeIsolated {
            let one = Self.height(Text("A").frame(height: 20))
            let two = Self.height(VStack(spacing: 12) { Text("A").frame(height: 20); Text("B").frame(height: 20) })
            XCTAssertEqual(one, 20, accuracy: 0.5)
            XCTAssertEqual(two, 52, accuracy: 0.5, "two rows and one gap, none after the last")
        }
    }

    func testNestedColumnsAddNoGapEach() {
        MainActor.assumeIsolated {
            let nested = Self.height(VStack(spacing: 12) {
                Text("A").frame(height: 20)
                VStack(spacing: 12) { Text("B").frame(height: 20); Text("C").frame(height: 20) }
            })
            XCTAssertEqual(nested, 84, accuracy: 0.5)
        }
    }
}
#endif
