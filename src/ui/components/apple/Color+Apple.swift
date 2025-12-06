// src/ui/components/apple/Color.swift
import Foundation

#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

public enum Color: Sendable, Equatable {
    case rgba(r: Double, g: Double, b: Double, a: Double = 1.0)

    /// Wrapping rather than flattening to rgba keeps a semantic colour
    /// semantic, so .primaryText.opacity(0.5) still follows the system theme.
    indirect case alphaAdjusted(base: Color, alpha: Double)

    /// One colour in light, another in dark; see Appearance.swift.
    indirect case adaptive(light: Color, dark: Color)

    // Semantic System Colors
    case windowBackground
    case controlBackground
    case primaryText
    case secondaryText
    case clear

    // Standard SwiftUI Palette
    case black
    case white
    case gray
    case red
    case green
    case blue
    case orange
    case yellow
    case purple

    /// SwiftUI's initialiser. Components run 0...1, as there.
    public init(red: Double, green: Double, blue: Double, opacity: Double = 1) {
        self = .rgba(r: red, g: green, b: blue, a: opacity)
    }

    /// SwiftUI spells this on Color itself, and `.background(.black.opacity(0.1))`
    /// depends on it — the View-level .opacity() fades a whole subtree instead.
    public func opacity(_ value: Double) -> Color {
        switch self {
        case .alphaAdjusted(let base, let alpha): return .alphaAdjusted(base: base, alpha: alpha * value)
        default: return .alphaAdjusted(base: self, alpha: value)
        }
    }

    #if os(macOS)
    public var nsColor: NSColor {
        switch self {
        case .alphaAdjusted(let base, let alpha):
            return base.nsColor.withAlphaComponent(CGFloat(alpha))
        case .adaptive: return resolved.nsColor
        case .rgba(let r, let g, let b, let a):
            return NSColor(red: r, green: g, blue: b, alpha: a)
        case .windowBackground: return .windowBackgroundColor
        case .controlBackground: return .controlBackgroundColor
        case .primaryText: return .labelColor
        case .secondaryText: return .secondaryLabelColor
        case .clear: return .clear
        case .black: return .black
        case .white: return .white
        case .gray: return .systemGray
        case .red: return .systemRed
        case .green: return .systemGreen
        case .blue: return .systemBlue
        case .orange: return .systemOrange
        case .yellow: return .systemYellow
        case .purple: return .systemPurple
        }
    }
    #elseif os(iOS)
    public var uiColor: UIColor {
        switch self {
        case .alphaAdjusted(let base, let alpha):
            return base.uiColor.withAlphaComponent(CGFloat(alpha))
        case .adaptive: return resolved.uiColor
        case .rgba(let r, let g, let b, let a):
            return UIColor(red: r, green: g, blue: b, alpha: a)
        case .windowBackground: return .systemBackground
        case .controlBackground: return .secondarySystemBackground
        case .primaryText: return .label
        case .secondaryText: return .secondaryLabel
        case .clear: return .clear
        case .black: return .black
        case .white: return .white
        case .gray: return .systemGray
        case .red: return .systemRed
        case .green: return .systemGreen
        case .blue: return .systemBlue
        case .orange: return .systemOrange
        case .yellow: return .systemYellow
        case .purple: return .systemPurple
        }
    }
    #endif

    // Helper for Cairo / Linux fallbacks
    public var rgbaComponents: (r: Double, g: Double, b: Double, a: Double) {
        switch self {
        case .alphaAdjusted(let base, let alpha):
            let c = base.rgbaComponents
            return (c.r, c.g, c.b, c.a * alpha)
        case .adaptive:
            return resolved.rgbaComponents
        case .rgba(let r, let g, let b, let a):
            return (r, g, b, a)
        case .clear:
            return (0, 0, 0, 0)
        case .black:
            return (0.0, 0.0, 0.0, 1.0)
        case .white:
            return (1.0, 1.0, 1.0, 1.0)
        case .gray:
            return (0.55, 0.55, 0.57, 1.0)
        case .red:
            return (1.0, 0.23, 0.19, 1.0)
        case .green:
            return (0.2, 0.78, 0.35, 1.0)
        case .blue:
            return (0.0, 0.48, 1.0, 1.0)
        case .orange:
            return (1.0, 0.58, 0.0, 1.0)
        case .yellow:
            return (1.0, 0.8, 0.0, 1.0)
        case .purple:
            return (0.69, 0.32, 0.87, 1.0)
        case .windowBackground, .controlBackground:
            return (0.95, 0.95, 0.95, 1.0)
        case .primaryText:
            return (0.0, 0.0, 0.0, 1.0)
        case .secondaryText:
            return (0.5, 0.5, 0.5, 1.0)
        }
    }
}
