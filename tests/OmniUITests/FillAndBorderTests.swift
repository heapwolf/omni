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

private let gtk_label_get_text_t: @convention(c) (NativeView) -> UnsafePointer<CChar>? =
    fn(libgtk, "gtk_label_get_text")

private func labelText(of view: NativeView?) -> String? {
    guard let view, let text = gtk_label_get_text_t(view) else { return nil }
    return String(cString: text)
}

private struct Row: View {
    var fills: Bool

    var body: some View {
        HStack(spacing: 0) {
            if fills {
                Text("grow").background(.controlBackground).frame(maxWidth: .infinity)
            } else {
                Text("grow").background(.controlBackground)
            }
            Text("fixed")
        }
    }
}

@MainActor private func styledWidgets(in widget: NativeView) -> [NativeView] {
    let mine = g_object_get_data(widget, CSSSlot.fill.rawValue) != nil ? [widget] : []
    return mine + children(of: widget).flatMap { styledWidgets(in: $0) }
}

@MainActor private func styledWidth(of view: some View) -> Int32 {
    let node = Node(view)
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

    return styledWidgets(in: node.native!).first.map { gtk_widget_get_allocated_width_t($0) } ?? -1
}

final class FillAndBorderTests: XCTestCase {
    override func setUp() { super.setUp(); gtk_init(nil, nil) }

    func testMaxWidthInfinityTakesTheSurplus() {
        MainActor.assumeIsolated {
            let plain = styledWidth(of: Row(fills: false))
            let filled = styledWidth(of: Row(fills: true))

            XCTAssertGreaterThan(plain, 0, "the plain row never laid out")
            XCTAssertGreaterThan(filled, plain * 2,
                                 "maxWidth .infinity gave \(filled)pt against \(plain)pt without it")
        }
    }

    /// Pango applies letter spacing; the assertion is that the attribute path
    /// runs and the label still holds its text.
    func testTrackedTextStillRenders() {
        MainActor.assumeIsolated {
            let node = Node(Text("tracked").tracking(1.5).lineSpacing(4))
            Engine.render(node)
            XCTAssertEqual(labelText(of: node.native!), "tracked")
        }
    }

    func testSpacingModifiersCarryTheirValues() {
        MainActor.assumeIsolated {
            let text = Text("x").tracking(2).lineSpacing(6).multilineTextAlignment(.trailing)
            XCTAssertEqual(text.tracking, 2)
            XCTAssertEqual(text.lineSpacing, 6)
            XCTAssertEqual(text.alignment, .trailing)
        }
    }

    func testEdgePaddingInsetsOnlyThatEdge() {
        MainActor.assumeIsolated {
            let one = PaddingModifier(insets: EdgeInsets(top: 0, leading: 0, bottom: 12, trailing: 0))
            let built = Text("x").padding(.bottom, 12)
            XCTAssertEqual(built.modifier.insets, one.insets)

            let sides = Text("x").padding(.horizontal, 8).modifier.insets
            XCTAssertEqual(sides, EdgeInsets(top: 0, leading: 8, bottom: 0, trailing: 8))

            let every = Text("x").padding(4).modifier.insets
            XCTAssertEqual(every, EdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4))
        }
    }

    func testBorderBecomesACSSDeclaration() {
        MainActor.assumeIsolated {
        let edged = ModifierView(content: Text("edged"), borderColor: .red, borderWidth: 2)
        XCTAssertEqual(edged.cssDeclarations, ["border: 2.0px solid rgba(255,58,48,1.0);"])

        let plain = ModifierView(content: Text("plain"))
        XCTAssertTrue(plain.cssDeclarations.isEmpty)
        }
    }
}
#endif
