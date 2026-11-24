// src/ui/windows/WinApp.swift
//
// The app on Windows: its window, the loop that runs it, its menu bar, and
// links (onedosh-admin://…) arriving at a running copy.

#if os(Windows)
import Foundation
import WinSDK
import CWindows

@MainActor
enum WinApp {
    /// Opens the app's window with the root in it and runs until it closes.
    static func run(_ config: WindowConfig) {
        Win32.setUp()
        Appearance.windowsSettingChanged()
        let surface = WinSurface(title: config.title, width: config.width, height: config.height,
                                 resizable: config.isResizable)
        WinSurface.main = surface
        Window.mainWindow = UnsafeMutableRawPointer(surface.hwnd)
        if let minWidth = config.minWidth, let minHeight = config.minHeight {
            surface.minSize = WinSize(width: minWidth, height: minHeight)
        } else if config.minWidth != nil || config.minHeight != nil {
            surface.minSize = WinSize(width: config.minWidth ?? 0, height: config.minHeight ?? 0)
        }
        surface.onClose = {
            config.onClose?()
            surface.destroy()
        }
        // The root goes in the window, and again whenever it changes.
        Engine.rootHost = { native in surface.setRoot(native) }
        surface.setRoot(Engine.root?.native)
        WinMenus.install(on: surface)
        WinDeepLinks.listen()

        if config.isVisible {
            ShowWindow(surface.hwnd, SW_SHOWDEFAULT)
            UpdateWindow(surface.hwnd)
            Window.isVisible = true
        }
        config.onAppear?()
        runLoop()
    }

    /// Win32 messages, the main dispatch queue (MainActor tasks, `.task`,
    /// DispatchQueue.main.async, every re-render after a @Published change),
    /// and Foundation's timers, in one loop. A bare GetMessage loop runs only
    /// the first: nothing queued for the main thread would ever run.
    static func runLoop() {
        let queue = omni_main_queue_handle()
        var message = MSG()
        while true {
            while PeekMessageW(&message, nil, 0, 0, UINT(PM_REMOVE)) {
                if message.message == UINT(WM_QUIT) { return }
                if WinMenus.translate(&message) { continue }
                TranslateMessage(&message)
                DispatchMessageW(&message)
            }
            omni_main_queue_drain()
            // Fires the timers that are due, and says when the next one is.
            let next = RunLoop.main.limitDate(forMode: .default)
            // Work the drain queued for the main thread runs before waiting.
            omni_main_queue_drain()
            var timeout = DWORD(INFINITE)
            if let next {
                let ms = next.timeIntervalSinceNow * 1000
                timeout = ms <= 0 ? 0 : DWORD(min(ms.rounded(.up), 60_000))
            }
            var handles: [HANDLE?] = [queue.map { HANDLE($0) }].compactMap { $0 }
            let count = DWORD(handles.count)
            _ = handles.withUnsafeMutableBufferPointer { buffer in
                MsgWaitForMultipleObjectsEx(count, buffer.baseAddress, timeout, DWORD(QS_ALLINPUT),
                                            DWORD(MWMO_INPUTAVAILABLE))
            }
        }
    }

    static func dismissKeyboard() {
        if let hwnd = WinSurface.main?.hwnd { SetFocus(hwnd) }
    }

    static func quit() {
        PostQuitMessage(0)
    }
}

// MARK: - The menu bar

/// The app's `.commands`, as Windows' menu bar: File (the app's own items,
/// then the File menu's, then Exit), Edit (for the focused text field), each
/// other menu, Help. ⌘ shortcuts are Ctrl ones.
@MainActor
enum WinMenus {
    private static var actions: [Int: () -> Void] = [:]
    private static var accelerators: HACCEL?
    private static var signature = ""
    private static weak var surface: WinSurface?
    private static var pending: [any View]?

    private enum Edit: Int {
        case undo = 0xE101, cut, copy, paste, delete, selectAll
    }
    private static let exitID = 0xE001

    static func install(on surface: WinSurface) {
        self.surface = surface
        if let pending { update(pending) }
    }

