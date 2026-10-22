// src/lib/components/apple/Font+Apple.swift
#if os(macOS) || os(iOS)
import Foundation
import CoreText

#if os(macOS)
    import AppKit
#elseif os(iOS)
    import UIKit
#endif

#if os(macOS)
public extension NSFont.Weight {
    init(_ weight: Font.Weight) {
        switch weight {
        case .ultraLight: self = .ultraLight
        case .thin: self = .thin
        case .light: self = .light
        case .regular: self = .regular
        case .medium: self = .medium
        case .semibold: self = .semibold
        case .bold: self = .bold
        case .heavy: self = .heavy
        case .black: self = .black
        }
    }
}
extension NSFont {
    /// The same face with figures of one width: OpenType's tnum.
    var withMonospacedDigits: NSFont {
        let feature: [NSFontDescriptor.FeatureKey: Int] = [.typeIdentifier: kNumberSpacingType,
                                                            .selectorIdentifier: kMonospacedNumbersSelector]
        let descriptor = fontDescriptor.addingAttributes([.featureSettings: [feature]])
        return NSFont(descriptor: descriptor, size: 0) ?? self
    }
}
#elseif os(iOS)
public extension UIFont.Weight {
    init(_ weight: Font.Weight) {
        switch weight {
        case .ultraLight: self = .ultraLight
        case .thin: self = .thin
        case .light: self = .light
        case .regular: self = .regular
        case .medium: self = .medium
        case .semibold: self = .semibold
        case .bold: self = .bold
        case .heavy: self = .heavy
        case .black: self = .black
        }
    }
}

extension Font {
    /// The UIFont for this Font. Shared by Text and the text fields, so a field
    /// set in the same Font as a label matches it.
    @MainActor var uiFont: UIFont {
        let font = baseUIFont
        return hasMonospacedDigits ? font.withMonospacedDigits : font
    }

    @MainActor private var baseUIFont: UIFont {
        let size = CGFloat(self.size)
        if let face = registeredFace(size: size) {
            return scaled(face as UIFont)
        }
        if let family, let custom = UIFont(name: Font.resolvedFamily(family), size: size) {
            return scaled(custom)
        }
        if matchesTextStyle, let style {
            return UIFont.preferredFont(forTextStyle: style.uiTextStyle)
        }
        return scaled(UIFont.systemFont(ofSize: size, weight: UIFont.Weight(weight)))
    }

    /// Follows the reader's text size, as a named style does, whatever its
    /// face and weight: SwiftUI's `Font.custom(_:size:relativeTo:)`. A font
    /// with no style is the size it was given.
    @MainActor private func scaled(_ font: UIFont) -> UIFont {
        guard let style else { return font }
        return UIFontMetrics(forTextStyle: style.uiTextStyle).scaledFont(for: font)
    }
}

extension UIFont {
    /// The same face with figures of one width: OpenType's tnum.
    var withMonospacedDigits: UIFont {
        let feature: [UIFontDescriptor.FeatureKey: Int] = [.type: kNumberSpacingType,
                                                            .selector: kMonospacedNumbersSelector]
        return UIFont(descriptor: fontDescriptor.addingAttributes([.featureSettings: [feature]]), size: 0)
    }
}

extension Font.TextStyle {
    var uiTextStyle: UIFont.TextStyle {
        switch self {
        case .largeTitle:  return .largeTitle
        case .title:       return .title1
        case .title2:      return .title2
        case .title3:      return .title3
        case .headline:    return .headline
        case .subheadline: return .subheadline
        case .body:        return .body
        case .callout:     return .callout
        case .footnote:    return .footnote
        case .caption:     return .caption1
        case .caption2:    return .caption2
        }
    }
}
#endif

// MARK: - Registered faces

/// Each registered family, by the name the app gave it, and the family its
/// faces declare to CoreText ("Inter Variable" for InterVariable.ttf).
@MainActor var registeredCoreTextFamilies: [String: String] = [:]

extension Font {
    /// CoreText's weight trait: UIFont.Weight's and NSFont.Weight's raw values.
    var coreTextWeight: CGFloat {
        switch weight {
        case .ultraLight: return -0.8
        case .thin: return -0.6
        case .light: return -0.4
        case .regular: return 0
        case .medium: return 0.23
        case .semibold: return 0.3
        case .bold: return 0.4
        case .heavy: return 0.56
        case .black: return 0.62
        }
    }

