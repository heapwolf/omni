#if os(Linux)
import Foundation
import Glibc

nonisolated(unsafe) let gtk_combo_box_text_new: @convention(c) () -> NativeView = fn(libgtk, "gtk_combo_box_text_new")
nonisolated(unsafe) let gtk_combo_box_text_append_text: @convention(c) (NativeView, UnsafePointer<CChar>) -> Void = fn(libgtk, "gtk_combo_box_text_append_text")
nonisolated(unsafe) let gtk_combo_box_set_active: @convention(c) (NativeView, Int32) -> Void = fn(libgtk, "gtk_combo_box_set_active")
nonisolated(unsafe) let gtk_combo_box_get_active: @convention(c) (NativeView) -> Int32 = fn(libgtk, "gtk_combo_box_get_active")

extension NativePicker {
    @MainActor public func makeNative() -> NativeView {
        let combo = gtk_combo_box_text_new()
        for opt in options {
            gtk_combo_box_text_append_text(combo, opt.label)
        }

        if let idx = options.firstIndex(where: { $0.tag == selection.wrappedValue }) {
            gtk_combo_box_set_active(combo, Int32(idx))
        }

        let sel = selection
        let opts = options
        bindLinuxEvent(combo, "changed") {
            let idx = Int(gtk_combo_box_get_active(combo))
            if idx >= 0 && idx < opts.count {
                sel.wrappedValue = opts[idx].tag
            }
        }
        return combo
    }

    @MainActor public func updateNative(_ view: NativeView) {
        let currentSelection = selection.wrappedValue
        let selectedIndex = options.firstIndex(where: { $0.tag == currentSelection }) ?? 0

        if gtk_combo_box_get_active(view) != Int32(selectedIndex) {
            gtk_combo_box_set_active(view, Int32(selectedIndex))
        }
    }
}
#endif
