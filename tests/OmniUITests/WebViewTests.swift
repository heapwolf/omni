import XCTest
@testable import OmniUI

final class WebPageTests: XCTestCase {
    private static let example = URL(string: "https://example.com/checkout")!
    private static let ret = URL(string: "example://checkout/done?token=tok_123")!

    // MARK: - The command queue

    func testLoadEnqueuesOneCommand() {
        MainActor.assumeIsolated {
            let page = WebPage()
            page.load(Self.example)

            let drained = page.drainCommands()
            XCTAssertEqual(drained.count, 1)
            guard case .load(let url) = drained[0] else {
                return XCTFail("expected .load, got \(drained[0])")
            }
            XCTAssertEqual(url, Self.example)
        }
    }

    func testCommandsDrainInOrderAndOnlyOnce() {
        MainActor.assumeIsolated {
            let page = WebPage()
            page.load(Self.example)
            page.goBack()
            page.reload()

            XCTAssertEqual(page.drainCommands().count, 3)
            XCTAssertTrue(page.drainCommands().isEmpty,
                          "a drained command must not be replayed on the next render")
        }
    }

    func testLoadHTMLCarriesItsBaseURL() {
        MainActor.assumeIsolated {
            let page = WebPage()
            page.loadHTML("<p>hi</p>", baseURL: Self.example)

            guard case .loadHTML(let html, let base) = page.drainCommands().first else {
                return XCTFail("expected .loadHTML")
            }
            XCTAssertEqual(html, "<p>hi</p>")
            XCTAssertEqual(base, Self.example)
        }
    }

    // A hosted checkout finishes by navigating to a URL the app owns.

    func testEveryNavigationIsAllowedByDefault() {
        MainActor.assumeIsolated {
            XCTAssertEqual(WebPage().policy(for: Self.example), .allow)
        }
    }

    func testTheReturnURLCanBeCancelled() {
        MainActor.assumeIsolated {
            let page = WebPage()
            var caught: URL?
            page.decidePolicy = { url in
                guard url.scheme == "example" else { return .allow }
                caught = url
                return .cancel
            }

            XCTAssertEqual(page.policy(for: Self.example), .allow)
            XCTAssertEqual(page.policy(for: Self.ret), .cancel)
            XCTAssertEqual(caught, Self.ret)
        }
    }

    func testMessagesReachTheHandler() {
        MainActor.assumeIsolated {
            let page = WebPage()
            var received: [String] = []
            page.onMessage = { received.append($0) }

            page.deliver(message: #"{"status":"succeeded"}"#)
            XCTAssertEqual(received, [#"{"status":"succeeded"}"#])
        }
    }

    // MARK: - Write-backs

    func testReportsLandOnThePage() {
        MainActor.assumeIsolated {
            let page = WebPage()
            page.report(title: "Checkout")
            page.report(isLoading: true)
            page.report(progress: 0.5)
            page.report(canGoBack: true)
            page.report(url: Self.example)
            page.report(error: "boom")

            XCTAssertEqual(page.title, "Checkout")
            XCTAssertTrue(page.isLoading)
            XCTAssertEqual(page.estimatedProgress, 0.5)
            XCTAssertTrue(page.canGoBack)
            XCTAssertFalse(page.canGoForward)
            XCTAssertEqual(page.url, Self.example)
            XCTAssertEqual(page.lastError, "boom")
        }
    }
}

#if os(Linux)

/// Body evaluations, counted.
@MainActor
private final class Renders {
    static var count = 0
}

@MainActor
private struct TitleReader: View {
    let page: WebPage
    var body: some View {
        Renders.count += 1
        return Text(page.title)
    }
}

/// Loads from inside body, as a @StateObject factory does.
@MainActor
private struct LoadsFromBody: View {
    let page: WebPage
    var body: some View {
        page.load(URL(string: "https://example.com")!)
        return Text("loaded")
    }
}

final class WebViewRenderTests: XCTestCase {
    private static let example = URL(string: "https://example.com/checkout")!

    override func setUp() {
        super.setUp()
        gtk_init(nil, nil)
    }

    /// A repeated report must not re-render: WebKit reports title and progress
    /// repeatedly during one navigation, and @Published has no equality check.
    func testRepeatedReportsDoNotRerender() {
        MainActor.assumeIsolated {
            let page = WebPage()
            Renders.count = 0

            let node = Node(TitleReader(page: page))
            Engine.render(node)
            XCTAssertEqual(Renders.count, 1)

            page.report(title: "Checkout")
            XCTAssertEqual(Renders.count, 2, "a changed title must re-render")

            page.report(title: "Checkout")
            page.report(title: "Checkout")
            XCTAssertEqual(Renders.count, 2, "an unchanged title must not re-render")
        }
    }

    func testTheViewMountsAndDrainsWhatItIsGiven() {
        MainActor.assumeIsolated {
            let page = WebPage()
            let node = Node(WebView(page))
            Engine.render(node)
            XCTAssertNotNil(node.native, "the web view produced no native view")

            // Enqueuing renders the node: drainCommands reads revision while the node is
            // current, which registers it as a dependent.
            page.load(Self.example)
            XCTAssertTrue(page.drainCommands().isEmpty,
                          "load() did not reach the backend: the node is not observing the page")
        }
    }

    func testEnqueuingDuringABodyDoesNotReenterTheRenderer() {
        MainActor.assumeIsolated {
            let page = WebPage()
            let node = Node(LoadsFromBody(page: page))

            // The assertion is mostly that this line returns at all.
            Engine.render(node)

            XCTAssertEqual(page.drainCommands().count, 1,
                           "the command should still be queued: nothing in this tree drains it")
        }
    }

    /// Absence is reported, not swallowed. On a machine with libwebkit2gtk this
    /// asserts the opposite.
    func testAMissingEngineIsVisible() {
        MainActor.assumeIsolated {
            let page = WebPage()
            let node = Node(WebView(page))
            Engine.render(node)

            if linuxWebEngineAvailable {
                XCTAssertNil(page.lastError)
            } else {
                XCTAssertNotNil(page.lastError,
                                "no engine and no error: the view would be silently blank")
                XCTAssertTrue(page.lastError?.contains("libwebkit2gtk") == true)
            }
        }
    }
}
#endif
