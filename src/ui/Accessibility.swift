// src/ui/Accessibility.swift
import Foundation
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#elseif os(Android)
import CAndroid
#endif

// MARK: - Identifier

/// Carries an identifier on the view it wraps; draws nothing. Kept as a node
/// by Omni.unpackViews, like the transition, so a path can find it.
public struct AccessibilityIdentifierView: OmniStructuralView {
    let identifier: String
    public var content: any View

    public typealias Body = Never
    public var body: Never { fatalError("Engine unpacks this") }
    public var unpacked: [any View] { [content] }
}

public extension View {
    /// SwiftUI's: a stable name for this view, for UI tests and for
    /// Interactions' paths. Set on the native view too.
    func accessibilityIdentifier(_ identifier: String) -> some View {
        AccessibilityIdentifierView(identifier: identifier, content: self)
    }
}

// MARK: - Hidden from assistive technology

/// Carries whether the view it wraps is hidden from VoiceOver. The same type
/// either way, so toggling it keeps the content's state.
public struct AccessibilityHiddenView: OmniStructuralView {
    let isHidden: Bool
    public var content: any View

    public typealias Body = Never
    public var body: Never { fatalError("Engine unpacks this") }
    public var unpacked: [any View] { [content] }
}

public extension View {
    /// SwiftUI's: hides this view and everything in it from VoiceOver. With
    /// `.opacity(0)`, content that stays mounted under a cover but can be
    /// neither seen, tapped nor read.
    func accessibilityHidden(_ hidden: Bool) -> some View {
        AccessibilityHiddenView(isHidden: hidden, content: self)
    }
}

// MARK: - Label, hint, value, traits, grouping

/// SwiftUI's AccessibilityChildBehavior: how an element treats what is in it.
public enum AccessibilityChildBehavior: Equatable, Sendable {
    /// One element, read as its children's text joined: a row.
    case combine
    /// One element that is only what it is told: its own label.
    case ignore
    /// Its children are elements; it is a group, not one.
    case contain
}

/// SwiftUI's AccessibilityTraits, the ones omni carries to every backend.
public struct AccessibilityTraits: OptionSet, Equatable, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static let isButton = AccessibilityTraits(rawValue: 1)
    public static let isHeader = AccessibilityTraits(rawValue: 2)
    public static let isSelected = AccessibilityTraits(rawValue: 4)
    public static let isLink = AccessibilityTraits(rawValue: 8)
}

/// What a view says to VoiceOver and TalkBack. Each modifier sets one field;
/// stacked, they all land on the same native view.
struct AccessibilityAttributes: Equatable {
    var label: String?
    var hint: String?
    var value: String?
    var children: AccessibilityChildBehavior?
    var traits: AccessibilityTraits = []
}

/// Carries attributes on the view it wraps; draws nothing. Kept as a node,
/// like the identifier, so Engine.applyAccessibility finds it.
public struct AccessibilityAttributesView: OmniStructuralView {
    let attributes: AccessibilityAttributes
    public var content: any View

    public typealias Body = Never
    public var body: Never { fatalError("Engine unpacks this") }
    public var unpacked: [any View] { [content] }
}

public extension View {
    /// What VoiceOver and TalkBack read for this view, in place of its text.
    func accessibilityLabel(_ label: String) -> some View {
        AccessibilityAttributesView(attributes: AccessibilityAttributes(label: label), content: self)
    }

    /// What happens if it is activated: "Available after verification".
    func accessibilityHint(_ hint: String) -> some View {
        AccessibilityAttributesView(attributes: AccessibilityAttributes(hint: hint), content: self)
    }

    /// Its current value, read after the label: a balance, a setting.
    func accessibilityValue(_ value: String) -> some View {
        AccessibilityAttributesView(attributes: AccessibilityAttributes(value: value), content: self)
    }

    /// One element for this view and what is in it, or a group of them.
    func accessibilityElement(children: AccessibilityChildBehavior = .ignore) -> some View {
        AccessibilityAttributesView(attributes: AccessibilityAttributes(children: children), content: self)
    }

    func accessibilityAddTraits(_ traits: AccessibilityTraits) -> some View {
        AccessibilityAttributesView(attributes: AccessibilityAttributes(traits: traits), content: self)
    }
}

