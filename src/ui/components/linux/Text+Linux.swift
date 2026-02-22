#if os(Linux)
import Foundation

nonisolated(unsafe) let gtk_label_set_text: @convention(c) (NativeView, UnsafePointer<CChar>) -> Void = fn(libgtk, "gtk_label_set_text")

// Add Pango Ellipsize C-Bindings
// 0 = NONE, 1 = START, 2 = MIDDLE, 3 = END
nonisolated(unsafe) let gtk_label_set_ellipsize: @convention(c) (NativeView, Int32) -> Void = fn(libgtk, "gtk_label_set_ellipsize")
nonisolated(unsafe) let gtk_label_set_lines: @convention(c) (NativeView, Int32) -> Void = fn(libgtk, "gtk_label_set_lines")

// Pango carries font attributes on GtkLabel; without these, .font() and
// .monospaced() were both silently ignored on Linux.
nonisolated(unsafe) let libpango = dlopen("libpango-1.0.so.0", RTLD_LAZY | RTLD_GLOBAL)
nonisolated(unsafe) let pango_attr_list_new: @convention(c) () -> UnsafeMutableRawPointer =
    fn(libpango, "pango_attr_list_new")
nonisolated(unsafe) let pango_attr_list_unref: @convention(c) (UnsafeMutableRawPointer) -> Void =
    fn(libpango, "pango_attr_list_unref")
nonisolated(unsafe) let pango_attr_list_insert: @convention(c) (UnsafeMutableRawPointer, UnsafeMutableRawPointer) -> Void =
    fn(libpango, "pango_attr_list_insert")
nonisolated(unsafe) let pango_attr_family_new: @convention(c) (UnsafePointer<CChar>) -> UnsafeMutableRawPointer =
    fn(libpango, "pango_attr_family_new")
nonisolated(unsafe) let pango_attr_size_new: @convention(c) (Int32) -> UnsafeMutableRawPointer =
    fn(libpango, "pango_attr_size_new")
nonisolated(unsafe) let gtk_label_set_attributes: @convention(c) (NativeView, UnsafeMutableRawPointer?) -> Void =
    fn(libgtk, "gtk_label_set_attributes")
// Pango numbers weights 100-900, exactly as FontWeight does.
nonisolated(unsafe) let pango_attr_weight_new: @convention(c) (Int32) -> UnsafeMutableRawPointer =
    fn(libpango, "pango_attr_weight_new")
// PangoStyle: 0 = NORMAL, 2 = ITALIC.
nonisolated(unsafe) let pango_attr_style_new: @convention(c) (Int32) -> UnsafeMutableRawPointer =
    fn(libpango, "pango_attr_style_new")
nonisolated(unsafe) let pango_attr_letter_spacing_new: @convention(c) (Int32) -> UnsafeMutableRawPointer =
    fn(libpango, "pango_attr_letter_spacing_new")

// Pango measures in 1024ths of a point.
private let pangoScale: Double = 1024

extension Text {
    @MainActor public func makeNative() -> NativeView {
        return gtk_label_new("")
    }

    @MainActor public func updateNative(_ view: NativeView) {
        gtk_label_set_text(view, text)

        if let h = height {
            gtk_widget_set_size_request(view, Int32(width ?? -1), Int32(h))
        }

        if width != nil || height != nil {
            switch alignment {
            case .leading: gtk_widget_set_halign(view, GtkAlign.start)
            case .trailing: gtk_widget_set_halign(view, GtkAlign.end)
            case .center: gtk_widget_set_halign(view, GtkAlign.center)
            }
        }

        // Rebuilt every update so a reused label never keeps a stale font.
        let attributes = pango_attr_list_new()
        pango_attr_list_insert(attributes,
            pango_attr_size_new(Int32(font.size * pangoScale)))
        pango_attr_list_insert(attributes,
            pango_attr_weight_new(Int32(font.weight.rawValue)))
        if font.isItalic {
            pango_attr_list_insert(attributes, pango_attr_style_new(2))
        }
        if tracking != 0 {
            pango_attr_list_insert(attributes,
                pango_attr_letter_spacing_new(Int32(tracking * pangoScale)))
        }
        // lineSpacing has no GTK3 equivalent and is not applied here.

        // .monospaced() wins over a custom family: it is the more specific of
        // the two requests, and code is the reason to ask for either.
        if isMonospaced {
            pango_attr_list_insert(attributes, pango_attr_family_new("monospace"))
        } else if let family = font.family {
            pango_attr_list_insert(attributes,
                pango_attr_family_new(Font.resolvedFamily(family)))
        }
        gtk_label_set_attributes(view, attributes)
        pango_attr_list_unref(attributes)

        gtk_label_set_lines(view, Int32(lineLimit ?? -1))
        switch truncationMode {
        case .none: gtk_label_set_ellipsize(view, 0)
        case .head: gtk_label_set_ellipsize(view, 1)
        case .middle: gtk_label_set_ellipsize(view, 2)
        case .tail: gtk_label_set_ellipsize(view, 3)
        }
    }
}
#endif
