#if os(macOS)
import XCTest
import AppKit
@testable import OmniUI

// What a paged, refreshable history screen needs: scroll geometry, refresh,
// a date picker, the share sheet and the clipboard.

@MainActor private final class Log { var values: [(Bool, Bool)] = [] }

@MainActor private struct Paged: View {
    let log: Log
    var body: some View {
        ScrollView {
            VStack {
                ForEach(0..<60, id: \.self) { index in Text("row \(index)").frame(height: 40) }
                // A scroll view inside: its own scrolling must not count.
                ScrollView(.horizontal) { HStack { Text("chip") } }
            }
        }
        .onScrollGeometryChange(for: Bool.self, of: { geometry in
            geometry.contentOffset.y + geometry.containerSize.height > geometry.contentSize.height - 200
        }, action: { old, new in log.values.append((old, new)) })
        .frame(width: 300, height: 400)
    }
}

final class ScrollingAndPickersTests: XCTestCase {

    func testScrollingNearTheEndReportsTheChange() {
        MainActor.assumeIsolated {
            let log = Log()
            let node = Node(Paged(log: log))
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 400),
                                  styleMask: [.titled], backing: .buffered, defer: false)
            Engine.render(node)
            window.contentView?.addSubview(node.native!)
            window.contentView?.layoutSubtreeIfNeeded()

            let scroll = scrollViews(in: node.native!).first { ($0 as? OmniScrollView)?.axis == .vertical }!
            XCTAssertEqual((scroll as? OmniScrollView)?.geometryObservers.count, 1)
            let inner = scrollViews(in: node.native!).first { ($0 as? OmniScrollView)?.axis == .horizontal }
            XCTAssertEqual((inner as? OmniScrollView)?.geometryObservers.count, 0, "the nested scroll view took the observer")

            let bottom = (scroll.documentView?.frame.height ?? 0) - scroll.contentView.bounds.height
            scroll.contentView.scroll(to: NSPoint(x: 0, y: bottom))
            scroll.reflectScrolledClipView(scroll.contentView)
            RunLoop.main.run(until: Date().addingTimeInterval(0.1))

            XCTAssertEqual(log.values.last?.1, true)
            XCTAssertEqual(log.values.last?.0, false)
        }
    }

    @MainActor func testRefreshableReachesTheScrollViewsEnvironment() async {
        var refreshed = false
        let node = Node(ScrollView { Text("x") }.refreshable { refreshed = true })
        Engine.render(node)
        var scrollNode: Node? = node
        while let current = scrollNode, !(current.nativeOwner is ScrollView) { scrollNode = current.kids.first }
        let action = scrollNode?.environment.refresh
        XCTAssertNotNil(action)
        await action?()
        XCTAssertTrue(refreshed)
    }

    func testTheDatePickerKeepsToItsRangeAndWritesBack() {
        MainActor.assumeIsolated {
            let today = Date(timeIntervalSince1970: 1_800_000_000)
            var picked = today
            let binding = Binding(get: { picked }, set: { picked = $0 })
            let node = Node(DatePicker("From", selection: binding, in: ...today, displayedComponents: .date))
            Engine.render(node)
            let picker = allViews(node.native!).compactMap { $0 as? NSDatePicker }.first!
            XCTAssertEqual(picker.maxDate, today)
            XCTAssertEqual(picker.datePickerElements, .yearMonthDay)

            let earlier = today.addingTimeInterval(-86_400 * 3)
            picker.dateValue = earlier
            _ = picker.target?.perform(picker.action, with: picker)
            XCTAssertEqual(picked, earlier)
        }
    }

    func testTheClipboardHoldsWhatWasCopied() {
        MainActor.assumeIsolated {
            Clipboard.copy("tx-4821")
            XCTAssertEqual(Clipboard.string, "tx-4821")
        }
    }

    func testAShareLinkIsAButtonWithItsLabel() {
        MainActor.assumeIsolated {
            let node = Node(ShareLink("Share Receipt", item: "Receipt"))
            Engine.render(node)
            let titles = allViews(node.native!).compactMap { ($0 as? NSButton)?.title }
            XCTAssertEqual(titles, ["Share Receipt"])
        }
    }
}

@MainActor private func allViews(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(allViews) }
@MainActor private func scrollViews(in view: NSView) -> [NSScrollView] { allViews(view).compactMap { $0 as? NSScrollView } }
#endif
