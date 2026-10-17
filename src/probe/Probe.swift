// src/probe/Probe.swift
// OmniProbe: drives an omni app from inside, for end-to-end tests. It reads
// the native views the app is showing and operates them as a person would:
// a tap reaches what a finger would, once the control is checked to be on
// screen, enabled and not covered.
//
// Linked only into a test build. A shipped app must never import it.

import Foundation
import OmniHTTP
@_spi(Probe) import OmniUI

// MARK: - What it sees

/// A rectangle in its window's coordinates, origin top left, in points.
public struct ProbeRect: Codable, Sendable, Equatable {
    public var x, y, width, height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x; self.y = y; self.width = width; self.height = height
    }
}

/// One thing on screen a test can find: a control, a field, a line of text, an
/// image, or anything given an `accessibilityIdentifier`.
public struct ProbeElement: Codable, Sendable, Equatable, CustomStringConvertible {
    public enum Role: String, Codable, Sendable {
        case button, text, field, secureField, toggle, control, image, other
    }

    public var identifier: String?
    /// The path a tap reports (Interactions): `HomeScreen/PrimaryButton/Button`.
    public var path: String?
    public var role: Role
    /// What it shows: a label's text, a button's title, a field's value. A
    /// control's is the text inside it. A secure field shows none.
    public var text: String?
    /// What VoiceOver and TalkBack read, where it is set.
    public var label: String?
    /// A toggle's state: "on" or "off".
    public var value: String?
    public var frame: ProbeRect
    public var isEnabled: Bool
    /// Not hidden, not transparent, in a window and inside its bounds.
    public var isVisible: Bool
    /// How deep in the view tree: for printing it as a tree.
    public var depth: Int

    public var description: String {
        var parts = [role.rawValue]
        if let identifier { parts.append("#\(identifier)") }
        if let text, !text.isEmpty { parts.append("\"\(text)\"") }
        if let label, label != text { parts.append("label \"\(label)\"") }
        if let value { parts.append(value) }
        if !isEnabled { parts.append("disabled") }
        if !isVisible { parts.append("hidden") }
        parts.append("(\(Int(frame.x)),\(Int(frame.y)) \(Int(frame.width))×\(Int(frame.height)))")
        return String(repeating: "  ", count: depth) + parts.joined(separator: " ")
    }
}

/// How a test names an element. A string literal is an identifier, an
/// interpolated one too: `tap("login.submit")`, `tap("keypad.\(digit)")`.
public enum ProbeQuery: Codable, Sendable, Equatable, ExpressibleByStringInterpolation, CustomStringConvertible {
    case id(String)
    /// Exactly this text.
    case text(String)
    case textContaining(String)
    /// Exactly this accessibility label.
    case label(String)
    /// Exactly this path, from Interactions.
    case path(String)

    public init(stringLiteral value: String) { self = .id(value) }

    func matches(_ element: ProbeElement) -> Bool {
        switch self {
        case .id(let id): return element.identifier == id
        case .text(let text): return element.text == text
        case .textContaining(let part): return element.text?.contains(part) == true
        case .label(let label): return element.label == label
        case .path(let path): return element.path == path
        }
    }

    public var description: String {
        switch self {
        case .id(let id): return "#\(id)"
        case .text(let text): return "text \"\(text)\""
        case .textContaining(let part): return "text containing \"\(part)\""
        case .label(let label): return "label \"\(label)\""
        case .path(let path): return "path \(path)"
        }
    }
}

public enum ProbeError: Error, CustomStringConvertible, Equatable {
    case notFound(ProbeQuery, screen: String)
    case ambiguous(ProbeQuery, matches: [String])
    case notActionable(ProbeQuery, element: String)
    case disabled(ProbeQuery, element: String)
    /// Something else is in the way: what a tap at its centre would reach.
    case covered(ProbeQuery, element: String, by: String)
    case offScreen(ProbeQuery, element: String)
    case timedOut(String, screen: String)

