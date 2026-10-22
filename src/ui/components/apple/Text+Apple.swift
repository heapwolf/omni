#if os(macOS) || os(iOS)
import Foundation

#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

#if os(macOS)
/// A label as wide as its cell draws it. NSTextField reports a natural width a
/// few points under what its cell needs (146.5 for 150.03 in semibold), and
/// laid out to the whole point below that, the last word was cut to "...".
///
/// A label of more than one line wraps at the width it is laid out to, as a
/// UILabel does: AppKit's needs that width told to it (preferredMaxLayoutWidth)
/// before it can say how tall it is.
final class OmniLabel: NSTextField {
    var wrapsToWidth = false

    override func layout() {
        super.layout()
        guard wrapsToWidth, bounds.width > 0, preferredMaxLayoutWidth != bounds.width else { return }
        preferredMaxLayoutWidth = bounds.width
        invalidateIntrinsicContentSize()
    }

    override var intrinsicContentSize: NSSize {
        let natural = super.intrinsicContentSize
        // Its one-line width even when it wraps: a row shrinks it from there.
        // Reported narrower, a wrapping label in a row took the little it was
        // given and wrapped a letter to a line.
        guard natural.width > 0, let cell else { return natural }
        let drawn = cell.cellSize(forBounds: NSRect(x: 0, y: 0, width: CGFloat.greatestFiniteMagnitude,
                                                    height: CGFloat.greatestFiniteMagnitude)).width
        return NSSize(width: max(natural.width, drawn.rounded(.up)), height: natural.height)
    }
}
#endif

#if os(iOS)
/// A label that can offer Copy: .textSelection(.enabled). A UILabel cannot be
/// selected, so a long press shows the system's edit menu with Copy in it.
final class OmniTextLabel: UILabel {
    var isCopyable = false {
        didSet {
            guard isCopyable != oldValue else { return }
            isUserInteractionEnabled = isCopyable
            if isCopyable, press == nil {
                let recognizer = UILongPressGestureRecognizer(target: self, action: #selector(longPressed(_:)))
                addGestureRecognizer(recognizer)
                press = recognizer
                if #available(iOS 16.0, *) {
                    let interaction = UIEditMenuInteraction(delegate: nil)
                    addInteraction(interaction)
                    menu = interaction
                }
            }
            press?.isEnabled = isCopyable
        }
    }
    private var press: UILongPressGestureRecognizer?
    /// The UIEditMenuInteraction, from iOS 16; UIMenuController before it.
    private var menu: AnyObject?

    /// A label of more than one line wraps at the width it's laid out to, told
    /// to it each time that width changes. Left to itself, a UILabel keeps the
    /// width of its first layout: one made before its screen had its width (a
    /// tab's first appearance) wrapped a word to a line until the app was
    /// opened again. As OmniLabel does on macOS.
    override func layoutSubviews() {
        super.layoutSubviews()
        guard numberOfLines != 1, bounds.width > 0, preferredMaxLayoutWidth != bounds.width else { return }
        preferredMaxLayoutWidth = bounds.width
        invalidateIntrinsicContentSize()
    }

    /// Its one-line width even when it wraps, so a stack gives it the room it
    /// has and it wraps only past that; its height, at the width it wraps to.
    override var intrinsicContentSize: CGSize {
        let natural = super.intrinsicContentSize
        guard numberOfLines != 1, natural.width > 0 else { return natural }
        let oneLine = sizeThatFits(CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude))
        return CGSize(width: max(natural.width, oneLine.width.rounded(.up)), height: natural.height)
    }

    override var canBecomeFirstResponder: Bool { isCopyable }

    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        isCopyable && action == #selector(copy(_:))
    }

    override func copy(_ sender: Any?) {
        UIPasteboard.general.string = text
    }

    @objc private func longPressed(_ recognizer: UILongPressGestureRecognizer) {
        guard recognizer.state == .began, isCopyable, becomeFirstResponder() else { return }
        let point = recognizer.location(in: self)
        if #available(iOS 16.0, *), let menu = menu as? UIEditMenuInteraction {
            menu.presentEditMenu(with: UIEditMenuConfiguration(identifier: nil, sourcePoint: point))
        } else {
            UIMenuController.shared.showMenu(from: self, rect: CGRect(origin: point, size: .zero))
        }
    }
}
#endif

