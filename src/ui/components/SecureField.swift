import Foundation

public struct SecureField: NativeComponent {
    public var title: String
    public var text: Binding<String>
    /// As TextField's: a property of the field, not the environment.
    public var focusBinding: Binding<Bool>?
    public var body: any View { self }

    public init(_ title: String, text: Binding<String>) {
        self.title = title
        self.text = text
    }

    /// SwiftUI's .focused, on a SecureField as on a TextField.
    public func focused(_ binding: Binding<Bool>) -> SecureField {
        var copy = self; copy.focusBinding = binding; return copy
    }

    public func focused<Value: Equatable>(_ binding: Binding<Value>, equals value: Value) -> SecureField {
        focused(Binding(
            get: { binding.wrappedValue == value },
            set: { isFocused in if isFocused { binding.wrappedValue = value } }))
    }

    /// Shares TextField's configuration: .textFieldStyle applies to both.
    @MainActor public var configuration: TextFieldConfiguration {
        Tracker.current?.environment.textFieldConfiguration ?? TextFieldConfiguration()
    }
}
