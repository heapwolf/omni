#if os(Linux)
import XCTest
import Glibc
@testable import OmniUI


private let gtk_adjustment_get_value_b: @convention(c) (UnsafeMutableRawPointer) -> Double =
    fn(libgtk, "gtk_adjustment_get_value")
private let gtk_adjustment_set_value_b: @convention(c) (UnsafeMutableRawPointer, Double) -> Void =
    fn(libgtk, "gtk_adjustment_set_value")
private let gtk_events_pending_b: @convention(c) () -> Int32 = fn(libgtk, "gtk_events_pending")
private let gtk_main_iteration_b: @convention(c) () -> Int32 = fn(libgtk, "gtk_main_iteration")
private let gtk_widget_size_allocate_b: @convention(c) (NativeView, UnsafeMutableRawPointer) -> Void =
    fn(libgtk, "gtk_widget_size_allocate")

private struct Scroller: View {
    @State var y: Double = 0
    var body: some View {
        ScrollView(axis: .vertical, offset: $y) {
            VStack(spacing: 0) {
                ForEach(0..<200, id: \.self) { index in
                    Text("line \(index)").frame(height: 20)
                }
            }
        }
    }
}

@MainActor private func pump(_ window: NativeView) {
    for _ in 0..<3 {
        var spun = 0
        while gtk_events_pending_b() != 0 && spun < 20_000 {
            _ = gtk_main_iteration_b()
            spun += 1
        }
        var rect: [Int32] = [0, 0, 400, 300]
        rect.withUnsafeMutableBytes { gtk_widget_size_allocate_b(window, $0.baseAddress!) }
    }
}

final class ScrollBindingTests: XCTestCase {

    override func setUp() {
        super.setUp()
        gtk_init(nil, nil)
    }

    @MainActor private static func mount() -> (Node, NativeView, UnsafeMutableRawPointer) {
        let node = Node(Scroller())
        Engine.render(node)
        let window = gtk_window_new(0)
        gtk_window_set_default_size(window, 400, 300)
        gtk_container_add(window, node.native!)
        gtk_widget_show_all(window)
        pump(window)
        return (node, window, gtk_scrolled_window_get_vadjustment(node.native!))
    }

    /// Scrolling the widget reaches the binding.
    func testTheViewReportsItsOffset() {
        MainActor.assumeIsolated {
            let (node, window, adjustment) = Self.mount()

            gtk_adjustment_set_value_b(adjustment, 640)
            pump(window)

            guard let scroller = node.view as? Scroller else { return XCTFail("no Scroller") }
            XCTAssertEqual(scroller.y, 640, accuracy: 1,
                           "the widget scrolled to 640 and the binding says \(scroller.y)")
        }
    }

    /// Writing the binding scrolls the widget.
    func testSettingTheBindingScrollsTheView() {
        MainActor.assumeIsolated {
            let (node, window, adjustment) = Self.mount()

            guard let scroller = node.view as? Scroller else { return XCTFail("no Scroller") }
            scroller.y = 1_200
            pump(window)

            XCTAssertEqual(gtk_adjustment_get_value_b(adjustment), 1_200, accuracy: 1,
                           "setting offset to 1200 left the widget at \(gtk_adjustment_get_value_b(adjustment))")
        }
    }

    /// The two halves must settle rather than oscillate.
    func testTheTwoHalvesSettle() {
        MainActor.assumeIsolated {
            let (node, window, adjustment) = Self.mount()
            guard let scroller = node.view as? Scroller else { return XCTFail("no Scroller") }

            scroller.y = 800
            pump(window)
            pump(window)

            XCTAssertEqual(gtk_adjustment_get_value_b(adjustment), 800, accuracy: 1)
            XCTAssertEqual(scroller.y, 800, accuracy: 1)
        }
    }
}
#endif
