#if os(macOS)
import XCTest
import AppKit
@testable import OmniUI

// SwiftUI styling API added for od-v2's signed-out screens, and the engine
// bug that hid environment modifiers inside stacks.
final class StylingTests: XCTestCase {

    @MainActor private static func firstTextField(in view: NSView?) -> NSTextField? {
        guard let view else { return nil }
        if let field = view as? NSTextField, field.isEditable { return field }
        for subview in view.subviews {
            if let found = Self.firstTextField(in: subview) { return found }
        }
        return nil
    }

    // unpackViews used to flatten EnvironmentModifierView away, so a modifier
    // on a stack's direct child never reached it.
    func testAnEnvironmentModifierSurvivesInsideAStack() {
        MainActor.assumeIsolated {
            let text = Binding(get: { "" }, set: { _ in })
            let node = Node(VStack {
                TextField("Email", text: text).textFieldStyle(.plain)
            })
            Engine.render(node)
            let field = Self.firstTextField(in: node.native)
            XCTAssertNotNil(field)
            XCTAssertEqual(field?.isBezeled, false, ".textFieldStyle(.plain) did not reach the field")
        }
    }

    func testTheDefaultFieldKeepsItsBorder() {
        MainActor.assumeIsolated {
            let text = Binding(get: { "" }, set: { _ in })
            let node = Node(VStack { TextField("Email", text: text) })
            Engine.render(node)
            XCTAssertEqual(Self.firstTextField(in: node.native)?.isBezeled, true)
        }
    }

    func testSwiftUIColorInitialiser() {
        guard case let .rgba(r, g, b, a) = Color(red: 0.1, green: 0.2, blue: 0.3) else {
            return XCTFail("Color(red:green:blue:) is not an rgba colour")
        }
        XCTAssertEqual([r, g, b, a], [0.1, 0.2, 0.3, 1])
    }

    func testTextLineLimit() {
        MainActor.assumeIsolated {
            XCTAssertEqual(Text("x").lineLimit(1).lineLimit, 1)
            XCTAssertNil(Text("x").lineLimit(nil).lineLimit)
        }
    }

    func testImageSizingModifiers() {
        MainActor.assumeIsolated {
            let image = Image(systemName: "eye").resizable().scaledToFill()
            XCTAssertTrue(image.isResizable)
            XCTAssertEqual(image.contentMode, .fill)
            XCTAssertFalse(Image(systemName: "eye").isResizable)
        }
    }

    // SwiftUI's .shadow(color:radius:x:y:), applied on every render.
    func testShadowTakesSwiftUIsParametersAndFollowsState() {
        MainActor.assumeIsolated {
            let node = Node(Text("x").shadow(color: .red, radius: 3, x: 1, y: 3))
            Engine.render(node)
            let shadow = node.native?.shadow
            XCTAssertEqual(shadow?.shadowBlurRadius, 3)
            XCTAssertEqual(shadow?.shadowOffset, NSSize(width: 1, height: -3), "y runs down, as in SwiftUI")

            node.adopt(Text("x").shadow(color: .clear, radius: 6))
            Engine.render(node)
            XCTAssertEqual(node.native?.shadow?.shadowBlurRadius, 6, "a changed shadow was not applied")
            XCTAssertEqual(node.native?.shadow?.shadowOffset, .zero, "SwiftUI's default offset is none")
        }
    }

    // A styled Text label keeps its font and colour through the default style.
    func testAButtonKeepsItsLabelsFont() {
        MainActor.assumeIsolated {
            let body = SystemButtonStyle().makeBody(configuration: ButtonStyleConfiguration(
                label: .init(content: Text("Go").font(.system(size: 20, weight: .medium))),
                isPressed: false, action: {}, foregroundColor: nil))
            let primitive = (body as? AnyView)?.content as? SystemButtonPrimitive
            XCTAssertEqual(primitive?.font, .system(size: 20, weight: .medium))
        }
    }
}
#endif
