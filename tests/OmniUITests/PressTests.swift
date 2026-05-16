#if os(macOS)
import XCTest
import AppKit
@testable import OmniUI

// A Button with a custom style is pressable and sees isPressed; onChange hands
// its action the value before the change.

@MainActor private var seenPressed: [Bool] = []
@MainActor private var taps = 0
@MainActor private var changes: [(Int, Int)] = []
@MainActor private var counter: Binding<Int>?

private struct RecordingStyle: ButtonStyle {
    func makeBody(configuration: ButtonStyleConfiguration) -> some View {
        seenPressed.append(configuration.isPressed)
        return AnyView(configuration.label).opacity(configuration.isPressed ? 0.5 : 1)
    }
}

private struct Styled: View {
    var body: some View {
        Button(action: { taps += 1 }) { Text("Send") }.buttonStyle(RecordingStyle())
    }
}

private struct Counting: View {
    @State private var value = 1
    var body: some View {
        counter = $value
        return Text("\(value)").onChange(of: value) { old, new in changes.append((old, new)) }
    }
}

final class PressTests: XCTestCase {

    @MainActor private static func find<T: NSView>(_ type: T.Type, in view: NSView?) -> T? {
        guard let view else { return nil }
        if let match = view as? T { return match }
        for subview in view.subviews {
            if let found = find(type, in: subview) { return found }
        }
        return nil
    }

    @MainActor private static func mouse(_ type: NSEvent.EventType, at point: NSPoint, in view: NSView) -> NSEvent {
        NSEvent.mouseEvent(with: type, location: view.convert(point, to: nil), modifierFlags: [],
                           timestamp: 0, windowNumber: view.window?.windowNumber ?? 0, context: nil,
                           eventNumber: 0, clickCount: 1, pressure: 1)!
    }

    @MainActor private static func spin() {
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
    }

    /// The press view in a window, laid out, so events have somewhere to land.
    @MainActor private static func mounted(_ node: Node) -> (NSWindow, OmniPressView?) {
        Engine.render(node)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 100),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView?.addSubview(node.native!)
        window.contentView?.layoutSubtreeIfNeeded()
        return (window, find(OmniPressView.self, in: node.native))
    }

    func testACustomStyleSeesThePressAndReleaseRunsTheAction() {
        MainActor.assumeIsolated {
            seenPressed = []
            taps = 0
            let node = Node(Styled())
            let (window, press) = Self.mounted(node)
            guard let press else { return XCTFail("a styled Button was not wrapped in a press view") }
            XCTAssertEqual(seenPressed.last, false)

            let middle = NSPoint(x: press.bounds.midX, y: press.bounds.midY)
            press.mouseDown(with: Self.mouse(.leftMouseDown, at: middle, in: press))
            Self.spin()
            XCTAssertEqual(seenPressed.last, true, "the style did not see isPressed")
            XCTAssertEqual(taps, 0, "the action ran on the way down")

            press.mouseUp(with: Self.mouse(.leftMouseUp, at: middle, in: press))
            Self.spin()
            XCTAssertEqual(seenPressed.last, false)
            XCTAssertEqual(taps, 1)
            _ = window
        }
    }

    func testReleasingFarOutsideDoesNotRunTheAction() {
        MainActor.assumeIsolated {
            taps = 0
            let node = Node(Styled())
            let (window, press) = Self.mounted(node)
            guard let press else { return XCTFail("no press view") }
            press.mouseDown(with: Self.mouse(.leftMouseDown, at: NSPoint(x: 1, y: 1), in: press))
            let far = NSPoint(x: press.bounds.maxX + 200, y: press.bounds.maxY + 200)
            press.mouseDragged(with: Self.mouse(.leftMouseDragged, at: far, in: press))
            Self.spin()
            XCTAssertEqual(seenPressed.last, false, "dragging off did not un-press")
            press.mouseUp(with: Self.mouse(.leftMouseUp, at: far, in: press))
            Self.spin()
            XCTAssertEqual(taps, 0)
            _ = window
        }
    }

    func testAPlainTextButtonStaysThePlatformsButton() {
        MainActor.assumeIsolated {
            let node = Node(Button("Send") {})
            Engine.render(node)
            XCTAssertNil(Self.find(OmniPressView.self, in: node.native))
            XCTAssertNotNil(Self.find(NSButton.self, in: node.native))
        }
    }

    func testARicherLabelIsPressableToo() {
        MainActor.assumeIsolated {
            let node = Node(Button(action: {}) { HStack { Text("Send") } })
            Engine.render(node)
            XCTAssertNotNil(Self.find(OmniPressView.self, in: node.native))
        }
    }

    func testOnChangeHandsOverTheOldValue() {
        MainActor.assumeIsolated {
            changes = []
            let node = Node(Counting())
            Engine.render(node)
            counter?.wrappedValue = 5
            Self.spin()
            XCTAssertEqual(changes.count, 1)
            XCTAssertEqual(changes.first?.0, 1)
            XCTAssertEqual(changes.first?.1, 5)
        }
    }
}
#endif
