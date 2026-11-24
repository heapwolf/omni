// src/ui/windows/WinSheet.swift
//
// A sheet on Windows is what Windows 11 calls a content dialog: a rounded
// panel centred over the window, which dims and takes no input while it's
// up. It's a window of its own (a popup the main window owns), so it is
// above the main window's text fields and web views too, which no drawing
// in the main window could be.
//
// Its height is the first detent's, as macOS's sheet is (PresentationOptions'
// sheetSize there): .large the window's, .medium half, a fitted one the
// content's own height at the sheet's width.

#if os(Windows)
import Foundation
import WinSDK

@MainActor
final class WinSheet {
    let surface: WinSurface
    weak var owner: WinSurface?
    private let options: () -> PresentationOptions
    var onDismiss: (() -> Void)?
    private var isDismissed = false

    init(content: NativeView, options: @escaping () -> PresentationOptions, over owner: WinSurface?) {
        self.owner = owner
        self.options = options
        surface = WinSurface(title: "", width: 480, height: 320, owner: owner, popup: true)
        surface.setRoot(content)
        let opts = options()
        surface.backdrop = opts.background ?? Color(light: .white, dark: .rgba(r: 0.17, g: 0.17, b: 0.17, a: 1))
        // Windows 11's rounded corners and shadow for a popup.
        var corner: Int32 = 2 // DWMWCP_ROUND
        _ = DwmSetWindowAttribute(surface.hwnd, DWORD(33), &corner, DWORD(MemoryLayout<Int32>.size))
        var margins = MARGINS(cxLeftWidth: 1, cxRightWidth: 1, cyTopHeight: 1, cyBottomHeight: 1)
        _ = DwmExtendFrameIntoClientArea(surface.hwnd, &margins)
        surface.onEscape = { [weak self] in self?.dismissIfAllowed() }
        surface.onClose = { [weak self] in self?.dismissIfAllowed() }
    }

    func present() {
        guard let owner else { return }
        owner.sheets.append(self)
        owner.dimmed = true
        resize()
        // Modal: the window behind takes no clicks or keys until it's dismissed.
        EnableWindow(owner.hwnd, false)
        ShowWindow(surface.hwnd, SW_SHOW)
        SetForegroundWindow(surface.hwnd)
        SetFocus(surface.hwnd)
    }

    func setContent(_ native: NativeView) {
        surface.setRoot(native)
        resize()
    }

    /// Sized and centred over its owner's client area.
    func resize() {
        guard let owner, !isDismissed else { return }
        let area = owner.size
        let opts = options()
        let margin = 32.0
        let maxWidth = max(200, area.width - margin * 2)
        let maxHeight = max(120, area.height - margin * 2)
        let natural = surface.root?.natural(width: nil) ?? .zero
        let width = min(maxWidth, max(440, min(natural.width, 760)))
        let height: Double
        switch opts.orderedDetents.first?.kind ?? .large {
        case .large: height = maxHeight
        case .medium: height = maxHeight * 0.5
        case .fraction(let fraction): height = maxHeight * fraction
        case .height(let points): height = points
        case .fitted: height = surface.root?.natural(width: width).height ?? maxHeight
        }
        let h = min(max(height, 120), maxHeight)
        var origin = POINT(x: LONG(((area.width - width) / 2) * owner.scale), y: LONG(((area.height - h) / 2) * owner.scale))
        ClientToScreen(owner.hwnd, &origin)
        SetWindowPos(surface.hwnd, nil, origin.x, origin.y, Int32(width * owner.scale), Int32(h * owner.scale),
                     UINT(SWP_NOZORDER | SWP_NOACTIVATE))
        surface.setNeedsLayout()
    }

    private func dismissIfAllowed() {
        if options().interactiveDismissDisabled == true { return }
        onDismiss?()
    }

