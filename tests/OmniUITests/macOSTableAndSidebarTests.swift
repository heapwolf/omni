#if os(macOS)
import XCTest
import AppKit
@testable import OmniUI

/// The native sidebar and table, driven as a person would: the bindings follow
/// what's chosen, and what's chosen follows the bindings.
@MainActor
final class macOSTableAndSidebarTests: XCTestCase {
    final class Box<Value>: @unchecked Sendable {
        var value: Value
        init(_ value: Value) { self.value = value }
        var binding: Binding<Value> { Binding(get: { self.value }, set: { self.value = $0 }) }
    }

    struct User { let id: String; let name: String; let email: String; let status: String }
    let users = [User(id: "u1", name: "Ada Lovelace", email: "ada@x.com", status: "Active"),
                 User(id: "u2", name: "Grace Hopper", email: "grace@x.com", status: "Restricted"),
                 User(id: "u3", name: "Alan Turing", email: "alan@x.com", status: "Active")]

    enum Screen: Hashable { case users, transactions, flags }

    private func host(_ view: any View, width: CGFloat = 900, height: CGFloat = 500) -> NSView {
        let node = Node(view)
        Engine.render(node)
        let root = node.native!
        let host = NSView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        host.addSubview(root)
        NSLayoutConstraint.activate([
            root.widthAnchor.constraint(equalToConstant: width), root.heightAnchor.constraint(equalToConstant: height),
            root.leadingAnchor.constraint(equalTo: host.leadingAnchor), root.topAnchor.constraint(equalTo: host.topAnchor)
        ])
        host.layoutSubtreeIfNeeded()
        return host
    }

    private func tables(in view: NSView) -> [NSTableView] {
        ((view as? NSTableView).map { [$0] } ?? []) + view.subviews.flatMap { tables(in: $0) }
    }

    // MARK: Sidebar

    private func sidebar(_ selection: Box<Screen?>) -> Sidebar<Screen> {
        Sidebar(selection: selection.binding) {
            SidebarSection("Customers") {
                SidebarItem("Users", systemImage: "person.2", tag: Screen.users)
            }
            SidebarSection("Finance") {
                SidebarItem("Transactions", systemImage: "arrow.left.arrow.right", tag: Screen.transactions)
            }
            SidebarSection("Configuration") {
                SidebarItem("Feature flags", systemImage: "flag", tag: Screen.flags, badge: "12")
            }
        }
    }

    func testTheSidebarShowsSectionsAndFollowsTheBinding() {
        MainActor.assumeIsolated {
            let selection = Box<Screen?>(.transactions)
            let view = host(sidebar(selection), width: 240)
            guard let table = tables(in: view).first else { return XCTFail("no source list") }
            XCTAssertEqual(table.style, .sourceList)
            XCTAssertEqual(table.numberOfRows, 6, "three headers, three items")
            XCTAssertTrue(table.delegate!.tableView!(table, isGroupRow: 0))
            XCTAssertEqual(table.selectedRow, 3, "Transactions, under its header")
        }
    }

    func testChoosingInTheSidebarSetsTheBinding() {
        MainActor.assumeIsolated {
            let selection = Box<Screen?>(.users)
            let view = host(sidebar(selection), width: 240)
            let table = tables(in: view)[0]
            table.selectRowIndexes(IndexSet(integer: 5), byExtendingSelection: false)
            XCTAssertEqual(selection.value, .flags)
            XCTAssertFalse(table.delegate!.tableView!(table, shouldSelectRow: 0), "a header isn't chosen")
        }
    }

    // MARK: Table

    private func table(selection: Box<Set<String>>, sort: Box<TableSort?>, opened: Box<String?>,
                       hidden: Set<String> = []) -> Table<User, String> {
        Table(users, id: \.id, selection: selection.binding, sort: sort.binding, hiddenColumns: hidden,
              actions: { user in [ActionItem("Restrict \(user.name)", isDestructive: true) {}] },
              onOpen: { opened.value = $0.id }) {
            TableColumn("Name", sortKey: "name", compact: true) { TableCell($0.name) }
            TableColumn("Email", sortKey: "email") { TableCell($0.email, style: .secondary) }
            TableColumn("Status", width: 110) { TableCell($0.status, style: .badge($0.status == "Active" ? .positive : .warning)) }
        }
    }

