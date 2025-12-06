#if os(macOS) || os(iOS)
import Foundation

#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

extension TextField {
    @MainActor public func makeNative() -> NativeView {
        #if os(macOS)
        let tf = NSTextField()
        tf.placeholderString = placeholder
        tf.translatesAutoresizingMaskIntoConstraints = false
        #elseif os(iOS)
        let tf = UITextField()
        tf.placeholder = placeholder
        tf.borderStyle = .roundedRect
        tf.translatesAutoresizingMaskIntoConstraints = false
        #endif

        // Low horizontal hugging, or the field stays at its caret-sized width.
        tf.setContentHuggingPriority(.init(rawValue: 1), for: .horizontal)
        return tf
    }

    @MainActor public func updateNative(_ view: NativeView) {
        let field = self // capture for closures

        let configuration = self.configuration
        let limit = configuration.maxLength

        #if os(macOS)
        if let tf = view as? NSTextField {
            if tf.stringValue != textBinding.wrappedValue {
                tf.stringValue = textBinding.wrappedValue
            }
            // macOS has no keyboard modes; applied only where they mean something.
            let plain = configuration.style.isPlain
            tf.isBezeled = !plain
            tf.drawsBackground = !plain
            tf.focusRingType = plain ? .none : .default
            // The one type AppKit autofills from: a code from Messages or Mail.
            let codeType: NSTextContentType? = configuration.contentType == .oneTimeCode ? .oneTimeCode : nil
            if tf.contentType != codeType { tf.contentType = codeType }
            applyFocus(tf)
        }
        bindAppleEvent(view, "textDidChangeNotification") { [weak view] in
            if let tf = view as? NSTextField { field.commit(tf.stringValue, limit: limit) }
        }

        #elseif os(iOS)
        // Resolved once above, for both branches.
        if let tf = view as? UITextField {
            if tf.text != textBinding.wrappedValue { tf.text = textBinding.wrappedValue }

            tf.keyboardType = Self.uiKeyboardType(configuration.keyboardType)
            tf.autocapitalizationType = Self.uiAutocapitalization(configuration.resolvedAutocapitalization)
            tf.autocorrectionType = configuration.resolvedAutocorrectionDisabled ? .no : .yes
            tf.returnKeyType = Self.uiReturnKey(configuration.submitLabel)
            let contentType = configuration.contentType.map(Self.uiContentType)
            if tf.textContentType != contentType { tf.textContentType = contentType }
            tf.borderStyle = configuration.style.isPlain ? .none : .roundedRect
            if let font = Tracker.current?.environment.font { tf.font = font.uiFont }

            applyFocus(tf)
        }
        let onSubmit = configuration.onSubmit
        bindAppleEvent(view, "editingChanged") { [weak view] in
            guard let tf = view as? UITextField else { return }
            // Truncating here rather than only in the binding keeps the field
            // itself from briefly showing the over-long text.
            let limited = field.limited(tf.text ?? "", to: limit)
            if tf.text != limited { tf.text = limited }
            field.commit(limited, limit: limit)
        }
        // The binding follows the field however focus moves: a tap, the return
        // key, a tap elsewhere ending editing. Left true after the keyboard went
        // away, the next render would bring it straight back.
        if let focusBinding {
            bindAppleEvent(view, "editingDidBegin") {
                if !focusBinding.wrappedValue { focusBinding.wrappedValue = true }
            }
            bindAppleEvent(view, "editingDidEnd") {
                if focusBinding.wrappedValue { focusBinding.wrappedValue = false }
            }
        }
        if onSubmit != nil || focusBinding != nil {
            bindAppleEvent(view, "editingDidEndOnExit") { [weak view] in
                onSubmit?()
                if let tf = view as? UITextField, !tf.isFirstResponder {
                    field.focusBinding?.wrappedValue = false
                }
            }
        }
        #endif
    }

    @MainActor private func applyFocus(_ view: NativeView) {
        guard let focusBinding else { return }
        let wantsFocus = focusBinding.wrappedValue

        #if os(iOS)
        guard let tf = view as? UITextField else { return }
        if wantsFocus, !tf.isFirstResponder {
            tf.becomeFirstResponder()
        } else if !wantsFocus, tf.isFirstResponder {
            tf.resignFirstResponder()
        }
        #elseif os(macOS)
        guard let tf = view as? NSTextField else { return }
        let isFocused = tf.window?.firstResponder === tf.currentEditor()
        if wantsFocus, !isFocused {
            tf.window?.makeFirstResponder(tf)
        } else if !wantsFocus, isFocused {
            tf.window?.makeFirstResponder(nil)
        }
        #endif
    }

    #if os(iOS)
    /// SwiftUI's mapping, one to one.
    static func uiContentType(_ type: TextContentType) -> UITextContentType {
        switch type {
        case .emailAddress: return .emailAddress
        case .oneTimeCode: return .oneTimeCode
        case .telephoneNumber: return .telephoneNumber
        case .name: return .name
        case .givenName: return .givenName
        case .familyName: return .familyName
        case .fullStreetAddress: return .fullStreetAddress
        case .addressCity: return .addressCity
        case .addressState: return .addressState
        case .postalCode: return .postalCode
        case .username: return .username
        }
    }

    /// Internal: SecureField maps the same configuration.
    static func uiKeyboardType(_ type: KeyboardType) -> UIKeyboardType {
        switch type {
        case .default: return .default
        case .emailAddress: return .emailAddress
        case .numberPad: return .numberPad
        case .phonePad: return .phonePad
        case .URL: return .URL
        case .decimalPad: return .decimalPad
        }
    }

    private static func uiAutocapitalization(_ mode: TextInputAutocapitalization) -> UITextAutocapitalizationType {
        switch mode {
        case .never: return .none
        case .sentences: return .sentences
        case .words: return .words
        case .characters: return .allCharacters
        }
    }

    private static func uiReturnKey(_ label: SubmitLabel) -> UIReturnKeyType {
        switch label {
        case .done: return .done
        case .next: return .next
        case .go: return .go
        case .search: return .search
        case .send: return .send
        }
    }
    #endif
}
#endif
