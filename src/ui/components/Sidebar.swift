import Foundation

// A sidebar of sections, and a split view that puts it beside the detail.
//
//   NavigationSplitView(showsDetail: $showsDetail) {
//       Sidebar(selection: $screen) {
//           SidebarSection("Customers") {
//               SidebarItem("Users", systemImage: "person.2", tag: Screen.users)
//           }
//       }
//   } detail: {
//       screen(for: screen)
//   }
//
// macOS: an NSSplitView with a translucent source-list sidebar (NSTableView,
// .sourceList), its width between 200 and 360. Elsewhere, composed: side by
// side when there is room, and on a phone-width window the sidebar, then the
// detail pushed over it with a Back button, as SwiftUI's collapses.

public struct SidebarItem<Tag: Hashable> {
    public var title: String
    public var systemImage: String?
    public var tag: Tag
    /// A count or a short word after the title ("3", "New"); nil for none.
    public var badge: String?

    public init(_ title: String, systemImage: String? = nil, tag: Tag, badge: String? = nil) {
        self.title = title
        self.systemImage = systemImage
        self.tag = tag
        self.badge = badge
    }
}

public struct SidebarSection<Tag: Hashable> {
    public var title: String?
    public var items: [SidebarItem<Tag>]

    public init(_ title: String? = nil, @SidebarItemBuilder<Tag> items: () -> [SidebarItem<Tag>]) {
        self.title = title
        self.items = items()
    }
}

@resultBuilder public enum SidebarItemBuilder<Tag: Hashable> {
    public static func buildExpression(_ item: SidebarItem<Tag>) -> [SidebarItem<Tag>] { [item] }
    public static func buildExpression(_ items: [SidebarItem<Tag>]) -> [SidebarItem<Tag>] { items }
    public static func buildBlock(_ parts: [SidebarItem<Tag>]...) -> [SidebarItem<Tag>] { parts.flatMap { $0 } }
    public static func buildOptional(_ part: [SidebarItem<Tag>]?) -> [SidebarItem<Tag>] { part ?? [] }
    public static func buildEither(first: [SidebarItem<Tag>]) -> [SidebarItem<Tag>] { first }
    public static func buildEither(second: [SidebarItem<Tag>]) -> [SidebarItem<Tag>] { second }
    public static func buildArray(_ parts: [[SidebarItem<Tag>]]) -> [SidebarItem<Tag>] { parts.flatMap { $0 } }
}

@resultBuilder public enum SidebarSectionBuilder<Tag: Hashable> {
    public static func buildExpression(_ section: SidebarSection<Tag>) -> [SidebarSection<Tag>] { [section] }
    public static func buildBlock(_ parts: [SidebarSection<Tag>]...) -> [SidebarSection<Tag>] { parts.flatMap { $0 } }
    public static func buildOptional(_ part: [SidebarSection<Tag>]?) -> [SidebarSection<Tag>] { part ?? [] }
    public static func buildEither(first: [SidebarSection<Tag>]) -> [SidebarSection<Tag>] { first }
    public static func buildEither(second: [SidebarSection<Tag>]) -> [SidebarSection<Tag>] { second }
    public static func buildArray(_ parts: [[SidebarSection<Tag>]]) -> [SidebarSection<Tag>] { parts.flatMap { $0 } }
}

/// The rows a sidebar draws, sections flattened: what both renderings read.
public struct SidebarRow: Equatable {
    public enum Kind: Equatable { case header, item }
    public let kind: Kind
    public let title: String
    public let systemImage: String?
    public let badge: String?
    /// The item's place in `items`; nil for a header.
    public let index: Int?
}

public struct Sidebar<Tag: Hashable>: View {
    public var sections: [SidebarSection<Tag>]
    public var selection: Binding<Tag?>

    public init(selection: Binding<Tag?>, @SidebarSectionBuilder<Tag> _ sections: () -> [SidebarSection<Tag>]) {
        self.selection = selection
        self.sections = sections()
    }

