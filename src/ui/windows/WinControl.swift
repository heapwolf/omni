// src/ui/windows/WinControl.swift
//
// A Win32 control a WinView holds: an EDIT for a TextField, a COMBOBOX for a
// Picker, WebView2's host for a WebView. It's made once its view is in a
// window (a child window needs a parent to be created in), placed by the
// window after each layout, hidden when scrolled or clipped out of sight,
// and given the window's font and colours.
//
// Subclasses keep what the component last asked for (text, placeholder,
// colours) and apply it when the control exists, so a component's update
// never has to know whether it has been made yet.

#if os(Windows)
import Foundation
import WinSDK

@MainActor
open class WinControl {
    public weak var view: WinView?
    public private(set) var hwnd: HWND?
    weak var surface: WinSurface?
    /// The font the control was last given, at which size and scale.
    private var font: HFONT?
    private var fontKey: (Double, Int, Double)?
    var textStyle = WinTextStyle(size: 13) { didSet { if textStyle != oldValue { refreshFont() } } }
    private var lastRect: RECT?
    private var isShown = false

    static var byHwnd: [HWND: WinControl] = [:]

    public init() {}

    /// The window class and styles: what CreateWindowExW is given.
    open var className: String { "STATIC" }
    open var style: DWORD { DWORD(WS_CHILD) | DWORD(WS_TABSTOP) }
    open var exStyle: DWORD { 0 }

    /// Makes the control's window, a child of the window it's in.
    open func makeWindow(parent: HWND) -> HWND? {
        CreateWindowExW(exStyle, Win32.wide(className), nil, style, 0, 0, 0, 0, parent, nil, Win32.instance, nil)
    }

    /// False for a control whose window procedure isn't ours to wrap (WebView2's host).
    open var wantsSubclass: Bool { true }

    /// Called once the control exists: apply what was asked for so far.
    open func created() {}

    /// Its size in points, given at most `width` across.
    open func naturalSize(width: Double?) -> WinSize? { nil }

    /// WM_COMMAND notifications (EN_CHANGE, CBN_SELCHANGE, BN_CLICKED).
    open func command(_ code: Int) {}

    /// WM_NOTIFY, for the common controls that use it.
    open func notify(_ header: UnsafeMutablePointer<NMHDR>) -> LRESULT? { nil }

    /// WM_CTLCOLOREDIT/STATIC/LISTBOX: the colours to draw with, or nil for Windows'.
    open func colors(_ hdc: HDC) -> HBRUSH? {
        let dark = Appearance.current == .dark
        let text = view?.inheritedForeground ?? (dark ? .white : .black)
        SetTextColor(hdc, Win32.rgb(text))
        let back: Color = dark ? .rgba(r: 0.17, g: 0.17, b: 0.17, a: 1) : .white
        SetBkColor(hdc, Win32.rgb(back))
        return WinControl.brush(for: back)
    }

    private static var brushes: [COLORREF: HBRUSH] = [:]
    static func brush(for color: Color) -> HBRUSH? {
        let ref = Win32.rgb(color)
        if let found = brushes[ref] { return found }
        let made = CreateSolidBrush(ref)
        brushes[ref] = made
        return made
    }

    // MARK: Lifecycle

    func attachIfNeeded() {
        guard let view, let surface = view.surface else { return }
        if let hwnd, self.surface === surface { return }
        if let hwnd {
            // Moved to another window (a sheet's content, rebuilt): follow it.
            SetParent(hwnd, surface.hwnd)
            self.surface = surface
            refreshFont()
            return
        }
        self.surface = surface
        guard let made = makeWindow(parent: surface.hwnd) else { return }
        hwnd = made
        WinControl.byHwnd[made] = self
        if wantsSubclass { subclass(made) }
        if Appearance.current == .dark { applyTheme(dark: true) }
        refreshFont()
        applyEnabled()
        created()
        view.setNeedsLayout()
    }

    func applyTheme(dark: Bool) {
        guard let hwnd else { return }
        _ = SetWindowTheme(hwnd, Win32.wide(dark ? "DarkMode_CFD" : "Explorer"), nil)
    }

    open func destroy() {
        guard let hwnd else { return }
        WinControl.byHwnd[hwnd] = nil
        DestroyWindow(hwnd)
        self.hwnd = nil
        if let font { DeleteObject(font) }
        font = nil
        fontKey = nil
    }

    func hide() {
        guard let hwnd, isShown else { return }
        ShowWindow(hwnd, SW_HIDE)
        isShown = false
    }

    func applyEnabled() {
        guard let hwnd, let view else { return }
        EnableWindow(hwnd, !view.isDisabled)
    }

