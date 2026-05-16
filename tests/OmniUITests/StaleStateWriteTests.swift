#if os(macOS) || os(iOS)
import XCTest
@testable import OmniUI

// A `.task` or a sheet's callback keeps the copy of the view it was made from.
// After the parent rebuilds that view, a write through the old copy has to land
// on what is on screen. When adoption copied values into fresh boxes instead,
// it landed in a box nothing rendered from: OneDosh's Home never showed the
// wallets its task loaded, and a PIN sheet's Forgot PIN never closed it.

@MainActor
private struct Child: View {
    @State var count = 0
    var body: some View { Text("child=\(count)") }
}

@MainActor
private struct Parent: View {
    @State var tick = 0
    var body: some View {
        VStack {
            Text("tick=\(tick)")
            Child()
        }
    }
}

final class StaleStateWriteTests: XCTestCase {
    func testAWriteThroughAnEarlierCopyReachesTheLiveView() {
        MainActor.assumeIsolated {
            let parent = Parent()
            let node = Node(parent)
            Engine.render(node)

            guard let stale = node.kids[1].view as? Child else {
                return XCTFail("expected a Child, got \(node.kids[1].view.type)")
            }

            // The parent rebuilds Child: a new struct, adopting the old state.
            parent.tick = 1
            guard let live = node.kids[1].view as? Child else {
                return XCTFail("expected a Child, got \(node.kids[1].view.type)")
            }

            // What a task started on the first render would do.
            stale.count = 5
            XCTAssertEqual(live.count, 5)

            // And the other way: the live copy's write is what the old one reads.
            live.count = 9
            XCTAssertEqual(stale.count, 9)
        }
    }
}
#endif
