#if os(Linux)
import Foundation
import Glibc

extension VStack {
    @MainActor public func makeNative() -> NativeView {
        return gtk_box_new(GtkOrientation.vertical, Int32(resolvedSpacing))
    }

    @MainActor public func updateNative(_ view: NativeView) {
        gtk_box_set_spacing(view, Int32(resolvedSpacing))
    }

    @MainActor public func insertChild(_ child: NativeView, into parent: NativeView) {
        // fill=1: a child that expands must be stretched into its share of
        // the surplus, not centred in it.
        gtk_box_pack_start(parent, child, 0, 1, 0)
        narrowSpacer(child, to: GtkOrientation.vertical)

        let wantsWidth = gtk_widget_get_hexpand(child) != 0
        gtk_widget_set_halign(child, wantsWidth ? GtkAlign.fill : alignment.gtkAlign)
        carryExpand(from: child, to: parent)

        gtk_widget_set_valign(parent, gtk_widget_get_vexpand(parent) != 0 ? GtkAlign.fill : GtkAlign.center)
    }
}
#endif
