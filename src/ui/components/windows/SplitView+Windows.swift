// src/lib/components/windows/SplitView+Windows.swift
#if os(Windows)
    import Foundation
    import CWindows

    extension SplitView {
        @MainActor
        public func makeNative() -> NativeView {
            return omni_win_create_splitview(nil, isVertical)
        }

        @MainActor
        public func updateNative(_ view: NativeView) {
            omni_win_splitview_set_orientation(view, isVertical)
        }

        @MainActor
        public func insertChild(_ child: NativeView, into parent: NativeView) {
            omni_win_add_child(parent, child)

            // Trigger a layout re-calculation when panes are added
            omni_win_splitview_set_orientation(parent, isVertical)
        }
    }
#endif
