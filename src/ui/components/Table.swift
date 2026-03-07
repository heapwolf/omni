import Foundation

// A table of rows: columns, sorting the app does (or the server does: the
// table only says what was asked for), selection, opening a row, a "⋯" of
// actions on every row, and columns that can be hidden.
//
//   Table(users, id: \.id, selection: $selected, sort: $sort,
//         actions: { user in [ActionItem("Restrict", isDestructive: true) { … }] },
//         onOpen: { user in open(user) }) {
//       TableColumn("Name", compact: true) { TableCell($0.name) }
//       TableColumn("Email", sortKey: "email") { TableCell($0.email, style: .secondary) }
//       TableColumn("Status", width: 110) { TableCell($0.status, style: .badge(.positive)) }
//   }
//
// Cells are declarative (text, and how to show it) so every platform draws
// them natively. macOS: NSTableView. Elsewhere, composed: a table with a header
// when there is room, and at phone width one row per item, of the columns
// marked `compact`, the first as its title.

public struct TableCell: Equatable {
    public enum Tone: Equatable { case neutral, positive, warning, negative, info }
    public enum Style: Equatable {
        case primary
        case secondary
        /// IDs, references, amounts that line up.
        case monospaced
        /// A status: the text in a tinted capsule.
        case badge(Tone)
    }

    /// A status beside the text ("Restricted" by a name), in its capsule.
    public struct Flag: Equatable {
        public var text: String
        public var tone: Tone
        public init(_ text: String, tone: Tone) {
            self.text = text
            self.tone = tone
        }
    }

    public var text: String
    public var style: Style
    /// Trailing for numbers.
    public var trailing: Bool
    public var flag: Flag?

    public init(_ text: String, style: Style = .primary, trailing: Bool = false, flag: Flag? = nil) {
        self.text = text
        self.style = style
        self.trailing = trailing
        self.flag = flag
    }
}

public struct TableColumn<Row> {
    public var id: String
    public var title: String
    /// Its starting width; nil to share what's left.
    public var width: Double?
    /// The least it gives up to when the columns don't fit (60 unless said):
    /// a date's, so it stays read whole while a long name is cut.
    public var minWidth: Double?
    /// The key the sort binding gets when this column's header is clicked;
    /// nil for a column that doesn't sort.
    public var sortKey: String?
    /// Shown at phone width.
    public var isCompact: Bool
    public var cell: (Row) -> TableCell

    public init(_ title: String, id: String? = nil, width: Double? = nil, minWidth: Double? = nil, sortKey: String? = nil,
                compact: Bool = false, cell: @escaping (Row) -> TableCell) {
        self.id = id ?? title
        self.title = title
        self.width = width
        self.minWidth = minWidth
        self.sortKey = sortKey
        self.isCompact = compact
        self.cell = cell
    }
}

@resultBuilder public enum TableColumnBuilder<Row> {
    public static func buildExpression(_ column: TableColumn<Row>) -> [TableColumn<Row>] { [column] }
    public static func buildBlock(_ parts: [TableColumn<Row>]...) -> [TableColumn<Row>] { parts.flatMap { $0 } }
    public static func buildOptional(_ part: [TableColumn<Row>]?) -> [TableColumn<Row>] { part ?? [] }
    public static func buildEither(first: [TableColumn<Row>]) -> [TableColumn<Row>] { first }
    public static func buildEither(second: [TableColumn<Row>]) -> [TableColumn<Row>] { second }
}

/// What a header click asks for.
public struct TableSort: Hashable, Sendable {
    public var key: String
    public var ascending: Bool
    public init(_ key: String, ascending: Bool = true) {
        self.key = key
        self.ascending = ascending
    }
}

/// A column as the renderings need it, without its row type.
public struct TableColumnSpec: Equatable {
    public let id: String
    public let title: String
    public let width: Double?
    public var minWidth: Double? = nil
    public let sortKey: String?
    public let isCompact: Bool
}

public struct Table<Row, ID: Hashable>: View {
    public var rows: [Row]
    public var id: KeyPath<Row, ID>
    public var columns: [TableColumn<Row>]
    public var selection: Binding<Set<ID>>?
    public var sort: Binding<TableSort?>?
    /// Column IDs not shown (the app keeps it, per screen).
    public var hiddenColumns: Set<String>
    public var actions: ((Row) -> [ActionItem])?
    public var onOpen: ((Row) -> Void)?
    /// Said when there are no rows.
    public var emptyText: String

