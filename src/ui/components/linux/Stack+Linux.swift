// src/lib/components/linux/Stack+Linux.swift
#if os(Linux)
import Foundation

nonisolated(unsafe) let gtk_orientable_set_orientation: @convention(c) (NativeView, Int32) -> Void =
    fn(libgtk, "gtk_orientable_set_orientation")
nonisolated(unsafe) let gtk_container_get_children: @convention(c) (NativeView) -> UnsafeMutableRawPointer? =
    fn(libgtk, "gtk_container_get_children")
nonisolated(unsafe) let g_list_free: @convention(c) (UnsafeMutableRawPointer?) -> Void =
    fn(libgtk, "g_list_free")

extension Stack {
    @MainActor func applyAxis(_ view: NativeView) {
        gtk_orientable_set_orientation(
            view, axis == .vertical ? GtkOrientation.vertical : GtkOrientation.horizontal)

        // GList: { data, next, prev }. The pointers are the widgets themselves
        // here, unlike JNI, so enumerating is enough and nothing need be kept.
        var node = gtk_container_get_children(view)
        let head = node
        while let current = node {
            if let child = current.load(fromByteOffset: 0, as: UnsafeMutableRawPointer?.self) {
                if axis == .vertical {
                    let wantsWidth = gtk_widget_get_hexpand(child) != 0
                    gtk_widget_set_halign(child, wantsWidth ? GtkAlign.fill : alignment.horizontal.gtkAlign)
                    gtk_widget_set_valign(child, GtkAlign.fill)
                } else {
                    let wantsHeight = gtk_widget_get_vexpand(child) != 0
                    gtk_widget_set_valign(child, wantsHeight ? GtkAlign.fill : alignment.vertical.gtkAlign)
                    gtk_widget_set_halign(child, GtkAlign.fill)
                }
            }
            node = current.load(fromByteOffset: 8, as: UnsafeMutableRawPointer?.self)
        }
        g_list_free(head)
    }

    /// Nothing to remember: the children can be enumerated when needed.
    @MainActor func recordChild(_ child: NativeView, of parent: NativeView) {}
}
#endif
