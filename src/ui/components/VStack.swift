import Foundation

public struct VStack: NativeComponent {
    public var spacing: Double?
    public var alignment: HorizontalAlignment

    public var content: any View
    public var children: [any View] {
        Omni.unpackViews(content).map { child in
            if let divider = child as? Divider, divider.isVertical == nil {
                return Divider(isVertical: false)
            }
            return child
        }
    }
    /// SwiftUI leaves spacing to the system when unset; 8 is what the
    /// platforms here have always used.
    var resolvedSpacing: Double { spacing ?? 8 }

    public var body: any View { self }

    public init(alignment: HorizontalAlignment = .center, spacing: Double? = nil, @ViewBuilder _ content: @escaping () -> any View) {
        self.alignment = alignment
        self.spacing = spacing
        self.content = content()
    }
}
