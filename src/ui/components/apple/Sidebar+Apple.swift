#if os(macOS)
import Foundation
import AppKit

// MARK: - The split

/// NavigationSplitView on macOS: an NSSplitView, the sidebar on the window's
/// translucent sidebar material, its width between 200 and 360 and kept as the
/// window resizes; the detail takes the rest.
struct SplitNative: NativeComponent, NativePanes {
    let sidebarWidth: Double
    let children: [any View]

    @MainActor func makeNative() -> NativeView {
        let split = OmniSplitView()
        split.sidebarWidth = CGFloat(sidebarWidth)
        split.delegate = split
        split.isVertical = true
        split.dividerStyle = .thin
        split.translatesAutoresizingMaskIntoConstraints = false
        // Resizing grows the detail; the sidebar keeps its width.
        split.setContentHuggingPriority(.init(rawValue: 1), for: .horizontal)
        split.setContentHuggingPriority(.init(rawValue: 1), for: .vertical)
        return split
    }

    @MainActor func updateNative(_ view: NativeView) {}

    @MainActor func detach(_ child: NativeView, from parent: NativeView) {
        if child.superview?.superview === parent { child.removeFromSuperview() }
    }

    /// Into the first empty pane (one whose view was replaced, or every pane
    /// on a rebuild, in order), else a new one: the sidebar's, then the detail's.
    @MainActor func insertChild(_ child: NativeView, into parent: NativeView) {
        guard let split = parent as? NSSplitView else { return }
        if let empty = split.arrangedSubviews.first(where: { $0.subviews.isEmpty }) {
            return fill(empty, with: child)
        }
        let pane: NSView
        if split.arrangedSubviews.isEmpty {
            let material = NSVisualEffectView()
            material.material = .sidebar
            material.blendingMode = .behindWindow
            material.state = .followsWindowActiveState
            pane = material
            NSLayoutConstraint.activate([
                pane.widthAnchor.constraint(greaterThanOrEqualToConstant: 200),
                pane.widthAnchor.constraint(lessThanOrEqualToConstant: 360)
            ])
            // Its width holds against anything a screen in the detail would
            // like (a row sharing its room, 740; a fill, 700 and 900 within a
            // pinned frame), so it doesn't change from screen to screen, as a
            // Mac sidebar doesn't: at 260 it was 200 on one screen and 339 on
            // the next. A screen that can't fit truncates its labels (750)
            // before it narrows. The window's own size is never the content's
            // to change (contentHost).
            let preferred = pane.widthAnchor.constraint(equalToConstant: CGFloat(sidebarWidth))
            preferred.priority = .init(rawValue: 800)
            preferred.isActive = true
            (split as? OmniSplitView)?.preferred = preferred
            split.addArrangedSubview(pane)
            split.setHoldingPriority(.init(rawValue: 260), forSubviewAt: 0)
        } else {
            pane = NSView()
            pane.widthAnchor.constraint(greaterThanOrEqualToConstant: 360).isActive = true
            split.addArrangedSubview(pane)
            split.setHoldingPriority(.init(rawValue: 250), forSubviewAt: split.arrangedSubviews.count - 1)
        }
        pane.translatesAutoresizingMaskIntoConstraints = false
        fill(pane, with: child)
    }

    @MainActor private func fill(_ pane: NSView, with child: NativeView) {
        pane.addSubview(child)
        // Under a transparent title bar, the sidebar starts below it and the
        // traffic lights, as Finder's and Mail's does; its material, the
        // pane, runs to the window's top. The detail draws its own header
        // there, as a toolbar row.
        let top = pane is NSVisualEffectView ? CGFloat(Engine.safeArea.top) : 0
        NSLayoutConstraint.activate([
            child.topAnchor.constraint(equalTo: pane.topAnchor, constant: top),
            child.bottomAnchor.constraint(equalTo: pane.bottomAnchor),
            child.leadingAnchor.constraint(equalTo: pane.leadingAnchor),
            child.trailingAnchor.constraint(equalTo: pane.trailingAnchor)
        ])
    }
}

/// The sidebar keeps its width: its preferred-width constraint (800) holds
/// against anything a screen in the detail would like, and dragging the
/// divider moves it. NSSplitView's own holding priority only decides which
/// side a window resize goes to (the detail's); set as high as the width,
/// it kept the 200 the sidebar had while the split was first laid out small.
final class OmniSplitView: NSSplitView, NSSplitViewDelegate {
    var sidebarWidth: CGFloat = 240
    weak var preferred: NSLayoutConstraint?

    func splitView(_ splitView: NSSplitView, constrainSplitPosition proposedPosition: CGFloat,
                   ofSubviewAt dividerIndex: Int) -> CGFloat {
        let position = min(max(proposedPosition, 200), 360)
        preferred?.constant = position
        return position
    }
}

// MARK: - The sidebar

