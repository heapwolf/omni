#if os(macOS)
import XCTest
import AppKit
@testable import OmniUI

/// What a live resize costs: a long page, laid out at a width a step
/// narrower each time, as a window being dragged is.
@MainActor
private struct LongPage: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(0..<300, id: \.self) { index in
                    HStack(spacing: 12) {
                        Text("Row \(index)")
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("1,250,000.00 NGN")
                            Text("Sep 30, 2026 at 7:51 AM")
                        }
                    }
                    .padding(8)
                }
            }
            .padding(24)
        }
    }
}

@MainActor private final class Counts { var builds = 0; var sizes: [Double] = [] }

@MainActor private struct Counted: View {
    let counts: Counts
    var body: some View {
        counts.builds += 1
        return Text("content")
    }
}

final class macOSResizeCostTests: XCTestCase {
    /// Responsive's reader: it reports each size, and its content, which
    /// ignores the size, isn't rebuilt for each one.
    func testAMeasureOnlyReaderDoesNotRebuildItsContentOnResize() {
        MainActor.assumeIsolated {
            let counts = Counts()
            let node = Node(GeometryReader(onResize: { counts.sizes.append($0.width) }) { Counted(counts: counts) })
            Engine.render(node)
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 400),
                                  styleMask: [.titled, .resizable], backing: .buffered, defer: false)
            window.contentView = node.native
            window.layoutIfNeeded()
            let built = counts.builds
            for step in 1...5 {
                window.setContentSize(NSSize(width: 600 - CGFloat(step * 20), height: 400))
                window.layoutIfNeeded()
            }
            XCTAssertEqual(counts.sizes.last, 500)
            XCTAssertEqual(counts.builds, built, "rebuilt on every step of a resize")
        }
    }

    func testAResizeStepOfALongPage() {
        MainActor.assumeIsolated {
            let node = Node(LongPage())
            Engine.render(node)
            guard let root = node.native else { return XCTFail("no root view") }
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 800),
                                  styleMask: [.titled, .resizable], backing: .buffered, defer: false)
            window.contentView = root
            window.layoutIfNeeded()
            let steps = 40
            let start = Date()
            for step in 0..<steps {
                window.setContentSize(NSSize(width: 1000 - CGFloat(step * 10), height: 800))
                window.layoutIfNeeded()
            }
            let perStep = Date().timeIntervalSince(start) / Double(steps) * 1000
            print("RESIZE-COST ms per step: \(String(format: "%.2f", perStep))")
            // ~5 ms in a debug build; ~900 when the scroll view measured its
            // content with fittingSize on every layout.
            XCTAssertLessThan(perStep, 100, "a live resize of a long page re-solves it from scratch")
        }
    }
}
#endif
