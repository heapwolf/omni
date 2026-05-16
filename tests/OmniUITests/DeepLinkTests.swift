import XCTest
@testable import OmniUI

final class DeepLinkTests: XCTestCase {
    private static let link = URL(string: "example://checkout/done?token=tok_1")!

    override func setUp() {
        super.setUp()
        MainActor.assumeIsolated { DeepLink.reset() }
    }

    func testALinkArrivingFirstIsHeldUntilAHandlerExists() {
        MainActor.assumeIsolated {
            DeepLink.receive(Self.link)

            var received: [URL] = []
            DeepLink.install { received.append($0) }

            XCTAssertEqual(received, [Self.link],
                           "a cold-start link was dropped: it arrived before the handler")
        }
    }

    func testAHeldLinkIsDeliveredOnlyOnce() {
        MainActor.assumeIsolated {
            DeepLink.receive(Self.link)

            var first: [URL] = []
            DeepLink.install { first.append($0) }
            var second: [URL] = []
            DeepLink.install { second.append($0) }

            XCTAssertEqual(first.count, 1)
            XCTAssertTrue(second.isEmpty, "the held link was delivered twice")
        }
    }

    func testLinksArrivingLaterGoStraightToTheHandler() {
        MainActor.assumeIsolated {
            var received: [URL] = []
            DeepLink.install { received.append($0) }

            DeepLink.receive(Self.link)
            DeepLink.receive(URL(string: "example://settings")!)

            XCTAssertEqual(received.count, 2)
        }
    }

    func testAnAppWithNoHandlerDoesNotCrash() {
        MainActor.assumeIsolated {
            DeepLink.install(nil)
            DeepLink.receive(Self.link)
        }
    }

    // MARK: - argv

    /// Linux and Windows have no callback: the link is in argv.

    func testTheLaunchURLIsFoundAmongTheArguments() {
        MainActor.assumeIsolated {
            let found = DeepLink.launchURL(in: ["/usr/bin/app", "example://pay/42"])
            XCTAssertEqual(found?.absoluteString, "example://pay/42")
        }
    }

    func testOrdinaryArgumentsAreNotMistakenForLinks() {
        MainActor.assumeIsolated {
            XCTAssertNil(DeepLink.launchURL(in: ["/usr/bin/app"]))
            XCTAssertNil(DeepLink.launchURL(in: ["/usr/bin/app", "--verbose", "somefile.txt"]))
        }
    }

    /// argv[0] is the executable's path and is never the link, even though a
    /// path is something URL(string:) will happily accept.
    func testTheExecutablePathIsNotTreatedAsALink() {
        MainActor.assumeIsolated {
            XCTAssertNil(DeepLink.launchURL(in: ["/opt/apps/my:app/bin/app"]))
        }
    }
}
