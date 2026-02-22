#if os(Linux)
import Foundation
import Glibc

// MARK: - Widgets

nonisolated(unsafe) let gtk_window_new: @convention(c) (Int32) -> NativeView =
    fn(libgtk, "gtk_window_new")
nonisolated(unsafe) let gtk_window_set_default_size: @convention(c) (NativeView, Int32, Int32) -> Void =
    fn(libgtk, "gtk_window_set_default_size")
nonisolated(unsafe) let gtk_window_set_resizable: @convention(c) (NativeView, Int32) -> Void =
    fn(libgtk, "gtk_window_set_resizable")
// The trailing GError** is untyped and always nil: only success matters.
nonisolated(unsafe) let gtk_window_set_icon_from_file: @convention(c) (NativeView, UnsafePointer<CChar>?, UnsafeMutableRawPointer?) -> Int32 =
    fn(libgtk, "gtk_window_set_icon_from_file")
nonisolated(unsafe) let gtk_label_new: @convention(c) (UnsafePointer<CChar>?) -> NativeView =
    fn(libgtk, "gtk_label_new")
nonisolated(unsafe) let gtk_button_set_label: @convention(c) (NativeView, UnsafePointer<CChar>) -> Void =
    fn(libgtk, "gtk_button_set_label")
nonisolated(unsafe) let gtk_widget_set_sensitive: @convention(c) (NativeView, Int32) -> Void =
    fn(libgtk, "gtk_widget_set_sensitive")
nonisolated(unsafe) let gtk_widget_set_size_request: @convention(c) (NativeView, Int32, Int32) -> Void =
    fn(libgtk, "gtk_widget_set_size_request")
nonisolated(unsafe) let gtk_box_set_spacing: @convention(c) (NativeView, Int32) -> Void =
    fn(libgtk, "gtk_box_set_spacing")
nonisolated(unsafe) let gtk_widget_set_halign: @convention(c) (NativeView, Int32) -> Void =
    fn(libgtk, "gtk_widget_set_halign")
nonisolated(unsafe) let gtk_widget_set_valign: @convention(c) (NativeView, Int32) -> Void =
    fn(libgtk, "gtk_widget_set_valign")
nonisolated(unsafe) let gtk_widget_set_hexpand: @convention(c) (NativeView, Int32) -> Void =
    fn(libgtk, "gtk_widget_set_hexpand")
nonisolated(unsafe) let gtk_widget_set_vexpand: @convention(c) (NativeView, Int32) -> Void =
    fn(libgtk, "gtk_widget_set_vexpand")
nonisolated(unsafe) let gtk_widget_get_hexpand: @convention(c) (NativeView) -> Int32 =
    fn(libgtk, "gtk_widget_get_hexpand")
nonisolated(unsafe) let gtk_widget_get_vexpand: @convention(c) (NativeView) -> Int32 =
    fn(libgtk, "gtk_widget_get_vexpand")
nonisolated(unsafe) let gtk_widget_set_hexpand_set: @convention(c) (NativeView, Int32) -> Void =
    fn(libgtk, "gtk_widget_set_hexpand_set")
nonisolated(unsafe) let gtk_widget_set_vexpand_set: @convention(c) (NativeView, Int32) -> Void =
    fn(libgtk, "gtk_widget_set_vexpand_set")
nonisolated(unsafe) let gtk_widget_get_hexpand_set: @convention(c) (NativeView) -> Int32 =
    fn(libgtk, "gtk_widget_get_hexpand_set")
nonisolated(unsafe) let gtk_widget_get_vexpand_set: @convention(c) (NativeView) -> Int32 =
    fn(libgtk, "gtk_widget_get_vexpand_set")
nonisolated(unsafe) let gtk_widget_set_name: @convention(c) (NativeView, UnsafePointer<CChar>) -> Void =
    fn(libgtk, "gtk_widget_set_name")
nonisolated(unsafe) let gtk_widget_get_name: @convention(c) (NativeView) -> UnsafePointer<CChar>? =
    fn(libgtk, "gtk_widget_get_name")
nonisolated(unsafe) let gtk_widget_get_size_request: @convention(c) (NativeView, UnsafeMutablePointer<Int32>, UnsafeMutablePointer<Int32>) -> Void =
    fn(libgtk, "gtk_widget_get_size_request")

enum GtkOrientation {
    static let horizontal: Int32 = 0
    static let vertical: Int32 = 1
}

// GtkAlign
enum GtkAlign {
    static let fill: Int32 = 0
    static let start: Int32 = 1
    static let end: Int32 = 2
    static let center: Int32 = 3
}

