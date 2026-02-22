// src/lib/components/linux/Frame+Linux.swift
#if os(Linux)
import Foundation
import Glibc

extension Frame {
    @MainActor public func makeNative() -> NativeView {
        let view = gtk_box_new(GtkOrientation.vertical, 0)
        applySize(view)
        return view
    }

    @MainActor public func updateNative(_ view: NativeView) {
        applySize(view)
    }

    @MainActor public func insertChild(_ child: NativeView, into parent: NativeView) {
        // Not packFill: a frame answers for its own size, so the
        // content's expand must stop here. See applySize.
        gtk_box_pack_start(parent, child, 1, 1, 0)

        // A pinned axis places the child per alignment; an unpinned one is
        // still the child's to fill.
        gtk_widget_set_halign(child, width == nil ? GtkAlign.fill : alignment.horizontal.gtkAlign)
        gtk_widget_set_valign(child, height == nil ? GtkAlign.fill : alignment.vertical.gtkAlign)

        carryExpand(from: child, to: parent)
    }

    @MainActor private func applySize(_ view: NativeView) {
        gtk_widget_set_size_request(view, Int32(width ?? -1), Int32(height ?? -1))
        gtk_widget_set_hexpand(view, 0)
        gtk_widget_set_vexpand(view, 0)
        gtk_widget_set_hexpand_set(view, width == nil ? 0 : 1)
        gtk_widget_set_vexpand_set(view, height == nil ? 0 : 1)
    }
}
#endif