    /// Placed over its view, in pixels, clipped to what of it can be seen.
    func position(scale: Double) {
        guard let hwnd, let view else { return }
        let full = contentRect(in: view.windowFrame)
        let visible = view.visibleWindowRect.intersection(full)
        if visible.width < 1 || visible.height < 1 || isInvisible(view) {
            hide()
            return
        }
        let rect = RECT(left: LONG((full.x * scale).rounded()), top: LONG((full.y * scale).rounded()),
                        right: LONG((full.maxX * scale).rounded()), bottom: LONG((full.maxY * scale).rounded()))
        if lastRect.map({ $0.left != rect.left || $0.top != rect.top || $0.right != rect.right || $0.bottom != rect.bottom }) ?? true {
            SetWindowPos(hwnd, nil, rect.left, rect.top, rect.right - rect.left, rect.bottom - rect.top,
                         UINT(SWP_NOZORDER | SWP_NOACTIVATE))
            lastRect = rect
            sized()
        }
        // Partly scrolled out: only the visible part shows.
        if visible != full {
            let region = CreateRectRgn(LONG(((visible.x - full.x) * scale).rounded()),
                                       LONG(((visible.y - full.y) * scale).rounded()),
                                       LONG(((visible.maxX - full.x) * scale).rounded()),
                                       LONG(((visible.maxY - full.y) * scale).rounded()))
            SetWindowRgn(hwnd, region, true)
        } else {
            SetWindowRgn(hwnd, nil, true)
        }
        if !isShown {
            ShowWindow(hwnd, SW_SHOWNA)
            isShown = true
        }
    }

    /// Called after the control's size changed.
    open func sized() {}

    private func isInvisible(_ view: WinView) -> Bool {
        var v: WinView? = view
        while let current = v {
            if current.isHidden || current.opacity <= 0.01 { return true }
            v = current.parent
        }
        return false
    }

    // MARK: Font

    func refreshFont() {
        guard let hwnd, let surface else { return }
        let scale = surface.scale
        let key = (textStyle.size, textStyle.weight, scale)
        if let fontKey, fontKey == key { return }
        let made = CreateFontW(-Int32((textStyle.size * scale).rounded()), 0, 0, 0, Int32(textStyle.weight),
                               textStyle.italic ? 1 : 0, 0, 0, DWORD(DEFAULT_CHARSET), DWORD(OUT_DEFAULT_PRECIS),
                               DWORD(CLIP_DEFAULT_PRECIS), DWORD(CLEARTYPE_QUALITY), DWORD(DEFAULT_PITCH),
                               Win32.wide(textStyle.family ?? "Segoe UI"))
        SendMessageW(hwnd, UINT(WM_SETFONT), WPARAM(UInt(bitPattern: Int(bitPattern: made))), 1)
        if let font { DeleteObject(font) }
        font = made
        fontKey = key
        view?.setNeedsLayout()
    }

    /// A line of the control's font, in points: what an edit or a combo box is tall.
    var lineHeight: Double {
        let layout = WinTextLayout("Ag", style: WinTextStyle(family: textStyle.family, size: textStyle.size,
                                                             weight: textStyle.weight), maxWidth: nil)
        return layout.height
    }

    // MARK: Keys

    private var previousProc: WNDPROC?

    /// The control's own window procedure, wrapped: Tab moves focus through
    /// the window's controls, and subclasses see keys first (Return to submit).
    private func subclass(_ hwnd: HWND) {
        let proc: WNDPROC = { hwnd, message, wParam, lParam in
            MainActor.assumeIsolated {
                guard let hwnd, let control = WinControl.byHwnd[hwnd] else { return 0 }
                return control.handle(message, wParam, lParam)
            }
        }
        let previous = SetWindowLongPtrW(hwnd, GWLP_WNDPROC, unsafeBitCast(proc, to: LONG_PTR.self))
        previousProc = unsafeBitCast(previous, to: WNDPROC.self)
    }

    func callDefault(_ message: UINT, _ wParam: WPARAM, _ lParam: LPARAM) -> LRESULT {
        guard let hwnd else { return 0 }
        return CallWindowProcW(previousProc, hwnd, message, wParam, lParam)
    }

    /// Return true to swallow a key.
    open func keyDown(_ key: Int) -> Bool { false }
    open func focusChanged(_ focused: Bool) {}

    func handle(_ message: UINT, _ wParam: WPARAM, _ lParam: LPARAM) -> LRESULT {
        switch Int32(message) {
        case WM_KEYDOWN:
            if Int32(wParam) == VK_TAB {
                surface?.moveFocus(from: self, backwards: GetKeyState(VK_SHIFT) < 0)
                return 0
            }
            if keyDown(Int(wParam)) { return 0 }
        case WM_CHAR:
            // The beep an edit makes for Return and Tab it doesn't take.
            if wParam == 13 || wParam == 9 || wParam == 27 { return 0 }
        case WM_GETDLGCODE:
            return callDefault(message, wParam, lParam) | LRESULT(DLGC_WANTALLKEYS)
        case WM_SETFOCUS:
            focusChanged(true)
        case WM_KILLFOCUS:
            focusChanged(false)
        case WM_MOUSEWHEEL:
            // A control that doesn't scroll gives the wheel to the window, so the
            // form it's in scrolls under the pointer.
            if !scrollsItself {
                if let parent = surface?.hwnd { return SendMessageW(parent, message, wParam, lParam) }
            }
        default:
            break
        }
        return callDefault(message, wParam, lParam)
    }

    open var scrollsItself: Bool { false }

    /// The control's text, as Windows has it.
    var windowText: String {
        guard let hwnd else { return "" }
        let length = GetWindowTextLengthW(hwnd)
        var buffer = [WCHAR](repeating: 0, count: Int(length) + 1)
        _ = GetWindowTextW(hwnd, &buffer, length + 1)
        return String(decoding: buffer.prefix(Int(length)), as: UTF16.self)
    }

    func setWindowText(_ text: String) {
        guard let hwnd else { return }
        _ = SetWindowTextW(hwnd, Win32.wide(text))
    }
}
#endif