/// Sidebar on macOS: a source list, as Finder's and Mail's.
struct SidebarNative: NativeComponent {
    let rows: [SidebarRow]
    let selectedIndex: Int?
    let onSelect: (Int) -> Void

    @MainActor func makeNative() -> NativeView {
        let table = NSTableView()
        table.style = .sourceList
        table.headerView = nil
        table.rowSizeStyle = .medium
        table.backgroundColor = .clear
        table.focusRingType = .none
        table.allowsEmptySelection = true
        table.addTableColumn(NSTableColumn(identifier: .init("omni.sidebar")))

        let coordinator = SidebarCoordinator(table)
        table.dataSource = coordinator
        table.delegate = coordinator

        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.setContentHuggingPriority(.init(rawValue: 1), for: .horizontal)
        scroll.setContentHuggingPriority(.init(rawValue: 1), for: .vertical)
        sidebarRegistry[ObjectIdentifier(scroll)] = coordinator
        return scroll
    }

    @MainActor func unmountNative(_ view: NativeView) {
        sidebarRegistry.removeValue(forKey: ObjectIdentifier(view))
    }

    @MainActor func updateNative(_ view: NativeView) {
        guard let coordinator = sidebarRegistry[ObjectIdentifier(view)] else { return }
        coordinator.onSelect = onSelect
        if coordinator.rows != rows {
            coordinator.rows = rows
            coordinator.table.reloadData()
        }
        coordinator.select(selectedIndex)
    }
}

@MainActor private var sidebarRegistry: [ObjectIdentifier: SidebarCoordinator] = [:]

/// An item's cell: its symbol in the accent colour, its badge muted, both in
/// the selected text colour on a highlighted row (accent on accent vanished).
final class SidebarCellView: NSTableCellView {
    var badge: NSTextField?

    override var backgroundStyle: NSView.BackgroundStyle {
        didSet { restyle() }
    }

    func restyle() {
        let highlighted = backgroundStyle == .emphasized
        imageView?.contentTintColor = highlighted ? .alternateSelectedControlTextColor : .controlAccentColor
        badge?.textColor = highlighted ? .alternateSelectedControlTextColor : .secondaryLabelColor
    }
}

@MainActor
final class SidebarCoordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    let table: NSTableView
    var rows: [SidebarRow] = []
    var onSelect: (Int) -> Void = { _ in }
    /// Set while the selection is being matched to the binding, so it isn't
    /// reported back as the person's choice.
    private var isSyncing = false

    init(_ table: NSTableView) {
        self.table = table
    }

    func numberOfRows(in tableView: NSTableView) -> Int { rows.count }

    func tableView(_ tableView: NSTableView, isGroupRow row: Int) -> Bool { rows[row].kind == .header }

    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool { rows[row].kind == .item }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let item = rows[row]
        let cell = SidebarCellView()
        let label = NSTextField(labelWithString: item.title)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.lineBreakMode = .byTruncatingTail
        cell.addSubview(label)
        cell.textField = label

        if item.kind == .header {
            label.font = .systemFont(ofSize: NSFont.smallSystemFontSize, weight: .semibold)
            label.textColor = .secondaryLabelColor
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
                label.trailingAnchor.constraint(lessThanOrEqualTo: cell.trailingAnchor),
                label.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
            ])
            return cell
        }

        let image = NSImageView()
        image.translatesAutoresizingMaskIntoConstraints = false
        image.image = item.systemImage.flatMap { NSImage(systemSymbolName: $0, accessibilityDescription: nil) }
        cell.addSubview(image)
        cell.imageView = image

        var constraints = [
            image.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
            image.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            image.widthAnchor.constraint(equalToConstant: 18),
            label.leadingAnchor.constraint(equalTo: image.trailingAnchor, constant: 6),
            label.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
        ]
        if let badge = item.badge {
            let count = NSTextField(labelWithString: badge)
            count.translatesAutoresizingMaskIntoConstraints = false
            count.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
            cell.addSubview(count)
            cell.badge = count
            constraints += [
                count.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -6),
                count.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                label.trailingAnchor.constraint(lessThanOrEqualTo: count.leadingAnchor, constant: -6)
            ]
        } else {
            constraints.append(label.trailingAnchor.constraint(lessThanOrEqualTo: cell.trailingAnchor, constant: -6))
        }
        NSLayoutConstraint.activate(constraints)
        cell.restyle()
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard !isSyncing else { return }
        let row = table.selectedRow
        guard rows.indices.contains(row), let index = rows[row].index else { return }
        onSelect(index)
    }

    /// The binding's item, shown selected.
    func select(_ index: Int?) {
        let row = index.flatMap { wanted in rows.firstIndex { $0.index == wanted } }
        guard table.selectedRow != (row ?? -1) else { return }
        isSyncing = true
        if let row {
            table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        } else {
            table.deselectAll(nil)
        }
        isSyncing = false
    }
}
#endif
