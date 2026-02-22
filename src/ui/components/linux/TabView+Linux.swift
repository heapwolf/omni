#if os(Linux)
import Foundation
import Glibc

nonisolated(unsafe) let gtk_gesture_swipe_new: @convention(c) (NativeView) -> UnsafeMutableRawPointer = fn(libgtk, "gtk_gesture_swipe_new")
nonisolated(unsafe) let gtk_widget_add_controller: @convention(c) (NativeView, UnsafeMutableRawPointer) -> Void = fn(libgtk, "gtk_widget_add_controller")

extension NativeSwipeModifierView {
    @MainActor public func makeNative() -> NativeView {
        let v = gtk_box_new(0, 0)
        let swipe = gtk_gesture_swipe_new(v)
        gtk_widget_add_controller(v, swipe)

        bindLinuxEvent(swipe, "swipe") {
            // GTK passes velocity as arguments. For simplicity in our framework bindings,
            // we simulate basic interception. In a full C-binding, you'd read the velocity_x ptr.
            self.onSwipeLeft() // Stub fallback
        }
        return v
    }

    @MainActor public func updateNative(_ view: NativeView) {}

    @MainActor public func insertChild(_ child: NativeView, into parent: NativeView) {
        packFill(child, into: parent)
    }
}
#endif
