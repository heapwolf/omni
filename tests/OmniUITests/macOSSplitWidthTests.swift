#if os(macOS)
import XCTest
import AppKit
@testable import OmniUI

final class macOSSplitWidthTests: XCTestCase {
    /// The sidebar opens at its width (240), whatever the detail shows.
    func testTheSidebarOpensAtItsWidth() {
        MainActor.assumeIsolated {
            let node = Node(NavigationSplitView { Text("Sidebar") } detail: { Text("Detail") })
            Engine.render(node)
            let window = OmniWindow(contentRect: NSRect(x: 0, y: 0, width: 1100, height: 700),
                                    styleMask: [.titled, .resizable], backing: .buffered, defer: false)
            window.contentView = OmniWindow.contentHost(for: node.native!)
            window.layoutIfNeeded()
            window.layoutIfNeeded()
            let split = try! XCTUnwrap(node.native as? NSSplitView)
            XCTAssertEqual(split.arrangedSubviews.first?.frame.width, 240)
            // And it stays as the window resizes.
            window.setContentSize(NSSize(width: 900, height: 700))
            window.layoutIfNeeded()
            XCTAssertEqual(split.arrangedSubviews.first?.frame.width, 240)
        }
    }
}
#endif