    public init(_ rows: [Row], id: KeyPath<Row, ID>, selection: Binding<Set<ID>>? = nil,
                sort: Binding<TableSort?>? = nil, hiddenColumns: Set<String> = [],
                emptyText: String = "Nothing to show.",
                actions: ((Row) -> [ActionItem])? = nil, onOpen: ((Row) -> Void)? = nil,
                @TableColumnBuilder<Row> columns: () -> [TableColumn<Row>]) {
        self.rows = rows
        self.id = id
        self.selection = selection
        self.sort = sort
        self.hiddenColumns = hiddenColumns
        self.emptyText = emptyText
        self.actions = actions
        self.onOpen = onOpen
        self.columns = columns()
    }

    /// Everything a rendering draws, read once.
    var model: TableModel {
        let shown = columns.filter { !hiddenColumns.contains($0.id) }
        let rows = self.rows, id = self.id
        let ids = rows.map { AnyHashable($0[keyPath: id]) }
        let selection = self.selection, sort = self.sort, actions = self.actions, onOpen = self.onOpen
        return TableModel(
            columns: shown.map { TableColumnSpec(id: $0.id, title: $0.title, width: $0.width, minWidth: $0.minWidth,
                                                 sortKey: $0.sortKey, isCompact: $0.isCompact) },
            cells: rows.map { row in shown.map { $0.cell(row) } },
            ids: ids,
            selected: Set((selection?.wrappedValue ?? []).map { AnyHashable($0) }),
            sort: sort?.wrappedValue,
            allowsSelection: selection != nil,
            hasActions: actions != nil,
            emptyText: emptyText,
            onSelect: { indexes in
                selection?.wrappedValue = Set(indexes.compactMap { rows.indices.contains($0) ? rows[$0][keyPath: id] : nil })
            },
            onSort: { next in sort?.wrappedValue = next },
            onOpen: { index in if rows.indices.contains(index) { onOpen?(rows[index]) } },
            actions: { index in rows.indices.contains(index) ? (actions?(rows[index]) ?? []) : [] })
    }

    public var body: some View {
        #if os(macOS)
        return TableNative(model: model)
        #else
        return TableComposed(model: model)
        #endif
    }
}

/// A table without its row type: what TableNative and TableComposed draw.
public struct TableModel {
    public let columns: [TableColumnSpec]
    public let cells: [[TableCell]]
    public let ids: [AnyHashable]
    public let selected: Set<AnyHashable>
    public let sort: TableSort?
    public let allowsSelection: Bool
    public let hasActions: Bool
    public let emptyText: String
    public let onSelect: ([Int]) -> Void
    public let onSort: (TableSort) -> Void
    public let onOpen: (Int) -> Void
    public let actions: (Int) -> [ActionItem]

    /// A header clicked: this column ascending, or the other way if it already was.
    func sort(byColumn index: Int) -> TableSort? {
        guard let key = columns[index].sortKey else { return nil }
        if let sort, sort.key == key { return TableSort(key, ascending: !sort.ascending) }
        return TableSort(key)
    }
}

extension TableCell.Tone {
    var color: Color {
        switch self {
        case .neutral: return .gray
        case .positive: return .green
        case .warning: return .orange
        case .negative: return .red
        case .info: return .blue
        }
    }
}

// MARK: - Composed

/// The table, composed: a header and rows when there is room; at phone width,
/// one row per item, of the compact columns.
struct TableComposed: View {
    let model: TableModel

    var body: some View {
        let model = self.model
        return Responsive(breakpoints: [600]) { proxy in
            if model.cells.isEmpty {
                return AnyView(VStack { Spacer(); Text(model.emptyText).foregroundColor(.secondaryText); Spacer() })
            }
            return proxy.width >= 600 ? AnyView(TableWide(model: model)) : AnyView(TableCompact(model: model))
        }
    }
}

