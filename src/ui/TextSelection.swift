// src/ui/TextSelection.swift
// SwiftUI's .textSelection(.enabled), and .contentShape.
import Foundation

/// Whether the text under a view can be selected and copied.
public struct TextSelectability: Equatable, Sendable {
    let isEnabled: Bool
    public static let enabled = TextSelectability(isEnabled: true)
    public static let disabled = TextSelectability(isEnabled: false)
}

struct TextSelectabilityKey: EnvironmentKey {
    static let defaultValue = false
}

public extension EnvironmentValues {
    /// Set by .textSelection(_:); each Text under it reads it.
    var isTextSelectable: Bool {
        get { self[TextSelectabilityKey.self] }
        set { self[TextSelectabilityKey.self] = newValue }
    }
}

public extension View {
    /// Lets the reader copy the text under this view: selectable on macOS and
    /// Android; on iOS, where a label cannot be selected, a long press offers Copy.
    func textSelection(_ selectability: TextSelectability) -> some View {
        environment(\.isTextSelectable, selectability.isEnabled)
    }

    /// SwiftUI's hit-testing shape. omni's views take touches across their whole
    /// frame, which is what `contentShape(Rectangle())` asks for; other shapes
    /// are accepted and hit-test as their frame.
    func contentShape<S: Shape>(_ shape: S) -> some View {
        self
    }
}

// MARK: - Redaction

/// SwiftUI's RedactionReasons: why content is hidden behind placeholders.
public struct RedactionReasons: OptionSet, Equatable, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    /// Loading: each Text draws as a rounded block the size of its text.
    public static let placeholder = RedactionReasons(rawValue: 1)
    /// Private: the same blocks, for content to hide from a glance.
    public static let privacy = RedactionReasons(rawValue: 2)
}

struct RedactionReasonsKey: EnvironmentKey {
    static let defaultValue: RedactionReasons = []
}

public extension EnvironmentValues {
    var redactionReasons: RedactionReasons {
        get { self[RedactionReasonsKey.self] }
        set { self[RedactionReasonsKey.self] = newValue }
    }
}

public extension View {
    /// A skeleton of this view: the real rows, with their text as blocks, while
    /// they load. An empty set shows them again.
    func redacted(reason: RedactionReasons) -> some View {
        environment(\.redactionReasons, reason)
    }

    func unredacted() -> some View {
        environment(\.redactionReasons, [])
    }
}

extension Text {
    /// Whether this Text draws as a placeholder block, and in what colour.
    @MainActor var redactionFill: Color? {
        guard let reasons = Tracker.current?.environment.redactionReasons, !reasons.isEmpty else { return nil }
        return (textColor ?? .primaryText).opacity(0.16)
    }
}
