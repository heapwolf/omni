// src/lib/components/linux/PressGesture+Linux.swift
#if os(Linux)
    import Foundation

    // A relief-less GtkButton, as TapGestureView is: GTK tracks the press, and
    // says so with "pressed" and "released" around "clicked".
    public extension PressGestureView {
        @MainActor
        func makeNative() -> NativeView {
            let view = gtk_button_new()
            gtk_button_set_relief(view, 1)
            return view
        }

        @MainActor
        func updateNative(_ view: NativeView) {
            let change = onPressChange
            bindLinuxEvent(view, "pressed") { change(true) }
            bindLinuxEvent(view, "released") { change(false) }
            bindLinuxEvent(view, "clicked", action)
        }

        @MainActor
        func insertChild(_ child: NativeView, into parent: NativeView) {
            // GtkButton is a GtkBin: one child, filling the whole button.
            gtk_container_add(parent, child)
            carryExpand(from: child, to: parent)
        }
    }
#endif
