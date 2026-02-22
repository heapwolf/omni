#if os(Linux)
import Foundation
import Glibc

/// Marks the widget a Spacer builds, so an enclosing stack can recognise one
/// among its children. GTK's widget name is otherwise only a CSS selector.
private let spacerName = "omni-spacer"

extension Spacer {
    @MainActor public func makeNative() -> NativeView {
        let view = gtk_box_new(0, 0)
        gtk_widget_set_name(view, spacerName)

        gtk_widget_set_hexpand(view, 1)
        gtk_widget_set_vexpand(view, 1)

        if let min = minLength {
            gtk_widget_set_size_request(view, Int32(min), Int32(min))
        }
        return view
    }

    @MainActor public func updateNative(_ view: NativeView) {
        // Everything a Spacer has is fixed at construction.
    }
}

@MainActor func narrowSpacer(_ child: NativeView, to axis: Int32) {
    guard let name = gtk_widget_get_name(child), String(cString: name) == spacerName else { return }

    let horizontal = axis == GtkOrientation.horizontal
    gtk_widget_set_hexpand(child, horizontal ? 1 : 0)
    gtk_widget_set_vexpand(child, horizontal ? 0 : 1)

    // minLength is a length along the axis, not a square.
    var width: Int32 = -1, height: Int32 = -1
    gtk_widget_get_size_request(child, &width, &height)
    gtk_widget_set_size_request(child, horizontal ? width : -1, horizontal ? -1 : height)
}
#endif
