#if os(Linux)
import XCTest
import Glibc
@testable import OmniUI

// NavigationLink must push its destination onto the enclosing NavigationStack.
private let gtk_button_clicked_nav: @convention(c) (NativeView) -> Void =
    fn(libgtk, "gtk_button_clicked")

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

final class NavigationTests: XCTestCase {

    override func setUp() {
        super.setUp()
        gtk_init(nil, nil)
    }

    func testNavigationLinkPushesItsDestination() {
        MainActor.assumeIsolated {
            let node = Node(Screen())
            Engine.render(node)

            XCTAssertTrue(labels(in: node.native!).contains("root"),
                          "root screen missing; got \(labels(in: node.native!))")
            XCTAssertFalse(labels(in: node.native!).contains("detail"),
                           "detail visible before pushing")

            guard let button = button(titled: "Push", in: node.native!) else {
                return XCTFail("no NavigationLink button rendered")
            }
            gtk_button_clicked_nav(button)

            XCTAssertTrue(labels(in: node.native!).contains("detail"),
                          "tapping the link did not push; visible labels: \(labels(in: node.native!))")
        }
    }
}
#endif
