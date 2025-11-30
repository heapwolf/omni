// src/lib/components/Font.swift
import Foundation

/// A size, a weight, and optionally a registered family. Shaped after
/// SwiftUI's Font: members, nested Weight, and .weight/.bold/.italic.
public struct Font: Equatable, Sendable {
    /// Numbered as CSS, Pango and Android number weights, so each backend uses the
    /// raw value directly.
    public enum Weight: Int, Equatable, Sendable {
        case ultraLight = 100
        case thin = 200
        case light = 300
        case regular = 400
        case medium = 500
        case semibold = 600
        case bold = 700
        case heavy = 800
        case black = 900
    }

    /// One of the named styles, when the font came from one.
    public enum TextStyle: Equatable, Sendable {
        case largeTitle, title, title2, title3, headline, subheadline
        case body, callout, footnote, caption, caption2

        /// The weight the style carries unless asked for another.
        public var defaultWeight: Weight {
            self == .headline ? .semibold : .regular
        }
    }

    public var style: TextStyle?
    public var size: Double
    public var weight: Weight
    public var isItalic: Bool

    /// The name passed to `register(_:as:)`, or nil for the platform UI font.
    public var family: String?

    /// Every digit as wide as the next, so figures line up and a changing
    /// amount does not shift: SwiftUI's monospacedDigit().
    public var hasMonospacedDigits = false

    public init(style: TextStyle? = nil, size: Double, weight: Weight = .regular,
                isItalic: Bool = false, family: String? = nil) {
        self.style = style
        self.size = size
        self.weight = weight
        self.isItalic = isItalic
        self.family = family
    }

    public static let largeTitle = Font(style: .largeTitle, size: 34)
    public static let title = Font(style: .title, size: 28)
    public static let title2 = Font(style: .title2, size: 22)
    public static let title3 = Font(style: .title3, size: 20)
    /// Semibold, which is what distinguishes it from .body; both are 17pt.
    public static let headline = Font(style: .headline, size: 17, weight: .semibold)
    public static let subheadline = Font(style: .subheadline, size: 15)
    public static let body = Font(style: .body, size: 17)
    public static let callout = Font(style: .callout, size: 16)
    public static let footnote = Font(style: .footnote, size: 13)
    public static let caption = Font(style: .caption, size: 12)
    public static let caption2 = Font(style: .caption2, size: 11)

    public static func system(size: Double, weight: Weight = .regular) -> Font {
        Font(size: size, weight: weight)
    }

    /// A font registered with `register(_:as:)`.
    public static func custom(_ family: String, size: Double,
                              weight: Weight = .regular) -> Font {
        Font(size: size, weight: weight, family: family)
    }

    public func weight(_ weight: Weight) -> Font {
        var copy = self; copy.weight = weight; return copy
    }

    public func bold() -> Font { weight(.bold) }

    public func italic() -> Font {
        var copy = self; copy.isItalic = true; return copy
    }

    public func monospacedDigit() -> Font {
        var copy = self; copy.hasMonospacedDigits = true; return copy
    }

    public var matchesTextStyle: Bool {
        style != nil && family == nil && !isItalic && !hasMonospacedDigits && weight == style?.defaultWeight
    }
}

// MARK: - Registration

@MainActor var registeredFamilies: [String: String] = [:]

public extension Font {
    /// Where the build puts the app's fonts, one folder per family: the app's
    /// own `Fonts/<Family>/*.ttf|otf`. Must match the CLI's AppFonts.directory.
    static let bundledDirectory = "Fonts"

    /// A file `register(_:as:)` can load.
    static func isFontFile(_ name: String) -> Bool {
        let lowered = name.lowercased()
        return lowered.hasSuffix(".ttf") || lowered.hasSuffix(".otf")
    }
}

#if !os(macOS) && !os(iOS)
public extension Font {
    /// Apple registers the bundled fonts here. Android's generated activity
    /// registers them from the APK's assets before the engine starts;
    /// Linux and Windows bundle none yet.
    @MainActor static func registerBundled() {}
}
#endif

public extension Font {
    /// The platform's name for a registered family, or the name as given when
    /// nothing was registered under it.
    @MainActor static func resolvedFamily(_ family: String) -> String {
        registeredFamilies[family] ?? family
    }
}
