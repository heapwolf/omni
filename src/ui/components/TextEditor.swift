import Foundation

public struct TextEditor: NativeComponent {
    public var text: Binding<String>
    public var body: any View { self }

    public init(text: Binding<String>) {
        self.text = text
    }
}
