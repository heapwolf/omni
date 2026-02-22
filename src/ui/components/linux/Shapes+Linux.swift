#if os(Linux)
import Foundation
import Glibc

extension ClipModifierView {
    @MainActor public func makeNative() -> NativeView {
        gtk_box_new(GtkOrientation.vertical, 0)
    }

    @MainActor public func updateNative(_ view: NativeView) {
        applyCSS(cornerCSS, to: view, slot: .clip)
    }

    @MainActor public func insertChild(_ child: NativeView, into parent: NativeView) {
        packFill(child, into: parent)

        applyCSS(cornerCSS, to: child, slot: .clip)
    }

    /// A circle is a square with a radius larger than it can use; GTK clamps.
    private var cornerCSS: [String] {
        ["border-radius: \(isCircular ? 9999 : Int(radius))px;"]
    }
}
#endif