extension Engine {
    /// The native view shows its node's accessibility settings.
    static func applyAccessibility(_ node: Node) {
        guard let native = node.native else { return }
        if let identifier = node.accessibilityIdentifier {
            #if os(iOS)
            native.accessibilityIdentifier = identifier
            #elseif os(macOS)
            native.setAccessibilityIdentifier(identifier)
            #endif
        }
        if let hidden = node.accessibilityHidden {
            #if os(iOS)
            native.accessibilityElementsHidden = hidden
            #elseif os(macOS)
            native.setAccessibilityHidden(hidden)
            #elseif os(Android)
            omni_jni_set_accessibility_hidden(OmniAndroid.env, native, hidden ? 1 : 0)
            #endif
        }
        if let attributes = node.accessibility { apply(attributes, to: native) }
        _ = native
    }

    /// Only the fields the modifier set: an outer .accessibilityHint must not
    /// clear the label an inner .accessibilityLabel put on the same view.
    private static func apply(_ attributes: AccessibilityAttributes, to native: NativeView) {
        let isElement = attributes.children.map { $0 != .contain }
            ?? (attributes.label != nil || attributes.value != nil || !attributes.traits.isEmpty)
        #if os(iOS)
        if isElement { native.isAccessibilityElement = true }
        if attributes.children == .contain { native.isAccessibilityElement = false; native.shouldGroupAccessibilityChildren = true }
        if let label = attributes.label {
            native.accessibilityLabel = label
        } else if attributes.children == .combine {
            // Read when asked, so a child's text changing later is read as it is now.
            if #available(iOS 17.0, *) {
                native.accessibilityLabelBlock = { [weak native] in native.map(Self.combinedText) ?? nil }
            } else {
                native.accessibilityLabel = combinedText(native)
            }
        }
        if let hint = attributes.hint { native.accessibilityHint = hint }
        if let value = attributes.value { native.accessibilityValue = value }
        if attributes.traits.contains(.isButton) { native.accessibilityTraits.insert(.button) }
        if attributes.traits.contains(.isHeader) { native.accessibilityTraits.insert(.header) }
        if attributes.traits.contains(.isSelected) { native.accessibilityTraits.insert(.selected) }
        if attributes.traits.contains(.isLink) { native.accessibilityTraits.insert(.link) }
        #elseif os(macOS)
        if isElement { native.setAccessibilityElement(true) }
        if let label = attributes.label {
            native.setAccessibilityLabel(label)
        } else if attributes.children == .combine {
            native.setAccessibilityLabel(combinedText(native))
        }
        if let hint = attributes.hint { native.setAccessibilityHelp(hint) }
        if let value = attributes.value { native.setAccessibilityValue(value) }
        if attributes.traits.contains(.isButton) { native.setAccessibilityRole(.button) }
        if attributes.traits.contains(.isHeader) { native.setAccessibilityRoleDescription("heading") }
        #elseif os(Android)
        // TalkBack reads a screen-reader stop's children as one, so combine is a
        // stop. Each field separately: Java merges them with what is there.
        let label: String? = attributes.label
        let value: String? = attributes.value
        let hint: String? = attributes.hint
        omni_jni_set_accessibility(OmniAndroid.env, native, label, value, hint,
                                   isElement ? 1 : 0, Int32(attributes.traits.rawValue))
        #endif
    }

    #if os(iOS)
    /// The text of the labels under `view`, in order, as one line.
    private static func combinedText(_ view: UIView) -> String? {
        var parts: [String] = []
        func walk(_ v: UIView) {
            if v.accessibilityElementsHidden || v.isHidden { return }
            if let label = v as? UILabel, let text = label.text, !text.isEmpty { parts.append(text); return }
            if v !== view, let text = v.accessibilityLabel, !text.isEmpty { parts.append(text); return }
            v.subviews.forEach(walk)
        }
        walk(view)
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }
    #elseif os(macOS)
    private static func combinedText(_ view: NSView) -> String? {
        var parts: [String] = []
        func walk(_ v: NSView) {
            if v.isHidden { return }
            if let field = v as? NSTextField, !field.stringValue.isEmpty { parts.append(field.stringValue); return }
            v.subviews.forEach(walk)
        }
        walk(view)
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }
    #endif
}

// MARK: - Reduce Motion

public extension EnvironmentValues {
    /// SwiftUI's: the reader asked for less motion (iOS and macOS's Reduce
    /// Motion, Android's "Remove animations"). Swap a move or a flip for a fade.
    @MainActor var accessibilityReduceMotion: Bool {
        #if os(iOS)
        return UIAccessibility.isReduceMotionEnabled
        #elseif os(macOS)
        return NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        #elseif os(Android)
        return omni_jni_reduce_motion(OmniAndroid.env) != 0
        #else
        return false
        #endif
    }
}
