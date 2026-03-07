import Foundation

// SwiftUI's lazy stacks build rows on demand. These build eagerly: the layout
// is identical, only the work is not deferred, so a very long LazyVStack costs
// what a VStack costs. List's ForEach path is the one that actually virtualises
// (see LazyRowSource in List.swift); reach for it when the count is large.

public struct LazyVStack: View {
    private let alignment: HorizontalAlignment
    private let spacing: Double?
    private let content: any View

    public init(alignment: HorizontalAlignment = .center, spacing: Double? = nil,
                @ViewBuilder _ content: @escaping () -> any View) {
        self.alignment = alignment
        self.spacing = spacing
        self.content = content()
    }

    public var body: some View {
        let captured = content
        return VStack(alignment: alignment, spacing: spacing) { captured }
    }
}

public struct LazyHStack: View {
    private let alignment: VerticalAlignment
    private let spacing: Double?
    private let content: any View

    public init(alignment: VerticalAlignment = .center, spacing: Double? = nil,
                @ViewBuilder _ content: @escaping () -> any View) {
        self.alignment = alignment
        self.spacing = spacing
        self.content = content()
    }

    public var body: some View {
        let captured = content
        return HStack(alignment: alignment, spacing: spacing) { captured }
    }
}
