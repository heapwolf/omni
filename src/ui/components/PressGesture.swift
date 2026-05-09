// src/lib/components/PressGesture.swift
import Foundation

/// A press as a button feels it: held down, let go, or dragged off and back
/// on. The action runs on release inside; a scroll that takes the touch, or a
/// release outside, does not run it.
public struct PressGestureView: NativeComponent {
    public var content: any View
    /// Whether the touch is down and inside, each time that changes.
    public var onPressChange: (Bool) -> Void
    public var action: () -> Void

    public var children: [any View] { Omni.unpackViews(content) }

    public init(content: any View, onPressChange: @escaping (Bool) -> Void, action: @escaping () -> Void) {
        self.content = content
        self.onPressChange = onPressChange
        self.action = action
    }
}

/// How far, in points, a touch can stray outside before it no longer presses:
/// UIKit's own allowance for a button.
let pressSlop: Double = 70

// MARK: - A styled Button's press

/// A Button with a custom style: the style's body inside the area that takes
/// the press, re-made with `isPressed` as it changes. A View rather than
/// structural, so the press is @State that lives across renders.
struct PressableButton: View {
    let style: any ButtonStyle
    let label: ButtonStyleConfiguration.Label
    let action: () -> Void
    let foregroundColor: Color?

    @State private var isPressed = false

    var body: some View {
        let configuration = ButtonStyleConfiguration(label: label, isPressed: isPressed,
                                                     action: action, foregroundColor: foregroundColor)
        let pressed = $isPressed
        return PressGestureView(content: style.makeBody(configuration: configuration),
                                onPressChange: { isDown in
                                    if pressed.wrappedValue != isDown { pressed.wrappedValue = isDown }
                                },
                                action: action)
    }
}

/// The default style for a label richer than one Text: the label, dimmed
/// while held, as SwiftUI's automatic style does.
struct DimmingButtonStyle: ButtonStyle {
    func makeBody(configuration: ButtonStyleConfiguration) -> some View {
        AnyView(configuration.label).opacity(configuration.isPressed ? 0.6 : 1)
    }
}
