import Foundation

#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

// A shape's outline, drawn along its path as SwiftUI does: .stroke centres
// the line on the edge, .strokeBorder keeps it inside. Native on Apple (a
// CAShapeLayer) and on Android (a drawable). The other backends still draw a
// border on the bounds and clip it to the shape, which loses the line at
// rounded corners.

public enum ShapeOutline: Sendable, Equatable {
    case rectangle(cornerRadius: Double)
    case circle
    case ellipse
    case capsule
}

public extension Shape {
    /// The outline this shape draws along.
    var outline: ShapeOutline {
        if let rounded = self as? RoundedRectangle { return .rectangle(cornerRadius: rounded.cornerRadius) }
        if self is Circle { return .circle }
        if self is Ellipse { return .ellipse }
        if self is Capsule { return .capsule }
        return .rectangle(cornerRadius: 0)
    }

    /// SwiftUI's stroke: the line is centred on the shape's edge, so half of
    /// it lies outside the shape's frame.
    func stroke(_ color: Color, lineWidth: Double = 1) -> AnyView {
        #if os(macOS) || os(iOS)
        AnyView(ShapeStroke(outline: outline, color: color, lineWidth: lineWidth, isInset: false))
        #elseif os(Android)
        AnyView(ShapeStroke(outline: outline, color: color, lineWidth: lineWidth, isInset: false))
        #else
        AnyView(ShapeDefaultFill().border(color, width: lineWidth).clipShape(self))
        #endif
    }

    /// SwiftUI's strokeBorder: the whole line inside the shape's frame.
    func strokeBorder(_ color: Color, lineWidth: Double = 1) -> AnyView {
        #if os(macOS) || os(iOS)
        AnyView(ShapeStroke(outline: outline, color: color, lineWidth: lineWidth, isInset: true))
        #elseif os(Android)
        AnyView(ShapeStroke(outline: outline, color: color, lineWidth: lineWidth, isInset: true))
        #else
        AnyView(ShapeDefaultFill().border(color, width: lineWidth).clipShape(self))
        #endif
    }
}

#if os(macOS) || os(iOS)
public struct ShapeStroke: NativeComponent {
    public var outline: ShapeOutline
    public var color: Color
    public var lineWidth: Double
    public var isInset: Bool

    @MainActor public func makeNative() -> NativeView {
        let view = OmniStrokeView()
        view.translatesAutoresizingMaskIntoConstraints = false
        // Fills its frame, like any shape.
        let low = NativeLayoutPriority(rawValue: 1)
        view.setContentHuggingPriority(low, for: .horizontal)
        view.setContentHuggingPriority(low, for: .vertical)
        view.setContentCompressionResistancePriority(low, for: .horizontal)
        view.setContentCompressionResistancePriority(low, for: .vertical)
        return view
    }

    @MainActor public func updateNative(_ view: NativeView) {
        guard let view = view as? OmniStrokeView else { return }
        view.outline = outline
        view.lineWidth = lineWidth
        view.isInset = isInset
        #if os(macOS)
        view.strokeColor = color.nsColor.cgColor
        view.needsLayout = true
        #else
        view.strokeColor = color.uiColor.cgColor
        view.setNeedsLayout()
        #endif
    }
}

public final class OmniStrokeView: NativeView {
    var outline: ShapeOutline = .rectangle(cornerRadius: 0)
    var lineWidth: Double = 1
    var isInset = false
    var strokeColor: CGColor?
    private let shape = CAShapeLayer()

    #if os(macOS)
    public override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.addSublayer(shape)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    nonisolated public override var isFlipped: Bool { true }
    public override func layout() {
        super.layout()
        redraw()
    }
    #else
    public override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
        layer.addSublayer(shape)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    public override func layoutSubviews() {
        super.layoutSubviews()
        redraw()
    }
    #endif

    private func redraw() {
        let width = CGFloat(lineWidth)
        let rect = isInset ? bounds.insetBy(dx: width / 2, dy: width / 2) : bounds
        shape.frame = bounds
        shape.path = Self.path(outline, in: rect, inset: isInset ? width / 2 : 0)
        shape.fillColor = nil
        shape.strokeColor = strokeColor
        shape.lineWidth = width
    }

    /// Radii are clamped to half the short side, as SwiftUI's are.
    nonisolated static func path(_ outline: ShapeOutline, in rect: CGRect, inset: CGFloat) -> CGPath {
        guard rect.width > 0, rect.height > 0 else { return CGMutablePath() }
        let half = min(rect.width, rect.height) / 2
        switch outline {
        case .rectangle(let radius):
            let r = min(max(CGFloat(radius) - inset, 0), half)
            return CGPath(roundedRect: rect, cornerWidth: r, cornerHeight: r, transform: nil)
        case .capsule:
            return CGPath(roundedRect: rect, cornerWidth: half, cornerHeight: half, transform: nil)
        case .ellipse:
            return CGPath(ellipseIn: rect, transform: nil)
        case .circle:
            let square = CGRect(x: rect.midX - half, y: rect.midY - half, width: half * 2, height: half * 2)
            return CGPath(ellipseIn: square, transform: nil)
        }
    }
}
#endif

#if os(Android)
import CAndroid

public struct ShapeStroke: NativeComponent {
    public var outline: ShapeOutline
    public var color: Color
    public var lineWidth: Double
    public var isInset: Bool

    @MainActor public func makeNative() -> NativeView {
        // No size of its own: a plain View takes all the height it is offered.
        OmniAndroid.createView(OmniAndroid.env, "com/omni/OmniEventBridge$FillView")
    }

    @MainActor public func updateNative(_ view: NativeView) {
        // Usually an overlay: the size of what it decorates, never more.
        AndroidExpansion.fill(view)
        let kind: Int32
        var radius = 0.0
        switch outline {
        case .rectangle(let cornerRadius): kind = 0; radius = cornerRadius
        case .capsule: kind = 1
        case .ellipse: kind = 2
        case .circle: kind = 3
        }
        let c = color.rgbaComponents
        omni_jni_set_stroke(OmniAndroid.env, view, kind, Float(radius), Float(lineWidth),
                            isInset ? 1 : 0,
                            Int32(c.a * 255), Int32(c.r * 255), Int32(c.g * 255), Int32(c.b * 255))
    }
}
#endif
