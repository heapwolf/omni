import Foundation

#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

/// SwiftUI's UnitPoint: (0, 0) is the top leading corner, (1, 1) the bottom
/// trailing one.
public struct UnitPoint: Hashable, Sendable {
    public var x: Double
    public var y: Double
    public init(x: Double, y: Double) { self.x = x; self.y = y }

    public static let zero = UnitPoint(x: 0, y: 0)
    public static let center = UnitPoint(x: 0.5, y: 0.5)
    public static let top = UnitPoint(x: 0.5, y: 0)
    public static let bottom = UnitPoint(x: 0.5, y: 1)
    public static let leading = UnitPoint(x: 0, y: 0.5)
    public static let trailing = UnitPoint(x: 1, y: 0.5)
    public static let topLeading = UnitPoint(x: 0, y: 0)
    public static let topTrailing = UnitPoint(x: 1, y: 0)
    public static let bottomLeading = UnitPoint(x: 0, y: 1)
    public static let bottomTrailing = UnitPoint(x: 1, y: 1)
}

/// SwiftUI's Gradient, colours only: evenly spaced stops.
public struct Gradient: Sendable {
    public var colors: [Color]
    public init(colors: [Color]) { self.colors = colors }
}

// Fills whatever it is given, like a Color or a Shape.
//
// Native on Apple (a CAGradientLayer) and Android (a shader). Elsewhere it is
// the first colour until those backends draw one.
#if os(macOS) || os(iOS)
public struct LinearGradient: NativeComponent {
    public var gradient: Gradient
    public var startPoint: UnitPoint
    public var endPoint: UnitPoint

    public init(gradient: Gradient, startPoint: UnitPoint, endPoint: UnitPoint) {
        self.gradient = gradient
        self.startPoint = startPoint
        self.endPoint = endPoint
    }

    public init(colors: [Color], startPoint: UnitPoint, endPoint: UnitPoint) {
        self.init(gradient: Gradient(colors: colors), startPoint: startPoint, endPoint: endPoint)
    }

    @MainActor public func makeNative() -> NativeView {
        let view = OmniGradientView()
        view.translatesAutoresizingMaskIntoConstraints = false
        // Expands like a Spacer: a gradient has no size of its own.
        let low = NativeLayoutPriority(rawValue: 1)
        view.setContentHuggingPriority(low, for: .horizontal)
        view.setContentHuggingPriority(low, for: .vertical)
        view.setContentCompressionResistancePriority(low, for: .horizontal)
        view.setContentCompressionResistancePriority(low, for: .vertical)
        return view
    }

    @MainActor public func updateNative(_ view: NativeView) {
        guard let view = view as? OmniGradientView else { return }
        #if os(macOS)
        view.gradientLayer.colors = gradient.colors.map { $0.nsColor.cgColor }
        // AppKit's layer is not flipped: y runs bottom to top.
        view.gradientLayer.startPoint = CGPoint(x: startPoint.x, y: 1 - startPoint.y)
        view.gradientLayer.endPoint = CGPoint(x: endPoint.x, y: 1 - endPoint.y)
        #else
        view.gradientLayer.colors = gradient.colors.map { $0.uiColor.cgColor }
        view.gradientLayer.startPoint = CGPoint(x: startPoint.x, y: startPoint.y)
        view.gradientLayer.endPoint = CGPoint(x: endPoint.x, y: endPoint.y)
        #endif
    }
}

#if os(macOS)
public final class OmniGradientView: NSView {
    let gradientLayer = CAGradientLayer()
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer = gradientLayer
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}
#else
public final class OmniGradientView: UIView {
    public override class var layerClass: AnyClass { CAGradientLayer.self }
    var gradientLayer: CAGradientLayer { layer as! CAGradientLayer }
}
#endif

#else
public struct LinearGradient: View {
    public var gradient: Gradient
    public var startPoint: UnitPoint
    public var endPoint: UnitPoint

    public init(gradient: Gradient, startPoint: UnitPoint, endPoint: UnitPoint) {
        self.gradient = gradient
        self.startPoint = startPoint
        self.endPoint = endPoint
    }

    public init(colors: [Color], startPoint: UnitPoint, endPoint: UnitPoint) {
        self.init(gradient: Gradient(colors: colors), startPoint: startPoint, endPoint: endPoint)
    }

    public var body: some View {
        #if os(Android)
        AndroidGradientFill(colors: gradient.colors, startPoint: startPoint, endPoint: endPoint)
        #else
        ShapeDefaultFill().background(gradient.colors.first ?? .clear)
        #endif
    }
}
#endif

#if os(Android)
import CAndroid

/// LinearGradient's view: a plain View with the gradient as its background.
/// Fills like a Color, but isn't a Spacer, so a stack doesn't narrow it.
struct AndroidGradientFill: NativeComponent {
    var colors: [Color]
    var startPoint: UnitPoint
    var endPoint: UnitPoint

    @MainActor func makeNative() -> NativeView {
        OmniAndroid.createView(OmniAndroid.env, "android/view/View")
    }

    @MainActor func updateNative(_ view: NativeView) {
        AndroidExpansion.claim(view, horizontal: true, vertical: true)
        let argb: [Int32] = colors.map { color in
            let c = color.rgbaComponents
            let bits = UInt32(c.a * 255) << 24 | UInt32(c.r * 255) << 16
                | UInt32(c.g * 255) << 8 | UInt32(c.b * 255)
            return Int32(bitPattern: bits)
        }
        argb.withUnsafeBufferPointer { buffer in
            omni_jni_set_linear_gradient(OmniAndroid.env, view, buffer.baseAddress, Int32(buffer.count),
                                         Float(startPoint.x), Float(startPoint.y),
                                         Float(endPoint.x), Float(endPoint.y))
        }
    }
}
#endif
