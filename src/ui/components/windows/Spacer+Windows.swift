// src/lib/components/windows/Spacer+Windows.swift
#if os(Windows)
    import Foundation
    import CWindows

    extension Spacer {
        @MainActor
        public func makeNative() -> NativeView {
            // Treat nil as 0 so the stack layout can dynamically expand it
            return omni_win_create_spacer(nil, minLength ?? 0)
        }

        @MainActor
        public func updateNative(_ view: NativeView) {
            if let min = minLength {
                omni_win_spacer_set_min_length(view, min)
            }
        }
    }
#endif
