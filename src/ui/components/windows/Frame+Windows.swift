// src/ui/components/windows/Frame+Windows.swift
#if os(Windows)
import Foundation

extension Frame {
    @MainActor public func makeNative() -> NativeView {
        WinView.make("Frame", layout: .bin)
    }

    @MainActor public func updateNative(_ view: NativeView) {
        let v = winView(view)
        v.fixedWidth = width
        v.fixedHeight = height
        // A pinned axis is the frame's to size; an unpinned one is as flexible as the content.
        v.hexpand = false
        v.vexpand = false
        v.hexpandSet = width != nil
        v.vexpandSet = height != nil
        v.contentAlignment = alignment
        v.cursor = cursor
        v.onTap = onTap
        v.onTapLocation = onTapLocation
        v.onScrollWheel = onScroll
        v.onDrag = onDrag
        v.onDragEnded = onDragEnded
        for child in v.children { place(child) }
    }

    @MainActor public func insertChild(_ child: NativeView, into parent: NativeView) {
        let c = winView(child)
        winView(parent).add(c)
        place(c)
    }

    /// A pinned axis places the child by alignment; an unpinned one is the child's to fill.
    @MainActor private func place(_ child: WinView) {
        child.halign = width == nil ? .fill : alignment.horizontal.winAlign
        child.valign = height == nil ? .fill : alignment.vertical.winAlign
    }
}

public extension TapGestureView {
    @MainActor func makeNative() -> NativeView {
        WinView.make("TapGesture", layout: .bin)
    }

    @MainActor func updateNative(_ view: NativeView) {
        winView(view).onTap = action
    }

    @MainActor func insertChild(_ child: NativeView, into parent: NativeView) {
        winPackFill(child, into: parent)
    }
}

public extension PressGestureView {
    @MainActor func makeNative() -> NativeView {
        WinView.make("PressGesture", layout: .bin)
    }

    @MainActor func updateNative(_ view: NativeView) {
        let v = winView(view)
        v.onPress = onPressChange
        v.onTap = action
    }

    @MainActor func insertChild(_ child: NativeView, into parent: NativeView) {
        winPackFill(child, into: parent)
    }
}
#endif
