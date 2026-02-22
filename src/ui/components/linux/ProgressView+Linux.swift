#if os(Linux)
import Foundation
import Glibc

nonisolated(unsafe) let gtk_spinner_new: @convention(c) () -> NativeView = fn(libgtk, "gtk_spinner_new")
nonisolated(unsafe) let gtk_spinner_start: @convention(c) (NativeView) -> Void = fn(libgtk, "gtk_spinner_start")
nonisolated(unsafe) let gtk_progress_bar_new: @convention(c) () -> NativeView =
    fn(libgtk, "gtk_progress_bar_new")
nonisolated(unsafe) let gtk_progress_bar_set_fraction: @convention(c) (NativeView, Double) -> Void =
    fn(libgtk, "gtk_progress_bar_set_fraction")

extension ProgressView {
    @MainActor public func makeNative() -> NativeView {
        guard fraction != nil else {
            let spinner = gtk_spinner_new()
            gtk_spinner_start(spinner)
            return spinner
        }
        return gtk_progress_bar_new()
    }

    @MainActor public func updateNative(_ view: NativeView) {
        guard let fraction else { return }
        gtk_progress_bar_set_fraction(view, fraction)
    }
}
#endif