    func testTheTableHasItsRowsColumnsAndActions() {
        MainActor.assumeIsolated {
            let view = host(table(selection: Box([]), sort: Box(TableSort("name")), opened: Box(nil)))
            guard let table = tables(in: view).first else { return XCTFail("no table") }
            XCTAssertEqual(table.numberOfRows, 3)
            XCTAssertEqual(table.tableColumns.map(\.title), ["Name", "Email", "Status", ""], "the last is the row's ⋯")
            XCTAssertEqual(table.sortDescriptors.first?.key, "name", "the binding's sort is shown")
            XCTAssertNil(table.tableColumns[2].sortDescriptorPrototype, "Status doesn't sort")
            let actions = table.delegate!.tableView!(table, viewFor: table.tableColumns[3], row: 1) as? ActionMenuButton
            XCTAssertEqual(actions?.provide?().map(\.title), ["Restrict Grace Hopper"], "read when the menu opens")
        }
    }

    /// The screen re-renders on every selection change (each arrow key): the
    /// same rows keep their cells, and only new rows reload them.
    func testTheSameRowsAreNotReloaded() {
        MainActor.assumeIsolated {
            let view = host(table(selection: Box([]), sort: Box(nil), opened: Box(nil)))
            let table = tables(in: view)[0]
            let coordinator = try! XCTUnwrap(table.delegate as? TableCoordinator)
            let shown = try! XCTUnwrap(coordinator.model)
            func model(cells: [[TableCell]], selected: Set<AnyHashable>) -> TableModel {
                TableModel(columns: shown.columns, cells: cells, ids: shown.ids, selected: selected, sort: shown.sort,
                           allowsSelection: shown.allowsSelection, hasActions: shown.hasActions, emptyText: shown.emptyText,
                           onSelect: shown.onSelect, onSort: shown.onSort, onOpen: shown.onOpen, actions: shown.actions)
            }
            let before = table.view(atColumn: 0, row: 0, makeIfNecessary: false)
            XCTAssertNotNil(before)

            coordinator.update(model(cells: shown.cells, selected: ["u2"]))
            XCTAssertTrue(table.view(atColumn: 0, row: 0, makeIfNecessary: false) === before, "the same rows keep their cells")
            XCTAssertEqual(table.selectedRowIndexes, IndexSet(integer: 1), "the selection still follows")

            var changed = shown.cells
            changed[0][0] = TableCell("Ada King")
            coordinator.update(model(cells: changed, selected: ["u2"]))
            table.layoutSubtreeIfNeeded()
            let after = table.view(atColumn: 0, row: 0, makeIfNecessary: true) as? NSTableCellView
            XCTAssertEqual(after?.textField?.stringValue, "Ada King", "changed rows reload")
        }
    }

    /// Server-driven: a header click doesn't reorder the rows, it asks for them.
    func testAHeaderClickAsksForTheSort() {
        MainActor.assumeIsolated {
            let sort = Box<TableSort?>(TableSort("name"))
            let view = host(table(selection: Box([]), sort: sort, opened: Box(nil)))
            let table = tables(in: view)[0]
            table.sortDescriptors = [NSSortDescriptor(key: "email", ascending: false)]
            XCTAssertEqual(sort.value, TableSort("email", ascending: false))
        }
    }

    func testSelectingAndOpeningRows() {
        MainActor.assumeIsolated {
            let selection = Box<Set<String>>(["u3"])
            let opened = Box<String?>(nil)
            let view = host(table(selection: selection, sort: Box(nil), opened: opened))
            let table = tables(in: view)[0]
            XCTAssertEqual(table.selectedRowIndexes, IndexSet(integer: 2), "the binding's selection is shown")

            table.selectRowIndexes(IndexSet([0, 1]), byExtendingSelection: false)
            XCTAssertEqual(selection.value, ["u1", "u2"])

            table.selectRowIndexes(IndexSet(integer: 1), byExtendingSelection: false)
            (table.delegate as? TableCoordinator)?.open()
            XCTAssertEqual(opened.value, "u2")
        }
    }

    func testAHiddenColumnIsNotShown() {
        MainActor.assumeIsolated {
            let view = host(table(selection: Box([]), sort: Box(nil), opened: Box(nil), hidden: ["Email"]))
            XCTAssertEqual(tables(in: view)[0].tableColumns.map(\.title), ["Name", "Status", ""])
        }
    }

    func testAFlagIsShownBesideItsText() {
        MainActor.assumeIsolated {
            let view = TableCoordinator.view(for: TableCell("Grace Hopper", flag: TableCell.Flag("Restricted", tone: .negative)))
            func texts(_ v: NSView) -> [String] { ((v as? NSTextField).map { [$0.stringValue] } ?? []) + v.subviews.flatMap(texts) }
            XCTAssertEqual(texts(view), ["Grace Hopper", "Restricted"])
            XCTAssertEqual((view as? NSTableCellView)?.textField?.stringValue, "Grace Hopper", "the text is the cell's, for type-select and VoiceOver")
        }
    }
}
#endif
