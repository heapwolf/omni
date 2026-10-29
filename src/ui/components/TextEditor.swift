import Foundation

public struct TextEditor: NativeComponent {
    public var text: Binding<String>
    public var body: any View { self }
    var style: TextEditorStyle = .automatic
    var focusBinding: Binding<Bool>?

    public init(text: Binding<String>) {
        self.text = text
    }

    /// SwiftUI's: `.plain` draws no border or background of its own, and no
    /// inset, for an app that draws the box around it. iOS; macOS's draws
    /// neither already.
    public func textEditorStyle(_ style: TextEditorStyle) -> TextEditor {
        var copy = self
        copy.style = style
        return copy
    }

    /// Whether it's being typed into: set as focus comes and goes, and
    /// focusing it when set true. iOS.
    public func focused(_ binding: Binding<Bool>) -> TextEditor {
        var copy = self
        copy.focusBinding = binding
        return copy
    }
}

public enum TextEditorStyle: Sendable, Equatable {
    case automatic
    case plain
}
