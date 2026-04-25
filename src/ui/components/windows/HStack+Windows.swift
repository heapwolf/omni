// src/lib/components/windows/HStack+Windows.swift
#if os(Windows)
    import Foundation
    import CWindows

    extension HStack {

        @MainActor
        public func makeNative() -> NativeView {
            return omni_win_create_hstack(nil, self.resolvedSpacing)
        }

        @MainActor
        public func updateNative(_ view: NativeView) {
            omni_win_set_stack_spacing(view, self.resolvedSpacing)
        }

        @MainActor
        public func insertChild(_ child: NativeView, into parent: NativeView) {
            // 1. Add the child to the Win32 window tree
            omni_win_add_child(parent, child)

            // 2. Trigger the C++ OmniHStackWndProc WM_SIZE logic to immediately
            // recalculate the layout now that a new child has been added.
            omni_win_set_stack_spacing(parent, self.resolvedSpacing)
        }
    }
#endif
