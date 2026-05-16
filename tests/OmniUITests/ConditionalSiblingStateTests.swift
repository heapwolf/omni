#if os(macOS) || os(iOS)
import XCTest
@testable import OmniUI

// An `if` going false unpacks to nothing, so the stack's list of kids gets
// shorter. The kids still there must keep their nodes and their state: OneDosh
// hides its tab bar for a card flow, and rebuilding every kid sent Cards back to
// its dashboard the moment Add Money opened the flow.

@MainActor
private struct Counter: View {
    @State var count = 0
    var body: some View { Text("count=\(count)") }
}

@MainActor
private struct Screen: View {
    @State var showsBar = true
    var body: some View {
        VStack {
            Counter()
            if showsBar { Text("bar") }
        }
    }
}

final class ConditionalSiblingStateTests: XCTestCase {
    func testASiblingKeepsItsStateWhenAnIfBesideItGoesAway() {
        MainActor.assumeIsolated {
            let screen = Screen()
            let node = Node(screen)
            Engine.render(node)

            // Screen's body is the VStack, so its node holds the stack's kids.
            let stack = node
            guard let before = stack.kids.first?.view as? Counter else {
                return XCTFail("expected a Counter first, got \(stack.kids.map(\.view.type))")
            }
            before.count = 3

            screen.showsBar = false
            XCTAssertEqual(stack.kids.count, 1)
            guard let after = stack.kids.first?.view as? Counter else {
                return XCTFail("expected the Counter to remain")
            }
            XCTAssertEqual(after.count, 3)

            screen.showsBar = true
            XCTAssertEqual(stack.kids.count, 2)
            XCTAssertEqual((stack.kids.first?.view as? Counter)?.count, 3)
        }
    }
}
#endif
