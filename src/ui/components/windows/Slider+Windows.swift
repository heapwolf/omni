// src/lib/components/windows/Slider+Windows.swift
#if os(Windows)
    import Foundation
    import CWindows

    extension Slider {
        // We use a fixed internal resolution of 10,000 steps for the Win32 Trackbar
        // to accurately represent the Swift Double precision.
        private var resolution: Double { 10000.0 }

        @MainActor
        public func makeNative() -> NativeView {
            let slider = omni_win_create_slider(nil, 0, 0, 150, 30)

            // Lock the Win32 trackbar to a high-resolution 0-10,000 integer range
            omni_win_slider_set_range(slider, 0, Int32(resolution))

            // Map the Win32 HSCROLL event back to the Swift binding
            bindWindowsEvent(slider, "action") { [value, range] in
                let intPos = omni_win_slider_get_value(slider)

                // Map the integer position (0-10000) back to the Double range
                let fraction = Double(intPos) / resolution
                let mappedValue = range.lowerBound + fraction * (range.upperBound - range.lowerBound)

                value.wrappedValue = mappedValue
            }

            return slider
        }

        @MainActor
        public func updateNative(_ view: NativeView) {
            let current = value.wrappedValue

            // Map current Double back to the 0...10000 integer space
            let fraction = (current - range.lowerBound) / (range.upperBound - range.lowerBound)
            let targetPos = Int32(fraction * resolution)

            let viewPos = omni_win_slider_get_value(view)

            // Only send the update if it has changed to prevent infinite loops
            if viewPos != targetPos {
                omni_win_slider_set_value(view, targetPos)
            }
        }
    }
#endif