extension HorizontalAlignment {
    var gtkAlign: Int32 {
        switch self {
        case .leading: return GtkAlign.start
        case .center: return GtkAlign.center
        case .trailing: return GtkAlign.end
        }
    }
}

extension VerticalAlignment {
    var gtkAlign: Int32 {
        switch self {
        case .top: return GtkAlign.start
        case .center: return GtkAlign.center
        case .bottom: return GtkAlign.end
        }
    }
}

// MARK: - Entries

nonisolated(unsafe) let gtk_entry_new: @convention(c) () -> NativeView =
    fn(libgtk, "gtk_entry_new")
nonisolated(unsafe) let gtk_entry_get_text: @convention(c) (NativeView) -> UnsafePointer<CChar> =
    fn(libgtk, "gtk_entry_get_text")
nonisolated(unsafe) let gtk_entry_set_text: @convention(c) (NativeView, UnsafePointer<CChar>) -> Void =
    fn(libgtk, "gtk_entry_set_text")
// Input purpose is a hint to input methods; max length GTK enforces itself.
nonisolated(unsafe) let gtk_entry_set_input_purpose: @convention(c) (NativeView, Int32) -> Void =
    fn(libgtk, "gtk_entry_set_input_purpose")
nonisolated(unsafe) let gtk_entry_set_max_length: @convention(c) (NativeView, Int32) -> Void =
    fn(libgtk, "gtk_entry_set_max_length")
nonisolated(unsafe) let gtk_widget_grab_focus: @convention(c) (NativeView) -> Void =
    fn(libgtk, "gtk_widget_grab_focus")
nonisolated(unsafe) let gtk_widget_has_focus: @convention(c) (NativeView) -> Int32 =
    fn(libgtk, "gtk_widget_has_focus")
nonisolated(unsafe) let gtk_entry_set_placeholder_text: @convention(c) (NativeView, UnsafePointer<CChar>) -> Void =
    fn(libgtk, "gtk_entry_set_placeholder_text")

// MARK: - Expansion

@MainActor func carryExpand(from child: NativeView, to parent: NativeView) {
    if gtk_widget_get_hexpand(child) != 0 && gtk_widget_get_hexpand_set(parent) == 0 {
        gtk_widget_set_hexpand(parent, 1)
        gtk_widget_set_hexpand_set(parent, 0)
    }
    if gtk_widget_get_vexpand(child) != 0 && gtk_widget_get_vexpand_set(parent) == 0 {
        gtk_widget_set_vexpand(parent, 1)
        gtk_widget_set_vexpand_set(parent, 0)
    }
}

/// Packs a wrapper's single child so it fills the wrapper: padding,
/// background, sheet host.
@MainActor func packFill(_ child: NativeView, into parent: NativeView) {
    gtk_box_pack_start(parent, child, 1, 1, 0)
    carryExpand(from: child, to: parent)
}

// MARK: - Menus

nonisolated(unsafe) let gtk_menu_bar_new: @convention(c) () -> NativeView =
    fn(libgtk, "gtk_menu_bar_new")
nonisolated(unsafe) let gtk_menu_new: @convention(c) () -> NativeView =
    fn(libgtk, "gtk_menu_new")
nonisolated(unsafe) let gtk_menu_item_new_with_label: @convention(c) (UnsafePointer<CChar>) -> NativeView =
    fn(libgtk, "gtk_menu_item_new_with_label")
nonisolated(unsafe) let gtk_menu_item_set_submenu: @convention(c) (NativeView, NativeView) -> Void =
    fn(libgtk, "gtk_menu_item_set_submenu")
nonisolated(unsafe) let gtk_menu_shell_append: @convention(c) (NativeView, NativeView) -> Void =
    fn(libgtk, "gtk_menu_shell_append")

// MARK: - GObject

// The third parameter is optional so both call sites type-check: Canvas passes
// nil to clear associated data, Events always passes a live pointer.
nonisolated(unsafe) let g_object_set_data_full: @convention(c) (NativeView, UnsafePointer<CChar>, UnsafeMutableRawPointer?, @convention(c) (UnsafeMutableRawPointer?) -> Void) -> Void =
    fn(libgobj, "g_object_set_data_full")
nonisolated(unsafe) let g_signal_connect_data: @convention(c) (NativeView, UnsafePointer<CChar>, UnsafeMutableRawPointer, UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, Int32) -> Int =
    fn(libgobj, "g_signal_connect_data")
nonisolated(unsafe) let g_free: @convention(c) (UnsafeMutableRawPointer) -> Void =
    fn(libgobj, "g_free")
nonisolated(unsafe) let g_object_get_data: @convention(c) (NativeView, UnsafePointer<CChar>) -> UnsafeMutableRawPointer? =
    fn(libgobj, "g_object_get_data")

#endif
