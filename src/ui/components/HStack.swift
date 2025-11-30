import Foundation

public struct HStack: NativeComponent {
    public var spacing: Double?
    public var alignment: VerticalAlignment

    // Store the raw content from the builder
    public var content: any View

    // Compute children dynamically for the Engine
    public var children: [any View] {
        // A Divider in a row runs vertically. Resolved here so every backend
        // sees an already-decided orientation.
        Omni.unpackViews(content).map { child in
            if let divider = child as? Divider, divider.isVertical == nil {
                return Divider(isVertical: true)
            }
            return child
        }
    }
    /// SwiftUI leaves spacing to the system when unset; 8 is what the
    /// platforms here have always used.
    var resolvedSpacing: Double { spacing ?? 8 }

    public var body: any View { self }

    public init(
        alignment: VerticalAlignment = .center,
        spacing: Double? = nil,
        @ViewBuilder _ content: @escaping () -> any View
    ) {
        self.alignment = alignment
        self.spacing = spacing
        self.content = content()
    }
}
