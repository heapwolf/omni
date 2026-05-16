#if os(Linux)
import XCTest
import Glibc
@testable import OmniUI


private let g_type_from_name: @convention(c) (UnsafePointer<CChar>) -> UInt =
    fn(libgobj, "g_type_from_name")
private let g_signal_lookup: @convention(c) (UnsafePointer<CChar>, UInt) -> UInt32 =
    fn(libgobj, "g_signal_lookup")
private let g_signal_handlers_disconnect_matched: @convention(c) (
    NativeView, UInt32, UInt32, UInt32,
    UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, UnsafeMutableRawPointer?
) -> UInt32 = fn(libgobj, "g_signal_handlers_disconnect_matched")
private let gtk_button_clicked: @convention(c) (NativeView) -> Void =
    fn(libgtk, "gtk_button_clicked")

private let G_SIGNAL_MATCH_ID: UInt32 = 1 << 0

@MainActor
private final class Hits {
    var count = 0
}

private func drainHandlerCount(_ widget: NativeView,
                               signal: String,
                               typeName: String) -> UInt32 {
    let gtype = g_type_from_name(typeName)
    let signalID = g_signal_lookup(signal, gtype)
    XCTAssertNotEqual(signalID, 0, "could not look up \(typeName)::\(signal)")
    return g_signal_handlers_disconnect_matched(
        widget, G_SIGNAL_MATCH_ID, signalID, 0, nil, nil, nil
    )
}

final class LinuxEventBindingTests: XCTestCase {

    override func setUp() {
        super.setUp()
        gtk_init(nil, nil)
    }

    func testRepeatedRendersKeepExactlyOneHandler() {
        MainActor.assumeIsolated {
            let node = Node(Button("Tap", action: {}))
            Engine.render(node)
            let button = node.native!

            for _ in 0..<5 { Engine.render(node) }

            XCTAssertEqual(drainHandlerCount(button, signal: "clicked",
                                             typeName: "GtkButton"),
                           1,
                           "six renders must still leave a single click handler")
        }
    }

    func testClickFiresTheActionExactlyOnce() {
        MainActor.assumeIsolated {
            let hits = Hits()
            let node = Node(Button("Tap", action: { hits.count += 1 }))
            Engine.render(node)
            for _ in 0..<3 { Engine.render(node) }

            gtk_button_clicked(node.native!)

            XCTAssertEqual(hits.count, 1,
                           "action ran once per connected handler instead of once")
        }
    }

    // Re-rendering replaces the view, so the handler must invoke the closure
    // from the newest render, not the one captured on first bind.
    func testRerenderSwapsInTheNewClosure() {
        MainActor.assumeIsolated {
            let stale = Hits()
            let fresh = Hits()

            let node = Node(Button("Tap", action: { stale.count += 1 }))
            Engine.render(node)

            node.view = Button("Tap", action: { fresh.count += 1 })
            Engine.render(node)

            gtk_button_clicked(node.native!)

            XCTAssertEqual(stale.count, 0, "the superseded closure still ran")
            XCTAssertEqual(fresh.count, 1, "the current closure did not run")
        }
    }
}
#endif
