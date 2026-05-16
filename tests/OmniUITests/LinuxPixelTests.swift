#if os(Linux)
import XCTest
import Glibc
@testable import OmniUI


private let gtk_widget_draw: @convention(c) (NativeView, UnsafeMutableRawPointer) -> Void =
    fn(libgtk, "gtk_widget_draw")
private let gtk_widget_get_allocated_width_px: @convention(c) (NativeView) -> Int32 =
    fn(libgtk, "gtk_widget_get_allocated_width")
private let gtk_widget_get_allocated_height_px: @convention(c) (NativeView) -> Int32 =
    fn(libgtk, "gtk_widget_get_allocated_height")
private let gtk_events_pending_px: @convention(c) () -> Int32 =
    fn(libgtk, "gtk_events_pending")
private let gtk_main_iteration_px: @convention(c) () -> Int32 =
    fn(libgtk, "gtk_main_iteration")

private let cairo_image_surface_create: @convention(c) (Int32, Int32, Int32) -> UnsafeMutableRawPointer =
    fn(libcairo, "cairo_image_surface_create")
private let cairo_create_surface: @convention(c) (UnsafeMutableRawPointer) -> UnsafeMutableRawPointer =
    fn(libcairo, "cairo_create")
private let cairo_surface_write_to_png: @convention(c) (UnsafeMutableRawPointer, UnsafePointer<CChar>) -> Int32 =
    fn(libcairo, "cairo_surface_write_to_png")
private let cairo_image_surface_get_data: @convention(c) (UnsafeMutableRawPointer) -> UnsafeMutablePointer<UInt8>? =
    fn(libcairo, "cairo_image_surface_get_data")
private let cairo_image_surface_get_stride: @convention(c) (UnsafeMutableRawPointer) -> Int32 =
    fn(libcairo, "cairo_image_surface_get_stride")
private let cairo_surface_flush: @convention(c) (UnsafeMutableRawPointer) -> Void =
    fn(libcairo, "cairo_surface_flush")

private let CAIRO_FORMAT_ARGB32: Int32 = 0

// GtkAllocation is a GdkRectangle: four ints, x/y/width/height.
private let gtk_widget_get_allocation: @convention(c) (NativeView, UnsafeMutableRawPointer) -> Void =
    fn(libgtk, "gtk_widget_get_allocation")

private struct GtkAllocation {
    var x: Int32 = 0, y: Int32 = 0, width: Int32 = 0, height: Int32 = 0

    init(of widget: NativeView) {
        var fields = [Int32](repeating: 0, count: 4)
        fields.withUnsafeMutableBytes { gtk_widget_get_allocation(widget, $0.baseAddress!) }
        (x, y, width, height) = (fields[0], fields[1], fields[2], fields[3])
    }
}

@MainActor
private struct SpacedScreen: View {
    var body: some View {
        VStack(spacing: 8) {
            Text("top")
            Spacer()
            Text("bottom")
        }
    }
}

@MainActor
private struct Screen: View {
    var body: some View {
        VStack(spacing: 8) {
            Text("Hello from Omni")
            Button("Tap me", action: {})
        }
    }
}

private func paintedPixelCount(_ surface: UnsafeMutableRawPointer,
                               width: Int, height: Int) -> Int {
    cairo_surface_flush(surface)
    guard let data = cairo_image_surface_get_data(surface) else { return 0 }
    let stride = Int(cairo_image_surface_get_stride(surface))

    var painted = 0
    for y in 0..<height {
        for x in 0..<width {
            // ARGB32 is premultiplied little-endian: byte 3 is alpha.
            if data[y * stride + x * 4 + 3] != 0 { painted += 1 }
        }
    }
    return painted
}

/// Renders `view` in a window of the given size and returns the root
/// widget's allocation once layout has settled.
@MainActor
private func allocation(of view: any View,
                        width: Int32, height: Int32) -> GtkAllocation {
    let node = Node(view)
    Engine.render(node)

    let window = gtk_window_new(0)
    gtk_window_set_default_size(window, width, height)
    gtk_container_add(window, node.native!)
    gtk_widget_show_all(window)

    var pumped = 0
    while gtk_events_pending_px() != 0 && pumped < 5_000 {
        _ = gtk_main_iteration_px()
        pumped += 1
    }

    return GtkAllocation(of: node.native!)
}

final class LinuxPixelTests: XCTestCase {

    override func setUp() {
        super.setUp()
        gtk_init(nil, nil)
    }

    func testStackWithoutSpacerHugsContentAndCenters() {
        MainActor.assumeIsolated {
            let height: Int32 = 240
            let alloc = allocation(of: Screen(), width: 420, height: height)

            XCTAssertLessThan(alloc.height, height,
                              "stack should size to its content, not fill")
            XCTAssertGreaterThan(alloc.height, 1)

            let expectedY = (height - alloc.height) / 2
            XCTAssertEqual(alloc.y, expectedY, accuracy: 2,
                           "stack is not vertically centered in the window")
        }
    }

    // A Spacer wants the surplus space, so the stack must fill instead.
    func testStackWithSpacerFillsTheWindow() {
        MainActor.assumeIsolated {
            let height: Int32 = 240
            let alloc = allocation(of: SpacedScreen(), width: 420, height: height)

            XCTAssertEqual(alloc.height, height, accuracy: 2,
                           "a stack containing a Spacer should fill its parent")
            XCTAssertEqual(alloc.y, 0, accuracy: 2)
        }
    }

    func testTreeActuallyPaintsPixels() {
        MainActor.assumeIsolated {
            let node = Node(Screen())
            Engine.render(node)

            let width: Int32 = 420
            let height: Int32 = 240

            let window = gtk_window_new(0)
            gtk_window_set_default_size(window, width, height)
            gtk_container_add(window, node.native!)
            gtk_widget_show_all(window)

            var pumped = 0
            while gtk_events_pending_px() != 0 && pumped < 5_000 {
                _ = gtk_main_iteration_px()
                pumped += 1
            }

            XCTAssertGreaterThan(gtk_widget_get_allocated_width_px(node.native!), 1)
            XCTAssertGreaterThan(gtk_widget_get_allocated_height_px(node.native!), 1)

            // Draw the window, not just the content box: the window is what
            // paints the theme background, so this matches what is on screen.
            let surface = cairo_image_surface_create(CAIRO_FORMAT_ARGB32, width, height)
            let cr = cairo_create_surface(surface)
            gtk_widget_draw(window, cr)

            "/tmp/omni-render.png".withCString { path in
                XCTAssertEqual(cairo_surface_write_to_png(surface, path), 0,
                               "could not write the PNG")
            }

            let painted = paintedPixelCount(surface, width: Int(width), height: Int(height))
            XCTAssertGreaterThan(painted, 100,
                                 "the widget tree painted nothing — the window "
                                 + "will appear empty on screen")
        }
    }
}
#endif
