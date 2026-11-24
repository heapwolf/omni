// src/ui/components/windows/Text+Windows.swift
#if os(Windows)
import Foundation

extension Text {
    @MainActor public func makeNative() -> NativeView {
        WinView.make("Text", layout: .leaf)
    }

    @MainActor public func updateNative(_ view: NativeView) {
        let v = winView(view)
        var style = WinTextStyle(resolvedFont, monospaced: isMonospaced)
        style.alignment = alignment == .center ? 1 : alignment == .trailing ? 2 : 0
        style.lineLimit = lineLimit ?? 0
        style.wraps = lineLimit != 1
        switch truncationMode {
        case .none: style.trim = 0
        case .tail: style.trim = 1
        case .head: style.trim = 2
        case .middle: style.trim = 3
        }
        style.tracking = tracking
        style.lineSpacing = lineSpacing
        style.strikethrough = isStrikethrough && strikethroughColor == nil
        let content = text
        let color = textColor
        let strike = isStrikethrough ? strikethroughColor : nil
        v.fixedWidth = width
        v.fixedHeight = height
        v.measure = { proposed in
            let layout = WinTextCache.shared.layout(content, style, maxWidth: proposed)
            return WinSize(width: layout.width, height: layout.height)
        }
        // A line that truncates gives way to its neighbours down to a few
        // characters; a paragraph that wraps, down to a short line.
        v.minimumWidth = {
            let full = WinTextCache.shared.layout(content, style, maxWidth: nil).width
            return min(full, style.size * (style.wraps ? 4 : 2))
        }
        v.draw = { [weak v] canvas, rect in
            let layout = WinTextCache.shared.layout(content, style, maxWidth: rect.width)
            let ink = color ?? v?.inheritedForeground ?? .primaryText
            // Centred in a frame taller than the text, as a label is.
            let y = max(0, ((rect.height - layout.height) / 2).rounded())
            canvas.text(layout, at: 0, y, ink)
            if let strike {
                canvas.line(0, y + layout.height / 2, layout.width, y + layout.height / 2, width: 1, strike)
            }
        }
    }
}
#endif
