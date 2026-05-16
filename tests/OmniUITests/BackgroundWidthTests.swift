#if os(Linux)
import XCTest
import Glibc
@testable import OmniUI


private let gtk_widget_get_allocated_width_t: @convention(c) (NativeView) -> Int32 =
    fn(libgtk, "gtk_widget_get_allocated_width")
private let gtk_events_pending_t: @convention(c) () -> Int32 = fn(libgtk, "gtk_events_pending")
private let gtk_main_iteration_t: @convention(c) () -> Int32 = fn(libgtk, "gtk_main_iteration")
private let gtk_widget_size_allocate_t: @convention(c) (NativeView, UnsafeMutableRawPointer) -> Void =
    fn(libgtk, "gtk_widget_size_allocate")

private let windowWidth: Int32 = 480

/// A short label in a row with a trailing Spacer, inside a column carrying the
/// colour, beside an expanding sibling.
private struct Panel: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack { Text("the view above") }.frame(height: 80)
            Divider()
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("token from decidePolicy")
                        Text("none yet")
                    }
                    Spacer()
                }
                .padding(horizontal: 16, vertical: 12)
            }
            .background(.controlBackground)
        }
    }
}

@MainActor private func styledWidgets(in widget: NativeView) -> [NativeView] {
    let mine = g_object_get_data(widget, CSSSlot.fill.rawValue) != nil ? [widget] : []
    return mine + children(of: widget).flatMap { styledWidgets(in: $0) }
}

final class BackgroundWidthTests: XCTestCase {
    override func setUp() { super.setUp(); gtk_init(nil, nil) }

    func testAColumnsBackgroundSpansItsWidth() {
        MainActor.assumeIsolated {
            let node = Node(Panel())
            Engine.render(node)

            let window = gtk_window_new(0)
            gtk_window_set_default_size(window, windowWidth, 300)
            gtk_container_add(window, node.native!)
            gtk_widget_show_all(window)

            var spun = 0
            while gtk_events_pending_t() != 0 && spun < 20_000 { _ = gtk_main_iteration_t(); spun += 1 }
            var rect: [Int32] = [0, 0, windowWidth, 300]
            rect.withUnsafeMutableBytes { gtk_widget_size_allocate_t(window, $0.baseAddress!) }
            while gtk_events_pending_t() != 0 && spun < 40_000 { _ = gtk_main_iteration_t(); spun += 1 }

            let styled = styledWidgets(in: node.native!)
            XCTAssertEqual(styled.count, 1, "expected exactly one styled widget, found \(styled.count)")

            guard let panel = styled.first else { return }
            XCTAssertEqual(gtk_widget_get_allocated_width_t(panel), windowWidth,
                           "the background painted \(gtk_widget_get_allocated_width_t(panel))pt of \(windowWidth)")
        }
    }
}
#endif
