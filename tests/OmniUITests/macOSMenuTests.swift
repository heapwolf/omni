#if os(macOS)
import XCTest
import AppKit
@testable import OmniUI

@MainActor private final class Taps { var go: [String] = [] }

/// `.commands` is read where a view's body returns it, as an app's does.
@MainActor private struct Office: View {
    let taps: Taps
    var body: some View {
        Text("x").commands {
            Menu(applicationItems: {
                MenuAction("Settings...", shortcut: ",") { taps.go.append("settings") }
            })
            Menu("Go") {
                MenuAction("Users", shortcut: "1") { taps.go.append("users") }
                MenuDivider()
                MenuAction("Find...", shortcut: "f", modifiers: [.command, .shift]) { taps.go.append("find") }
                MenuAction("Ledger", isEnabled: false) { taps.go.append("ledger") }
            }
            Menu("File") { MenuAction("Sign Out") { taps.go.append("out") } }
            Menu("Recent") {
                ForEach(["Ada", "Sam"], id: \.self) { name in MenuAction(name) { taps.go.append(name) } }
            }
        }
    }
}

final class macOSMenuTests: XCTestCase {
    /// A Mac app's menu bar, in the order macOS puts it, with the standard
    /// menus around the app's own.
    func testTheMenuBarHasTheStandardMenusAroundTheApps() {
        MainActor.assumeIsolated {
            Engine.appName = "Office"
            let taps = Taps()
            let view = Office(taps: taps)
            let node = Node(view)
            Engine.render(node)
            let bar = try! XCTUnwrap(NSApplication.shared.mainMenu)
            XCTAssertEqual(bar.items.map(\.title), ["Office", "File", "Edit", "Go", "Recent", "Window"])
            XCTAssertEqual(bar.items[4].submenu?.items.map(\.title), ["Ada", "Sam"], "a ForEach's items")

            let app = try! XCTUnwrap(bar.items[0].submenu)
            XCTAssertEqual(app.items.first?.title, "About Office")
            XCTAssertEqual(app.items[2].title, "Settings...", "the app's items, after About")
            XCTAssertEqual(app.items.last?.title, "Quit Office")

            let edit = try! XCTUnwrap(bar.items[2].submenu)
            XCTAssertEqual(edit.items.first { $0.title == "Copy" }?.action, Selector("copy:"), "⌘C reaches a text field")
            XCTAssertNil(edit.items.first { $0.title == "Copy" }?.target, "through the responder chain")

            let file = try! XCTUnwrap(bar.items[1].submenu)
            XCTAssertEqual(file.items.map(\.title), ["Sign Out", "", "Close"])

            let go = try! XCTUnwrap(bar.items[3].submenu)
            XCTAssertTrue(go.items[1].isSeparatorItem)
            let find = go.items[2]
            XCTAssertEqual(find.keyEquivalent, "f")
            XCTAssertEqual(find.keyEquivalentModifierMask, [.command, .shift])
            let ledger = try! XCTUnwrap(go.items[3] as? NSMenuItemValidation)
            XCTAssertFalse(ledger.validateMenuItem(go.items[3]), "disabled")

            go.performActionForItem(at: 0)
            XCTAssertEqual(taps.go, ["users"])
            XCTAssertNotNil(NSApplication.shared.windowsMenu)
        }
    }
}
#endif
