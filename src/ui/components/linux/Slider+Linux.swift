#if os(Linux)
import Foundation
import Glibc

nonisolated(unsafe) let gtk_scale_new_with_range: @convention(c) (Int32, Double, Double, Double) -> NativeView = fn(libgtk, "gtk_scale_new_with_range")
nonisolated(unsafe) let gtk_range_set_value: @convention(c) (NativeView, Double) -> Void = fn(libgtk, "gtk_range_set_value")
nonisolated(unsafe) let gtk_range_get_value: @convention(c) (NativeView) -> Double = fn(libgtk, "gtk_range_get_value")

extension Slider {
    @MainActor public func makeNative() -> NativeView {
        // 0 = GTK_ORIENTATION_HORIZONTAL, with step of 1% of range
        let step = (range.upperBound - range.lowerBound) / 100.0
        let scale = gtk_scale_new_with_range(0, range.lowerBound, range.upperBound, step)

        bindLinuxEvent(scale, "value-changed") { [value] in
            value.wrappedValue = gtk_range_get_value(scale)
        }
        gtk_widget_set_hexpand(scale, 1)
        return scale
    }

    @MainActor public func updateNative(_ view: NativeView) {
        let current = value.wrappedValue
        if gtk_range_get_value(view) != current {
            gtk_range_set_value(view, current)
        }
    }
}
#endif
