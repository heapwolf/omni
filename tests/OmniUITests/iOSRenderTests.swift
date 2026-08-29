#if os(iOS)
import XCTest
import UIKit
@testable import OmniUI


@MainActor
private struct Counter: View {
    @State var n = 0
    var body: some View { Text("n=\(n)") }
}

@MainActor
private struct RowList: View {
    var body: some View {
        VStack {
            ForEach(0..<3) { Text("row \($0)") }
        }
    }
}

@MainActor
private struct TwoLabels: View {
    var body: some View {
        VStack {
            Text("first")
            Text("second")
        }
    }
}

final class iOSRenderTests: XCTestCase {

    private func labelText(_ view: NativeView?) -> String? {
        (view as? UILabel)?.text
    }

    func testTextProducesAUILabelCarryingItsString() {
        MainActor.assumeIsolated {
            let node = Node(Text("hello ios"))
            Engine.render(node)

            XCTAssertNotNil(node.native, "Text did not produce a native view")
            XCTAssertEqual(labelText(node.native), "hello ios")
        }
    }

    func testVStackRendersEachChildAsItsOwnWidget() {
        MainActor.assumeIsolated {
            let node = Node(TwoLabels())
            Engine.render(node)

            XCTAssertNotNil(node.native)

            XCTAssertEqual(node.kids.count, 2, "VStack should hold two child nodes")
            XCTAssertEqual(node.kids.compactMap { labelText($0.native) },
                           ["first", "second"])

            guard let stack = node.native as? UIStackView else {
                return XCTFail("root view was not a UIStackView")
            }
            // Creating the views is not enough; they must be arranged
            // subviews of the stack, or the screen renders empty.
            for kid in node.kids {
                XCTAssertTrue(stack.arrangedSubviews.contains(kid.native!),
                              "child view was never added to the VStack's arranged subviews")
            }
        }
    }

    func testButtonProducesAUIButtonWithItsTitle() {
        MainActor.assumeIsolated {
            let node = Node(Button("Tap me", action: {}))
            Engine.render(node)

            let native = node.native
            XCTAssertNotNil(native)
            let title = (native as? UIButton)?.title(for: .normal)
            XCTAssertEqual(title, "Tap me")
        }
    }

    // The render loop: mutating @State on a live view instance must push the new
    // value all the way into the UILabel.
    func testStateMutationUpdatesTheNativeWidget() {
        MainActor.assumeIsolated {
            let view = Counter()
            let node = Node(view)
            Engine.render(node)

            XCTAssertEqual(labelText(node.native), "n=0")

            view.n = 5

            XCTAssertEqual(labelText(node.native), "n=5",
                           "State change did not reach the native widget")
        }
    }

    func testForEachRowsRenderAndAreParented() {
        MainActor.assumeIsolated {
            let node = Node(RowList())
            Engine.render(node)

            XCTAssertEqual(node.kids.count, 3, "expected one node per row")
            XCTAssertEqual(node.kids.compactMap { labelText($0.native) },
                           ["row 0", "row 1", "row 2"])

            guard let stack = node.native as? UIStackView else {
                return XCTFail("root view was not a UIStackView")
            }
            for kid in node.kids {
                XCTAssertTrue(stack.arrangedSubviews.contains(kid.native!),
                              "a ForEach row was never added to the stack's arranged subviews")
            }
        }
    }

    func testUnmountPrunesStateSubscriptions() {
        MainActor.assumeIsolated {
            Tracker.deps.removeAll()

            let node = Node(Counter())
            Engine.render(node)
            XCTAssertFalse(Tracker.deps.isEmpty,
                           "rendering a stateful view should register a subscription")

            node.unmount()
            XCTAssertTrue(Tracker.deps.isEmpty,
                          "unmount left orphaned entries in Tracker.deps")
        }
    }
}
#endif
