// src/lib/components/windows/TabView+Windows.swift
#if os(Windows)
    import Foundation
    import CWindows

    extension NativeSwipeModifierView {
        @MainActor
        public func makeNative() -> NativeView {
            let sv = omni_win_create_swipe_view(nil)

            bindWindowsEvent(sv, "action") { [onSwipeLeft, onSwipeRight] in
                // We use wParam sent from OmniSwipeWndProc: 1 = Left, 2 = Right
                // (Routed via WindowsEventRegistry)
                onSwipeLeft()
            }

            bindWindowsEvent(sv, "swipeLeft") { [onSwipeLeft] in
                onSwipeLeft()
            }

            bindWindowsEvent(sv, "swipeRight") { [onSwipeRight] in
                onSwipeRight()
            }

            return sv
        }

        @MainActor
        public func updateNative(_ view: NativeView) {
            let leftAction = onSwipeLeft
            let rightAction = onSwipeRight

            bindWindowsEvent(view, "swipeLeft") { leftAction() }
            bindWindowsEvent(view, "swipeRight") { rightAction() }
        }

        @MainActor
        public func insertChild(_ child: NativeView, into parent: NativeView) {
            omni_win_add_child(parent, child)
            omni_win_fill_parent(child, parent)
        }
    }
#endif