extension Text {
    @MainActor public func makeNative() -> NativeView {
        #if os(macOS)
        let l = OmniLabel(labelWithString: "")
        l.isEditable = false
        l.isBordered = false
        l.drawsBackground = false
        l.translatesAutoresizingMaskIntoConstraints = false

        l.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        return l
        #elseif os(iOS)
        let l = OmniTextLabel()
        l.translatesAutoresizingMaskIntoConstraints = false

        l.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        return l
        #endif
    }

    @MainActor public func updateNative(_ view: NativeView) {
        #if os(macOS)
        guard let l = view as? NSTextField else { return }
        // Its own .font, else an ancestor's.
        let font = resolvedFont
        // Each property only when it differs: AppKit counts every assignment
        // as a change and lays the window out again, and a screen re-renders
        // all its labels on any change of its state (an arrow key's selection).
        if l.stringValue != text { l.stringValue = text }

        // .redacted: the text kept for its size, clear, on a block of its colour.
        let redaction = redactionFill
        let color = redaction != nil ? .clear : textColor?.nsColor ?? .labelColor // Default system text color
        if l.textColor != color { l.textColor = color }
        if redaction != nil || l.layer?.backgroundColor != nil {
            l.wantsLayer = true
            l.layer?.backgroundColor = redaction?.nsColor.cgColor
            l.layer?.cornerRadius = redaction == nil ? 0 : 4
        }
        let selectable = Tracker.current?.environment.isTextSelectable ?? false
        if l.isSelectable != selectable { l.isSelectable = selectable }

        // A named style keeps the macOS scale, which runs smaller than the
        // cross-platform numbers on Font; 13pt body against iOS's 17.
        let size: CGFloat = font.style.map { (style: Font.TextStyle) -> CGFloat in
            switch style {
            case .largeTitle: return 26
            case .title: return 22
            case .title2: return 17
            case .title3: return 15
            case .headline, .body: return 13
            case .subheadline: return 11
            case .callout: return 12
            case .footnote: return 10
            case .caption: return 10
            case .caption2: return 10
            }
        } ?? CGFloat(font.size)
        let weight = NSFont.Weight(font.weight)

        var resolved: NSFont
        if isMonospaced {
            // .monospaced() wins over a custom family: it is the more specific
            // of the two requests, and code is the reason to ask for either.
            resolved = NSFont.monospacedSystemFont(ofSize: size, weight: weight)
        } else if let face = font.registeredFace(size: size) {
            resolved = face as NSFont
        } else if let family = font.family,
                  let custom = NSFont(name: Font.resolvedFamily(family), size: size) {
            resolved = custom
        } else {
            resolved = NSFont.systemFont(ofSize: size, weight: weight)
        }
        if font.isItalic {
            let italic = resolved.fontDescriptor.withSymbolicTraits(.italic)
            resolved = NSFont(descriptor: italic, size: size) ?? resolved
        }
        if font.hasMonospacedDigits { resolved = resolved.withMonospacedDigits }
        if l.font != resolved { l.font = resolved }

        let textAlignment: NSTextAlignment = switch alignment {
        case .leading: .left
        case .center: .center
        case .trailing: .right
        }
        if l.alignment != textAlignment { l.alignment = textAlignment }

        if l.maximumNumberOfLines != (lineLimit ?? 0) { l.maximumNumberOfLines = lineLimit ?? 0 }
        // One line truncates where it says; more wrap by word, and only the
        // last line they have room for truncates. A truncating break mode on
        // its own keeps an NSTextField to one line whatever the limit.
        let wraps = lineLimit != 1
        let truncating: NSLineBreakMode = switch truncationMode {
        case .none: .byClipping
        case .head: .byTruncatingHead
        case .middle: .byTruncatingMiddle
        case .tail: .byTruncatingTail
        }
        let lineBreak: NSLineBreakMode = wraps ? .byWordWrapping : truncating
        if l.lineBreakMode != lineBreak { l.lineBreakMode = lineBreak }
        if l.cell?.wraps != wraps { l.cell?.wraps = wraps }
        let truncatesLast = wraps && truncationMode != .none
        if l.cell?.truncatesLastVisibleLine != truncatesLast { l.cell?.truncatesLastVisibleLine = truncatesLast }
        if let label = l as? OmniLabel, label.wrapsToWidth != wraps {
            label.wrapsToWidth = wraps
            label.invalidateIntrinsicContentSize()
        }

        if let h = height {
            let heightConstraints = l.constraints.filter { $0.firstAttribute == .height }
            if heightConstraints.isEmpty {
                l.heightAnchor.constraint(equalToConstant: CGFloat(h)).isActive = true
            } else if heightConstraints.first?.constant != CGFloat(h) {
                heightConstraints.first?.constant = CGFloat(h)
            }
        }

        if let w = width {
            let widthConstraints = l.constraints.filter { $0.firstAttribute == .width }
            if widthConstraints.isEmpty {
                l.widthAnchor.constraint(equalToConstant: CGFloat(w)).isActive = true
            } else if widthConstraints.first?.constant != CGFloat(w) {
                widthConstraints.first?.constant = CGFloat(w)
            }
        }

        if lineSpacing != 0 || tracking != 0 {
            l.attributedStringValue = spacedText(font: l.font, color: l.textColor,
                                                 alignment: l.alignment, lineBreak: l.lineBreakMode)
        }

        #elseif os(iOS)
        guard let l = view as? UILabel else { return }
        // Its own .font, else an ancestor's.
        let font = resolvedFont
        (l as? OmniTextLabel)?.isCopyable = Tracker.current?.environment.isTextSelectable ?? false
        l.text = text

        if let color = textColor {
            l.textColor = color.uiColor
        } else {
            l.textColor = .label // Default system text color
        }
        // .redacted: the text kept for its size, clear, on a block of its colour.
        if let redaction = redactionFill {
            l.textColor = .clear
            l.backgroundColor = redaction.uiColor
            l.layer.cornerRadius = 4
            l.layer.masksToBounds = true
        } else if l.layer.cornerRadius == 4, l.layer.masksToBounds {
            l.backgroundColor = nil
            l.layer.cornerRadius = 0
            l.layer.masksToBounds = false
        }

        let size = CGFloat(font.size)
        let weight = UIFont.Weight(font.weight)

        if isMonospaced {
            // .monospaced() wins over a custom family: it is the more specific
            // of the two requests, and code is the reason to ask for either.
            l.font = UIFont.monospacedSystemFont(ofSize: size, weight: weight)
        } else {
            l.font = font.uiFont
        }
        if font.isItalic, let italic = l.font.fontDescriptor.withSymbolicTraits(.traitItalic) {
            l.font = UIFont(descriptor: italic, size: l.font.pointSize)
        }

        switch alignment {
        case .leading: l.textAlignment = .left
        case .center: l.textAlignment = .center
        case .trailing: l.textAlignment = .right
        }

        l.numberOfLines = lineLimit ?? 0
        switch truncationMode {
        case .none: l.lineBreakMode = .byClipping
        case .head: l.lineBreakMode = .byTruncatingHead
        case .middle: l.lineBreakMode = .byTruncatingMiddle
        case .tail: l.lineBreakMode = .byTruncatingTail
        }

        if let h = height {
            let heightConstraints = l.constraints.filter { $0.firstAttribute == .height }
            if heightConstraints.isEmpty {
                l.heightAnchor.constraint(equalToConstant: CGFloat(h)).isActive = true
            } else {
                heightConstraints.first?.constant = CGFloat(h)
            }
        }

        if lineSpacing != 0 || tracking != 0 {
            l.attributedText = spacedText(font: l.font, color: l.textColor,
                                          alignment: l.textAlignment, lineBreak: l.lineBreakMode)
        }
        #endif
    }

    /// Neither label type spaces lines or letters without attributes, so the
    /// resolved font, colour and wrapping are carried into one.
    @MainActor private func spacedText(font: NativeFont?, color: NativeColor?,
                                       alignment: NSTextAlignment,
                                       lineBreak: NSLineBreakMode) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = CGFloat(lineSpacing)
        paragraph.alignment = alignment
        paragraph.lineBreakMode = lineBreak

        var attributes: [NSAttributedString.Key: Any] = [.paragraphStyle: paragraph]
        if let font { attributes[.font] = font }
        if let color { attributes[.foregroundColor] = color }
        if tracking != 0 { attributes[.kern] = CGFloat(tracking) }
        return NSAttributedString(string: text, attributes: attributes)
    }
}
#endif