    public var description: String {
        switch self {
        case .notFound(let query, let screen):
            return "nothing matches \(query). On screen:\n\(screen)"
        case .ambiguous(let query, let matches):
            return "\(matches.count) elements match \(query):\n" + matches.joined(separator: "\n")
        case .notActionable(let query, let element):
            return "\(query) is not something to tap or type into: \(element)"
        case .disabled(let query, let element):
            return "\(query) is disabled: \(element)"
        case .covered(let query, let element, let by):
            return "\(query) is covered; a tap would reach \(by) instead: \(element)"
        case .offScreen(let query, let element):
            return "\(query) is off screen and could not be scrolled to: \(element)"
        case .timedOut(let what, let screen):
            return "timed out waiting for \(what). On screen:\n\(screen)"
        }
    }
}

// MARK: - The driver a journey is written against

/// What a journey drives: OmniProbe in the same process, or (later) the same
/// commands sent to an app on a simulator or emulator. Every action waits for
/// the app to settle before it returns, so a journey needs no sleeps.
@MainActor public protocol ProbeDriver {
    func tree() async throws -> [ProbeElement]
    func tap(_ query: ProbeQuery) async throws
    /// Types `text` at the end of the field's value, or in place of it.
    func type(_ text: String, into query: ProbeQuery, replacing: Bool) async throws
    /// The element, once it is visible.
    @discardableResult
    func waitFor(_ query: ProbeQuery, timeout: Double) async throws -> ProbeElement
    /// Once nothing matching is visible.
    func waitForAbsence(of query: ProbeQuery, timeout: Double) async throws
    /// Once nothing is fetching, animating or changing on screen.
    func waitForIdle(timeout: Double) async throws
}

public extension ProbeDriver {
    func type(_ text: String, into query: ProbeQuery) async throws {
        try await type(text, into: query, replacing: false)
    }

    @discardableResult
    func waitFor(_ query: ProbeQuery) async throws -> ProbeElement {
        try await waitFor(query, timeout: 10)
    }

    func waitForAbsence(of query: ProbeQuery) async throws {
        try await waitForAbsence(of: query, timeout: 10)
    }

    func waitForIdle() async throws {
        try await waitForIdle(timeout: 10)
    }

    /// Whether a visible element matches, now.
    func exists(_ query: ProbeQuery) async throws -> Bool {
        try await tree().contains { $0.isVisible && query.matches($0) }
    }

    /// The screen, one element a line, indented as a tree.
    func screen() async throws -> String {
        try await tree().map(\.description).joined(separator: "\n")
    }
}

// MARK: - In the same process

/// OmniProbe in the app's own process: tier 1 on macOS, and the agent behind
/// the socket on a device.
@MainActor public final class Probe: ProbeDriver {
    /// The views to look in, front first. By default, the app's windows.
    private let roots: @MainActor () -> [NativeView]

    public init(roots: (@MainActor () -> [NativeView])? = nil) {
        self.roots = roots ?? { Probe.windowRoots() }
    }

    /// Located elements, each with its native view.
    struct Located {
        var element: ProbeElement
        var view: NativeView
    }

    func locateAll() -> [Located] {
        let roots = self.roots()
        // What the next frame would show: the platform lays out pending
        // changes before it draws, and a test's window gets no frames to draw.
        roots.forEach(Probe.layOut)
        return Interactions.batch { roots.flatMap { Probe.collect(from: $0) } }
    }

    public func tree() async throws -> [ProbeElement] {
        locateAll().map(\.element)
    }

    private func describeScreen() -> String {
        let lines = locateAll().filter(\.element.isVisible).map(\.element.description)
        // Enough to see where it is, not a page of every glyph.
        return lines.prefix(120).joined(separator: "\n") + (lines.count > 120 ? "\n…" : "")
    }

