// src/ui/components/windows/Modifiers+Windows.swift
//
// ModifierView on Windows: one WinView (a bin) carries everything the
// modifier says, as the Linux backend's GtkBox does. Its sizing follows
// GTK's: a fixed size is a size request that also stops the content's expand
// carrying past it; .infinity is an expand of its own.

#if os(Windows)
import Foundation

extension ModifierView {
    @MainActor func applyWindows(_ v: WinView) {
        v.fixedWidth = width
        v.fixedHeight = height
        v.minWidth = minWidth
        v.minHeight = minHeight
        v.maxWidth = maxWidth.flatMap { $0.isFinite ? $0 : nil }
        v.maxHeight = maxHeight.flatMap { $0.isFinite ? $0 : nil }
        v.hexpand = fillsWidth
        v.vexpand = fillsHeight
        v.hexpandSet = width != nil || fillsWidth
        v.vexpandSet = height != nil || fillsHeight
        v.padding = padding ?? EdgeInsets()
        if let alignment { v.contentAlignment = alignment }

        // Paint: only what this modifier says. Another modifier around the
        // same content is a view of its own.
        v.opacity = opacity ?? 1
        v.scale = scale ?? 1
        v.offsetX = offsetX ?? 0
        v.offsetY = offsetY ?? 0
        v.zIndex = zIndex ?? 0
        v.background = backgroundColor
        v.foreground = foregroundColor
        v.tint = tint
        v.borderColor = borderWidth != nil ? (borderColor ?? .clear) : nil
        v.borderWidth = borderWidth ?? 0
        if let disabled { v.disabled = disabled }
        if let allowsHitTesting { v.hitTesting = allowsHitTesting }
        for child in v.children { place(child) }
    }

    @MainActor func insertWindows(_ child: WinView, into parent: WinView) {
        parent.add(child)
        place(child)
    }

    /// .padding and .background wrap their content edge to edge; .frame with
    /// an alignment places it there at its own size, unless it fills.
    @MainActor private func place(_ child: WinView) {
        if let alignment {
            child.halign = alignment.horizontal.winAlign
            child.valign = alignment.vertical.winAlign
        } else {
            child.halign = .fill
            child.valign = .fill
        }
    }
}
#endif
