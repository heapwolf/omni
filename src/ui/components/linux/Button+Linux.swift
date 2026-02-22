// src/lib/components/linux/Button+Linux.swift
#if os(Linux)
    import Foundation

    // MARK: - GTK Bindings

    let gtk_button_new_with_label: @convention(c) (UnsafePointer<CChar>) -> NativeView = fn(libgtk, "gtk_button_new_with_label")

    // MARK: - Linux Implementation

    public extension SystemButtonPrimitive {
        @MainActor
        func makeNative() -> NativeView {
            return gtk_button_new_with_label("")
        }

        @MainActor
        func updateNative(_ view: NativeView) {
            gtk_button_set_label(view, title)
            bindLinuxEvent(view, "clicked", action)
        }
    }
#endif
