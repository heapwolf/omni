#if os(Linux)
import XCTest
import Glibc
@testable import OmniUI
import KitchenSinkUI

// Renders the example app the way a person would see it — one capture per tab,
// reached by clicking the real tab buttons — and asserts each screen actually
// paints. It is the engine-level counterpart to running the APK by hand: it
// catches a component that builds no widget, a modifier a backend drops, and a
// container that collapses its subtree, without needing a screen.

private let gtk_widget_draw_ks: @convention(c) (NativeView, UnsafeMutableRawPointer) -> Void =
    fn(libgtk, "gtk_widget_draw")
private let gtk_events_pending_ks: @convention(c) () -> Int32 = fn(libgtk, "gtk_events_pending")
private let gtk_main_iteration_ks: @convention(c) () -> Int32 = fn(libgtk, "gtk_main_iteration")
private let gtk_widget_size_allocate_ks: @convention(c) (NativeView, UnsafeMutableRawPointer) -> Void =
    fn(libgtk, "gtk_widget_size_allocate")
private let gtk_button_clicked_ks: @convention(c) (NativeView) -> Void =
    fn(libgtk, "gtk_button_clicked")
private let cairo_image_surface_create_ks: @convention(c) (Int32, Int32, Int32) -> UnsafeMutableRawPointer =
    fn(libcairo, "cairo_image_surface_create")
private let cairo_create_ks: @convention(c) (UnsafeMutableRawPointer) -> UnsafeMutableRawPointer =
    fn(libcairo, "cairo_create")
private let cairo_surface_write_to_png_ks: @convention(c) (UnsafeMutableRawPointer, UnsafePointer<CChar>) -> Int32 =
    fn(libcairo, "cairo_surface_write_to_png")
private let cairo_image_surface_get_data_ks: @convention(c) (UnsafeMutableRawPointer) -> UnsafeMutablePointer<UInt8>? =
    fn(libcairo, "cairo_image_surface_get_data")
private let cairo_image_surface_get_stride_ks: @convention(c) (UnsafeMutableRawPointer) -> Int32 =
    fn(libcairo, "cairo_image_surface_get_stride")
private let cairo_surface_flush_ks: @convention(c) (UnsafeMutableRawPointer) -> Void =
    fn(libcairo, "cairo_surface_flush")

final class KitchenSinkRenderTests: XCTestCase {

    // Static, along with `capture` below, for the reason
    // TextFieldConfigurationTests spells out: every body runs inside
    // MainActor.assumeIsolated, and reading an instance member from in there
    // sends `self` — an XCTestCase, which is not Sendable — into the closure.
    // Swift 6 rejects it. Nothing here reads instance state, so nothing is lost.
    private static let width: Int32 = 480
    private static let height: Int32 = 760

    override func setUp() {
        super.setUp()
        gtk_init(nil, nil)
    }

    func testEveryScreenBuildsAndPaints() {
        MainActor.assumeIsolated {
            let node = Node(KitchenSinkView())
            Engine.render(node)
            XCTAssertNotNil(node.native, "the sink produced no root widget")

            let window = gtk_window_new(0)
            gtk_window_set_default_size(window, Self.width, Self.height)
            gtk_container_add(window, node.native!)
            gtk_widget_show_all(window)

            // Every order, not just left to right: swapping between two screens
            // that each own a scroll view is what shook out the container reuse
            // bugs, and a tab is often revisited.
            // The Web screen's marker is one of its static labels, not the
            // page title: the title comes from the engine, and this machine may
            // or may not have one.
            let screens = [("Inbox", "2 unread"), ("Compose", "New message"),
                           ("Profile", "Activity"), ("Web", "token from decidePolicy")]
            var widgetsAfterFirstVisit: [String: Int] = [:]

            for (tab, marker) in screens + screens.reversed() + screens {
                if let tabButton = button(titled: tab, in: window) {
                    gtk_button_clicked_ks(tabButton)
                } else {
                    XCTFail("no \(tab) tab button in the rendered tree")
                }
                Engine.render(node)
                gtk_widget_show_all(window)

                let (painted, colours) = Self.capture(window, to: "/tmp/omni-kitchensink-\(tab.lowercased()).png")

                XCTAssertTrue(labels(in: window).contains(marker),
                              "the \(tab) screen is not showing: no \"\(marker)\" label")
                XCTAssertGreaterThan(painted, 10_000, "the \(tab) screen painted almost nothing")
                XCTAssertGreaterThan(colours, 20,
                                     "the \(tab) screen used only \(colours) colours — widgets are probably not drawing")

                // Leaving a screen has to take its widgets with it. A backend
                // that forgets a subtree without detaching it grows the tree
                // every visit, and on Android a single-child container throws
                // outright when the replacement arrives on top of the old one.
                let widgets = widgetCount(in: window)
                if let first = widgetsAfterFirstVisit[tab] {
                    XCTAssertEqual(widgets, first,
                                   "revisiting \(tab) left \(widgets - first) widgets behind")
                } else {
                    widgetsAfterFirstVisit[tab] = widgets
                }
            }
        }
    }

    /// Draws the window into an image and returns how much of it was painted.
    @MainActor private static func capture(_ window: NativeView, to path: String) -> (painted: Int, colours: Int) {
        var pumped = 0
        while gtk_events_pending_ks() != 0 && pumped < 20_000 {
            _ = gtk_main_iteration_ks()
            pumped += 1
        }

        // gtk_widget_draw refuses to render a widget that still needs
        // allocation, which scrolled content reliably does after only pumping
        // the loop. Allocate explicitly first.
        var rect: [Int32] = [0, 0, Self.width, Self.height]
        rect.withUnsafeMutableBytes { gtk_widget_size_allocate_ks(window, $0.baseAddress!) }
        while gtk_events_pending_ks() != 0 && pumped < 40_000 {
            _ = gtk_main_iteration_ks()
            pumped += 1
        }

        // Allocated again: the pump above runs GTK's idle queue, and anything
        // that re-renders from there — a GeometryReader writing its size back
        // into state, which ProfileScreen does — queues a fresh resize and puts
        // alloc_needed straight back. Drawing then paints nothing at all.
        rect.withUnsafeMutableBytes { gtk_widget_size_allocate_ks(window, $0.baseAddress!) }

        let surface = cairo_image_surface_create_ks(0, Self.width, Self.height)
        gtk_widget_draw_ks(window, cairo_create_ks(surface))
        path.withCString { XCTAssertEqual(cairo_surface_write_to_png_ks(surface, $0), 0) }

        cairo_surface_flush_ks(surface)
        guard let data = cairo_image_surface_get_data_ks(surface) else {
            XCTFail("no surface data")
            return (0, 0)
        }
        let stride = Int(cairo_image_surface_get_stride_ks(surface))

        var painted = 0
        var distinct = Set<UInt32>()
        for y in 0..<Int(Self.height) {
            for x in 0..<Int(Self.width) {
                let offset = y * stride + x * 4
                guard data[offset + 3] != 0 else { continue }
                painted += 1
                distinct.insert(UInt32(data[offset]) << 16 | UInt32(data[offset + 1]) << 8 | UInt32(data[offset + 2]))
            }
        }
        return (painted, distinct.count)
    }
}
#endif
