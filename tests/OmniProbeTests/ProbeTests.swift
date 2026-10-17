#if os(macOS)
import XCTest
import AppKit
@testable import OmniProbe
import OmniUI

// OmniProbe against small screens in a real window: what it sees, what a tap
// and typing reach, and what stops them.

@MainActor private var sent = 0
/// Hosts open in the current test, closed after it.
@MainActor private var hosts: [ProbeHost] = []
@MainActor private var typed: Binding<String>?

private struct Form: View {
    @State private var email = ""
    @State private var isConfirmed = false
    var body: some View {
        typed = $email
        return VStack(spacing: 12) {
            Text(isConfirmed ? "Sent to \(email)" : "Sign in")
            TextField("Email", text: $email).accessibilityIdentifier("login.email")
            Button(action: { isConfirmed = true; sent += 1 }) { Text("Continue") }
                .buttonStyle(Pill())
                .accessibilityIdentifier("login.submit")
            Button(action: {}) { Text("Disabled") }.disabled(true).accessibilityIdentifier("login.off")
        }
        .padding(20)
    }
}

private struct Pill: ButtonStyle {
    func makeBody(configuration: ButtonStyleConfiguration) -> some View {
        AnyView(configuration.label).padding(12).background(.blue)
    }
}

private struct Covered: View {
    var body: some View {
        ZStack {
            Button("Under") { sent += 1 }.accessibilityIdentifier("under")
            Text("Lid").frame(width: 400, height: 400).background(.white)
                .onTapGesture {}
        }
    }
}

final class ProbeTests: XCTestCase {

    /// The view in a window of its own, through the same host a journey uses.
    @MainActor private func mount(_ view: some View) -> (Probe, ProbeHost) {
        let host = ProbeHost(view, width: 400, height: 400)
        hosts.append(host)
        return (host.probe, host)
    }

    override func tearDown() {
        MainActor.assumeIsolated {
            hosts.forEach { $0.close() }
            hosts = []
        }
        super.tearDown()
    }

    @MainActor func testItSeesIdentifiersTextAndRoles() async throws {
        let (probe, _) = mount(Form())
        let tree = try await probe.tree()
        let submit = try XCTUnwrap(tree.first { $0.identifier == "login.submit" })
        XCTAssertEqual(submit.role, .button)
        XCTAssertEqual(submit.text, "Continue", "a control's text is the text inside it")
        XCTAssertTrue(submit.isVisible)
        XCTAssertEqual(tree.first { $0.identifier == "login.email" }?.role, .field)
        XCTAssertTrue(tree.contains { $0.role == .text && $0.text == "Sign in" })
        XCTAssertEqual(tree.first { $0.identifier == "login.off" }?.isEnabled, false)
    }

    @MainActor func testTypingAndTappingRunTheAppsOwnHandlers() async throws {
        sent = 0
        let (probe, _) = mount(Form())
        try await probe.type("ada@example.com", into: "login.email")
        XCTAssertEqual(typed?.wrappedValue, "ada@example.com", "typing did not reach the binding")
        try await probe.tap("login.submit")
        XCTAssertEqual(sent, 1)
        try await probe.waitFor(.text("Sent to ada@example.com"))
    }

    @MainActor func testATapByTextReachesTheButtonAroundIt() async throws {
        sent = 0
        let (probe, _) = mount(Form())
        try await probe.tap(.text("Continue"))
        XCTAssertEqual(sent, 1)
    }

    @MainActor func testADisabledControlIsNotTapped() async throws {
        let (probe, _) = mount(Form())
        do {
            try await probe.tap("login.off")
            XCTFail("a disabled button was tapped")
        } catch let error as ProbeError {
            guard case .disabled = error else { return XCTFail("\(error)") }
        }
    }

    @MainActor func testACoveredControlIsNotTapped() async throws {
        sent = 0
        let (probe, _) = mount(Covered())
        do {
            try await probe.tap("under")
            XCTFail("a covered button was tapped")
        } catch let error as ProbeError {
            guard case .covered = error else { return XCTFail("\(error)") }
        }
        XCTAssertEqual(sent, 0)
    }

    @MainActor func testAMissingElementSaysWhatIsOnScreen() async throws {
        let (probe, _) = mount(Form())
        do {
            try await probe.waitFor("nowhere", timeout: 0.2)
            XCTFail("found what is not there")
        } catch let error as ProbeError {
            XCTAssertTrue(error.description.contains("#login.submit"), "\(error)")
        }
    }

    @MainActor func testIdleWaitsForAFetch() async throws {
        let (probe, _) = mount(Form())
        try await probe.waitForIdle()
    }
}
#endif
