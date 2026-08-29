#if os(iOS)
import XCTest
import UIKit
@testable import OmniUI


@MainActor
private final class Hits {
    var count = 0
}

final class iOSEventBindingTests: XCTestCase {

    func testRepeatedRendersKeepExactlyOneHandler() {
        MainActor.assumeIsolated {
            let node = Node(Button("Tap", action: {}))
            Engine.render(node)
            guard let button = node.native as? UIButton else {
                return XCTFail("Button did not produce a UIButton")
            }

            for _ in 0..<5 { Engine.render(node) }

            XCTAssertEqual(button.allTargets.count, 1,
                           "six renders must still leave a single bound target")
        }
    }

    func testClickFiresTheActionExactlyOnce() {
        MainActor.assumeIsolated {
            let hits = Hits()
            let node = Node(Button("Tap", action: { hits.count += 1 }))
            Engine.render(node)
            for _ in 0..<3 { Engine.render(node) }

            guard let button = node.native as? UIButton else {
                return XCTFail("Button did not produce a UIButton")
            }
            button.sendActions(for: .touchUpInside)

            XCTAssertEqual(hits.count, 1,
                           "action ran once per connected handler instead of once")
        }
    }

    // Re-rendering replaces the view, so the handler must invoke the closure
    // from the newest render, not the one captured on first bind.
    func testRerenderSwapsInTheNewClosure() {
        MainActor.assumeIsolated {
            let stale = Hits()
            let fresh = Hits()

            let node = Node(Button("Tap", action: { stale.count += 1 }))
            Engine.render(node)

            node.view = Button("Tap", action: { fresh.count += 1 })
            Engine.render(node)

            guard let button = node.native as? UIButton else {
                return XCTFail("Button did not produce a UIButton")
            }
            button.sendActions(for: .touchUpInside)

            XCTAssertEqual(stale.count, 0, "the superseded closure still ran")
            XCTAssertEqual(fresh.count, 1, "the current closure did not run")
        }
    }
}
#endif
