#if os(Linux)
import XCTest
import Glibc
@testable import OmniUI


@MainActor
private final class Unmounts {
    static var order: [String] = []
    static func reset() { order = [] }
}

/// Records its own unmount.
private struct Tracked: NativeComponent {
    let name: String
    var id: AnyHashable { AnyHashable(name) }

    func makeNative() -> NativeView { gtk_label_new(name) }
    func updateNative(_ view: NativeView) {}
    func unmountNative(_ view: NativeView) { Unmounts.order.append(name) }
}

/// A container, so the depth-first order can be asserted.
private struct TrackedBox: NativeComponent {
    let name: String
    let kids: [any View]
    var id: AnyHashable { AnyHashable(name) }
    var children: [any View] { kids }

    func makeNative() -> NativeView { gtk_box_new(1, 0) }
    func updateNative(_ view: NativeView) {}
    func unmountNative(_ view: NativeView) { Unmounts.order.append(name) }
    func insertChild(_ child: NativeView, into parent: NativeView) {
        gtk_container_add(parent, child)
    }
}

/// Swaps its child for a different type, so the engine discards the subtree.
private struct Swapper: View {
    @State var showFirst = true
    var body: some View {
        VStack {
            if showFirst {
                TrackedBox(name: "box", kids: [Tracked(name: "leaf")])
            } else {
                Text("replaced")
            }
        }
    }
}

final class UnmountHookTests: XCTestCase {

    override func setUp() {
        super.setUp()
        gtk_init(nil, nil)
    }

    func testDiscardedSubtreesAreToldTheyAreGoing() {
        MainActor.assumeIsolated {
            Unmounts.reset()

            let swapper = Swapper()
            let node = Node(swapper)
            Engine.render(node)
            XCTAssertEqual(Unmounts.order, [], "nothing has been discarded yet")

            swapper.showFirst = false

            XCTAssertEqual(Unmounts.order, ["leaf", "box"],
                           "expected the child to be told first, got \(Unmounts.order)")
        }
    }

    /// The default must be a no-op.
    func testTheDefaultIsANoOp() {
        MainActor.assumeIsolated {
            let node = Node(Text("plain"))
            Engine.render(node)
            node.unmount()   // would not compile, or would trap, if the default were missing
        }
    }
}
#endif