    /// Called as the app's body renders, with the menus it declares.
    static func update(_ menus: [any View]) {
        guard let surface else { pending = menus; return }
        pending = nil
        var nextActions: [Int: () -> Void] = [:]
        var keys: [ACCEL] = []
        var id = 1
        var description = ""

        func items(_ views: [any View]) -> [any View] {
            views.flatMap { view -> [any View] in
                if let identified = view as? IdentifiedView { return items(Omni.unpackViews(identified.content)) }
                if let structural = view as? any OmniStructuralView, !(view is Menu) {
                    return items(structural.unpacked)
                }
                return [view]
            }
        }

        func fill(_ menu: HMENU, with views: [any View]) {
            for view in items(views) {
                if view is MenuDivider {
                    AppendMenuW(menu, UINT(MF_SEPARATOR), 0, nil)
                    description += "-|"
                    continue
                }
                guard let action = view as? MenuAction else { continue }
                let shortcut = action.shortcut.map { accelerator($0, action.modifiers) } ?? nil
                let label = action.title + (shortcut.map { "\t" + $0.label } ?? "")
                var flags = UINT(MF_STRING)
                if !action.isEnabled { flags |= UINT(MF_GRAYED) }
                AppendMenuW(menu, flags, UINT_PTR(id), Win32.wide(label))
                if action.isEnabled {
                    nextActions[id] = action.action
                    if var key = shortcut?.accel {
                        key.cmd = WORD(id)
                        keys.append(key)
                    }
                }
                description += "\(label)\(action.isEnabled)|"
                id += 1
            }
        }

        let declared = items(menus).compactMap { $0 as? Menu }
        func custom(_ title: String) -> Menu? { declared.first { !$0.isApplication && $0.title == title } }

        let bar = CreateMenu()!
        let file = CreatePopupMenu()!
        let appItems = declared.filter(\.isApplication).flatMap(\.items)
        fill(file, with: appItems)
        if let fileMenu = custom("File") {
            if !appItems.isEmpty { AppendMenuW(file, UINT(MF_SEPARATOR), 0, nil) }
            fill(file, with: fileMenu.items)
        }
        if GetMenuItemCount(file) > 0 { AppendMenuW(file, UINT(MF_SEPARATOR), 0, nil) }
        AppendMenuW(file, UINT(MF_STRING), UINT_PTR(exitID), Win32.wide("Exit\tAlt+F4"))
        AppendMenuW(bar, UINT(MF_POPUP), UINT_PTR(UInt(bitPattern: Int(bitPattern: file))), Win32.wide("&File"))

        let edit = CreatePopupMenu()!
        for (title, item) in [("&Undo\tCtrl+Z", Edit.undo), ("-", .undo), ("Cu&t\tCtrl+X", .cut), ("&Copy\tCtrl+C", .copy),
                              ("&Paste\tCtrl+V", .paste), ("&Delete\tDel", .delete), ("-", .undo),
                              ("Select &All\tCtrl+A", .selectAll)] {
            if title == "-" { AppendMenuW(edit, UINT(MF_SEPARATOR), 0, nil) }
            else { AppendMenuW(edit, UINT(MF_STRING), UINT_PTR(item.rawValue), Win32.wide(title)) }
        }
        if let editMenu = custom("Edit") {
            AppendMenuW(edit, UINT(MF_SEPARATOR), 0, nil)
            fill(edit, with: editMenu.items)
        }
        AppendMenuW(bar, UINT(MF_POPUP), UINT_PTR(UInt(bitPattern: Int(bitPattern: edit))), Win32.wide("&Edit"))

        for menu in declared where !menu.isApplication && !["File", "Edit", "Help"].contains(menu.title) {
            let popup = CreatePopupMenu()!
            description += "[\(menu.title)]"
            fill(popup, with: menu.items)
            AppendMenuW(bar, UINT(MF_POPUP), UINT_PTR(UInt(bitPattern: Int(bitPattern: popup))), Win32.wide(menu.title))
        }
        if let help = custom("Help") {
            let popup = CreatePopupMenu()!
            fill(popup, with: help.items)
            AppendMenuW(bar, UINT(MF_POPUP), UINT_PTR(UInt(bitPattern: Int(bitPattern: popup))), Win32.wide("&Help"))
        }

        actions = nextActions
        guard description != signature else {
            DestroyMenu(bar)
            return
        }
        signature = description
        let old = GetMenu(surface.hwnd)
        SetMenu(surface.hwnd, bar)
        if let old { DestroyMenu(old) }
        if let accelerators { DestroyAcceleratorTable(accelerators) }
        accelerators = keys.isEmpty ? nil : keys.withUnsafeMutableBufferPointer {
            CreateAcceleratorTableW($0.baseAddress, Int32($0.count))
        }
        DrawMenuBar(surface.hwnd)
        surface.setNeedsLayout()
    }

