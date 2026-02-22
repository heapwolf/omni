#if os(Linux)
import Foundation
import Glibc

nonisolated(unsafe) let gtk_viewport_new: @convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?) -> NativeView = fn(libgtk, "gtk_viewport_new")
nonisolated(unsafe) let gtk_scrolled_window_set_policy: @convention(c) (NativeView, Int32, Int32) -> Void = fn(libgtk, "gtk_scrolled_window_set_policy")
enum GtkPolicy {
    static let automatic: Int32 = 1
    static let never: Int32 = 2
}

nonisolated(unsafe) let gtk_scrolled_window_get_vadjustment: @convention(c) (NativeView) -> UnsafeMutableRawPointer = fn(libgtk, "gtk_scrolled_window_get_vadjustment")
nonisolated(unsafe) let gtk_adjustment_get_value: @convention(c) (UnsafeMutableRawPointer) -> Double = fn(libgtk, "gtk_adjustment_get_value")
nonisolated(unsafe) let gtk_adjustment_set_value: @convention(c) (UnsafeMutableRawPointer, Double) -> Void = fn(libgtk, "gtk_adjustment_set_value")

class ScrollProxy {
    var onScroll: ((Double) -> Void)?
    var lastValue: Double = 0
}

extension ScrollView {
    @MainActor public func makeNative() -> NativeView {
        let sv = gtk_scrolled_window_new(nil, nil)

        // Fills the space it is given; GtkBox reads these when distributing surplus.
        gtk_widget_set_hexpand(sv, 1)
        gtk_widget_set_vexpand(sv, 1)

        // Only the scrolling axis may overflow: on AUTOMATIC the other axis reports
        // no natural size and the content collapses.
        let vertical = axis == .vertical
        gtk_scrolled_window_set_policy(sv,
                                       vertical ? GtkPolicy.never : GtkPolicy.automatic,
                                       vertical ? GtkPolicy.automatic : GtkPolicy.never)
        // Own the viewport: the implicit one outlives its child ("already has a child").
        gtk_container_add(sv, gtk_viewport_new(nil, nil))

        let proxy = ScrollProxy()
        let ptr = Unmanaged.passRetained(proxy).toOpaque()
        g_object_set_data_full(sv, "proxy_scroll", ptr) { pPtr in if let p = pPtr { Unmanaged<ScrollProxy>.fromOpaque(p).release() } }

        let vadj = gtk_scrolled_window_get_vadjustment(sv)
        let cb: @convention(c) (UnsafeMutableRawPointer, UnsafeMutableRawPointer) -> Void = { adj, pPtr in
            let storedProxy = Unmanaged<ScrollProxy>.fromOpaque(pPtr).takeUnretainedValue()
            storedProxy.lastValue = gtk_adjustment_get_value(adj)

            // Must use GTK's loop: gtk_main() never drains the libdispatch main queue.
            let hop = Unmanaged.passRetained(storedProxy).toOpaque()
            g_idle_add({ pointer in
                guard let pointer else { return 0 }
                let proxy = Unmanaged<ScrollProxy>.fromOpaque(pointer).takeRetainedValue()
                MainActor.assumeIsolated { proxy.onScroll?(proxy.lastValue) }
                return 0 // G_SOURCE_REMOVE — a one-shot
            }, hop)
        }
        g_signal_connect_data(vadj, "value-changed", unsafeBitCast(cb, to: UnsafeMutableRawPointer.self), ptr, nil, 0)
        return sv
    }

    @MainActor public func updateNative(_ view: NativeView) {
        let currentOffset = offset
        if let ptr = g_object_get_data(view, "proxy_scroll") {
            Unmanaged<ScrollProxy>.fromOpaque(ptr).takeUnretainedValue().onScroll = { val in
                currentOffset?.wrappedValue = val
            }
        }

        if let target = currentOffset?.wrappedValue {
            let adjustment = gtk_scrolled_window_get_vadjustment(view)
            if abs(gtk_adjustment_get_value(adjustment) - target) > 0.5 {
                gtk_adjustment_set_value(adjustment, target)
            }
        }
    }

    @MainActor public func insertChild(_ child: NativeView, into parent: NativeView) {
        gtk_container_add(gtk_bin_get_child(parent) ?? parent, child)
        carryExpand(from: child, to: parent)

        if axis == .vertical {
            gtk_widget_set_valign(child, GtkAlign.start)
        } else {
            gtk_widget_set_halign(child, GtkAlign.start)
        }
    }
}
#endif
