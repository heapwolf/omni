#if os(Linux)
import XCTest
import Glibc
@testable import OmniUI


private let gtk_events_pending_t: @convention(c) () -> Int32 = fn(libgtk, "gtk_events_pending")
private let gtk_main_iteration_t: @convention(c) () -> Int32 = fn(libgtk, "gtk_main_iteration")

/// onAppear is deferred to GTK's loop, so the loop has to turn.
@MainActor private func spinGTK() {
    var spun = 0
    while gtk_events_pending_t() != 0 && spun < 10_000 { _ = gtk_main_iteration_t(); spun += 1 }
}


/// A second onAppear overload once made every call site ambiguous. This file
/// failing to compile is the regression.
private struct Watched: View {
    var onShow: () -> Void

    var body: some View {
        Text("watched")
            .onAppear(perform: onShow)
            .onDisappear { }
            .task { }
    }
}

final class LifecycleModifierTests: XCTestCase {
    override func setUp() { super.setUp(); gtk_init(nil, nil) }

    func testOnAppearFiresOnce() {
        MainActor.assumeIsolated {
            var shown = 0
            let node = Node(Watched(onShow: { shown += 1 }))
            Engine.render(node)
            Engine.render(node)
            spinGTK()
            XCTAssertEqual(shown, 1)
        }
    }
}
#endif
