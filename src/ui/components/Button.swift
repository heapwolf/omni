// src/lib/components/Button.swift
import Foundation

// MARK: - Style Protocols

public struct ButtonStyleConfiguration {
    public struct Label: OmniStructuralView {
        public var content: any View
        public init(content: any View) { self.content = content }
        public typealias Body = Never
        public var body: Never { fatalError("Engine unpacks this") }
        public var unpacked: [any View] { [content] }
    }

    public let label: Label
    /// Whether the button is held down, with the touch inside it.
    public let isPressed: Bool
    public let action: () -> Void
    public let foregroundColor: Color?
}

/// @MainActor: makeBody builds a View and reads the label's content. Still
/// Sendable, since a style is a value an app hands in.
@MainActor
public protocol ButtonStyle: Sendable {
    associatedtype Body: View
    @ViewBuilder func makeBody(configuration: ButtonStyleConfiguration) -> Body
}

// MARK: - Environment Integration

public struct ButtonStyleKey: EnvironmentKey {
    public static let defaultValue: any ButtonStyle = SystemButtonStyle()
}

public extension EnvironmentValues {
    var buttonStyle: any ButtonStyle {
        get { self[ButtonStyleKey.self] }
        set { self[ButtonStyleKey.self] = newValue }
    }
}

// MARK: - Native Primitive

public struct SystemButtonPrimitive: NativeComponent {
    public var title: String
    public var action: () -> Void
    public var foregroundColor: Color?
    /// nil keeps the platform's button font.
    public var font: Font?

    public init(_ title: String, action: @escaping () -> Void = {}, foregroundColor: Color? = nil,
                font: Font? = nil) {
        self.title = title
        self.action = action
        self.foregroundColor = foregroundColor
        self.font = font
    }

}

// MARK: - Default Style

public struct SystemButtonStyle: ButtonStyle {
    public func makeBody(configuration: ButtonStyleConfiguration) -> some View {
        if let textLabel = configuration.label.content as? Text {
            // A label's own font and colour survive, as in SwiftUI; an unstyled
            // Text keeps the platform's button look.
            return AnyView(SystemButtonPrimitive(textLabel.text,
                                                 action: configuration.action,
                                                 foregroundColor: configuration.foregroundColor
                                                    ?? textLabel.textColor,
                                                 font: textLabel.isFontSet ? textLabel.font
                                                    : Tracker.current?.environment.font))
        }
        // A richer label was replaced with the word "Button". The label matters
        // in that case, so keep it and make it tappable.
        return AnyView(TapGestureView(content: configuration.label.content,
                                      action: configuration.action))
    }
}

// MARK: - The Public Button API

/// SwiftUI's ButtonRole: what a button does, which an alert shows by its
/// placement and colour.
public struct ButtonRole: Equatable, Sendable {
    let kind: Int
    public static let destructive = ButtonRole(kind: 1)
    public static let cancel = ButtonRole(kind: 2)
}

public struct Button<Label: View>: OmniStructuralView {
    public var action: () -> Void
    public var label: Label
    public var foregroundColor: Color?
    public var role: ButtonRole?

    public init(action: @escaping () -> Void, @ViewBuilder label: () -> Label) {
        self.action = action
        self.label = label()
    }

    public init(role: ButtonRole?, action: @escaping () -> Void, @ViewBuilder label: () -> Label) {
        self.action = action
        self.label = label()
        self.role = role
    }

    public init(_ title: String, action: @escaping () -> Void) where Label == Text {
        self.action = action
        self.label = Text(title)
    }

    public init(_ title: String, role: ButtonRole?, action: @escaping () -> Void) where Label == Text {
        self.action = action
        self.label = Text(title)
        self.role = role
    }

    // View.foregroundColor() wraps a view in an external container and recolours
    // from the outside.
    public func foregroundColor(_ color: Color) -> Button<Label> {
        var copy = self
        copy.foregroundColor = color
        return copy
    }

    public typealias Body = Never
    public var body: Never { fatalError("Engine unpacks this") }

    @MainActor public var unpacked: [any View] {
        // Read directly from your Node's EnvironmentValues!
        let style = Tracker.current?.environment.buttonStyle ?? SystemButtonStyle()
        let wrapped = ButtonStyleConfiguration.Label(content: label)

        if style is SystemButtonStyle {
            // One Text: the platform's own button, which shows its own press.
            if label is Text {
                let config = ButtonStyleConfiguration(label: wrapped, isPressed: false,
                                                      action: action, foregroundColor: foregroundColor)
                return [style.makeBody(configuration: config)]
            }
            return [PressableButton(style: DimmingButtonStyle(), label: wrapped,
                                    action: action, foregroundColor: foregroundColor)]
        }
        // A custom style draws the button; the press around it is omni's, so
        // the style sees isPressed and needs no gesture of its own.
        return [PressableButton(style: style, label: wrapped, action: action, foregroundColor: foregroundColor)]
    }
}

// MARK: - The Modifier

public extension View {
    func buttonStyle<S: ButtonStyle>(_ style: S) -> some View {
        // Delegates directly to the generic .environment(\.keyPath) method!
        self.environment(\.buttonStyle, style)
    }
}
