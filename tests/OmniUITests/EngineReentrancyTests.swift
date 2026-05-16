#if os(Linux)
import XCTest
import Glibc
@testable import OmniUI


@MainActor
private final class Counter: ObservableObject {
    @Published var value = 0
}

/// Reads and writes in one expression, which is what makes the notification
/// re-entrant.
private struct WritesStateFromBody: View {
    let model: Counter
    var body: some View {
        model.value += 1
        return Text("v=\(model.value)")
    }
}

final class EngineReentrancyTests: XCTestCase {

    override func setUp() {
        super.setUp()
        gtk_init(nil, nil)
    }

    func testWritingStateFromBodyDoesNotRecurse() {
        MainActor.assumeIsolated {
            let model = Counter()
            let node = Node(WritesStateFromBody(model: model))

            // Mostly asserts that this returns at all.
            Engine.render(node)

            XCTAssertEqual(model.value, 1,
                           "body ran \(model.value) times; the re-entrant pass was not dropped")
            XCTAssertNotNil(node.native)
        }
    }

    /// The guard is per node: an unrelated node must still render mid-pass.
    func testAnUnrelatedNodeStillRendersDuringARender() {
        MainActor.assumeIsolated {
            let model = Counter()
            let other = Node(Text("other"))
            var renderedOther = false

            struct Nested: View {
                let onBody: () -> Void
                var body: some View {
                    onBody()
                    return Text("nested")
                }
            }

            let node = Node(Nested(onBody: {
                Engine.render(other)
                renderedOther = true
            }))
            Engine.render(node)

            XCTAssertTrue(renderedOther)
            XCTAssertNotNil(other.native, "a different node was blocked by the re-entrancy guard")
            _ = model
        }
    }
}
#endif
