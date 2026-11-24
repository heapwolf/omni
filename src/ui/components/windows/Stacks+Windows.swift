// src/ui/components/windows/Stacks+Windows.swift: VStack, HStack, Stack, ZStack, Spacer.
#if os(Windows)
import Foundation

extension VStack {
    @MainActor public func makeNative() -> NativeView {
        WinView.make("VStack", layout: .box(.vertical))
    }

    @MainActor public func updateNative(_ view: NativeView) {
        let v = winView(view)
        v.spacing = resolvedSpacing
        // Across, each child at its own width placed by the stack's alignment;
        // one that expands across still fills (the layout reads that live).
        for child in v.children { WinStacks.placeInColumn(child, alignment.winAlign) }
    }

    @MainActor public func insertChild(_ child: NativeView, into parent: NativeView) {
        let c = winView(child)
        winView(parent).add(c)
        WinStacks.placeInColumn(c, alignment.winAlign)
    }
}

extension HStack {
    @MainActor public func makeNative() -> NativeView {
        WinView.make("HStack", layout: .box(.horizontal))
    }

    @MainActor public func updateNative(_ view: NativeView) {
        let v = winView(view)
        v.spacing = resolvedSpacing
        for child in v.children { WinStacks.placeInRow(child, alignment.winAlign) }
    }

    @MainActor public func insertChild(_ child: NativeView, into parent: NativeView) {
        let c = winView(child)
        winView(parent).add(c)
        WinStacks.placeInRow(c, alignment.winAlign)
    }
}

@MainActor
enum WinStacks {
    /// A Spacer in a column takes height only: GTK's narrowSpacer.
    static func placeInColumn(_ child: WinView, _ align: WinAlign) {
        if child.isSpacer {
            child.hexpand = false
            child.vexpand = true
        }
        child.halign = align
        child.valign = .fill
    }

    static func placeInRow(_ child: WinView, _ align: WinAlign) {
        if child.isSpacer {
            child.hexpand = true
            child.vexpand = false
        }
        child.valign = align
        child.halign = .fill
    }
}

extension Stack {
    /// A stack whose axis changed (a responsive layout) lays its children
    /// out along the new one; each child's alignment follows.
    @MainActor func applyAxis(_ view: NativeView) {
        let v = winView(view)
        v.layout = .box(axis)
        for child in v.children {
            if axis == .vertical { WinStacks.placeInColumn(child, alignment.horizontal.winAlign) }
            else { WinStacks.placeInRow(child, alignment.vertical.winAlign) }
        }
        v.setNeedsLayout()
    }

    @MainActor func recordChild(_ child: NativeView, of parent: NativeView) {}
}

extension ZStack {
    @MainActor public func makeNative() -> NativeView {
        WinView.make(isNavigationContainer ? "NavigationStack" : "ZStack", layout: .overlay)
    }

    @MainActor public func updateNative(_ view: NativeView) {
        let v = winView(view)
        v.contentAlignment = alignment
        for child in v.children { place(child) }
    }

    @MainActor public func insertChild(_ child: NativeView, into parent: NativeView) {
        let c = winView(child)
        winView(parent).add(c)
        place(c)
    }

    /// Its own size, placed by the alignment, unless it expands (a colour, a spacer).
    @MainActor private func place(_ child: WinView) {
        child.halign = alignment.horizontal.winAlign
        child.valign = alignment.vertical.winAlign
    }
}

extension Spacer {
    @MainActor public func makeNative() -> NativeView {
        let native = WinView.make("Spacer", layout: .leaf)
        let v = winView(native)
        v.isSpacer = true
        v.hexpand = true
        v.vexpand = true
        v.hitTesting = false
        return native
    }

    @MainActor public func updateNative(_ view: NativeView) {
        winView(view).spacerLength = minLength ?? 0
    }
}
#endif
