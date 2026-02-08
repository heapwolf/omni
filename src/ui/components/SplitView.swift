import Foundation

public struct SplitView: NativeComponent {
    public var isVertical: Bool
    public var children: [any View]
    public var body: any View { self }

    /// `isVertical: true` means the divider is vertical (side-by-side panes).
    @MainActor public init(isVertical: Bool = true, @ViewBuilder _ content: () -> [any View]) {
        self.isVertical = isVertical
        self.children = content()
    }
}
