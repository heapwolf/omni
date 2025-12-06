#if os(macOS)
import Foundation
import AppKit

/// Table on macOS: an NSTableView in a scroll view, virtualised as AppKit's
/// is. Header clicks report the sort the app should fetch; the selection and
/// the sort shown follow their bindings; double-click or Return opens a row;
/// the last column is the row's "⋯" when it has actions.
struct TableNative: NativeComponent {
    let model: TableModel

    static let actionsColumn = NSUserInterfaceItemIdentifier("omni.actions")

    @MainActor func makeNative() -> NativeView {
        let table = NSTableView()
        table.style = .inset
        table.usesAlternatingRowBackgroundColors = true
        table.rowHeight = 28
        table.intercellSpacing = NSSize(width: 12, height: 4)
        table.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        table.allowsColumnReordering = false

        let coordinator = TableCoordinator(table)
        table.dataSource = coordinator
        table.delegate = coordinator
        table.target = coordinator
        table.doubleAction = #selector(TableCoordinator.open)

        let scroll = TableScrollView()
        scroll.coordinator = coordinator
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.setContentHuggingPriority(.init(rawValue: 1), for: .horizontal)
        scroll.setContentHuggingPriority(.init(rawValue: 1), for: .vertical)
        tableRegistry[ObjectIdentifier(scroll)] = coordinator
        return scroll
    }

    @MainActor func unmountNative(_ view: NativeView) {
        tableRegistry.removeValue(forKey: ObjectIdentifier(view))
    }

    @MainActor func updateNative(_ view: NativeView) {
        guard let coordinator = tableRegistry[ObjectIdentifier(view)] else { return }
        coordinator.update(model)
    }
}

@MainActor private var tableRegistry: [ObjectIdentifier: TableCoordinator] = [:]

/// Fits its columns to its width whenever that changes: AppKit only shares
/// out width when a column is dragged, so a table starting narrower than its
/// columns scrolled sideways, its last columns out of sight.
final class TableScrollView: NSScrollView {
    weak var coordinator: TableCoordinator?
    private var fittedWidth: CGFloat = -1

    override func layout() {
        super.layout()
        guard abs(bounds.width - fittedWidth) > 0.5 else { return }
        fit()
    }

    /// The columns to the width: the flexible ones share it (sizeToFit),
    /// and when even so they are wider than the view (set widths, and the
    /// rest at their least), every column gives in proportion, down to its
    /// least. A column off the right edge, scrolled to, read as missing.
    func fit() {
        guard let table = documentView as? NSTableView else { return }
        fittedWidth = bounds.width
        table.sizeToFit()
        for _ in 0..<3 {
            let over = table.frame.width - contentView.bounds.width
            guard over > 0.5 else { break }
            let give = table.tableColumns.map { max(0, $0.width - $0.minWidth) }
            let room = give.reduce(0, +)
            guard room > 0.5 else { break }
            for (column, spare) in zip(table.tableColumns, give) where spare > 0 {
                column.width -= min(spare, over * spare / room)
            }
            table.tile()
        }
    }

    /// Fit again, the columns having changed.
    func refit() {
        fittedWidth = -1
        needsLayout = true
    }
}

