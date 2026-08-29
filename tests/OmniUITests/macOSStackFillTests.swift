#if os(macOS)
import XCTest
import AppKit
@testable import OmniUI


@MainActor
private struct DeepRow: View {
    var body: some View {
        VStack {
            VStack {
                HStack {
                    Text("x")
                    Spacer()
                }
            }
        }
    }
}

@MainActor
private struct PlainRow: View {
    var body: some View {
        VStack {
            Text("just some text")
        }
    }
}

// NavigationStack's toolbar row: a slim Back bar above real content, inside a
// VStack taller than either row. The Spacer wants horizontal room only.
@MainActor
private struct ToolbarOverContent: View {
    var body: some View {
        VStack {
            HStack {
                Button("Back", action: {})
                Spacer()
            }
            Text("content")
        }
    }
}

// A filter bar: labelled groups that want no room, in a row given more than
// they need. Each keeps its own width; the leftover goes after the last.
@MainActor
private struct FilterBar: View {
    var body: some View {
        HStack(spacing: 16) {
            HStack(spacing: 6) { Text("Status"); Text("All").frame(width: 120) }
            HStack(spacing: 6) { Text("KYC"); Text("All").frame(width: 120) }
        }
    }
}

private struct Msg { let id: Int; let name: String }

@MainActor
private struct Row: View {
    let msg: Msg
    var body: some View {
        HStack(spacing: 10) {
            Text(msg.name)
            Text("preview text").font(.caption)
            Spacer()
        }
        .padding(8)
    }
}

@MainActor
private struct RealisticInboxScreen: View {
    @MainActor var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                Text("2 unread")
                List {
                    ForEach([Msg(id: 1, name: "Ada"), Msg(id: 2, name: "Grace"),
                             Msg(id: 3, name: "Alan"), Msg(id: 4, name: "Barbara")], id: \.id) { m in
                        Row(msg: m)
                    }
                }
            }
        }
    }
}

@MainActor
final class macOSStackFillTests: XCTestCase {

    @MainActor private func layout(_ view: any View, width: CGFloat, height: CGFloat = 400) -> NativeView {
        let node = Node(view)
        Engine.render(node)
        guard let root = node.native else {
            fatalError("no root view")
        }

        let host = NSView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        host.addSubview(root)
        NSLayoutConstraint.activate([
            root.widthAnchor.constraint(equalToConstant: width),
            root.heightAnchor.constraint(equalToConstant: height),
            root.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            root.topAnchor.constraint(equalTo: host.topAnchor)
        ])
        host.layoutSubtreeIfNeeded()
        return root
    }

    func testRealisticInboxScreenStretchesThroughZStackAndScrollViewToListRows() {
        MainActor.assumeIsolated {
            let root = layout(RealisticInboxScreen(), width: 420, height: 800)

            guard let zstack = root as? OmniZStackView else {
                return XCTFail("unexpected root view: \(root)")
            }
            XCTAssertGreaterThan(zstack.frame.width, 400,
                                 "NavigationStack's ZStack wrapper did not stretch to the window's width")

            // zstack > VStack(alignment: .leading) { Text("2 unread"); List }
            guard let outerVStack = zstack.subviews.first as? NSStackView else {
                return XCTFail("unexpected view hierarchy under ZStack: \(zstack.subviews)")
            }
            XCTAssertGreaterThan(outerVStack.frame.width, 400,
                                 "the outer content did not stretch to the ZStack's width")

            // A List of one ForEach is virtualised: its ScrollView sits inside
            // the GeometryReader that measures the viewport.
            func scrollView(in view: NSView) -> NSScrollView? {
                (view as? NSScrollView) ?? view.subviews.lazy.compactMap(scrollView).first
            }
            guard let holder = outerVStack.arrangedSubviews.last, let list = scrollView(in: holder),
                  let rows = list.documentView as? NSStackView else {
                return XCTFail("no List found in \(outerVStack.arrangedSubviews)")
            }
            XCTAssertGreaterThan(holder.frame.width, 400, "the List did not stretch to fill its container")
            XCTAssertGreaterThan(list.frame.width, 400,
                                 "the List's own ScrollView did not stretch to fill its container")

            // Less the filler and the spacers standing in for rows out of view.
            let realRows = rows.arrangedSubviews.filter { !($0 is OmniAutoFillerView) && $0.frame.height > 0 }
            XCTAssertEqual(realRows.count, 4, "expected 4 message rows")
            for row in realRows {
                XCTAssertGreaterThan(row.frame.width, 380,
                                     "a row did not span the list's width: \(row.frame)")
            }
        }
    }

    func testSpacerReachesThroughNestedStacksToFillWidth() {
        MainActor.assumeIsolated {
            let root = layout(DeepRow(), width: 400)

            guard let outerStack = root as? NSStackView,
                  let midStack = outerStack.arrangedSubviews.first as? NSStackView,
                  let innerHStack = midStack.arrangedSubviews.first as? NSStackView else {
                return XCTFail("unexpected view hierarchy: \(root)")
            }

            XCTAssertEqual(innerHStack.frame.width, 400, accuracy: 1,
                           "a Spacer three stacks deep did not stretch its row to the full width")
        }
    }

    // The fix must not force ordinary content wider than it naturally is -
    // only a child whose content actually wants the extra space should take it.
    func testPlainTextDoesNotStretchToFillWidth() {
        MainActor.assumeIsolated {
            let root = layout(PlainRow(), width: 400)

            guard let outerStack = root as? NSStackView,
                  let label = outerStack.arrangedSubviews.first as? NSTextField else {
                return XCTFail("unexpected view hierarchy: \(root)")
            }

            XCTAssertLessThan(label.frame.width, 200,
                              "plain Text stretched to fill its VStack instead of sizing to its own content")
        }
    }

    func testSpacerInARowDoesNotClaimTheEnclosingStacksSurplusHeight() {
        MainActor.assumeIsolated {
            let root = layout(ToolbarOverContent(), width: 400, height: 500)

            guard let outerStack = root as? NSStackView,
                  outerStack.arrangedSubviews.count == 3,
                  outerStack.arrangedSubviews[2] is OmniAutoFillerView else {
                return XCTFail("unexpected view hierarchy: \(root)")
            }
            let toolbarRow = outerStack.arrangedSubviews[0]
            let content = outerStack.arrangedSubviews[1]
            let autoFiller = outerStack.arrangedSubviews[2]

            XCTAssertLessThan(toolbarRow.frame.height, 60,
                              "the Back row claimed vertical surplus that belongs to the content below it")
            XCTAssertLessThan(content.frame.minY, 60,
                              "content was pushed down by an oversized toolbar row instead of sitting right below it")
            XCTAssertGreaterThan(autoFiller.frame.height, 400,
                                "the auto-inserted filler did not absorb the leftover height")
        }
    }

    func testGroupsInARowKeepTheirWidthsAndTheLeftoverGoesAfterThem() {
        MainActor.assumeIsolated {
            let root = layout(FilterBar(), width: 900)
            guard let row = root as? NSStackView else { return XCTFail("unexpected view hierarchy: \(root)") }
            let groups = row.arrangedSubviews.filter { !($0 is OmniAutoFillerView) }
            XCTAssertEqual(groups.count, 2)
            for group in groups {
                XCTAssertLessThan(group.frame.width, 220, "a group took the row's leftover: \(group.frame)")
            }
            XCTAssertEqual(groups[1].frame.minX - groups[0].frame.maxX, 16, accuracy: 1,
                           "the second group was pushed away from the first")
        }
    }
}
#endif
