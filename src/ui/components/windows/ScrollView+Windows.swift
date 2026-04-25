// src/lib/components/windows/ScrollView+Windows.swift
#if os(Windows)
    import Foundation
    import CWindows

    extension ScrollView {
        @MainActor
        public func makeNative() -> NativeView {
            let isVert = self.axis == .vertical
            return omni_win_create_scrollview(nil, isVert)
        }

        @MainActor
        public func updateNative(_ view: NativeView) {
            // Rebound every render, so the closure always holds the current
            // binding; the same shape the Apple backend uses.
            let currentOffset = self.offset
            bindWindowsEvent(view, "scroll") {
                currentOffset?.wrappedValue = omni_win_scrollview_get_offset(view)
            }

            // Apply programmatic scrolling if the user modifies the bound state directly
            if let targetOffset = currentOffset?.wrappedValue {
                let current = omni_win_scrollview_get_offset(view)
                if abs(targetOffset - current) > 1.0 {
                    omni_win_scrollview_set_offset(view, targetOffset)
                }
            }
        }

        @MainActor
        public func insertChild(_ child: NativeView, into parent: NativeView) {
            omni_win_add_child(parent, child)

            // In a full layout engine pass, you'd calculate the child's true height.
            // For now, we apply a placeholder large content size so the scrollbar is active.
            let isVert = self.axis == .vertical
            omni_win_scrollview_update_content_size(parent, isVert ? 0 : 2000, isVert ? 2000 : 0)
        }
    }
#endif
