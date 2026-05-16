#if os(Linux)
import XCTest
import Glibc
@testable import OmniUI


private let gtk_adjustment_set_value_v: @convention(c) (UnsafeMutableRawPointer, Double) -> Void =
    fn(libgtk, "gtk_adjustment_set_value")
private let gtk_adjustment_get_upper_v: @convention(c) (UnsafeMutableRawPointer) -> Double =
    fn(libgtk, "gtk_adjustment_get_upper")
private let gtk_events_pending_v: @convention(c) () -> Int32 = fn(libgtk, "gtk_events_pending")
private let gtk_main_iteration_v: @convention(c) () -> Int32 = fn(libgtk, "gtk_main_iteration")
private let gtk_widget_size_allocate_v: @convention(c) (NativeView, UnsafeMutableRawPointer) -> Void =
    fn(libgtk, "gtk_widget_size_allocate")

private let rowHeight: Double = 30
private let rowCount = 10_000

private struct BigList: View {
    var body: some View {
        List {
            ForEach(0..<rowCount, id: \.self) { index in
                Text("row \(index)").frame(height: rowHeight)
            }
        }
    }
}

/// Pump, allocate, pump: the viewport measurement and the scroll callback both
/// land on GTK's idle queue.
@MainActor private func settle(_ window: NativeView, _ node: Node) {
    for _ in 0..<3 {
        var pumped = 0
        while gtk_events_pending_v() != 0 && pumped < 20_000 {
            _ = gtk_main_iteration_v()
            pumped += 1
        }
        var rect: [Int32] = [0, 0, 480, 760]
        rect.withUnsafeMutableBytes { gtk_widget_size_allocate_v(window, $0.baseAddress!) }
        Engine.render(node)
    }
}

@MainActor private func findRows(_ node: Node) -> VirtualisedRows? {
    if let rows = node.view as? VirtualisedRows { return rows }
    for kid in node.kids {
        if let found = findRows(kid) { return found }
    }
    return nil
}

@MainActor private func findScrolledWindow(_ widget: NativeView) -> NativeView? {
    if isA(widget, "GtkScrolledWindow") { return widget }
    for child in children(of: widget) {
        if let found = findScrolledWindow(child) { return found }
    }
    return nil
}

final class VirtualisedListTests: XCTestCase {

    override func setUp() {
        super.setUp()
        gtk_init(nil, nil)
    }

    func testTenThousandRowsMountATinyWindow() {
        MainActor.assumeIsolated {
            let node = Node(BigList())
            Engine.render(node)

            let window = gtk_window_new(0)
            gtk_window_set_default_size(window, 480, 760)
            gtk_container_add(window, node.native!)
            gtk_widget_show_all(window)
            settle(window, node)

            guard let rows = findRows(node) else {
                return XCTFail("List did not virtualise: no VirtualisedRows in the tree")
            }

            let mounted = rows.window(count: rowCount)
            XCTAssertEqual(mounted.lowerBound, 0, "an unscrolled list starts at the top")
            XCTAssertLessThan(mounted.count, 100,
                              "mounted \(mounted.count) of \(rowCount) rows — the window is not bounded")
            XCTAssertGreaterThan(mounted.count, 1,
                                 "mounted \(mounted.count) rows, which is too few to fill 760pt")

            // The widget tree, not just the arithmetic.
            XCTAssertLessThan(widgetCount(in: window), 500,
                              "the tree holds \(widgetCount(in: window)) widgets for \(rowCount) rows")

            let visible = labels(in: window)
            XCTAssertTrue(visible.contains("row 0"))
            XCTAssertFalse(visible.contains("row \(rowCount - 1)"),
                           "the last row is mounted, so nothing was virtualised")
        }
    }

    func testScrollingMovesTheWindow() {
        MainActor.assumeIsolated {
            let node = Node(BigList())
            Engine.render(node)

            let window = gtk_window_new(0)
            gtk_window_set_default_size(window, 480, 760)
            gtk_container_add(window, node.native!)
            gtk_widget_show_all(window)
            settle(window, node)

            guard let scroller = findScrolledWindow(node.native!) else {
                return XCTFail("no GtkScrolledWindow in the rendered list")
            }
            let adjustment = gtk_scrolled_window_get_vadjustment(scroller)

            // Only meaningful if the content is taller than the viewport.
            XCTAssertGreaterThan(gtk_adjustment_get_upper_v(adjustment), 10_000,
                                 "the spacers are not holding the list's full height open")

            gtk_adjustment_set_value_v(adjustment, 3_000)
            settle(window, node)

            guard let rows = findRows(node) else { return XCTFail("no VirtualisedRows") }
            let mounted = rows.window(count: rowCount)

            // 3000pt at 30pt a row is row 100, less the overscan.
            XCTAssertGreaterThan(mounted.lowerBound, 80,
                                 "the window is still at \(mounted.lowerBound) after scrolling 3000pt")
            XCTAssertLessThan(mounted.count, 100, "the window grew instead of moving")

            let visible = labels(in: window)
            XCTAssertTrue(visible.contains("row 100"), "row 100 should be on screen at 3000pt")
            XCTAssertFalse(visible.contains("row 0"), "row 0 is still mounted after scrolling past it")
        }
    }
}
#endif
