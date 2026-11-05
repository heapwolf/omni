#if os(Linux)
import Foundation
import Glibc

// No video on Linux yet: an empty box, so what's under it (its first frame, as a still) shows.
extension Video {
    @MainActor public func makeNative() -> NativeView {
        let view = gtk_box_new(0, 0)
        if isResizable {
            gtk_widget_set_hexpand(view, 1)
            gtk_widget_set_vexpand(view, 1)
        }
        return view
    }

    @MainActor public func updateNative(_ view: NativeView) {}
}
#endif