    func dismiss() {
        guard !isDismissed else { return }
        isDismissed = true
        if let owner {
            owner.sheets.removeAll { $0 === self }
            owner.dimmed = !owner.sheets.isEmpty
            // Before the sheet goes, or Windows activates another app's window.
            if owner.sheets.isEmpty { EnableWindow(owner.hwnd, true) }
            SetForegroundWindow(owner.hwnd)
        }
        surface.setRoot(nil)
        surface.destroy()
    }
}

// MARK: - Alerts

/// An alert as Windows' task dialog: the title as the main instruction, the
/// message under it, a button per action. The cancel action is also Escape
/// and the close box.
@MainActor
enum WinAlert {
    typealias TaskDialogIndirect = @convention(c) (UnsafePointer<TASKDIALOGCONFIG>?, UnsafeMutablePointer<Int32>?,
                                                   UnsafeMutablePointer<Int32>?, UnsafeMutablePointer<WindowsBool>?) -> HRESULT

    /// Common Controls 6's, looked up once the app's activation context asks
    /// for that version (Win32.setUp). Imported directly, the .exe would bind
    /// to System32's version 5, which has no task dialog, and not start at all.
    static let taskDialogIndirect: TaskDialogIndirect? = {
        guard let module = LoadLibraryW(Win32.wide("comctl32.dll")),
              let symbol = GetProcAddress(module, "TaskDialogIndirect") else { return nil }
        return unsafeBitCast(symbol, to: TaskDialogIndirect.self)
    }()

    /// The index of the action chosen, or nil if it was cancelled with none.
    static func run(title: String, message: String?, actions: [AlertAction], owner: WinSurface?) -> Int? {
        var strings: [UnsafeMutablePointer<WCHAR>] = []
        defer { strings.forEach { $0.deallocate() } }
        func wide(_ text: String) -> UnsafeMutablePointer<WCHAR> {
            let units = Win32.wide(text)
            let pointer = UnsafeMutablePointer<WCHAR>.allocate(capacity: units.count)
            pointer.initialize(from: units, count: units.count)
            strings.append(pointer)
            return pointer
        }

        // Ids from 100, so none is taken for IDCANCEL (2).
        var buttons = actions.enumerated().map { index, action in
            TASKDIALOG_BUTTON(nButtonID: Int32(100 + index), pszButtonText: UnsafePointer(wide(action.title)))
        }
        let cancelIndex = actions.firstIndex { $0.role == .cancel }

        var config = TASKDIALOGCONFIG()
        config.cbSize = UINT(MemoryLayout<TASKDIALOGCONFIG>.size)
        config.hwndParent = owner?.hwnd
        config.hInstance = Win32.instance
        config.dwFlags = TASKDIALOG_FLAGS(TDF_POSITION_RELATIVE_TO_WINDOW.rawValue
                                          | (cancelIndex != nil ? TDF_ALLOW_DIALOG_CANCELLATION.rawValue : 0))
        config.pszWindowTitle = UnsafePointer(wide(Engine.appName ?? ""))
        config.pszMainInstruction = UnsafePointer(wide(title))
        if let message { config.pszContent = UnsafePointer(wide(message)) }
        var pressed: Int32 = 0
        let result = buttons.withUnsafeMutableBufferPointer { buffer -> HRESULT in
            config.cButtons = UINT(buffer.count)
            config.pButtons = UnsafePointer(buffer.baseAddress)
            config.nDefaultButton = Int32(100 + (actions.firstIndex { $0.role != .cancel } ?? 0))
            guard let taskDialog = WinAlert.taskDialogIndirect else { return -1 }
            return taskDialog(&config, &pressed, nil, nil)
        }
        // No task dialog (Common Controls 5): the cancel action, as if dismissed.
        guard result >= 0 else { return cancelIndex }
        if pressed == 2 { return cancelIndex } // IDCANCEL: Escape or the close box
        let index = Int(pressed) - 100
        return actions.indices.contains(index) ? index : cancelIndex
    }
}
#endif
