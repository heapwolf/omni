// src/lib/components/windows/Image+Windows.swift
#if os(Windows)
    import Foundation
    import CWindows

    extension Image {
        @MainActor
        public func makeNative() -> NativeView {
            return name.withCString { namePtr in
                omni_win_create_image(nil, namePtr, isSystem)
            }
        }

        @MainActor
        public func updateNative(_ view: NativeView) {
            // In the basic implementation, static images don't update after creation.
        }
    }
#endif
