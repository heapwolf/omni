// src/lib/components/windows/GeometryReader+Windows.swift
#if os(Windows)
    import Foundation
    import CWindows

    extension GeometryReader {
        @MainActor public func makeNative() -> NativeView {
            return omni_win_create_geometry_reader(nil)
        }

        @MainActor public func updateNative(_ view: NativeView) {
            let resizeAction = self.onResize

            // Bind a "resize" event string to this specific HWND
            bindWindowsEvent(view, "resize") {
                var w: Double = 0
                var h: Double = 0

                // Query the new bounds natively
                omni_win_get_bounds(view, &w, &h)

                let newSize = GeometryProxy(width: w, height: h)
                resizeAction(newSize)
            }
        }

        @MainActor public func insertChild(_ child: NativeView, into parent: NativeView) {
            // Add the child and force it to fill this GeometryReader container,
            // mirroring the Auto Layout logic from the Apple implementation.
            omni_win_add_child(parent, child)
            omni_win_fill_parent(child, parent)
        }
    }
#endif
