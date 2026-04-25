// src/lib/components/windows/Button+Windows.swift
#if os(Windows)
    import Foundation
    import CWindows

    public extension SystemButtonPrimitive {
        @MainActor
        func makeNative() -> NativeView {
            // control_id is 0 because WindowsEventRegistry handles mapping via HWND pointer
            return omni_win_create_button(nil, "", 0, 0, 100, 32, 0)
        }

        @MainActor
        func updateNative(_ view: NativeView) {
            title.withCString { titlePtr in
                omni_win_set_text(view, titlePtr)
            }

            // Map the Win32 WM_COMMAND click to the Swift action closure
            bindWindowsEvent(view, "clicked", action)
        }
    }
#endif
