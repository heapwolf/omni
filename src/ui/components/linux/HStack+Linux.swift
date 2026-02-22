#if os(Linux)
import Foundation

extension HStack {
    @MainActor public func makeNative() -> NativeView {
        return gtk_box_new(GtkOrientation.horizontal, Int32(resolvedSpacing))
    }

    @MainActor public func updateNative(_ view: NativeView) {
        gtk_box_set_spacing(view, Int32(resolvedSpacing))
    }

    @MainActor public func insertChild(_ child: NativeView, into parent: NativeView) {
        // fill=1: a child that expands must be stretched into its share of
        // the surplus, not centred in it.
        gtk_box_pack_start(parent, child, 0, 1, 0)
        narrowSpacer(child, to: GtkOrientation.horizontal)

        // See VStack.insertChild: a child that wants vertical room keeps
        // GtkAlign.fill, or the stack's alignment would cancel it out.
        let wantsHeight = gtk_widget_get_vexpand(child) != 0
        gtk_widget_set_valign(child, wantsHeight ? GtkAlign.fill : alignment.gtkAlign)
        carryExpand(from: child, to: parent)

        // See VStack.insertChild.
        gtk_widget_set_halign(parent, gtk_widget_get_hexpand(parent) != 0 ? GtkAlign.fill : GtkAlign.center)
    }
}
#endif
