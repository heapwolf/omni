// src/lib/components/Glass.swift
// SwiftUI's Liquid Glass (.glassEffect, GlassEffectContainer) and materials
// (.background(.ultraThinMaterial, in:)). Each backend draws the nearest it
// has:
//   iOS 26+, macOS 26+  the system's glass
//   earlier iOS, macOS  a blur material
//   Android             a translucent tint and hairline: Android has no blur
//                       of what lies behind a view
//   Linux               none: the content as it is
// Glass needs something behind it. On a flat colour it reads as grey.
import Foundation

public struct Glass: Equatable, Sendable {
    enum Variant: Equatable, Sendable { case regular, clear, identity }

    let variant: Variant
    var tint: Color?
    var isInteractive = false

    /// Frosted, for controls over content.
    public static let regular = Glass(variant: .regular)
    /// More transparent, for controls over rich imagery; needs its own dimming.
    public static let clear = Glass(variant: .clear)
    /// No glass, keeping the view's identity: for turning it off.
    public static let identity = Glass(variant: .identity)

    /// Tinted: the glass takes the colour's hue.
    public func tint(_ color: Color?) -> Glass {
        var copy = self; copy.tint = color; return copy
    }

    /// Reacts to touch: the glass gives as it is pressed.
    public func interactive(_ isEnabled: Bool = true) -> Glass {
        var copy = self; copy.isInteractive = isEnabled; return copy
    }
}

/// SwiftUI's materials, thinnest first.
public enum Material: Equatable, Sendable {
    case ultraThinMaterial, thinMaterial, regularMaterial, thickMaterial, ultraThickMaterial
}

/// What an effect view draws behind its content.
enum EffectKind: Equatable, Sendable {
    case glass(Glass)
    case material(Material)
}

/// A shape an effect takes: a corner radius, or rounded to a capsule.
struct EffectShape: Equatable, Sendable {
    var radius: Double
    var isCircular: Bool

    init<S: Shape>(_ shape: S) {
        isCircular = shape is Circle || shape is Capsule || shape is Ellipse
        radius = (shape as? RoundedRectangle)?.cornerRadius ?? 0
    }
}

/// The content, with glass or a material behind it in a shape.
public struct EffectBackgroundView: NativeComponent {
    public var content: any View
    let kind: EffectKind
    let shape: EffectShape
    /// The edge it fades out toward, clear there: a blur that recedes into
    /// the content rather than ending in a line. Also its content.
    var fade: Edge?
    /// A colour over the blur, under the content: the system's own tint
    /// rarely matches the background it sits on, and shows as a band.
    var tint: Color?

    public var children: [any View] { [content] }
}

/// SwiftUI's GlassEffectContainer: glass shapes inside it that come within
/// `spacing` of each other blend, and morph as they move. Elsewhere than
/// iOS 26 and macOS 26 it only groups them.
public struct GlassEffectContainerView: NativeComponent {
    public var content: any View
    let spacing: Double

    public var children: [any View] { [content] }
}

public struct GlassEffectContainer<Content: View>: View {
    let spacing: Double
    let content: Content

    public init(spacing: Double? = nil, @ViewBuilder content: () -> Content) {
        self.spacing = spacing ?? 8
        self.content = content()
    }

    public var body: some View {
        GlassEffectContainerView(content: content, spacing: spacing)
    }
}

public extension View {
    /// Liquid Glass behind this view, in `shape`: SwiftUI's
    /// `glassEffect(_:in:)`. For controls that float over content: never a
    /// card, a list, or text.
    func glassEffect<S: Shape>(_ glass: Glass = .regular, in shape: S) -> some View {
        EffectBackgroundView(content: self, kind: .glass(glass), shape: EffectShape(shape))
    }

    /// Liquid Glass in a capsule.
    func glassEffect(_ glass: Glass = .regular) -> some View {
        glassEffect(glass, in: Capsule())
    }

    /// A blur material behind this view, in `shape`.
    func background<S: Shape>(_ material: Material, in shape: S) -> some View {
        EffectBackgroundView(content: self, kind: .material(material), shape: EffectShape(shape))
    }

    func background(_ material: Material) -> some View {
        background(material, in: Rectangle())
    }

    /// A blur material behind this view, full at one edge and fading out
    /// toward `edge`: behind a status bar, toward the bottom. The fade
    /// covers whatever the view holds too, so give it none: put it in a
    /// background. Android, which has no blur, draws the material's fill
    /// without the fade.
    /// `tint`, translucent, takes the blur toward the background it sits on.
    func background(_ material: Material, fadingToward edge: Edge, tint: Color? = nil) -> some View {
        EffectBackgroundView(content: self, kind: .material(material), shape: EffectShape(Rectangle()),
                             fade: edge, tint: tint)
    }
}
