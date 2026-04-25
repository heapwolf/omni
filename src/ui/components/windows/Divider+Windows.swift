// src/lib/components/windows/Divider+Windows.swift
#if os(Windows)
    import Foundation
    import CWindows

    public extension Divider {

        @MainActor
        func makeNative() -> NativeView {
            // Provide a default thickness of 2 pixels.
            // The length (100) is a placeholder; the engine will resize it during layout passes.
            let w = resolvedIsVertical ? 2 : 100
            let h = resolvedIsVertical ? 100 : 2

            return omni_win_create_divider(nil, 0, 0, Int32(w), Int32(h), resolvedIsVertical)
        }

        @MainActor
        func updateNative(_ view: NativeView) {
            // Dividers are visually static. Layout and resizing are
            // handled automatically by the engine via Frame/Stack modifiers.
        }
    }
#endif
