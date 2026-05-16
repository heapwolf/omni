#if os(Linux)
import Glibc
@testable import OmniUI


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