    var items: [SidebarItem<Tag>] { sections.flatMap(\.items) }

    var rows: [SidebarRow] {
        var rows: [SidebarRow] = []
        var index = 0
        for section in sections where !section.items.isEmpty {
            if let title = section.title {
                rows.append(SidebarRow(kind: .header, title: title, systemImage: nil, badge: nil, index: nil))
            }
            for item in section.items {
                rows.append(SidebarRow(kind: .item, title: item.title, systemImage: item.systemImage,
                                       badge: item.badge, index: index))
                index += 1
            }
        }
        return rows
    }

    var selectedIndex: Int? {
        guard let tag = selection.wrappedValue else { return nil }
        return items.firstIndex { $0.tag == tag }
    }

    public var body: some View {
        let items = self.items
        let selection = self.selection
        let choose: (Int) -> Void = { index in
            if items.indices.contains(index) { selection.wrappedValue = items[index].tag }
        }
        #if os(macOS)
        return SidebarNative(rows: rows, selectedIndex: selectedIndex, onSelect: choose)
        #else
        return SidebarComposed(rows: rows, selectedIndex: selectedIndex, onSelect: choose)
        #endif
    }
}

/// The sidebar, composed: a column of section titles and rows, the selected
/// one filled.
struct SidebarComposed: View {
    let rows: [SidebarRow]
    let selectedIndex: Int?
    let onSelect: (Int) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    if row.kind == .header {
                        AnyView(Text(row.title).font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.secondaryText)
                            .padding(.horizontal, 10).padding(.top, 14).padding(.bottom, 4))
                    } else {
                        AnyView(item(row))
                    }
                }
            }
            .padding(10)
        }
    }

    private func item(_ row: SidebarRow) -> some View {
        let isSelected = row.index == selectedIndex
        return HStack(spacing: 8) {
            if let symbol = row.systemImage {
                Image(systemName: symbol).frame(width: 18, height: 18)
            }
            Text(row.title).lineLimit(1)
            Spacer()
            if let badge = row.badge {
                Text(badge).font(.system(size: 11)).foregroundColor(.secondaryText)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 30)
        .background(isSelected ? Color.gray.opacity(0.22) : Color.clear)
        .cornerRadius(6)
        .onTapGesture { if let index = row.index { onSelect(index) } }
    }
}

// MARK: - The split

public struct NavigationSplitView: View {
    public var sidebar: any View
    public var detail: any View
    /// Phone width only: whether the detail is pushed over the sidebar. The
    /// app sets it when something is chosen; Back clears it.
    public var showsDetail: Binding<Bool>
    public var sidebarWidth: Double

    public init(showsDetail: Binding<Bool> = .constant(false), sidebarWidth: Double = 240,
                @ViewBuilder sidebar: () -> any View, @ViewBuilder detail: () -> any View) {
        self.showsDetail = showsDetail
        self.sidebarWidth = sidebarWidth
        self.sidebar = sidebar()
        self.detail = detail()
    }

    public var body: some View {
        #if os(macOS)
        return SplitNative(sidebarWidth: sidebarWidth, children: [sidebar, detail])
        #else
        let sidebar = self.sidebar, detail = self.detail, showsDetail = self.showsDetail
        let width = sidebarWidth
        return Responsive(breakpoints: [700]) { proxy in
            if proxy.width >= 700 {
                return AnyView(HStack(spacing: 0) {
                    AnyView(sidebar).frame(width: width)
                    Divider()
                    AnyView(detail)
                })
            }
            if showsDetail.wrappedValue {
                return AnyView(VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left").frame(width: 14, height: 18)
                            Text("Back")
                        }
                        .onTapGesture { showsDetail.wrappedValue = false }
                        Spacer()
                    }
                    .padding(.horizontal, 16).frame(height: 44)
                    AnyView(detail)
                })
            }
            return AnyView(sidebar)
        }
        #endif
    }
}
