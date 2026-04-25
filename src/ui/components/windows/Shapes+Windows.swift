// src/lib/components/windows/Shapes+Windows.swift
#if os(Windows)
    import Foundation
    import CWindows

    extension ClipModifierView {
        @MainActor public func makeNative() -> NativeView {
            return omni_win_create_clip_view(nil)
        }

        @MainActor public func updateNative(_ view: NativeView) {
            omni_win_set_clip_radius(view, radius, isCircular)
        }

        @MainActor public func insertChild(_ child: NativeView, into parent: NativeView) {
            omni_win_add_child(parent, child)
            omni_win_fill_parent(child, parent)
        }
    }
#endif
