#if os(Linux)
import XCTest
import Glibc
@testable import OmniUI

// End-to-end checks that the Linux backend produces GTK widgets and keeps
// them in sync, reading state back out of GTK rather than out of Swift.

private let gtk_label_get_text: @convention(c) (NativeView) -> UnsafePointer<CChar>? =
    fn(libgtk, "gtk_label_get_text")
private let gtk_button_get_label: @convention(c) (NativeView) -> UnsafePointer<CChar>? =
    fn(libgtk, "gtk_button_get_label")
private let gtk_widget_get_parent: @convention(c) (NativeView) -> NativeView? =
    fn(libgtk, "gtk_widget_get_parent")
private let gtk_widget_get_allocated_width: @convention(c) (NativeView) -> Int32 =
    fn(libgtk, "gtk_widget_get_allocated_width")
private let gtk_widget_get_allocated_height: @convention(c) (NativeView) -> Int32 =
    fn(libgtk, "gtk_widget_get_allocated_height")
private let gtk_events_pending: @convention(c) () -> Int32 =
    fn(libgtk, "gtk_events_pending")
private let gtk_main_iteration: @convention(c) () -> Int32 =
    fn(libgtk, "gtk_main_iteration")

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

private func labelText(_ view: NativeView?) -> String? {
    guard let view, let cStr = gtk_label_get_text(view) else { return nil }
    return String(cString: cStr)
}

final class LinuxRenderTests: XCTestCase {

    override func setUp() {
        super.setUp()
        // Safe to call repeatedly; GTK ignores subsequent inits.
        gtk_init(nil, nil)
    }


    func testTextProducesAGtkLabelCarryingItsString() {
        MainActor.assumeIsolated {
            let node = Node(Text("hello linux"))
            Engine.render(node)

            XCTAssertNotNil(node.native, "Text did not produce a native widget")
            XCTAssertEqual(labelText(node.native), "hello linux")
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

            // Creating the widgets is not enough; they must be parented into
            // the box, or the window renders empty.
            for kid in node.kids {
                XCTAssertEqual(gtk_widget_get_parent(kid.native!), node.native,
                               "child widget was never packed into the VStack")
            }
        }
    }

    func testButtonProducesAGtkButtonWithItsTitle() {
        MainActor.assumeIsolated {
            let node = Node(Button("Tap me", action: {}))
            Engine.render(node)

            let native = node.native
            XCTAssertNotNil(native)
            let title = native.flatMap { gtk_button_get_label($0) }
                .map { String(cString: $0) }
            XCTAssertEqual(title, "Tap me")
        }
    }

    // The render loop: mutating @State on a live view instance must push the new
    // value all the way into the GTK label.
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

    func testWindowContentBecomesVisibleAndSized() {
        MainActor.assumeIsolated {
            let node = Node(TwoLabels())
            Engine.render(node)

            let window = gtk_window_new(0)
            gtk_window_set_default_size(window, 400, 200)
            gtk_container_add(window, node.native!)
            gtk_widget_show_all(window)

            var pumped = 0
            while gtk_events_pending() != 0 && pumped < 5_000 {
                _ = gtk_main_iteration()
                pumped += 1
            }

            XCTAssertNotEqual(gtk_widget_get_visible(node.native!), 0,
                              "the root box is not visible")
            for kid in node.kids {
                XCTAssertNotEqual(gtk_widget_get_visible(kid.native!), 0,
                                  "a label is not visible")
            }

            let w = gtk_widget_get_allocated_width(node.native!)
            let h = gtk_widget_get_allocated_height(node.native!)
            XCTAssertGreaterThan(w, 1, "root box was allocated no width")
            XCTAssertGreaterThan(h, 1, "root box was allocated no height")
        }
    }

    // ForEach now wraps each row in an IdentifiedView, which adds a node level
    // between the stack and the row. The rows must still be created and parented.
    func testForEachRowsRenderAndAreParented() {
        MainActor.assumeIsolated {
            let node = Node(RowList())
            Engine.render(node)

            XCTAssertEqual(node.kids.count, 3, "expected one node per row")
            XCTAssertEqual(node.kids.compactMap { labelText($0.native) },
                           ["row 0", "row 1", "row 2"])

            for kid in node.kids {
                XCTAssertEqual(gtk_widget_get_parent(kid.native!), node.native,
                               "a ForEach row was never packed into the stack")
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
