// src/lib/components/linux/Divider+Linux.swift
import Foundation

#if os(Linux)
import Glibc

// Bind the GTK C function
nonisolated(unsafe) let gtk_separator_new: @convention(c) (Int32) -> NativeView = fn(libgtk, "gtk_separator_new")

extension Divider {
    @MainActor public func makeNative() -> NativeView {
        let view = gtk_separator_new(resolvedIsVertical ? GtkOrientation.vertical : GtkOrientation.horizontal)

        // A rule spans its container: without the expand flag GTK gives a
        // separator its 1px natural length and it renders as a dot.
        gtk_widget_set_hexpand(view, resolvedIsVertical ? 0 : 1)
        gtk_widget_set_vexpand(view, resolvedIsVertical ? 1 : 0)
        return view
    }

    @MainActor public func updateNative(_ view: NativeView) {
        // Static view, no updates needed
    }
}
#endif
