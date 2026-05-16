#if os(Linux)
import XCTest
import Glibc
@testable import OmniUI

private let alloc_w: @convention(c) (NativeView) -> Int32 = fn(libgtk, "gtk_widget_get_allocated_width")
private let pending: @convention(c) () -> Int32 = fn(libgtk, "gtk_events_pending")
private let iterate: @convention(c) () -> Int32 = fn(libgtk, "gtk_main_iteration")

@MainActor
private struct Sample: View {
    let mono: Bool
    let size: Font
    @MainActor var body: some View {
        mono ? Text("iiiiiiiiii").monospaced().font(size)
             : Text("iiiiiiiiii").font(size)
    }
}

@MainActor private func width(mono: Bool, size: Font) -> Int32 {
    let node = Node(Sample(mono: mono, size: size))
    Engine.render(node)
    let window = gtk_window_new(0)
    gtk_container_add(window, node.native!)
    gtk_widget_show_all(window)
    var n = 0
    while pending() != 0 && n < 5000 { _ = iterate(); n += 1 }
    return alloc_w(node.native!)
}

final class TextFontTests: XCTestCase {
    override func setUp() { super.setUp(); gtk_init(nil, nil) }

    // Ten narrow glyphs are much wider in a fixed-pitch face than a proportional one.
    func testMonospacedChangesGlyphWidth() {
        MainActor.assumeIsolated {
            let proportional = width(mono: false, size: .body)
            let monospaced = width(mono: true, size: .body)
            print("WIDTHS proportional=\(proportional) monospaced=\(monospaced)")
            XCTAssertGreaterThan(monospaced, proportional,
                "monospaced() had no effect: both measured \(proportional)")
        }
    }

    func testFontSizeIsApplied() {
        MainActor.assumeIsolated {
            let small = width(mono: false, size: .caption)
            let large = width(mono: false, size: .largeTitle)
            print("WIDTHS caption=\(small) largeTitle=\(large)")
            XCTAssertGreaterThan(large, small, "font() had no effect on size")
        }
    }
}
#endif
