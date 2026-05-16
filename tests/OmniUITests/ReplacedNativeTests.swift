#if os(macOS)
import XCTest
import AppKit
import Combine
@_spi(Probe) @testable import OmniUI

// The shape od-v2's App has: a root that shows nothing until something
// async resolves, then a screen, behind a view whose type never changes.

@MainActor
private struct Gate: View {
    var open: Bool
    var body: some View {
        open ? AnyView(Text("screen")) : AnyView(EmptyView())
    }
}

@MainActor
private final class Flag: ObservableObject {
    @Published var open = false
}

@MainActor
private struct Observing: View {
    @ObservedObject var flag: Flag
    var body: some View {
        ZStack { Gate(open: flag.open) }
    }
}

// Re-renders on its own (its object changed), not because a parent did.
@MainActor
private struct OwnRender: View {
    @ObservedObject var flag: Flag
    var body: some View {
        flag.open ? AnyView(Text("middle")) : AnyView(EmptyView())
    }
}

final class ReplacedNativeTests: XCTestCase {

    // Forgot password went white: LoginScreen's own @State swapped its screen,
    // only it re-rendered, and nothing put the new native on screen. It must
    // land where the old one was: between its siblings, not after them.
    func testANativeReplacedInItsOwnRenderTakesTheSamePlace() {
        MainActor.assumeIsolated {
            let flag = Flag()
            let node = Node(VStack { Text("first"); OwnRender(flag: flag); Text("last") })
            Engine.render(node)

            flag.open = true
            RunLoop.main.run(until: Date().addingTimeInterval(0.1))

            let labels = (node.native as? NSStackView)?.arrangedSubviews
                .compactMap { ($0 as? NSTextField)?.stringValue ?? $0.subviews.compactMap { ($0 as? NSTextField)?.stringValue }.first }
            XCTAssertEqual(labels, ["first", "middle", "last"])
        }
    }

    // A border stroked over a field must not take its clicks.
    func testAnOverlayPassesClicksToTheViewBeneath() {
        MainActor.assumeIsolated {
            let text = Binding(get: { "" }, set: { _ in })
            let node = Node(TextField("Email", text: text).textFieldStyle(.plain)
                .frame(width: 200, height: 40)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(.gray, lineWidth: 1)))
            Engine.render(node)
            let host = node.native!
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 100),
                                  styleMask: [.titled], backing: .buffered, defer: false)
            window.contentView?.addSubview(host)
            window.contentView?.layoutSubtreeIfNeeded()

            let center = NSPoint(x: host.frame.midX, y: host.frame.midY)
            var hit = window.contentView?.hitTest(center)
            while let view = hit, !(view is NSTextField) { hit = view.superview }
            XCTAssertNotNil(hit, "the click went to the overlay, not the field")
        }
    }


    // ZStack's kid is Gate both times, so the engine adopts rather than
    // rebuilds. Gate's native goes from none to a Text; it must be inserted.
    func testAKidWhoseNativeAppearsIsInserted() {
        MainActor.assumeIsolated {
            let node = Node(ZStack { Gate(open: false) })
            Engine.render(node)
            XCTAssertEqual(node.native?.subviews.count, 0)

            node.adopt(ZStack { Gate(open: true) })
            Engine.render(node)
            XCTAssertEqual(node.native?.subviews.count, 1,
                           "the new native was built but never inserted")
        }
    }

    /// A node gone, a new one in its place: the allocator hands the new one the
    /// old address, and the subscription the old one left there must not count
    /// for it. It did: the new node was never subscribed, so an app launched
    /// again in the same process never heard its session sign in.
    func testANodeAtAGoneNodesAddressStillHearsItsObject() {
        MainActor.assumeIsolated {
            let flag = Flag()
            var addresses = Set<ObjectIdentifier>()
            var reused = false
            for round in 0..<60 {
                flag.open = false
                RunLoop.main.run(until: Date().addingTimeInterval(0.005))
                let node = Node(Observing(flag: flag))
                reused = reused || !addresses.insert(ObjectIdentifier(node)).inserted
                Engine.render(node)
                flag.open = true
                RunLoop.main.run(until: Date().addingTimeInterval(0.02))
                XCTAssertEqual(node.native?.subviews.count, 1, "round \(round): the change did not render")
                node.unmount()
            }
            XCTAssertTrue(reused, "no address came round again, so this proved nothing")
        }
    }

    /// The app's root shows nothing until its session loads, then a screen:
    /// the window is handed each. It was handed only the first, and on iOS,
    /// where the window comes later, that first was nil and launch crashed.
    func testTheWindowFollowsTheRootsNative() {
        MainActor.assumeIsolated {
            let flag = Flag()
            var shown: [NativeView?] = []
            let tree = HostedTree(OwnRender(flag: flag), asRoot: true) { shown.append($0) }
            defer { tree.tearDown() }
            XCTAssertEqual(shown.count, 1)
            XCTAssertNil(shown.last ?? nil, "an EmptyView root shows nothing")

            flag.open = true
            RunLoop.main.run(until: Date().addingTimeInterval(0.1))
            XCTAssertEqual(shown.count, 2, "the window was not handed the root's new native")
            XCTAssertTrue((shown.last ?? nil) is NSTextField)
        }
    }

    // objectWillChange fires before @Published stores the value. A render
    // on it reads the old value and the change is lost.
    func testObservedObjectChangeRendersTheNewValue() {
        MainActor.assumeIsolated {
            let flag = Flag()
            let node = Node(Observing(flag: flag))
            Engine.render(node)
            XCTAssertEqual(node.native?.subviews.count, 0)

            flag.open = true
            RunLoop.main.run(until: Date().addingTimeInterval(0.1))
            XCTAssertEqual(node.native?.subviews.count, 1,
                           "rendered before the write, so it saw open == false")
        }
    }
}
#endif
