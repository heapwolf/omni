#if os(macOS)
import XCTest
import AppKit
import WebKit
@testable import OmniUI

/// A web view fills what it's given, as SwiftUI's does. At the default
/// hugging it had no size of its own and a ZStack placed it at zero: a sign-in
/// page under a header came up as an empty window.
@MainActor
final class macOSWebViewFillTests: XCTestCase {
    private struct Screen: View {
        var body: some View {
            VStack(spacing: 0) {
                Text("header").frame(height: 56)
                ZStack {
                    WebView(url: URL(string: "about:blank")!)
                }
            }
        }
    }

    private func find(_ view: NSView) -> WKWebView? {
        if let web = view as? WKWebView { return web }
        for sub in view.subviews { if let found = find(sub) { return found } }
        return nil
    }

    func testAWebViewInAZStackFillsIt() {
        MainActor.assumeIsolated {
            let node = Node(Screen())
            Engine.render(node)
            guard let root = node.native else { return XCTFail("no root view") }
            let host = NSView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
            host.addSubview(root)
            NSLayoutConstraint.activate([
                root.widthAnchor.constraint(equalToConstant: 800),
                root.heightAnchor.constraint(equalToConstant: 600),
                root.leadingAnchor.constraint(equalTo: host.leadingAnchor),
                root.topAnchor.constraint(equalTo: host.topAnchor)
            ])
            host.layoutSubtreeIfNeeded()

            guard let web = find(root) else { return XCTFail("no web view") }
            XCTAssertEqual(web.frame.width, 800, accuracy: 1)
            XCTAssertEqual(web.frame.height, 544, accuracy: 1, "the window below the header")
        }
    }
}
#endif
