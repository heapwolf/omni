// No viewport height means every row is rendered, which is slow rather than wrong.

import Foundation

// MARK: - What a list can pull from

/// A source of rows a List can mount one at a time. Count and identity must be
/// answerable without building the row.
@MainActor
public protocol LazyRowSource {
    var rowCount: Int { get }
    /// Identity of the row at `index`.
    func rowIdentity(at index: Int) -> AnyHashable
    /// Called only for rows inside the window.
    func rowView(at index: Int) -> any View
}

extension ForEach: LazyRowSource {
    public var rowCount: Int { elements.count }

    public func rowIdentity(at index: Int) -> AnyHashable {
        identify?(elements[index]) ?? AnyHashable(index)
    }

    public func rowView(at index: Int) -> any View {
        content(elements[index])
    }
}

// MARK: - List

public struct List<Content: View>: OmniStructuralView {
    public var content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    /// SwiftUI's `List(items) { item in ... }`. Routed through ForEach so the
    /// row virtualisation below still applies.
    public init<Data: RandomAccessCollection, RowContent: View>(
        _ data: Data,
        @ViewBuilder rowContent: @escaping (Data.Element) -> RowContent
    ) where Content == ForEach<Data, RowContent>, Data.Element: Identifiable {
        self.content = ForEach(data, content: rowContent)
    }

    /// SwiftUI's `List(items, id: \.self) { item in ... }`.
    public init<Data: RandomAccessCollection, ID: Hashable, RowContent: View>(
        _ data: Data,
        id: KeyPath<Data.Element, ID>,
        @ViewBuilder rowContent: @escaping (Data.Element) -> RowContent
    ) where Content == ForEach<Data, RowContent> {
        self.content = ForEach(data, id: id, content: rowContent)
    }

    public typealias Body = Never
    public var body: Never { fatalError("Engine unpacks List dynamically") }

    public var unpacked: [any View] {
        // A single ForEach is the case worth virtualising. Anything else composes as
        // it always did.
        if let source = content as? any LazyRowSource {
            return [VirtualisedRows(source: source)]
        }
        return [ScrollView(axis: .vertical) { VStack { content } }]
    }
}

// MARK: - The window

struct VirtualisedRows: View {
    let source: any LazyRowSource

    @State private var scrollY: Double = 0
    @State private var viewportHeight: Double = 0
    @State private var measuredRowHeight: Double = 0

    /// Until a row has been measured; UIKit's own default row height.
    private static let estimatedRowHeight: Double = 44

    /// Rows kept mounted either side of the viewport: a flick outruns one frame of
    /// layout.
    private static let overscan = 4

    private var rowHeight: Double {
        measuredRowHeight > 0 ? measuredRowHeight : Self.estimatedRowHeight
    }

    var body: some View {
        GeometryReader(onResize: { proxy in
            // Guarded: @State notifies on every set, and this fires on every layout.
            if proxy.height > 0, abs(proxy.height - viewportHeight) > 0.5 {
                viewportHeight = proxy.height
            }
        }) {
            ScrollView(axis: .vertical, offset: $scrollY) {
                VStack(spacing: 0) {
                    rows
                }
            }
        }
    }

    @ViewBuilder
    private var rows: some View {
        let count = source.rowCount
        let window = self.window(count: count)

        // A Frame, not a Spacer: it must be exactly as tall as the rows it replaces.
        Frame(height: Double(window.lowerBound) * rowHeight) { EmptyView() }

        ForEach(Array(window), identity: { source.rowIdentity(at: $0) }) { index in
            // Only row 0 is measured: every row would oscillate the estimate.
            if index == 0 {
                AnyView(GeometryReader(onResize: { proxy in
                    if proxy.height > 0, abs(proxy.height - measuredRowHeight) > 0.5 {
                        measuredRowHeight = proxy.height
                    }
                }) {
                    source.rowView(at: index)
                })
            } else {
                AnyView(source.rowView(at: index))
            }
        }

        Frame(height: Double(count - window.upperBound) * rowHeight) { EmptyView() }
    }

    /// The rows to mount, clamped to 0..<count so a stale offset cannot index past
    /// the end of a shorter list.
    func window(count: Int) -> Range<Int> {
        guard count > 0 else { return 0..<0 }

        // No measurement yet: mount everything.
        guard viewportHeight > 0 else { return 0..<count }

        let visible = max(1, Int((viewportHeight / rowHeight).rounded(.up)))
        let first = max(0, Int(scrollY / rowHeight) - Self.overscan)
        let last = min(count, first + visible + Self.overscan * 2)
        return first..<max(first, last)
    }
}
