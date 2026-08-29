#if os(macOS)
import XCTest
import AppKit
@testable import OmniUI

final class macOSWindowSizeTests: XCTestCase {
    /// A page taller than the window, appearing in it (a row's detail opened
    /// in a short window), doesn't make the window grow to fit it.
    func testContentTallerThanTheWindowDoesNotGrowIt() {
        MainActor.assumeIsolated {
            let root = NSView()
            let window = OmniWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 400),
                                    styleMask: [.titled, .resizable], backing: .buffered, defer: false)
            window.contentView = OmniWindow.contentHost(for: root)
            window.layoutIfNeeded()
            XCTAssertEqual(root.frame.height, 400, "it fills the window")

            let page = NSView()
            page.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(page)
            NSLayoutConstraint.activate([
                page.topAnchor.constraint(equalTo: root.topAnchor), page.bottomAnchor.constraint(equalTo: root.bottomAnchor),
                page.leadingAnchor.constraint(equalTo: root.leadingAnchor), page.trailingAnchor.constraint(equalTo: root.trailingAnchor),
                page.heightAnchor.constraint(greaterThanOrEqualToConstant: 700)
            ])
            window.layoutIfNeeded()
            XCTAssertEqual(window.contentView?.frame.height, 400, "the window grew to fit the page")

            // Nor wider, nor narrower.
            let least = page.widthAnchor.constraint(greaterThanOrEqualToConstant: 800)
            least.isActive = true
            window.layoutIfNeeded()
            XCTAssertEqual(window.contentView?.frame.width, 600, "a page's least width grew the window")
            least.isActive = false
            page.widthAnchor.constraint(lessThanOrEqualToConstant: 500).isActive = true
            window.layoutIfNeeded()
            XCTAssertEqual(window.contentView?.frame.width, 600, "a page's most width shrank the window")
        }
    }
}
#endif
