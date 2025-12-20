import Foundation

public struct Toggle: NativeComponent {
    public var title: String
    public var isOnBinding: Binding<Bool>

    public var body: any View { self }

    public init(_ title: String, isOn: Binding<Bool>) {
        self.title = title
        self.isOnBinding = isOn
    }
}