    /// This font's registered family at its weight and slant, or nil if the
    /// family was never registered. The nearest of the family's faces; on a
    /// variable face, its weight axis set to exactly this weight, so one file
    /// serves all nine. Italic needs an italic face: without one it stays upright.
    @MainActor func registeredFace(size: CGFloat) -> CTFont? {
        guard let family, let declared = registeredCoreTextFamilies[family] else { return nil }
        let wanted = CTFontDescriptorCreateWithAttributes([
            kCTFontFamilyNameAttribute: declared,
            kCTFontTraitsAttribute: [kCTFontWeightTrait: coreTextWeight]
        ] as CFDictionary)
        let mandatory = Set([kCTFontFamilyNameAttribute as String]) as CFSet
        let matched = CTFontDescriptorCreateMatchingFontDescriptor(wanted, mandatory) ?? wanted
        var face = CTFontCreateWithFontDescriptor(matched, size, nil)

        let weightAxis = 0x77676874 // 'wght'
        let axes = CTFontCopyVariationAxes(face) as? [[CFString: Any]] ?? []
        if axes.contains(where: { ($0[kCTFontVariationAxisIdentifierKey] as? Int) == weightAxis }) {
            let exact = CTFontDescriptorCreateCopyWithVariation(CTFontCopyFontDescriptor(face),
                                                                weightAxis as CFNumber, CGFloat(weight.rawValue))
            face = CTFontCreateWithFontDescriptor(exact, size, nil)
        }
        if isItalic, let italic = CTFontCreateCopyWithSymbolicTraits(face, size, nil, .traitItalic, .traitItalic) {
            face = italic
        }
        return face
    }
}

public extension Font {
    /// Registers every face in the file at `path` under `family`. Register a
    /// family's files under one name (Regular, Bold, ... or one variable file
    /// and its italic) and a Font in that family picks the face for its weight.
    @discardableResult
    @MainActor static func register(_ path: String, as family: String) -> Bool {
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: path) else { return false }

        var error: Unmanaged<CFError>?
        // .process rather than .persistent: the font is this app's, and should
        // not outlive it in the user's session.
        guard CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error) else {
            error?.release()
            return false
        }

        var declared = family
        if let data = try? Data(contentsOf: url),
           let provider = CGDataProvider(data: data as CFData),
           let cgFont = CGFont(provider),
           let postScript = cgFont.postScriptName {
            declared = postScript as String
        }
        // The first file's name stands for the family where a name is wanted.
        if registeredFamilies[family] == nil { registeredFamilies[family] = declared }
        let faces = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor] ?? []
        if let first = faces.first,
           let name = CTFontDescriptorCopyAttribute(first, kCTFontFamilyNameAttribute) as? String {
            registeredCoreTextFamilies[family] = name
        }
        return true
    }

    /// The faces the build copied from the app's `Fonts/<Family>/`, each
    /// registered under its folder's name. Run before the first render.
    /// Without a bundle (`swift run`, tests), the package's own `Fonts/`.
    @MainActor static func registerBundled() {
        guard let root = bundledFonts() ?? packageFonts() else { return }
        let fm = FileManager.default
        for family in ((try? fm.contentsOfDirectory(atPath: root.path)) ?? []).sorted() {
            let folder = root.appendingPathComponent(family)
            for file in ((try? fm.contentsOfDirectory(atPath: folder.path)) ?? []).sorted()
                where isFontFile(file) {
                register(folder.appendingPathComponent(file).path, as: family)
            }
        }
    }

    private static func bundledFonts() -> URL? {
        guard let root = Bundle.main.resourceURL?.appendingPathComponent(bundledDirectory),
              FileManager.default.fileExists(atPath: root.path) else { return nil }
        return root
    }

    /// `Fonts/` beside the Package.swift above the running executable, which
    /// SwiftPM builds into `<package>/.build/...`.
    private static func packageFonts() -> URL? {
        let fm = FileManager.default
        var folder = Bundle.main.executableURL?.deletingLastPathComponent()
        while let current = folder, current.pathComponents.count > 1 {
            let fonts = current.appendingPathComponent(bundledDirectory)
            if fm.fileExists(atPath: current.appendingPathComponent("Package.swift").path),
               fm.fileExists(atPath: fonts.path) {
                return fonts
            }
            folder = current.deletingLastPathComponent()
        }
        return nil
    }
}
#endif
