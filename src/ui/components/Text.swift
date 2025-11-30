import Foundation

public enum TextAlignment: Equatable {
    case leading, center, trailing
}

public enum TruncationMode {
    case head, middle, tail, none
}

public struct Text: NativeComponent {
    public var text: String
    public var width: Double?
    public var height: Double?
    /// .leading, as SwiftUI's multilineTextAlignment default.
    public var alignment: TextAlignment = .leading

    public var lineLimit: Int? = nil
    public var truncationMode: TruncationMode = .tail

    public var font: Font = .body
    /// Set by .font on this Text, which wins over an inherited one, as in SwiftUI.
    public var isFontSet = false
    /// Set by monospacedDigit(), so the environment's font takes it too.
    public var hasMonospacedDigits = false
    public var isMonospaced: Bool = false

    public var textColor: Color? = nil

    /// Extra space between lines, in points. SwiftUI's meaning.
    public var lineSpacing: Double = 0
    /// Letter spacing in points.
    public var tracking: Double = 0

    public var body: any View { self }

    public init(_ text: String) { self.text = text }

    /// Sizing only. SwiftUI's `.frame(alignment:)` positions the view inside
    /// the frame, which is View.frame's job; paragraph alignment is
    /// multilineTextAlignment. Taking `alignment:` here would shadow the
    /// View-level modifier with a different meaning.
    public func frame(width: Double? = nil, height: Double? = nil) -> Text {
        var copy = self
        copy.width = width
        copy.height = height
        return copy
    }

    public func foregroundColor(_ color: Color) -> Text {
        var copy = self
        copy.textColor = color
        return copy
    }

    /// SwiftUI's: at most `limit` lines; nil is unlimited.
    public func lineLimit(_ limit: Int?) -> Text {
        var copy = self; copy.lineLimit = limit; return copy
    }

    public func truncationMode(_ mode: TruncationMode, lineLimit: Int? = 1) -> Text {
        var copy = self
        copy.truncationMode = mode
        copy.lineLimit = lineLimit
        return copy
    }

    /// This Text's own font, else the one .font set on an ancestor.
    @MainActor public var resolvedFont: Font {
        if isFontSet { return font }
        let inherited = Tracker.current?.environment.font ?? font
        return hasMonospacedDigits ? inherited.monospacedDigit() : inherited
    }

    public func font(_ font: Font) -> Text {
        var copy = self
        // A .monospacedDigit() already on the Text outlives a later font.
        copy.font = hasMonospacedDigits ? font.monospacedDigit() : font
        copy.isFontSet = true
        return copy
    }

    public func multilineTextAlignment(_ alignment: TextAlignment) -> Text {
        var copy = self
        copy.alignment = alignment
        return copy
    }

    public func lineSpacing(_ points: Double) -> Text {
        var copy = self
        copy.lineSpacing = points
        return copy
    }

    public func tracking(_ points: Double) -> Text {
        var copy = self
        copy.tracking = points
        return copy
    }

    /// Figures of one width, in the Text's own face, whichever it is given.
    public func monospacedDigit() -> Text {
        var copy = self
        copy.hasMonospacedDigits = true
        copy.font = font.monospacedDigit()
        return copy
    }

    public func monospaced(_ isActive: Bool = true) -> Text {
        var copy = self
        copy.isMonospaced = isActive
        return copy
    }
}

// MARK: - .font on any view

public struct FontKey: EnvironmentKey {
    public static let defaultValue: Font? = nil
}

public extension EnvironmentValues {
    /// nil is each view's own default.
    var font: Font? {
        get { self[FontKey.self] }
        set { self[FontKey.self] = newValue }
    }
}

public extension View {
    /// SwiftUI's: the font for text inside this view, fields included. A Text's
    /// own .font wins.
    func font(_ font: Font?) -> some View {
        EnvironmentModifierView(modifier: { $0.font = font }, content: self)
    }
}
