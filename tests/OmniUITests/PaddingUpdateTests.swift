#if os(macOS)
import XCTest
import AppKit
@testable import OmniUI

// A padding that changes on a later render moves what it wraps. Its child
// was placed once, as it was first inserted: OneDosh's Cards screen, padded
// below the status bar only once a card flow covered the tab bar, drew the
// flow's header under it.

@MainActor
private struct Padded: View {
    @State var inset = 0.0
    var body: some View {
        Text("A").frame(height: 20).padding(.top, inset)
    }
}

final class PaddingUpdateTests: XCTestCase {
    func testAChangedPaddingMovesTheChild() {
        MainActor.assumeIsolated {
            let node = Node(Padded())
            Engine.render(node)
            guard let padded = node.view as? Padded else {
                return XCTFail("expected Padded, got \(node.view)")
            }
            @MainActor func height() -> Double {
                guard let native = node.native else { XCTFail("nothing rendered"); return 0 }
                native.layoutSubtreeIfNeeded()
                return Double(native.fittingSize.height)
            }
            XCTAssertEqual(height(), 20, accuracy: 0.5)
            padded.inset = 44
            XCTAssertEqual(height(), 64, accuracy: 0.5, "the new padding, above the child")
            padded.inset = 0
            XCTAssertEqual(height(), 20, accuracy: 0.5, "and gone again")
        }
    }
}
#endif
