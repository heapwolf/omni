#if os(macOS)
import XCTest
import AppKit
@testable import OmniUI

final class AppLifecycleTests: XCTestCase {
    override func tearDown() {
        MainActor.assumeIsolated { AppLifecycle.enter(.foreground) }
        super.tearDown()
    }

    func testObserversHearEachChangeOnce() {
        MainActor.assumeIsolated {
            var phases: [AppLifecycle.Phase] = []
            let id = AppLifecycle.addObserver { phases.append($0) }
            defer { AppLifecycle.removeObserver(id) }

            // Android starts the activity at launch: already the foreground.
            AppLifecycle.enter(.foreground)
            AppLifecycle.enter(.background)
            AppLifecycle.enter(.background)
            AppLifecycle.enter(.foreground)

            XCTAssertEqual(phases, [.background, .foreground])
            XCTAssertEqual(AppLifecycle.phase, .foreground)
        }
    }

    func testARemovedObserverHearsNothing() {
        MainActor.assumeIsolated {
            let id = AppLifecycle.addObserver { _ in XCTFail("heard after removal") }
            AppLifecycle.removeObserver(id)
            AppLifecycle.enter(.background)
        }
    }

    /// A Mac app is in the background while hidden.
    func testHidingTheAppIsTheBackground() {
        MainActor.assumeIsolated {
            var phases: [AppLifecycle.Phase] = []
            let id = AppLifecycle.addObserver { phases.append($0) }
            defer { AppLifecycle.removeObserver(id) }

            NotificationCenter.default.post(name: NSApplication.didHideNotification, object: nil)
            NotificationCenter.default.post(name: NSApplication.didUnhideNotification, object: nil)

            XCTAssertEqual(phases, [.background, .foreground])
        }
    }

    func testFinishInBackgroundRunsTheWork() async {
        let done = expectation(description: "ran")
        await MainActor.run { AppLifecycle.finishInBackground { done.fulfill() } }
        await fulfillment(of: [done], timeout: 2)
    }

    // MARK: Activity

    func testAKeyOrAClickIsActivity() throws {
        try MainActor.assumeIsolated {
            var count = 0
            let id = Interactions.addActivityObserver { count += 1 }
            let key = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                                                     windowNumber: 0, context: nil, characters: "a",
                                                     charactersIgnoringModifiers: "a", isARepeat: false, keyCode: 0))
            let down = try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseDown, location: .zero, modifierFlags: [],
                                                        timestamp: 0, windowNumber: 0, context: nil,
                                                        eventNumber: 0, clickCount: 1, pressure: 1))
            let up = try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseUp, location: .zero, modifierFlags: [],
                                                      timestamp: 0, windowNumber: 0, context: nil,
                                                      eventNumber: 0, clickCount: 1, pressure: 0))
            MouseMonitor.handle(key)
            MouseMonitor.handle(down)
            MouseMonitor.handle(up)
            XCTAssertEqual(count, 2, "a key-down and a mouse-down; the mouse-up is the same click")

            Interactions.removeObserver(id)
            MouseMonitor.handle(key)
            XCTAssertEqual(count, 2, "removeObserver removes an activity observer too")
        }
    }
}
#endif
