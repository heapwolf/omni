import Foundation


/// The subset of UIKeyboardType that means something on every backend.
public enum KeyboardType: Sendable {
    case `default`
    case emailAddress
    /// Digits only. The OTP and PIN case.
    case numberPad
    /// Digits plus the separators a phone number uses.
    case phonePad
    case URL
    /// Digits and a decimal separator. Amount entry.
    case decimalPad
}

/// Matches SwiftUI's TextInputAutocapitalization.
public enum TextInputAutocapitalization: Sendable, Equatable {
    case never, sentences, words, characters
}

/// SwiftUI's `.textFieldStyle(.plain)` and friends. `.plain` draws no border
/// or background, for a field that sits inside its own styled container.
public struct TextFieldStyle: Sendable, Equatable {
    enum Kind: Sendable, Equatable { case automatic, plain, roundedBorder }
    let kind: Kind

    public static let automatic = TextFieldStyle(kind: .automatic)
    public static let plain = TextFieldStyle(kind: .plain)
    public static let roundedBorder = TextFieldStyle(kind: .roundedBorder)

    /// automatic is the rounded border every backend has always drawn.
    public var isPlain: Bool { kind == .plain }
}

/// What a field holds, for the system's autofill: the code just texted or
/// emailed, the person's own email or number. SwiftUI's textContentType, the
/// subset every backend can say.
public enum TextContentType: Sendable, Equatable {
    case emailAddress, oneTimeCode, telephoneNumber
    case name, givenName, familyName
    case fullStreetAddress, addressCity, addressState, postalCode
    case username
}

/// What the return key says and does.
public enum SubmitLabel: Sendable {
    case done, go, next, search, send
}

public struct TextFieldConfiguration {
    public var keyboardType: KeyboardType = .default
    public var autocapitalization: TextInputAutocapitalization = .sentences
    public var isAutocorrectionDisabled = false
    public var submitLabel: SubmitLabel = .done
    /// Applies to TextField and SecureField alike, as in SwiftUI.
    public var style: TextFieldStyle = .automatic
    /// Not a SwiftUI concept, but every real form wants one, and here it is
    /// enforced once rather than per backend.
    public var maxLength: Int?
    /// nil: the platform guesses, or offers nothing.
    public var contentType: TextContentType?
    public var onSubmit: (() -> Void)?

    public init() {}

    /// An email, URL or numeric keyboard implies neither capitalisation nor
    /// suggestions, so it settles both.
    public var resolvedAutocapitalization: TextInputAutocapitalization {
        switch keyboardType {
        case .default: return autocapitalization
        case .emailAddress, .URL, .numberPad, .phonePad, .decimalPad: return .never
        }
    }

    public var resolvedAutocorrectionDisabled: Bool {
        switch keyboardType {
        case .default: return isAutocorrectionDisabled
        case .emailAddress, .URL, .numberPad, .phonePad, .decimalPad: return true
        }
    }
}

public struct TextFieldConfigurationKey: EnvironmentKey {
    /// Computed, not stored: the configuration carries a closure so it is not
    /// Sendable, and a stored static would have to be.
    public static var defaultValue: TextFieldConfiguration { TextFieldConfiguration() }
}

public extension EnvironmentValues {
    var textFieldConfiguration: TextFieldConfiguration {
        get { self[TextFieldConfigurationKey.self] }
        set { self[TextFieldConfigurationKey.self] = newValue }
    }
}

// SwiftUI's names exactly. autocorrectionDisabled(_:) rather than an
// autocorrection(_:) whose polarity is inverted.

public extension View {
    func keyboardType(_ type: KeyboardType) -> some View {
        transformTextFieldConfiguration { $0.keyboardType = type }
    }

    func textInputAutocapitalization(_ mode: TextInputAutocapitalization) -> some View {
        transformTextFieldConfiguration { $0.autocapitalization = mode }
    }

    func autocorrectionDisabled(_ disabled: Bool = true) -> some View {
        transformTextFieldConfiguration { $0.isAutocorrectionDisabled = disabled }
    }

    func textFieldStyle(_ style: TextFieldStyle) -> some View {
        transformTextFieldConfiguration { $0.style = style }
    }

    func textContentType(_ type: TextContentType?) -> some View {
        transformTextFieldConfiguration { $0.contentType = type }
    }

    func submitLabel(_ label: SubmitLabel) -> some View {
        transformTextFieldConfiguration { $0.submitLabel = label }
    }

    /// Omni's own: SwiftUI has no length limit.
    func textFieldMaxLength(_ limit: Int?) -> some View {
        transformTextFieldConfiguration { $0.maxLength = limit }
    }

    func onSubmit(_ action: @escaping () -> Void) -> some View {
        transformTextFieldConfiguration { $0.onSubmit = action }
    }

    private func transformTextFieldConfiguration(
        _ transform: @escaping (inout TextFieldConfiguration) -> Void
    ) -> some View {
        EnvironmentModifierView(
            modifier: { environment in transform(&environment.textFieldConfiguration) },
            content: self)
    }
}

// MARK: - TextField

public struct TextField: NativeComponent {
    public var textBinding: Binding<String>
    public var placeholder: String

    /// Focus is a property of the field, not an environment value: it is about one
    /// field, and an inherited value would move with the tree.
    public var focusBinding: Binding<Bool>?

    public var body: any View { self }

    public init(_ textBinding: Binding<String>, placeholder: String = "") {
        self.textBinding = textBinding
        self.placeholder = placeholder
    }

    /// SwiftUI's spelling: the title doubles as the placeholder.
    public init(_ title: String, text: Binding<String>) {
        self.textBinding = text
        self.placeholder = title
    }

    public func focused(_ binding: Binding<Bool>) -> TextField {
        var copy = self; copy.focusBinding = binding; return copy
    }

    /// One field per focus state, so a caller with several does not need an enum.
    public func focused<Value: Equatable>(_ binding: Binding<Value>, equals value: Value) -> TextField {
        focused(Binding(
            get: { binding.wrappedValue == value },
            set: { isFocused in if isFocused { binding.wrappedValue = value } }))
    }

    // MARK: Shared behaviour
    //
    // Anything a backend would otherwise implement four times lives here.

    /// The configuration in effect for this field, resolved from the node's
    /// environment the same way Button resolves its style.
    @MainActor public var configuration: TextFieldConfiguration {
        Tracker.current?.environment.textFieldConfiguration ?? TextFieldConfiguration()
    }

    /// Truncates to `limit`. A field without one is unchanged, so this is safe
    /// to route every write through.
    public func limited(_ text: String, to limit: Int?) -> String {
        guard let limit, limit >= 0, text.count > limit else { return text }
        return String(text.prefix(limit))
    }

    @MainActor public func commit(_ raw: String, limit: Int?) {
        let text = limited(raw, to: limit)
        if textBinding.wrappedValue != text {
            textBinding.wrappedValue = text
        }
    }
}
