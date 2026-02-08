// Menus.swift
import Foundation

#if os(macOS)
    import AppKit
#elseif os(Linux)
    import Glibc
#endif

// MARK: - Declarative API

public struct Menu: View {
    public var title: String
    public var content: any View
    /// Its items go in the application menu, after About, rather than a menu of their own.
    public var isApplication = false
    @MainActor public var items: [any View] { Omni.unpackViews(content) }

    public typealias Body = Never
    public var body: Never { fatalError("Menu is parsed directly by the Engine") }

    public init(_ title: String, @ViewBuilder content: @escaping () -> any View) {
        self.title = title
        self.content = content()
    }

    /// Items for the application menu (the app's name), after About: Settings, an account.
    public init(applicationItems content: @escaping () -> any View) {
        self.title = ""
        self.content = content()
        self.isApplication = true
    }
}

/// The keys held with a shortcut. ⌘ alone unless said.
public struct EventModifiers: OptionSet, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static let command = EventModifiers(rawValue: 1)
    public static let shift = EventModifiers(rawValue: 2)
    public static let option = EventModifiers(rawValue: 4)
    public static let control = EventModifiers(rawValue: 8)
}

public struct MenuAction: View {
    public var title: String
    public var shortcut: String?
    public var modifiers: EventModifiers
    public var isEnabled: Bool
    public var action: () -> Void

    public typealias Body = Never
    public var body: Never { fatalError("MenuAction is parsed directly by the Engine") }

    public init(_ title: String, shortcut: String? = nil, modifiers: EventModifiers = .command, isEnabled: Bool = true,
                action: @escaping () -> Void) {
        self.title = title
        self.shortcut = shortcut
        self.modifiers = modifiers
        self.isEnabled = isEnabled
        self.action = action
    }
}

/// A line between a menu's groups of items.
public struct MenuDivider: View {
    public init() {}
    public typealias Body = Never
    public var body: Never { fatalError("MenuDivider is parsed directly by the Engine") }
}

public struct CommandWrapper: View {
    public var content: any View
    public var menusContent: any View
    @MainActor public var menus: [any View] { Omni.unpackViews(menusContent) }

    public init(content: any View, menus: any View) {
        self.content = content
        self.menusContent = menus
    }

    public typealias Body = Never
    public var body: Never { fatalError("Engine unpacks CommandWrapper dynamically") }
}

public extension View {
    func commands(@ViewBuilder _ menus: @escaping () -> any View) -> some View {
        CommandWrapper(content: self, menus: menus())
    }
}

// MARK: - macOS Implementation

