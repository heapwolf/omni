// src/lib/components/windows/Picker+Windows.swift
#if os(Windows)
    import Foundation
    import CWindows

    extension NativePicker {
        @MainActor
        public func makeNative() -> NativeView {
            // Create the ComboBox (height is 200 to allow room for the dropdown list)
            let picker = omni_win_create_picker(nil, 0, 0, 150, 200, 0)

            // Populate the dropdown options
            for option in options {
                option.label.withCString { labelPtr in
                    omni_win_picker_add_item(picker, labelPtr)
                }
            }

            // Bind the selection change event to the WM_COMMAND router
            bindWindowsEvent(picker, "action") { [selection, options] in
                let idx = Int(omni_win_picker_get_selection(picker))
                if idx >= 0 && idx < options.count {
                    // Update the Swift @State Binding
                    selection.wrappedValue = options[idx].tag
                }
            }

            return picker
        }

        @MainActor
        public func updateNative(_ view: NativeView) {
            let currentSelection = selection.wrappedValue
            let selectedIndex = options.firstIndex(where: { $0.tag == currentSelection }) ?? 0

            let currentIndexInWin32 = Int(omni_win_picker_get_selection(view))

            // Only send the update message if the UI doesn't already reflect the state,
            // preventing infinite state update loops.
            if currentIndexInWin32 != selectedIndex {
                omni_win_picker_set_selection(view, Int32(selectedIndex))
            }
        }
    }
#endif
