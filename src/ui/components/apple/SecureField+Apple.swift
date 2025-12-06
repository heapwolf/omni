#if os(macOS) || os(iOS)
import Foundation

#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

extension SecureField {
    @MainActor public func makeNative() -> NativeView {
        let binding = text // Capture struct locally for the closure

        #if os(macOS)
            let tf = NSSecureTextField()
            tf.placeholderString = title
            tf.translatesAutoresizingMaskIntoConstraints = false
            tf.setContentHuggingPriority(.init(rawValue: 1), for: .horizontal)

            // Use Apple event binding extension
            bindAppleEvent(tf, "controlTextDidChange:") { [weak tf] in
                if let tf = tf { binding.wrappedValue = tf.stringValue }
            }
            return tf

        #elseif os(iOS)
            let tf = UITextField()
            tf.placeholder = title
            tf.isSecureTextEntry = true
            tf.borderStyle = .roundedRect
            tf.translatesAutoresizingMaskIntoConstraints = false
            // See TextField+Apple.swift's makeNative for why this is needed.
            tf.setContentHuggingPriority(.init(rawValue: 1), for: .horizontal)

            bindAppleEvent(tf, "editingChanged") { [weak tf] in
                if let tf = tf { binding.wrappedValue = tf.text ?? "" }
            }
            return tf
        #endif
    }

    @MainActor public func updateNative(_ view: NativeView) {
        let currentText = text.wrappedValue

        #if os(macOS)
            if let tf = view as? NSSecureTextField {
                if tf.stringValue != currentText { tf.stringValue = currentText }
                let plain = configuration.style.isPlain
                tf.isBezeled = !plain
                tf.drawsBackground = !plain
                tf.focusRingType = plain ? .none : .default
            }
        #elseif os(iOS)
            if let tf = view as? UITextField {
                if tf.text != currentText { tf.text = currentText }
                tf.borderStyle = configuration.style.isPlain ? .none : .roundedRect
                if let font = Tracker.current?.environment.font { tf.font = font.uiFont }
                // A PIN wants the number pad as much as an OTP field does.
                tf.keyboardType = TextField.uiKeyboardType(configuration.keyboardType)

                if let focusBinding {
                    if focusBinding.wrappedValue, !tf.isFirstResponder { tf.becomeFirstResponder() }
                    else if !focusBinding.wrappedValue, tf.isFirstResponder { tf.resignFirstResponder() }
                    bindAppleEvent(tf, "editingDidBegin") {
                        if !focusBinding.wrappedValue { focusBinding.wrappedValue = true }
                    }
                    bindAppleEvent(tf, "editingDidEnd") {
                        if focusBinding.wrappedValue { focusBinding.wrappedValue = false }
                    }
                }
            }
        #endif
    }
}
#endif
