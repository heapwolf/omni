#if os(Linux)
import Foundation
import Glibc

nonisolated(unsafe) let gtk_text_view_new: @convention(c) () -> NativeView = fn(libgtk, "gtk_text_view_new")
private nonisolated(unsafe) let gtk_text_view_get_buffer: @convention(c) (NativeView) -> NativeView =
    fn(libgtk, "gtk_text_view_get_buffer")
private nonisolated(unsafe) let gtk_text_buffer_set_text: @convention(c) (NativeView, UnsafePointer<CChar>, Int32) -> Void =
    fn(libgtk, "gtk_text_buffer_set_text")
private nonisolated(unsafe) let gtk_text_buffer_get_bounds: @convention(c) (NativeView, UnsafeMutableRawPointer, UnsafeMutableRawPointer) -> Void =
    fn(libgtk, "gtk_text_buffer_get_bounds")
private nonisolated(unsafe) let gtk_text_buffer_get_text: @convention(c) (NativeView, UnsafeMutableRawPointer, UnsafeMutableRawPointer, Int32) -> UnsafeMutablePointer<CChar>? =
    fn(libgtk, "gtk_text_buffer_get_text")

/// A GtkTextIter is a stack struct GTK fills in. Its layout is private, so the
/// caller only has to hand over enough room; it is documented as 14 fields.
private let textIterSize = 14 * MemoryLayout<UnsafeRawPointer>.size

@MainActor private func bufferText(_ buffer: NativeView) -> String {
    var iters = [UInt8](repeating: 0, count: textIterSize * 2)
    return iters.withUnsafeMutableBytes { raw -> String in
        let start = raw.baseAddress!
        let end = start + textIterSize
        gtk_text_buffer_get_bounds(buffer, start, end)
        guard let chars = gtk_text_buffer_get_text(buffer, start, end, 0) else { return "" }
        defer { g_free(chars) }
        return String(cString: chars)
    }
}

extension TextEditor {
    @MainActor public func makeNative() -> NativeView {
        let view = gtk_text_view_new()

        // A GtkTextView's natural height is one line, which in a stack of
        // fields reads as a stray rule. Give it the room an editor implies.
        gtk_widget_set_size_request(view, -1, 96)
        gtk_widget_set_hexpand(view, 1)
        return view
    }

    @MainActor public func updateNative(_ view: NativeView) {
        let buffer = gtk_text_view_get_buffer(view)
        let binding = text

        if bufferText(buffer) != binding.wrappedValue {
            gtk_text_buffer_set_text(buffer, binding.wrappedValue, -1)
        }

        // The signal is on the buffer, not the view: GtkTextView has no
        // "changed" of its own and connecting there would silently never fire.
        bindLinuxEvent(buffer, "changed") {
            binding.wrappedValue = bufferText(buffer)
        }
    }
}
#endif