struct TableWide: View {
    let model: TableModel

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                ForEach(Array(model.columns.enumerated()), id: \.offset) { index, column in
                    AnyView(sized(header(index, column), column))
                }
                if model.hasActions { Spacer().frame(width: 24) }
            }
            .padding(.horizontal, 12).frame(height: 30)
            Divider()
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(model.cells.enumerated()), id: \.offset) { row, cells in
                        AnyView(line(row, cells))
                    }
                }
            }
        }
    }

    private func header(_ index: Int, _ column: TableColumnSpec) -> some View {
        let arrow = model.sort?.key == column.sortKey && column.sortKey != nil ? (model.sort!.ascending ? " ▲" : " ▼") : ""
        return Text(column.title + arrow).font(.system(size: 12, weight: .semibold)).foregroundColor(.secondaryText)
            .lineLimit(1)
            .onTapGesture { if let next = model.sort(byColumn: index) { model.onSort(next) } }
    }

    private func line(_ row: Int, _ cells: [TableCell]) -> some View {
        let isSelected = model.selected.contains(model.ids[row])
        return HStack(spacing: 12) {
            ForEach(Array(cells.enumerated()), id: \.offset) { index, cell in
                AnyView(sized(TableCellView(cell: cell), model.columns[index]))
            }
            if model.hasActions { ActionMenu(model.actions(row)).frame(width: 24) }
        }
        .padding(.horizontal, 12).frame(height: 36)
        .background(isSelected ? Color.gray.opacity(0.2) : Color.clear)
        .onTapGesture { model.onOpen(row) }
    }

    private func sized(_ view: some View, _ column: TableColumnSpec) -> some View {
        if let width = column.width { return AnyView(view.frame(width: width, alignment: .leading)) }
        return AnyView(view.frame(maxWidth: .infinity, alignment: .leading))
    }
}

struct TableCompact: View {
    let model: TableModel

    var body: some View {
        let compact = model.columns.indices.filter { model.columns[$0].isCompact }
        let shown = compact.isEmpty ? Array(model.columns.indices.prefix(2)) : compact
        let sortable = model.columns.filter { $0.sortKey != nil }
        return VStack(spacing: 0) {
            if !sortable.isEmpty, let current = model.sort ?? sortable.first.map({ TableSort($0.sortKey!) }) {
                HStack {
                    Spacer()
                    NativePicker(options: sortable.flatMap { column in
                        [(label: column.title + " ↑", tag: TableSort(column.sortKey!, ascending: true)),
                         (label: column.title + " ↓", tag: TableSort(column.sortKey!, ascending: false))]
                    }, selection: Binding(get: { current }, set: { model.onSort($0) }))
                }
                .padding(.horizontal, 16).frame(height: 40)
            }
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(model.cells.enumerated()), id: \.offset) { row, cells in
                        AnyView(item(row, cells, shown))
                    }
                }
            }
        }
    }

    private func item(_ row: Int, _ cells: [TableCell], _ shown: [Int]) -> some View {
        let first = cells[shown[0]]
        let rest = shown.dropFirst().map { cells[$0] }
        return VStack(spacing: 0) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(first.text).font(.system(size: 15, weight: .medium)).lineLimit(1)
                        if let flag = first.flag { FlagView(flag: flag) }
                    }
                    HStack(spacing: 8) {
                        ForEach(Array(rest.enumerated()), id: \.offset) { _, cell in AnyView(TableCellView(cell: cell)) }
                    }
                }
                Spacer()
                if model.hasActions { ActionMenu(model.actions(row)) }
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
            Divider()
        }
        .onTapGesture { model.onOpen(row) }
    }
}

/// One cell, composed.
struct TableCellView: View {
    let cell: TableCell

    var body: some View {
        guard let flag = cell.flag else { return AnyView(text) }
        return AnyView(HStack(spacing: 6) { text; FlagView(flag: flag) })
    }

    private var text: some View {
        switch cell.style {
        case .primary:
            return AnyView(Text(cell.text).font(.system(size: 13)).lineLimit(1))
        case .secondary:
            return AnyView(Text(cell.text).font(.system(size: 13)).foregroundColor(.secondaryText).lineLimit(1))
        case .monospaced:
            return AnyView(Text(cell.text).font(.system(size: 12)).monospaced().lineLimit(1))
        case .badge(let tone):
            return AnyView(Text(cell.text).font(.system(size: 11, weight: .semibold)).foregroundColor(tone.color)
                .padding(.horizontal, 8).padding(.vertical, 2)
                .background(tone.color.opacity(0.14)).cornerRadius(9))
        }
    }
}

struct FlagView: View {
    let flag: TableCell.Flag

    var body: some View {
        TableCellView(cell: TableCell(flag.text, style: .badge(flag.tone)))
    }
}
