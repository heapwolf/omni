#if os(Windows)
    import Foundation
    import CWindows

    extension Frame {
        @MainActor public func makeNative() -> NativeView {
            // Treat nil width/height as 0 for initial Win32 creation;
            // The Omni layout engine will calculate intrinsic sizes later.
            let w = width ?? 0
            let h = height ?? 0
            let v = omni_win_create_frame(nil, w, h)
            return v
        }

        @MainActor public func updateNative(_ view: NativeView) {
            // 1. Update Layout
            if let w = width, let h = height {
                omni_win_set_frame(view, w, h)
            }

            // 2. Cursor Styling
            if let cursor = self.cursor {
                cursor.withCString { ptr in
                    omni_win_set_cursor(view, ptr)
                }
            }

            // 3. Event Binding
            // (Assumes you've added "tap", "drag", "scroll" handlers to WindowsEventRegistry)
            if let tap = self.onTap {
                bindWindowsEvent(view, "tap") { tap() }
            }

            if let tapLoc = self.onTapLocation {
                // WindowsEventRegistry would need to unpack lParam for X/Y coordinates
                bindWindowsEvent(view, "tapLocation") { /* decode coords */ tapLoc(0, 0) }
            }

            if let drag = self.onDrag {
                bindWindowsEvent(view, "drag") { /* decode delta */ drag(0, 0) }
            }
        }

        @MainActor public func insertChild(_ child: NativeView, into parent: NativeView) {
            // Equivalent to adding the View, then applying leading/trailing/top/bottom constraints
            omni_win_add_child(parent, child)
            omni_win_fill_parent(child, parent)
        }
    }
#endif