@MainActor
final class TableCoordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    let table: NSTableView
    private(set) var model: TableModel?
    private var shownColumns: [TableColumnSpec] = []
    /// The rows last loaded: an update with the same ones keeps its cells.
    private var shownData: (ids: [AnyHashable], cells: [[TableCell]])?
    private var hasActionsColumn = false
    /// Set while the table is matched to the bindings, so that isn't reported
    /// back as the person's doing.
    private var isSyncing = false

    init(_ table: NSTableView) {
        self.table = table
    }

    func update(_ next: TableModel) {
        model = next
        isSyncing = true
        defer { isSyncing = false }

        let previous = shownData
        var isRebuilt = false
        if next.columns != shownColumns || next.hasActions != hasActionsColumn {
            rebuildColumns(next)
            isRebuilt = true
        }
        table.allowsMultipleSelection = next.allowsSelection
        table.allowsEmptySelection = true
        // Only when what's shown changed. A screen re-renders on every change
        // of its state, the selection included: reloading then rebuilt every
        // visible cell on each arrow key, and moving down a full page lagged.
        if isRebuilt || previous?.ids != next.ids || previous?.cells != next.cells {
            table.reloadData()
            shownData = (next.ids, next.cells)
        }

        let rows = IndexSet(next.ids.indices.filter { next.selected.contains(next.ids[$0]) })
        if table.selectedRowIndexes != rows { table.selectRowIndexes(rows, byExtendingSelection: false) }

        let descriptors = next.sort.map { [NSSortDescriptor(key: $0.key, ascending: $0.ascending)] } ?? []
        if table.sortDescriptors != descriptors { table.sortDescriptors = descriptors }
    }

    private func rebuildColumns(_ next: TableModel) {
        for column in table.tableColumns { table.removeTableColumn(column) }
        for spec in next.columns {
            let column = NSTableColumn(identifier: .init(spec.id))
            column.title = spec.title
            column.minWidth = CGFloat(spec.minWidth ?? 60)
            if let width = spec.width {
                column.width = CGFloat(width)
                column.resizingMask = .userResizingMask
            } else {
                column.width = 160
                column.resizingMask = [.autoresizingMask, .userResizingMask]
            }
            if let key = spec.sortKey {
                column.sortDescriptorPrototype = NSSortDescriptor(key: key, ascending: true)
            }
            table.addTableColumn(column)
        }
        if next.hasActions {
            let column = NSTableColumn(identifier: TableNative.actionsColumn)
            column.title = ""
            column.width = 28
            column.minWidth = 28
            column.maxWidth = 28
            column.resizingMask = []
            table.addTableColumn(column)
        }
        shownColumns = next.columns
        hasActionsColumn = next.hasActions
        table.sizeToFit()
        (table.enclosingScrollView as? TableScrollView)?.refit()
    }

    // MARK: Data

    func numberOfRows(in tableView: NSTableView) -> Int { model?.cells.count ?? 0 }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let model, let tableColumn else { return nil }
        if tableColumn.identifier == TableNative.actionsColumn {
            let button = ActionMenuButton()
            button.isBordered = false
            button.bezelStyle = .inline
            button.imagePosition = .imageOnly
            button.image = NSImage(systemSymbolName: "ellipsis", accessibilityDescription: "Actions")
            button.toolTip = "Actions"
            // The current model's, when opened: the cell may outlive this one.
            button.provide = { [weak self] in self?.model?.actions(row) ?? [] }
            return button
        }
        guard let index = shownColumns.firstIndex(where: { $0.id == tableColumn.identifier.rawValue }),
              model.cells.indices.contains(row), model.cells[row].indices.contains(index) else { return nil }
        return Self.view(for: model.cells[row][index])
    }

    /// A cell's text in its style; a badge in its tinted capsule; a flag, a
    /// badge after the text.
    static func view(for cell: TableCell) -> NSView {
        guard let flag = cell.flag else { return plainView(for: cell) }
        var bare = cell
        bare.flag = nil
        let text = plainView(for: bare)
        let badge = plainView(for: TableCell(flag.text, style: .badge(flag.tone)))
        let container = NSTableCellView()
        container.textField = (text as? NSTableCellView)?.textField
        for view in [text, badge] {
            view.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(view)
        }
        // The text gives way first: the flag is the thing to see.
        text.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        badge.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        NSLayoutConstraint.activate([
            text.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            text.topAnchor.constraint(equalTo: container.topAnchor),
            text.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            badge.leadingAnchor.constraint(equalTo: text.trailingAnchor, constant: 6),
            badge.topAnchor.constraint(equalTo: container.topAnchor),
            badge.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            badge.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor)
        ])
        return container
    }

    private static func plainView(for cell: TableCell) -> NSView {
        let label = NSTextField(labelWithString: cell.text)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.lineBreakMode = .byTruncatingTail
        label.alignment = cell.trailing ? .right : .left
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let container = NSTableCellView()
        container.textField = label
        switch cell.style {
        case .primary:
            label.font = .systemFont(ofSize: NSFont.systemFontSize)
        case .secondary:
            label.font = .systemFont(ofSize: NSFont.systemFontSize)
            label.textColor = .secondaryLabelColor
        case .monospaced:
            label.font = .monospacedSystemFont(ofSize: NSFont.systemFontSize - 1, weight: .regular)
        case .badge(let tone):
            let color = tone.color.nsColor
            label.font = .systemFont(ofSize: NSFont.smallSystemFontSize, weight: .semibold)
            label.textColor = color
            let capsule = NSView()
            capsule.translatesAutoresizingMaskIntoConstraints = false
            capsule.wantsLayer = true
            capsule.layer?.backgroundColor = color.withAlphaComponent(0.14).cgColor
            capsule.layer?.cornerRadius = 9
            capsule.addSubview(label)
            container.addSubview(capsule)
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: capsule.leadingAnchor, constant: 8),
                label.trailingAnchor.constraint(equalTo: capsule.trailingAnchor, constant: -8),
                label.centerYAnchor.constraint(equalTo: capsule.centerYAnchor),
                capsule.heightAnchor.constraint(equalToConstant: 18),
                capsule.centerYAnchor.constraint(equalTo: container.centerYAnchor),
                capsule.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                capsule.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor)
            ])
            return container
        }
        container.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            label.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            label.centerYAnchor.constraint(equalTo: container.centerYAnchor)
        ])
        return container
    }

    // MARK: What the person does

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard !isSyncing, let model, model.allowsSelection else { return }
        model.onSelect(Array(table.selectedRowIndexes))
    }

    func tableView(_ tableView: NSTableView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
        guard !isSyncing, let model, let first = tableView.sortDescriptors.first, let key = first.key else { return }
        model.onSort(TableSort(key, ascending: first.ascending))
    }

    @objc func open() {
        let row = table.clickedRow >= 0 ? table.clickedRow : table.selectedRow
        guard row >= 0 else { return }
        model?.onOpen(row)
    }
}
#endif