    /// The one visible element the query means, waiting briefly for it.
    private func locate(_ query: ProbeQuery, timeout: Double = 3) async throws -> Located {
        let deadline = Date().addingTimeInterval(timeout)
        while true {
            let matches = locateAll().filter { $0.element.isVisible && query.matches($0.element) }
            if matches.count == 1 { return matches[0] }
            if matches.count > 1 {
                // A control and the text inside it, which a tap on either reaches,
                // count as one.
                let actionable = Set(matches.compactMap { Probe.actionable(for: $0.view).map(ObjectIdentifier.init) })
                if actionable.count == 1, let first = matches.first { return first }
                throw ProbeError.ambiguous(query, matches: matches.map(\.element.description))
            }
            if Date() >= deadline { throw ProbeError.notFound(query, screen: describeScreen()) }
            try await Task.sleep(nanoseconds: 30_000_000)
        }
    }

    public func tap(_ query: ProbeQuery) async throws {
        let found = try await locate(query)
        guard let target = Probe.actionable(for: found.view) else {
            throw ProbeError.notActionable(query, element: found.element.description)
        }
        try check(target, for: query, element: found.element)
        Probe.perform(.tap, on: target)
        try await waitForIdle()
    }

    public func type(_ text: String, into query: ProbeQuery, replacing: Bool) async throws {
        let found = try await locate(query)
        guard let field = Probe.field(for: found.view) else {
            throw ProbeError.notActionable(query, element: found.element.description)
        }
        try check(field, for: query, element: found.element)
        Probe.perform(.type(text, replacing: replacing), on: field)
        try await waitForIdle()
    }

    /// Enabled, scrolled into view, and what a tap at its centre reaches.
    private func check(_ target: NativeView, for query: ProbeQuery, element: ProbeElement) throws {
        guard Probe.isEnabled(target) else { throw ProbeError.disabled(query, element: element.description) }
        Probe.scrollIntoView(target)
        guard Probe.isOnScreen(target) else { throw ProbeError.offScreen(query, element: element.description) }
        if let obstacle = Probe.obstacle(over: target) {
            throw ProbeError.covered(query, element: element.description, by: obstacle)
        }
    }

    @discardableResult
    public func waitFor(_ query: ProbeQuery, timeout: Double) async throws -> ProbeElement {
        let deadline = Date().addingTimeInterval(timeout)
        while true {
            if let match = locateAll().first(where: { $0.element.isVisible && query.matches($0.element) }) {
                return match.element
            }
            if Date() >= deadline { throw ProbeError.timedOut("\(query)", screen: describeScreen()) }
            try await Task.sleep(nanoseconds: 30_000_000)
        }
    }

    public func waitForAbsence(of query: ProbeQuery, timeout: Double) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while locateAll().contains(where: { $0.element.isVisible && query.matches($0.element) }) {
            if Date() >= deadline { throw ProbeError.timedOut("\(query) to go", screen: describeScreen()) }
            try await Task.sleep(nanoseconds: 30_000_000)
        }
    }

    /// Settled: no fetch under way, no animation running, and the screen the
    /// same across three looks 30ms apart.
    public func waitForIdle(timeout: Double) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        var last: [ProbeElement]?
        var steady = 0
        while true {
            try await Task.sleep(nanoseconds: 30_000_000)
            let now = locateAll().map(\.element)
            let busy = FetchActivity.inFlight > 0 || roots().contains(where: Probe.isAnimating)
            steady = !busy && now == last ? steady + 1 : 0
            if steady >= 2 { return }
            last = now
            if Date() >= deadline {
                let why = FetchActivity.inFlight > 0 ? "\(FetchActivity.inFlight) fetches to finish"
                    : busy ? "animations to finish" : "the screen to stop changing"
                throw ProbeError.timedOut(why, screen: describeScreen())
            }
        }
    }

    enum Action {
        case tap
        case type(String, replacing: Bool)
    }
}
