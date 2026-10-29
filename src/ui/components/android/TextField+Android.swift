#if os(Android)
import Foundation
import CAndroid

@MainActor private var textFieldHandlerRegistry: [UnsafeMutableRawPointer: EventHandlerString] = [:]

extension TextField {
    @MainActor public func makeNative() -> NativeView {
        let env = OmniAndroid.env
        let view = OmniAndroid.createView(env, "android/widget/EditText")
        OmniAndroid.makePlainField(view)
        AndroidExpansion.claim(view, horizontal: true, vertical: false)
        return view
    }

    @MainActor public func unmountNative(_ view: NativeView) {
        omni_jni_detach_text_field(OmniAndroid.env, view)
        textFieldHandlerRegistry.removeValue(forKey: view)
    }

    @MainActor public func updateNative(_ view: NativeView) {
        let env = OmniAndroid.env
        let field = self
        // Resolved from the environment, as Button resolves its style.
        let configuration = self.configuration
        let limit = configuration.maxLength

        // commit applies maxLength, so the limit needs no InputFilter and
        // behaves identically to the other three backends.
        syncTextField(view, to: textBinding.wrappedValue, handlers: &textFieldHandlerRegistry) { newText in
            Task { @MainActor in field.commit(newText, limit: limit) }
        }

        omni_jni_call_void_method_int(env, view, "setInputType", Self.inputType(
            keyboard: configuration.keyboardType,
            autocapitalization: configuration.resolvedAutocapitalization,
            autocorrectionDisabled: configuration.resolvedAutocorrectionDisabled))
        omni_jni_call_void_method_int(env, view, "setImeOptions", Self.imeOptions(configuration.submitLabel))
        omni_jni_set_autofill_hint(env, view, configuration.contentType.map(Self.autofillHint) ?? "")
    }

    /// androidx.autofill's HintConstants, by value: android.view.View's
    /// AUTOFILL_HINT_* where it has one.
    private static func autofillHint(_ type: TextContentType) -> String {
        switch type {
        case .emailAddress: return "emailAddress"
        case .oneTimeCode: return "smsOTPCode"
        case .telephoneNumber: return "phone"
        case .name: return "personName"
        case .givenName: return "personGivenName"
        case .familyName: return "personFamilyName"
        case .fullStreetAddress: return "postalAddress"
        case .addressCity: return "addressLocality"
        case .addressState: return "addressRegion"
        case .postalCode: return "postalCode"
        case .username: return "username"
        }
    }

    // android.text.InputType constants.
    private enum Input {
        static let typeClassText: Int32              = 0x00000001
        static let typeTextVariationEmail: Int32     = 0x00000020
        static let typeTextVariationURI: Int32       = 0x00000010
        static let typeTextFlagCapSentences: Int32   = 0x00004000
        static let typeTextFlagCapWords: Int32       = 0x00002000
        static let typeTextFlagCapCharacters: Int32  = 0x00001000
        static let typeTextFlagNoSuggestions: Int32  = 0x00080000
        static let typeClassNumber: Int32            = 0x00000002
        static let typeNumberFlagDecimal: Int32      = 0x00002000
        static let typeClassPhone: Int32             = 0x00000003
    }

    private static func inputType(keyboard: KeyboardType,
                                  autocapitalization: TextInputAutocapitalization,
                                  autocorrectionDisabled: Bool) -> Int32 {
        switch keyboard {
        case .numberPad: return Input.typeClassNumber
        case .decimalPad: return Input.typeClassNumber | Input.typeNumberFlagDecimal
        case .phonePad: return Input.typeClassPhone
        case .emailAddress:
            return Input.typeClassText | Input.typeTextVariationEmail | Input.typeTextFlagNoSuggestions
        case .URL:
            return Input.typeClassText | Input.typeTextVariationURI | Input.typeTextFlagNoSuggestions
        case .default:
            var type = Input.typeClassText
            switch autocapitalization {
            case .never: break
            case .sentences: type |= Input.typeTextFlagCapSentences
            case .words: type |= Input.typeTextFlagCapWords
            case .characters: type |= Input.typeTextFlagCapCharacters
            }
            if autocorrectionDisabled { type |= Input.typeTextFlagNoSuggestions }
            return type
        }
    }

    // android.view.inputmethod.EditorInfo constants.
    private static func imeOptions(_ label: SubmitLabel) -> Int32 {
        switch label {
        case .done: return 6    // IME_ACTION_DONE
        case .next: return 5    // IME_ACTION_NEXT
        case .go: return 2      // IME_ACTION_GO
        case .search: return 3  // IME_ACTION_SEARCH
        case .send: return 4    // IME_ACTION_SEND
        }
    }
}
#endif
