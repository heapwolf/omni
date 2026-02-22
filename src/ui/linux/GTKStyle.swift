// GTK paints backgrounds, opacity and corner radii through CSS, so every
// visual modifier is a declaration block on one widget.
#if os(Linux)
import Foundation
import Glibc

private nonisolated(unsafe) let gtk_css_provider_new: @convention(c) () -> UnsafeMutableRawPointer =
    fn(libgtk, "gtk_css_provider_new")
private nonisolated(unsafe) let gtk_css_provider_load_from_data: @convention(c) (UnsafeMutableRawPointer, UnsafePointer<CChar>, Int, UnsafeMutableRawPointer?) -> Int32 =
    fn(libgtk, "gtk_css_provider_load_from_data")
private nonisolated(unsafe) let gtk_widget_get_style_context: @convention(c) (NativeView) -> UnsafeMutableRawPointer =
    fn(libgtk, "gtk_widget_get_style_context")
private nonisolated(unsafe) let gtk_style_context_add_provider: @convention(c) (UnsafeMutableRawPointer, UnsafeMutableRawPointer, UInt32) -> Void =
    fn(libgtk, "gtk_style_context_add_provider")
private nonisolated(unsafe) let gtk_style_context_remove_provider: @convention(c) (UnsafeMutableRawPointer, UnsafeMutableRawPointer) -> Void =
    fn(libgtk, "gtk_style_context_remove_provider")
private nonisolated(unsafe) let g_object_unref: @convention(c) (UnsafeMutableRawPointer) -> Void =
    fn(libgobj, "g_object_unref")

/// Above the theme, below the user.
private let applicationPriority: UInt32 = 600

/// Where a widget's provider is parked. Distinct slots keep two modifiers on
/// the same widget from overwriting each other.
public enum CSSSlot: String {
    case fill = "omni_css"
    case clip = "omni_css_clip"
}

extension Color {
    /// A GTK CSS colour. Semantic colours resolve to theme names, not fixed
    /// values, so they follow a dark theme.
    var css: String {
        switch self {
        case .alphaAdjusted(let base, let alpha): return "alpha(\(base.css), \(alpha))"
        case .adaptive: return resolved.css
        case .windowBackground: return "@theme_bg_color"
        case .controlBackground: return "@theme_base_color"
        case .primaryText: return "@theme_fg_color"
        case .secondaryText: return "alpha(@theme_fg_color, 0.6)"
        case .rgba, .clear, .black, .white, .gray, .red, .green, .blue, .orange, .yellow, .purple:
            let c = rgbaComponents
            return "rgba(\(Int(c.r * 255)),\(Int(c.g * 255)),\(Int(c.b * 255)),\(c.a))"
        }
    }
}

@MainActor func applyCSS(_ declarations: [String], to view: NativeView, slot: CSSSlot = .fill) {
    let providerKey = slot.rawValue
    let existing = g_object_get_data(view, providerKey)
    guard !declarations.isEmpty || existing != nil else { return }

    let context = gtk_widget_get_style_context(view)
    if let existing { gtk_style_context_remove_provider(context, existing) }

    guard !declarations.isEmpty else {
        // Setting the data to nil runs the destroy notify, releasing the old one.
        return g_object_set_data_full(view, providerKey, nil) { _ in }
    }

    let provider = gtk_css_provider_new()
    _ = gtk_css_provider_load_from_data(provider, "*{\(declarations.joined(separator: " "))}", -1, nil)
    gtk_style_context_add_provider(context, provider, applicationPriority)
    g_object_set_data_full(view, providerKey, provider) { old in
        if let old { g_object_unref(old) }
    }
}
#endif
