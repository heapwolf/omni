// src/lib/components/windows/ProgressView+Windows.swift
#if os(Windows)
    import Foundation
    import CWindows

    extension ProgressView {
        @MainActor
        public func makeNative() -> NativeView {
            // Instantiate with default Windows progress bar dimensions.
            // Your stack/frame layout engine will handle exact placement later.
            return omni_win_create_progress(nil, 0, 0, 100, 15)
        }

        @MainActor
        public func updateNative(_ view: NativeView) {
            // Indeterminate progress bars do not need state updates
        }
    }
#endif
