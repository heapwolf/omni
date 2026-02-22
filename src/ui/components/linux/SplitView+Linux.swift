#if os(Linux)
import Foundation
import Glibc

nonisolated(unsafe) let gtk_paned_new: @convention(c) (Int32) -> NativeView = fn(libgtk, "gtk_paned_new")
nonisolated(unsafe) let gtk_paned_add1: @convention(c) (NativeView, NativeView) -> Void = fn(libgtk, "gtk_paned_add1")
nonisolated(unsafe) let gtk_paned_add2: @convention(c) (NativeView, NativeView) -> Void = fn(libgtk, "gtk_paned_add2")
nonisolated(unsafe) let gtk_paned_get_child1: @convention(c) (NativeView) -> NativeView? = fn(libgtk, "gtk_paned_get_child1")

extension SplitView {
    @MainActor public func makeNative() -> NativeView {
        // GTK_ORIENTATION_HORIZONTAL = 0 (side-by-side), GTK_ORIENTATION_VERTICAL = 1 (top-to-bottom)
        return gtk_paned_new(isVertical ? 0 : 1)
    }

    @MainActor public func updateNative(_ view: NativeView) {
        // Orientation cannot be trivially changed after creation in GTK Paned without rebuilding
    }

    @MainActor public func insertChild(_ child: NativeView, into parent: NativeView) {
        // GtkPaned only accepts exactly two children. Check if slot 1 is filled.
        if gtk_paned_get_child1(parent) == nil {
            gtk_paned_add1(parent, child)
        } else {
            gtk_paned_add2(parent, child)
        }
    }
}
#endif
