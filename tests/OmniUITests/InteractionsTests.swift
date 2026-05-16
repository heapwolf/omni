#if os(macOS)
import XCTest
import AppKit
@testable import OmniUI

// Views defined here are the app's: this module is not OmniUI.

@MainActor private struct Screen: View {
    var body: some View {
        VStack {
            Text("title")
            Button("Go") {}
            Row()
            Row()
            Button("Named") {}.accessibilityIdentifier("screen.named")
            ScrollView { Text("scrolled") }
        }
    }
}

@MainActor private struct Row: View {
    var body: some View {
        HStack { Text("label"); Text("detail") }.onTapGesture {}
    }
}

@MainActor private struct Tagged: View {
    var body: some View { Row().accessibilityIdentifier("tagged.row") }
}

final class InteractionsTests: XCTestCase {

    // MARK: Classifying a touch

    func testShortStillTouchIsATapAndAHeldOneALongPress() {
        XCTAssertEqual(Interactions.classify(dx: 2, dy: 3, duration: 0.1), .tap)
        XCTAssertEqual(Interactions.classify(dx: 2, dy: 3, duration: 0.8), .longPress)
    }

    func testALongDragIsASwipeAlongItsLongerAxis() {
        XCTAssertEqual(Interactions.classify(dx: -80, dy: 10, duration: 0.2), .swipeLeft)
        XCTAssertEqual(Interactions.classify(dx: 80, dy: -10, duration: 0.2), .swipeRight)
        XCTAssertEqual(Interactions.classify(dx: 5, dy: -60, duration: 0.2), .swipeUp)
        XCTAssertEqual(Interactions.classify(dx: 5, dy: 60, duration: 0.2), .swipeDown)
    }

    func testADragTooShortForASwipeIsNothing() {
        XCTAssertNil(Interactions.classify(dx: 18, dy: 0, duration: 0.2))
    }

    // MARK: Paths

    func testATapOnAButtonIsTheButtonUnderTheAppsView() {
        MainActor.assumeIsolated {
            let root = rendered(Screen())
            XCTAssertEqual(path(of: owners(root, "Button")[0], .tap), "Screen/Button")
        }
    }

    func testATapInsideATapGestureCountsForTheGestureAndRepeatedViewsGetTheirPosition() {
        MainActor.assumeIsolated {
            let root = rendered(Screen())
            let labels = owners(root, "Text").filter { text($0) == "detail" }
            XCTAssertEqual(path(of: labels[0], .tap), "Screen/Row[0]/TapGesture")
            XCTAssertEqual(path(of: labels[1], .tap), "Screen/Row[1]/TapGesture")
        }
    }

    func testAnIdentifierNamesTheElementAndReachesTheNativeView() {
        MainActor.assumeIsolated {
            let root = rendered(Screen())
            let named = owners(root, "Button")[1]
            XCTAssertEqual(path(of: named, .tap), "Screen/screen.named")
            XCTAssertEqual(named.native?.accessibilityIdentifier(), "screen.named")
        }
    }

    func testAnIdentifierOnAnAppViewRenamesThatSegment() {
        MainActor.assumeIsolated {
            let root = rendered(Tagged())
            let label = owners(root, "Text")[0]
            XCTAssertEqual(path(of: label, .tap), "Tagged/tagged.row/TapGesture")
        }
    }

    func testASwipeCountsForTheScrollViewItLandsIn() {
        MainActor.assumeIsolated {
            let root = rendered(Screen())
            let scrolled = owners(root, "Text").first { text($0) == "scrolled" }!
            XCTAssertEqual(path(of: scrolled, .swipeUp), "Screen/ScrollView")
        }
    }

    func testATapOnPlainTextIsTheText() {
        MainActor.assumeIsolated {
            let root = rendered(Screen())
            let title = owners(root, "Text").first { text($0) == "title" }!
            XCTAssertEqual(path(of: title, .tap), "Screen/Text[0]")
        }
    }

    // MARK: From a native view to the report

    func testATouchOnASubviewOfANativeFindsItsNodeAndReports() {
        MainActor.assumeIsolated {
            let root = rendered(Screen())
            let button = owners(root, "Button")[0]
            var events: [Interactions.Event] = []
            var others = 0
            let first = Interactions.addObserver { events.append($0) }
            let second = Interactions.addObserver { _ in others += 1 }
            defer { Interactions.removeObserver(first); Interactions.removeObserver(second) }

            // A view inside the button that omni did not make.
            let inner = NSView()
            button.native!.addSubview(inner)
            TouchReporter.began(at: CGPoint(x: 10, y: 10), time: 1, on: inner)
            TouchReporter.ended(at: CGPoint(x: 12, y: 11), time: 1.1, yDown: true)

            XCTAssertEqual(events, [Interactions.Event(kind: .tap, path: "Screen/Button")])
            XCTAssertEqual(others, 1, "every observer hears it")
        }
    }

    func testNothingIsReportedWithoutAnObserver() {
        MainActor.assumeIsolated {
            let root = rendered(Screen())
            TouchReporter.began(at: .zero, time: 0, on: owners(root, "Button")[0].native)
            let id = Interactions.addObserver { _ in XCTFail("reported a touch that began unobserved") }
            defer { Interactions.removeObserver(id) }
            TouchReporter.ended(at: .zero, time: 0.1, yDown: true)
        }
    }
}

// MARK: - Helpers

@MainActor private func rendered(_ view: any View) -> Node {
    let node = Node(view)
    Engine.render(node)
    return node
}

@MainActor private func path(of node: Node, _ kind: Interactions.Kind) -> String {
    Interactions.path(of: node, for: kind)
}

/// Nodes that made a native view, whose view's name is `name`, in tree order.
@MainActor private func owners(_ node: Node, _ name: String) -> [Node] {
    let own = node.nativeOwner != nil && Interactions.elementName(of: node) == name ? [node] : []
    return own + node.kids.flatMap { owners($0, name) }
}

@MainActor private func text(_ node: Node) -> String? {
    (node.view as? Text)?.text
}
#endif
