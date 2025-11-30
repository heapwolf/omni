import Foundation

public struct Divider: NativeComponent {
    /// nil means "ask the enclosing stack". SwiftUI's Divider takes no
    /// argument and draws across the stack's axis; HStack and VStack resolve
    /// this when they unpack their children.
    public var isVertical: Bool?

    /// A Divider outside any stack draws horizontally, as SwiftUI's does.
    public var resolvedIsVertical: Bool { isVertical ?? false }

    public init() {
        self.isVertical = nil
    }

    /// Explicit override, for a divider that must not follow its stack.
    public init(isVertical: Bool) {
        self.isVertical = isVertical
    }
}
