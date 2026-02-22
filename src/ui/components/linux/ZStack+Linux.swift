#if os(Linux)
import Foundation
import Glibc

nonisolated(unsafe) let gtk_overlay_new: @convention(c) () -> NativeView = fn(libgtk, "gtk_overlay_new")
nonisolated(unsafe) let gtk_overlay_add_overlay: @convention(c) (NativeView, NativeView) -> Void = fn(libgtk, "gtk_overlay_add_overlay")
/// GtkOverlay is a GtkBin: this is its main child, or nil if it has none yet.
nonisolated(unsafe) let gtk_bin_get_child: @convention(c) (NativeView) -> NativeView? = fn(libgtk, "gtk_bin_get_child")

extension ZStack {
    @MainActor public func makeNative() -> NativeView {
        return gtk_overlay_new()
    }

    @MainActor public func updateNative(_ view: NativeView) {
        // Alignment is applied per child, in insertChild.
    }

    @MainActor public func insertChild(_ child: NativeView, into parent: NativeView) {
        if gtk_bin_get_child(parent) == nil {
            gtk_container_add(parent, child)
        } else {
            gtk_overlay_add_overlay(parent, child)
        }
        // fill on the axis the child claimed, so a filling child still
        // stretches; otherwise place it at its own size per alignment.
        gtk_widget_set_halign(child,
            gtk_widget_get_hexpand(child) != 0 ? GtkAlign.fill : alignment.horizontal.gtkAlign)
        gtk_widget_set_valign(child,
            gtk_widget_get_vexpand(child) != 0 ? GtkAlign.fill : alignment.vertical.gtkAlign)

        carryExpand(from: child, to: parent)
    }
}
#endif
