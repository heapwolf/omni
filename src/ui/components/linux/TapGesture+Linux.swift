// src/lib/components/linux/TapGesture+Linux.swift
#if os(Linux)
    import Foundation

    let gtk_button_new: @convention(c) () -> NativeView = fn(libgtk, "gtk_button_new")
    // GtkReliefStyle: 0 = NORMAL, 1 = NONE (GTK_RELIEF_HALF was removed in GTK3).
    let gtk_button_set_relief: @convention(c) (NativeView, Int32) -> Void = fn(libgtk, "gtk_button_set_relief")

    public extension TapGestureView {
        @MainActor
        func makeNative() -> NativeView {
            let view = gtk_button_new()
            gtk_button_set_relief(view, 1)
            return view
        }

        @MainActor
        func updateNative(_ view: NativeView) {
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
