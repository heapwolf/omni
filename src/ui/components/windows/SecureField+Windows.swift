// src/lib/components/windows/SecureField+Windows.swift
#if os(Windows)
    import Foundation
    import CWindows

    extension SecureField {
        @MainActor public func makeNative() -> NativeView {
            let binding = text

            let tf = title.withCString { titlePtr in
                omni_win_create_textfield(nil, titlePtr, true) // true = ES_PASSWORD
            }

            bindWindowsEvent(tf, "action") { [binding] in
                // Allocate a buffer to read the UTF-8 text back from Win32
                let bufferSize = 1024
                var buffer = [CChar](repeating: 0, count: bufferSize)
                omni_win_textfield_get_text(tf, &buffer, Int32(bufferSize))

                binding.wrappedValue = String(cString: buffer)
            }

            return tf
        }

        @MainActor public func updateNative(_ view: NativeView) {
            let currentText = text.wrappedValue

            let bufferSize = 1024
            var buffer = [CChar](repeating: 0, count: bufferSize)
            omni_win_textfield_get_text(view, &buffer, Int32(bufferSize))
            let viewText = String(cString: buffer)

            // Prevent infinite state loops by checking if the UI already matches the state
            if currentText != viewText {
                currentText.withCString { strPtr in
                    omni_win_set_text(view, strPtr)
                }
            }
        }
    }
#endif
