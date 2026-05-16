#if os(macOS)
import XCTest
import AppKit
@testable import OmniUI

// SwiftUI APIs a lock screen needs: an alert with real buttons, openURL, and
// content hidden from VoiceOver without losing its state.

@MainActor private struct Hideable: View {
    var hidden: Bool
    var body: some View { Text("balance").opacity(hidden ? 0 : 1).accessibilityHidden(hidden) }
}

@MainActor private final class Box { var url: URL? }

@MainActor private struct Opener: View {
    let box: Box
    @Environment(\.openURL) private var openURL
    var body: some View {
        // Read in body: omni resolves @Environment against the node being
        // rendered, so a read inside the closure would get the default.
        let openURL = self.openURL
        return Text("x").onAppear { openURL(URL(string: "https://apps.apple.com/app/id1")!) }
    }
}

final class SystemAPITests: XCTestCase {

    // MARK: Alert

    func testAlertButtonsComeFromTheActionsWithCancelLast() {
        MainActor.assumeIsolated {
            let actions = AlertAction.from(TupleView((
                Button("Cancel", role: .cancel) {},
                Button("Log out", role: .destructive) {}
            )))
            XCTAssertEqual(AlertAction.shown(actions).map(\.title), ["Log out", "Cancel"])
            XCTAssertEqual(AlertAction.shown(actions).map(\.role), [.destructive, .cancel])
        }
    }

    func testAnAlertWithNoActionsHasAnOK() {
        XCTAssertEqual(AlertAction.shown([]).map(\.title), ["OK"])
    }

    func testChoosingAButtonDismissesThenRunsItsAction() {
        MainActor.assumeIsolated {
            var presented = true
            var order: [String] = []
            let binding = Binding(get: { presented }, set: { presented = $0; order.append("dismissed") })
            let alert = AlertModifierView(content: EmptyView(), isPresented: binding, title: "Log out?",
                                          actions: AlertAction.from(TupleView((
                                              Button("Cancel", role: .cancel) { order.append("cancel") },
                                              Button("Log out", role: .destructive) { order.append("log out") }
                                          ))))
            alert.respond(0)
            XCTAssertFalse(presented)
            XCTAssertEqual(order, ["dismissed", "log out"])
        }
    }

    func testTheNativeAlertShowsTheMessageAndButtons() {
        MainActor.assumeIsolated {
            var presented = true
            let binding = Binding(get: { presented }, set: { presented = $0 })
            let node = Node(Text("screen").alert("Log out?", isPresented: binding) {
                Button("Cancel", role: .cancel) {}
                Button("Log out", role: .destructive) {}
            } message: {
                Text("You'll need to verify your phone number next time you sign in.")
            })
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 200),
                                  styleMask: [.titled], backing: .buffered, defer: false)
            Engine.render(node)
            window.contentView?.addSubview(node.native!)
            Engine.render(node)
            RunLoop.main.run(until: Date().addingTimeInterval(0.2))

            let sheet = try? XCTUnwrap(window.attachedSheet)
            let texts = sheet.map(allViews)?.compactMap { ($0 as? NSTextField)?.stringValue } ?? []
            let buttons = sheet.map(allViews)?.compactMap { $0 as? NSButton } ?? []
            XCTAssertTrue(texts.contains("You'll need to verify your phone number next time you sign in."))
            // NSAlert lays its buttons out right to left; the first is the default.
            XCTAssertEqual(Set(buttons.map(\.title).filter { !$0.isEmpty }), ["Log out", "Cancel"])
            XCTAssertEqual(buttons.first { $0.title == "Cancel" }?.keyEquivalent, "\u{1b}")
            XCTAssertEqual(buttons.first { $0.title == "Log out" }?.hasDestructiveAction, true)
            if let sheet { window.endSheet(sheet) }
        }
    }

    // MARK: openURL

    func testOpenURLGoesToTheEnvironmentsHandler() {
        MainActor.assumeIsolated {
            let box = Box()
            let node = Node(Opener(box: box).environment(\.openURL, OpenURLAction { url in
                box.url = url
                return .handled
            }))
            Engine.render(node)
            RunLoop.main.run(until: Date().addingTimeInterval(0.1))
            XCTAssertEqual(box.url?.absoluteString, "https://apps.apple.com/app/id1")
        }
    }

    // MARK: Hidden from VoiceOver

    func testAccessibilityHiddenReachesTheNativeAndTogglingKeepsTheView() {
        MainActor.assumeIsolated {
            let node = Node(Hideable(hidden: true))
            Engine.render(node)
            let native = node.native
            XCTAssertEqual(native?.isAccessibilityHidden(), true)

            node.adopt(Hideable(hidden: false))
            Engine.render(node)
            XCTAssertTrue(node.native === native, "toggling rebuilt the content")
            XCTAssertEqual(node.native?.isAccessibilityHidden(), false)
        }
    }
}

@MainActor private func allViews(_ window: NSWindow) -> [NSView] {
    func walk(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(walk) }
    return window.contentView.map(walk) ?? []
}
#endif

#if os(macOS)
final class BindingMemberTests: XCTestCase {
    private struct Account { var name = ""; var number = "" }

    /// SwiftUI's `$value.property`: a binding to one field that writes back.
    func testABindingProjectsAProperty() {
        var account = Account()
        let binding = Binding(get: { account }, set: { account = $0 })
        let name = binding.name
        name.wrappedValue = "Grace"
        XCTAssertEqual(account.name, "Grace")
        XCTAssertEqual(binding.number.wrappedValue, "")
    }
}
#endif

#if os(macOS)
final class QRCodeTests: XCTestCase {
    /// A square image, larger than the text's length, for an address.
    func testAnAddressBecomesASquareCode() {
        let image = QRCode.cgImage(for: "0x1234567890abcdef1234567890abcdef12345678")
        XCTAssertNotNil(image)
        XCTAssertEqual(image?.width, image?.height)
        XCTAssertGreaterThan(image?.width ?? 0, 20)
    }

    func testTheNativeViewShowsIt() {
        MainActor.assumeIsolated {
            let node = Node(QRCode("hello"))
            Engine.render(node)
            XCTAssertNotNil((node.native as? NSImageView)?.image)
        }
    }
}
#endif
