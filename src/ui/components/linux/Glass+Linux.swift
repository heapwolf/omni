// src/lib/components/linux/Glass+Linux.swift
#if os(Linux)
    import Foundation

    // No glass or blur under GTK yet: the content as it is, in a box.
    public extension EffectBackgroundView {
        @MainActor func makeNative() -> NativeView { gtk_box_new(1, 0) }
        @MainActor func updateNative(_ view: NativeView) {}
        @MainActor func insertChild(_ child: NativeView, into parent: NativeView) { packFill(child, into: parent) }
    }

    public extension GlassEffectContainerView {
        @MainActor func makeNative() -> NativeView { gtk_box_new(1, 0) }
        @MainActor func updateNative(_ view: NativeView) {}
        @MainActor func insertChild(_ child: NativeView, into parent: NativeView) { packFill(child, into: parent) }
    }
#endif
