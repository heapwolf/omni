#if os(Linux)
import Foundation
import Glibc

extension TextField {
    @MainActor public func makeNative() -> NativeView {
        let view = gtk_entry_new()
        gtk_widget_set_hexpand(view, 1)
        return view
    }

    @MainActor public func updateNative(_ view: NativeView) {
        let field = self
        // Resolved from the environment, as Button resolves its style.
        let configuration = self.configuration
        let limit = configuration.maxLength
        let onSubmit = configuration.onSubmit
        let current = String(cString: gtk_entry_get_text(view))

        if current != textBinding.wrappedValue {
            gtk_entry_set_text(view, textBinding.wrappedValue)
        }

        gtk_entry_set_input_purpose(view, Self.gtkInputPurpose(configuration.keyboardType))

        // GTK enforces this natively, so a paste cannot exceed it either.
        gtk_entry_set_max_length(view, Int32(limit ?? 0))

        applyFocus(view)

        bindLinuxEvent(view, "changed") {
            field.commit(String(cString: gtk_entry_get_text(view)), limit: limit)
        }

        if onSubmit != nil {
            bindLinuxEvent(view, "activate") { onSubmit?() }
        }
    }

    @MainActor private func applyFocus(_ view: NativeView) {
        guard let focusBinding, focusBinding.wrappedValue else { return }
        if gtk_widget_has_focus(view) == 0 {
            gtk_widget_grab_focus(view)
        }
    }

    /// GtkInputPurpose values. Declared numerically rather than pulled from a
    /// header so this stays readable next to the enum it maps.
    private static func gtkInputPurpose(_ type: KeyboardType) -> Int32 {
        switch type {
        case .default: return 0       // GTK_INPUT_PURPOSE_FREE_FORM
        case .emailAddress: return 5  // GTK_INPUT_PURPOSE_EMAIL
        case .numberPad: return 2     // GTK_INPUT_PURPOSE_DIGITS
        case .decimalPad: return 3    // GTK_INPUT_PURPOSE_NUMBER
        case .phonePad: return 4      // GTK_INPUT_PURPOSE_PHONE
        case .URL: return 6           // GTK_INPUT_PURPOSE_URL
        }
    }
}
#endif
