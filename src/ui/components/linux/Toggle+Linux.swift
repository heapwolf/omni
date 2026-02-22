#if os(Linux)
import Foundation
import Glibc

nonisolated(unsafe) let gtk_check_button_new_with_label: @convention(c) (UnsafePointer<CChar>) -> NativeView = fn(libgtk, "gtk_check_button_new_with_label")
nonisolated(unsafe) let gtk_toggle_button_get_active: @convention(c) (NativeView) -> Int32 = fn(libgtk, "gtk_toggle_button_get_active")
nonisolated(unsafe) let gtk_toggle_button_set_active: @convention(c) (NativeView, Int32) -> Void = fn(libgtk, "gtk_toggle_button_set_active")

extension Toggle {
    @MainActor public func makeNative() -> NativeView {
        return gtk_check_button_new_with_label("")
    }

    @MainActor public func updateNative(_ view: NativeView) {
        let binding = isOnBinding

        gtk_button_set_label(view, title)

        let current = gtk_toggle_button_get_active(view) != 0
        if current != binding.wrappedValue {
            gtk_toggle_button_set_active(view, binding.wrappedValue ? 1 : 0)
        }

        bindLinuxEvent(view, "toggled") {
            binding.wrappedValue = gtk_toggle_button_get_active(view) != 0
        }
    }
}
#endif
