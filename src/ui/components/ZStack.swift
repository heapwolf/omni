import Foundation

public struct ZStack: NativeComponent {
    public var alignment: Alignment
    public var isNavigationContainer: Bool
    public var children: [any View]

    public init(
        alignment: Alignment = .center,
        isNavigationContainer: Bool = false,
        @ViewBuilder content: () -> any View
    ) {
        self.alignment = alignment
        self.isNavigationContainer = isNavigationContainer
        self.children = Omni.unpackViews(content())
    }
}

