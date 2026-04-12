// src/lib/components/Shapes.swift
import Foundation

// MARK: - 1. Shape Protocol

public protocol Shape: View {
    // AI heavily uses the .fill modifier to colorize shapes
    func fill<V: View>(_ content: V) -> AnyView
}

// MARK: - 2. Shape Primitives

public struct Rectangle: Shape {
    public init() {}
    public var body: some View { ShapeDefaultFill() }
    public func fill<V: View>(_ content: V) -> AnyView { AnyView(content) }
}

public struct RoundedRectangle: Shape {
    public var cornerRadius: Double
    public init(cornerRadius: Double) { self.cornerRadius = cornerRadius }

    public var body: some View {
        ShapeDefaultFill().cornerRadius(cornerRadius)
    }

    public func fill<V: View>(_ content: V) -> AnyView {
        AnyView(content.cornerRadius(cornerRadius))
    }
}

public struct Circle: Shape {
    public init() {}
    public var body: some View { ShapeDefaultFill().clipShape(self) }
    public func fill<V: View>(_ content: V) -> AnyView { AnyView(content.clipShape(self)) }
}

public extension Shape {
    /// Fills the shape with a colour. `.foregroundColor` reaches text, not
    /// shapes, so this is how a shape is coloured on every backend.
    func fill(_ color: Color) -> AnyView {
        AnyView(ShapeDefaultFill().background(color).clipShape(self))
    }
}

public struct Ellipse: Shape {
    public init() {}
    public var body: some View { ShapeDefaultFill().clipShape(self) }
    public func fill<V: View>(_ content: V) -> AnyView { AnyView(content.clipShape(self)) }
}

public struct Capsule: Shape {
    public init() {}
    public var body: some View { ShapeDefaultFill().clipShape(self) }
    public func fill<V: View>(_ content: V) -> AnyView { AnyView(content.clipShape(self)) }
}

/// A simple primitive that acts as the default fill for shapes if not explicitly colored
public struct ShapeDefaultFill: View {
    public init() {}
    public var body: some View { Spacer() } // Spacer expands to fill bounds natively
}

// MARK: - 3. View Modifiers

public extension View {
    /// Layers a view behind this one.
    ///
    /// Caveat, and it is a real one: this is a ZStack, so the result sizes to
    /// the *larger* of the two. SwiftUI sizes the result to the content and
    /// clips the background to it. An intrinsically-large background grows the
    /// layout here where SwiftUI would mask it. `alignment` is honoured.
    func background<V: View>(_ backgroundView: V, alignment: Alignment = .center) -> some View {
        ZStack(alignment: alignment) {
            backgroundView
            self
        }
    }

    /// SwiftUI's current spelling, with the background in a trailing closure.
    func background<V: View>(
        alignment: Alignment = .center,
        @ViewBuilder content: () -> V
    ) -> some View {
        let backgroundView = content()
        return ZStack(alignment: alignment) {
            backgroundView
            self
        }
    }

    func cornerRadius(_ radius: Double) -> some View {
        self.modifier(ClipModifier(radius: radius, isCircular: false))
    }

    func clipped() -> some View {
        self.modifier(ClipModifier(radius: 0, isCircular: false))
    }

    func clipShape<S: Shape>(_ shape: S) -> some View {
        let isCirc = shape is Circle || shape is Capsule || shape is Ellipse
        let radius = (shape as? RoundedRectangle)?.cornerRadius ?? 0
        return self.modifier(ClipModifier(radius: radius, isCircular: isCirc))
    }
}

public struct ClipModifier: ViewModifier {
    public var radius: Double
    public var isCircular: Bool

    public func body(content: Content) -> some View {
        ClipModifierView(content: content, radius: radius, isCircular: isCircular)
    }
}

public struct ClipModifierView: NativeComponent {
    public var content: any View
    public var radius: Double
    public var isCircular: Bool

    public var children: [any View] { [content] }

    public init(content: any View, radius: Double, isCircular: Bool) {
        self.content = content
        self.radius = radius
        self.isCircular = isCircular
    }
}