    /// A shortcut as Windows writes it, and the accelerator for it.
    private static func accelerator(_ key: String, _ modifiers: EventModifiers) -> (label: String, accel: ACCEL)? {
        guard let character = key.uppercased().unicodeScalars.first else { return nil }
        var virtualKey: Int
        var name = String(character)
        switch character {
        case "A"..."Z", "0"..."9": virtualKey = Int(character.value)
        case ",": virtualKey = 0xBC; name = ","   // VK_OEM_COMMA
        case ".": virtualKey = 0xBE; name = "."
        case "/": virtualKey = 0xBF; name = "/"
        case "-": virtualKey = 0xBD; name = "-"
        case "=", "+": virtualKey = 0xBB; name = "+"
        case "[": virtualKey = 0xDB; name = "["
        case "]": virtualKey = 0xDD; name = "]"
        case "\r", "\n": virtualKey = Int(VK_RETURN); name = "Enter"
        case "\u{1B}": virtualKey = Int(VK_ESCAPE); name = "Esc"
        default: return nil
        }
        var flags = BYTE(FVIRTKEY)
        var label = ""
        if modifiers.contains(.command) || modifiers.contains(.control) { flags |= BYTE(FCONTROL); label += "Ctrl+" }
        if modifiers.contains(.option) { flags |= BYTE(FALT); label += "Alt+" }
        if modifiers.contains(.shift) { flags |= BYTE(FSHIFT); label += "Shift+" }
        return (label + name, ACCEL(fVirt: flags, key: WORD(virtualKey), cmd: 0))
    }

    /// The menu's shortcuts, before the focused control sees the key.
    static func translate(_ message: inout MSG) -> Bool {
        guard let accelerators, let hwnd = surface?.hwnd else { return false }
        // Only the main window's: a sheet's keys are its own.
        guard message.hwnd == hwnd || IsChild(hwnd, message.hwnd) else { return false }
        return TranslateAcceleratorW(hwnd, accelerators, &message) != 0
    }

    static func perform(_ id: Int) -> Bool {
        if id == exitID {
            if let hwnd = surface?.hwnd { SendMessageW(hwnd, UINT(WM_CLOSE), 0, 0) }
            return true
        }
        if let edit = Edit(rawValue: id) {
            let message: Int32
            switch edit {
            case .undo: message = WM_UNDO
            case .cut: message = WM_CUT
            case .copy: message = WM_COPY
            case .paste: message = WM_PASTE
            case .delete: message = WM_CLEAR
            case .selectAll: message = EM_SETSEL
            }
            if let focused = GetFocus() {
                if edit == .selectAll { SendMessageW(focused, UINT(message), 0, -1) }
                else { SendMessageW(focused, UINT(message), 0, 0) }
            }
            return true
        }
        guard let action = actions[id] else { return false }
        action()
        return true
    }
}

// MARK: - Links into a running app

/// A link that opened a second copy of the app is handed to the first, which
/// is the one that receives it, as on macOS: the second copy sends it in a
/// WM_COPYDATA and exits.
@MainActor
enum WinDeepLinks {
    private static let tag: ULONG_PTR = 0x6F6D6E69 // "omni"

    /// Called before the window opens: true if another copy has the link now
    /// and this one should exit.
    static func handOff(_ url: URL?) -> Bool {
        let name = Win32.wide("Local\\omni-" + (Engine.appName ?? "app").filter { $0.isLetter || $0.isNumber })
        _ = CreateMutexW(nil, true, name)
        guard GetLastError() == DWORD(ERROR_ALREADY_EXISTS) else { return false }
        guard let window = FindWindowW(Win32.wide("OmniWindow"), Win32.wide(Engine.appName ?? "")) else { return false }
        SetForegroundWindow(window)
        guard let url else { return true }
        var bytes = Array(url.absoluteString.utf8)
        bytes.withUnsafeMutableBytes { buffer in
            var data = COPYDATASTRUCT(dwData: tag, cbData: DWORD(buffer.count), lpData: buffer.baseAddress)
            _ = withUnsafeMutablePointer(to: &data) { pointer in
                SendMessageW(window, UINT(WM_COPYDATA), 0, LPARAM(Int(bitPattern: pointer)))
            }
        }
        return true
    }

    static func listen() {}

    static func received(_ lParam: LPARAM) -> Bool {
        guard let data = UnsafePointer<COPYDATASTRUCT>(bitPattern: Int(lParam))?.pointee,
              data.dwData == tag, let bytes = data.lpData else { return false }
        let text = String(decoding: UnsafeRawBufferPointer(start: bytes, count: Int(data.cbData)), as: UTF8.self)
        if let url = URL(string: text) { DeepLink.receive(url) }
        return true
    }
}
#endif
