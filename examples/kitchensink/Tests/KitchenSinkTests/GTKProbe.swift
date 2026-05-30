// A copy of tests/OmniUITests/GTKProbe.swift.
//
// Not an oversight, and not ideal. The framework's probe lives in its own test
// target, and a test target is not something a package can depend on — since the
// examples became standalone packages (see Package.swift), KitchenSinkRenderTests
// has been unable to see any of it and has not compiled. It was written when the
// example was a target inside the root manifest.
//
// Copied rather than re-invented so the two read identically when one changes. If
// a third package ever needs it, that is the point at which omni should vend it as
// a real target instead.

#if os(Linux)
import Glibc
@testable import OmniUI

// Reads a rendered GTK tree the way a person reading the screen would: by
// widget type and by the text on it. Shared so that a test asserting what is
// visible does not have to know how GObject stores any of it.

private let gtk_container_get_children_p: @convention(c) (NativeView) -> UnsafeMutableRawPointer? =
    fn(libgtk, "gtk_container_get_children")
private let gtk_label_get_text_p: @convention(c) (NativeView) -> UnsafePointer<CChar>? =
    fn(libgtk, "gtk_label_get_text")
private let g_type_name_p: @convention(c) (UInt) -> UnsafePointer<CChar>? =
    fn(libgobj, "g_type_name")
private let g_type_from_name_p: @convention(c) (UnsafePointer<CChar>) -> UInt =
    fn(libgobj, "g_type_from_name")
private let g_type_is_a_p: @convention(c) (UInt, UInt) -> Int32 =
    fn(libgobj, "g_type_is_a")

private struct GList {
    var data: UnsafeMutableRawPointer?
    var next: UnsafeMutablePointer<GList>?
    var prev: UnsafeMutablePointer<GList>?
}

/// Every GTypeInstance starts with a pointer to its class, and every GTypeClass
/// starts with its GType.
func gtype(of widget: NativeView) -> UInt {
    widget.load(as: UnsafeRawPointer.self).load(as: UInt.self)
}

/// The GObject class name, e.g. "GtkButton".
func typeName(of widget: NativeView) -> String {
    guard let name = g_type_name_p(gtype(of: widget)) else { return "" }
    return String(cString: name)
}

/// True when the widget is `className` or a subclass of it. Calling a widget's
/// API without checking is a GTK-CRITICAL per call, and that noise is what
/// hides a real one.
func isA(_ widget: NativeView, _ className: String) -> Bool {
    g_type_is_a_p(gtype(of: widget), g_type_from_name_p(className)) != 0
}

func children(of widget: NativeView) -> [NativeView] {
    guard isA(widget, "GtkContainer"), let raw = gtk_container_get_children_p(widget) else { return [] }
    var found: [NativeView] = []
    var link: UnsafeMutablePointer<GList>? = raw.assumingMemoryBound(to: GList.self)
    while let node = link {
        if let child = node.pointee.data { found.append(child) }
        link = node.pointee.next
    }
    return found
}

/// Every piece of text in the tree, so a screen can be recognised by what it
/// says. A GtkButton's text is the label inside it, so buttons need no case.
func labels(in widget: NativeView) -> [String] {
    var found: [String] = []
    if isA(widget, "GtkLabel"), let text = gtk_label_get_text_p(widget) {
        found.append(String(cString: text))
    }
    return found + children(of: widget).flatMap { labels(in: $0) }
}

func button(titled title: String, in widget: NativeView) -> NativeView? {
    if isA(widget, "GtkButton"), labels(in: widget) == [title] { return widget }
    for child in children(of: widget) {
        if let match = button(titled: title, in: child) { return match }
    }
    return nil
}

func widgetCount(in widget: NativeView) -> Int {
    1 + children(of: widget).reduce(0) { $0 + widgetCount(in: $1) }
}
#endif
