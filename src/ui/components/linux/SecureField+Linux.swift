#if os(Linux)
import Foundation
import Glibc

nonisolated(unsafe) let gtk_entry_set_visibility: @convention(c) (NativeView, Int32) -> Void = fn(libgtk, "gtk_entry_set_visibility")

extension SecureField {
    @MainActor public func makeNative() -> NativeView {
        let entry = gtk_entry_new()
        gtk_entry_set_visibility(entry, 0) // 0 = invisible/password mode
        gtk_entry_set_placeholder_text(entry, title)
        gtk_widget_set_hexpand(entry, 1)

        let binding = text
        bindLinuxEvent(entry, "changed") {
            let ptr = gtk_entry_get_text(entry)
            binding.wrappedValue = String(cString: ptr)
        }
        return entry
    }

    @MainActor public func updateNative(_ view: NativeView) {
        let currentText = text.wrappedValue
        let ptr = gtk_entry_get_text(view)

        if String(cString: ptr) != currentText {
            gtk_entry_set_text(view, currentText)
        }
    }
}
#endif