#if os(macOS)
    @MainActor
    class StatusBarManager {
        static let shared = StatusBarManager()
        var statusItem: NSStatusItem?

        func setup(config: TrayConfig) {
            // Create the system tray item
            statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

            if let button = statusItem?.button {
                // Support SF Symbols (like "star.fill") or fallback to asset names
                button.image = NSImage(systemSymbolName: config.icon, accessibilityDescription: nil)
                               ?? NSImage(named: config.icon)
            }

            // Build the native menu
            let trayMenu = NSMenu()
            let views = Omni.unpackViews(config.menu())

            for view in views {
                for item in menuItems([view]).compactMap(nativeItem) { trayMenu.addItem(item) }
            }

            statusItem?.menu = trayMenu
        }
    }

    class ActionMenuItem: NSMenuItem, NSMenuItemValidation {
        var actionClosure: (() -> Void)?
        var isAvailable = true
        @objc func performAction() { actionClosure?() }
        func validateMenuItem(_ menuItem: NSMenuItem) -> Bool { isAvailable }
    }

    /// The menu bar has been set by the app (a `.commands`), not the default.
    @MainActor var hasAppMenus = false

    /// A menu's items, a ForEach's too: it wraps each in its identity.
    @MainActor func menuItems(_ views: [any View]) -> [any View] {
        views.flatMap { view -> [any View] in
            guard let identified = view as? IdentifiedView else { return [view] }
            return menuItems(Omni.unpackViews(identified.content))
        }
    }

    @MainActor private func nativeItem(_ view: any View) -> NSMenuItem? {
        if view is MenuDivider { return .separator() }
        guard let action = view as? MenuAction else { return nil }
        let item = ActionMenuItem(title: action.title, action: #selector(ActionMenuItem.performAction),
                                  keyEquivalent: action.shortcut.map { $0.lowercased() } ?? "")
        var mask: NSEvent.ModifierFlags = []
        if action.modifiers.contains(.command) { mask.insert(.command) }
        if action.modifiers.contains(.shift) { mask.insert(.shift) }
        if action.modifiers.contains(.option) { mask.insert(.option) }
        if action.modifiers.contains(.control) { mask.insert(.control) }
        item.keyEquivalentModifierMask = mask
        item.target = item
        item.actionClosure = action.action
        item.isAvailable = action.isEnabled
        return item
    }

    @MainActor private func standard(_ title: String, _ selector: String, _ key: String = "",
                                     _ mask: NSEvent.ModifierFlags = .command) -> NSMenuItem {
        // No target: the first responder answers (a text field copies), and
        // AppKit enables it only when something can.
        let item = NSMenuItem(title: title, action: Selector(selector), keyEquivalent: key)
        item.keyEquivalentModifierMask = mask
        return item
    }

    /// The menu bar, as macOS orders it: the application menu (About, the
    /// app's own items, Services, Hide, Quit), File (the app's, then Close),
    /// Edit (Undo to Select All: without it, ⌘C and ⌘V do nothing in a text
    /// field), the app's other menus, Window, then Help if the app has one.
    /// A menu of the app's titled "Edit" or "Window" adds to the standard one.
    @MainActor public func updateMacOSMenu(menus: [any View]) {
        let name = Engine.appName ?? ProcessInfo.processInfo.processName
        let declared = menus.compactMap { $0 as? Menu }
        func custom(_ title: String) -> Menu? { declared.first { !$0.isApplication && $0.title == title } }
        func items(of menu: Menu?) -> [NSMenuItem] { menu.map { menuItems($0.items).compactMap(nativeItem) } ?? [] }
        func submenu(_ title: String, _ items: [NSMenuItem]) -> NSMenuItem {
            let top = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            let menu = NSMenu(title: title)
            for item in items { menu.addItem(item) }
            top.submenu = menu
            return top
        }
        let mainMenu = NSMenu()

        var app = [standard("About \(name)", "orderFrontStandardAboutPanel:", "", [])]
        let appItems = menuItems(declared.filter(\.isApplication).flatMap(\.items)).compactMap(nativeItem)
        if !appItems.isEmpty { app += [.separator()] + appItems }
        let services = NSMenuItem(title: "Services", action: nil, keyEquivalent: "")
        services.submenu = NSMenu(title: "Services")
        NativeApp.shared.servicesMenu = services.submenu
        app += [.separator(), services, .separator(),
                standard("Hide \(name)", "hide:", "h"), standard("Hide Others", "hideOtherApplications:", "h", [.command, .option]),
                standard("Show All", "unhideAllApplications:"), .separator(),
                standard("Quit \(name)", "terminate:", "q")]
        mainMenu.addItem(submenu(name, app))

        let file = items(of: custom("File"))
        mainMenu.addItem(submenu("File", file + (file.isEmpty ? [] : [.separator()]) + [standard("Close", "performClose:", "w")]))

        var edit = [standard("Undo", "undo:", "z"), standard("Redo", "redo:", "z", [.command, .shift]), .separator(),
                    standard("Cut", "cut:", "x"), standard("Copy", "copy:", "c"), standard("Paste", "paste:", "v"),
                    standard("Delete", "delete:", "", []), standard("Select All", "selectAll:", "a")]
        let editExtra = items(of: custom("Edit"))
        if !editExtra.isEmpty { edit += [.separator()] + editExtra }
        mainMenu.addItem(submenu("Edit", edit))

        for menu in declared where !menu.isApplication && !["File", "Edit", "Window", "Help"].contains(menu.title) {
            mainMenu.addItem(submenu(menu.title, menuItems(menu.items).compactMap(nativeItem)))
        }

        var window = [standard("Minimize", "performMiniaturize:", "m"), standard("Zoom", "performZoom:", "", [])]
        let windowExtra = items(of: custom("Window"))
        if !windowExtra.isEmpty { window += [.separator()] + windowExtra }
        window += [.separator(), standard("Bring All to Front", "arrangeInFront:", "", [])]
        let windowItem = submenu("Window", window)
        mainMenu.addItem(windowItem)
        NativeApp.shared.windowsMenu = windowItem.submenu

        if let help = custom("Help") {
            let item = submenu("Help", menuItems(help.items).compactMap(nativeItem))
            mainMenu.addItem(item)
            NativeApp.shared.helpMenu = item.submenu
        }

        NativeApp.shared.mainMenu = mainMenu
        if !menus.isEmpty { hasAppMenus = true }
    }
#endif

// MARK: - Linux / GTK Implementation

#if os(Linux)
    class ClosureBox {
        let closure: () -> Void
        init(_ closure: @escaping () -> Void) { self.closure = closure }
    }

    func bindLinuxMenuAction(_ widget: NativeView, _ action: @escaping () -> Void) {
        let box = Unmanaged.passRetained(ClosureBox(action)).toOpaque()

        let callback: @convention(c) (NativeView, UnsafeMutableRawPointer) -> Void = { _, data in
            Unmanaged<ClosureBox>.fromOpaque(data).takeUnretainedValue().closure()
        }

        let destroy: @convention(c) (UnsafeMutableRawPointer, UnsafeMutableRawPointer?) -> Void = { data, _ in
            Unmanaged<ClosureBox>.fromOpaque(data).release()
        }

        g_signal_connect_data(widget, "activate", unsafeBitCast(callback, to: UnsafeMutableRawPointer.self), box, unsafeBitCast(destroy, to: UnsafeMutableRawPointer.self), 0)
    }

    @MainActor public func updateLinuxMenu(box: NativeView, menus: [any View], nodeId: ObjectIdentifier) {
        if let existing = Tracker.linuxMenuBars[nodeId] {
            gtk_widget_destroy(existing)
        }

        let menuBar = gtk_menu_bar_new()
        Tracker.linuxMenuBars[nodeId] = menuBar

        for view in menus {
            if let menu = view as? Menu {
                // C strings must be null-terminated
                let topItem = gtk_menu_item_new_with_label(menu.title)
                let subMenu = gtk_menu_new()

                for item in menu.items {
                    if let actionItem = item as? MenuAction {
                        // GTK accelerators require binding to the GtkWindow's accel group.
                        // For this POC, we format the label to display the Ctrl shortcut visually.
                        let labelText = actionItem.shortcut != nil ? "\(actionItem.title)\tCtrl+\(actionItem.shortcut!.uppercased())" : actionItem.title

                        let gtkItem = gtk_menu_item_new_with_label(labelText)
                        bindLinuxMenuAction(gtkItem, actionItem.action)
                        gtk_menu_shell_append(subMenu, gtkItem)
                    }
                }

                gtk_menu_item_set_submenu(topItem, subMenu)
                gtk_menu_shell_append(menuBar, topItem)
            }
        }

        gtk_box_pack_start(box, menuBar, 0, 0, 0)
        gtk_widget_show_all(menuBar)
    }
#endif
