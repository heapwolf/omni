#if os(iOS)
import XCTest
import UIKit
@testable import OmniUI

// NavigationLink must push its destination onto the enclosing NavigationStack.
// Mirrors NavigationTests, tapping the real UIButton instead of a GTK one.

@MainActor
private struct Screen: View {
    @MainActor var body: some View {
        NavigationStack {
            VStack {
                Text("root")
                NavigationLink("Push", destination: Text("detail"))
            }
        }
    }
}

final class iOSNavigationTests: XCTestCase {

    func testNavigationLinkPushesItsDestination() {
        MainActor.assumeIsolated {
            let node = Node(Screen())
            Engine.render(node)

            XCTAssertTrue(labels(in: node.native!).contains("root"),
                          "root screen missing; got \(labels(in: node.native!))")
            XCTAssertFalse(labels(in: node.native!).contains("detail"),
                           "detail visible before pushing")

            guard let pushButton = button(titled: "Push", in: node.native!) else {
                return XCTFail("no NavigationLink button rendered")
            }
            pushButton.sendActions(for: .touchUpInside)

            XCTAssertTrue(labels(in: node.native!).contains("detail"),
                          "tapping the link did not push; visible labels: \(labels(in: node.native!))")
        }
    }
}
#endif
