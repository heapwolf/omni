// src/ui/windows/WinSurface.swift
//
// A window omni draws: the app's main window, or a sheet's. It holds a tree
// of WinViews, lays it out to its client area, paints it with Direct2D,
// places the controls in it, and turns the mouse and keyboard into the
// views' taps, presses, drags, scrolls and hovers.

#if os(Windows)
import Foundation
import WinSDK
import CWindows

@MainActor
public final class WinSurface {
    public let hwnd: HWND
    public private(set) var root: WinView?
    private var target: UnsafeMutableRawPointer?
    /// Pixels per point.
    public private(set) var scale: Double = 1
    var minSize: WinSize?
    /// Called when the user closes it.
    var onClose: (() -> Void)?
    /// A sheet's: what's behind it is the owner's.
    weak var owner: WinSurface?
    /// The colour under everything, the window's.
    var backdrop: Color? = nil

    /// Sheets over it, and whether it's dimmed behind them.
    var sheets: [WinSheet] = []
    var dimmed = false { didSet { if dimmed != oldValue { setNeedsDisplay() } } }

    private var needsLayout = true
    private var paintPending = false

    static var all: [HWND: WinSurface] = [:]
    static var main: WinSurface?

    // MARK: Making

    private static let className = Win32.wide("OmniWindow")
    private static var registered = false

    private static func register() {
        guard !registered else { return }
        registered = true
        var wc = WNDCLASSEXW()
        wc.cbSize = UINT(MemoryLayout<WNDCLASSEXW>.size)
        wc.style = UINT(CS_DBLCLKS)
        wc.lpfnWndProc = { hwnd, message, wParam, lParam in
            MainActor.assumeIsolated {
                guard let hwnd else { return 0 }
                if let surface = WinSurface.all[hwnd] {
                    if let result = surface.handle(message, wParam, lParam) { return result }
                }
                return DefWindowProcW(hwnd, message, wParam, lParam)
            }
        }
        wc.hInstance = Win32.instance
        wc.hCursor = Win32.arrowCursor
        // Our own icon, if the build embedded one (resource 1); else Windows'.
        wc.hIcon = LoadIconW(Win32.instance, Win32.resource(1)) ?? LoadIconW(nil, Win32.resource(32512))
        className.withUnsafeBufferPointer { name in
            wc.lpszClassName = name.baseAddress
            _ = RegisterClassExW(&wc)
        }
    }

    /// A top-level window: the app's (owner nil), or a sheet over its owner.
    init(title: String, width: Double, height: Double, resizable: Bool = true, owner: WinSurface? = nil,
         popup: Bool = false) {
        Win32.setUp()
        WinSurface.register()
        let systemScale = Double(GetDpiForSystem()) / 96
        var style = DWORD(WS_OVERLAPPEDWINDOW) | DWORD(WS_CLIPCHILDREN)
        if !resizable { style &= ~(DWORD(WS_THICKFRAME) | DWORD(WS_MAXIMIZEBOX)) }
        if popup { style = DWORD(bitPattern: Int32(bitPattern: 0x8000_0000)) | DWORD(WS_CLIPCHILDREN) } // WS_POPUP
        let made = CreateWindowExW(popup ? DWORD(WS_EX_TOOLWINDOW) : 0, WinSurface.className, Win32.wide(title), style,
                                   Int32(bitPattern: 0x8000_0000), Int32(bitPattern: 0x8000_0000), // CW_USEDEFAULT
                                   Int32(width * systemScale), Int32(height * systemScale),
                                   owner?.hwnd, nil, Win32.instance, nil)!
        hwnd = made
        self.owner = owner
        scale = Double(GetDpiForWindow(made)) / 96
        WinSurface.all[made] = self
        // The client area is the size asked for, not the window with its frame.
        if !popup { resizeClient(width: width, height: height) }
        Win32.applyTitleBarAppearance(made, dark: Appearance.current == .dark)
        target = omni_r_target_create(UnsafeMutableRawPointer(made))
    }

    func resizeClient(width: Double, height: Double) {
        var rect = RECT(left: 0, top: 0, right: LONG(width * scale), bottom: LONG(height * scale))
        _ = AdjustWindowRectExForDpi(&rect, DWORD(GetWindowLongW(hwnd, GWL_STYLE)), false,
                                     DWORD(GetWindowLongW(hwnd, GWL_EXSTYLE)), GetDpiForWindow(hwnd))
        SetWindowPos(hwnd, nil, 0, 0, rect.right - rect.left, rect.bottom - rect.top,
                     UINT(SWP_NOMOVE | SWP_NOZORDER | SWP_NOACTIVATE))
    }

    func destroy() {
        WinSurface.all[hwnd] = nil
        if let target { omni_r_target_destroy(target) }
        target = nil
        if let root { root.rootOf = nil }
        root = nil
        DestroyWindow(hwnd)
    }

    static func forget(_ view: WinView) {
        for surface in all.values {
            if surface.pressed === view { surface.pressed = nil }
            if surface.hovered === view { surface.hovered = nil }
            if surface.focusedView === view { surface.focusedView = nil }
        }
    }

    // MARK: Content

    /// What fills the window: the app's root native, whichever it is now.
    public func setRoot(_ native: NativeView?) {
        let next = native.map(WinView.from)
        if next === root { return }
        root?.rootOf = nil
        root = next
        next?.rootOf = self
        next?.attached()
        setNeedsLayout()
    }

    public var size: WinSize {
        var rect = RECT()
        GetClientRect(hwnd, &rect)
        return WinSize(width: Double(rect.right - rect.left) / scale, height: Double(rect.bottom - rect.top) / scale)
    }

    // MARK: Invalidation

    func setNeedsLayout() {
        needsLayout = true
        setNeedsDisplay()
    }

    func setNeedsDisplay() {
        guard !paintPending else { return }
        paintPending = true
        InvalidateRect(hwnd, nil, false)
    }

    /// Lays out now, if anything changed: before reading a view's frame.
    public func layoutIfNeeded() {
        guard needsLayout, let root else { return }
        needsLayout = false
        let s = size
        root.layout(in: WinRect(x: 0, y: 0, width: s.width, height: s.height))
        root.forEachInSubtree { view in
            view.control?.attachIfNeeded()
            view.control?.position(scale: scale)
        }
        afterLayout.forEach { $0() }
        afterLayout.removeAll()
    }

    /// Run once after the next layout: GeometryReader's sizes, scroll positions.
    var afterLayout: [() -> Void] = []

    private func paint() {
        paintPending = false
        layoutIfNeeded()
        guard let target else { return }
        var ps = PAINTSTRUCT()
        BeginPaint(hwnd, &ps)
        omni_r_begin(target, Float(scale * 96))
        let back = backdrop ?? (Appearance.current == .dark ? Color.rgba(r: 0.12, g: 0.12, b: 0.12, a: 1) : .white)
        let c = back.rgbaComponents
        omni_r_clear(target, Float(c.r), Float(c.g), Float(c.b), Float(c.a))
        let canvas = WinCanvas(target: target)
        WinCanvas.current = canvas
        WinCanvas.currentSurface = self
        wantsFrame = false
        if let root { WinPainter.paint(root, on: canvas) }
        if dimmed {
            canvas.fill(WinRect(x: 0, y: 0, width: size.width, height: size.height), .rgba(r: 0, g: 0, b: 0, a: 0.3))
        }
        WinCanvas.current = nil
        if omni_r_end(target) != 0 {
            // The device went (a driver update, a remote session): drawn again on a new one.
            omni_r_target_destroy(target)
            self.target = omni_r_target_create(UnsafeMutableRawPointer(hwnd))
            InvalidateRect(hwnd, nil, false)
        }
        EndPaint(hwnd, &ps)
        if wantsFrame { scheduleAnimationFrame() }
    }

    // MARK: Animation frames

    /// Set by a view that drew something moving (a spinner) in this paint:
    /// while one is on screen, the window repaints about 60 times a second.
    var wantsFrame = false
    private var frameTimer: UINT_PTR = 0

    private func scheduleAnimationFrame() {
        guard frameTimer == 0 else { return }
        frameTimer = SetTimer(hwnd, 1, 16, nil)
    }

    // MARK: Input state

    private(set) var pressed: WinView?
    private var pressStart: (x: Double, y: Double) = (0, 0)
    private var pressInside = false
    private var dragging = false
    private var hovered: WinView?
    private var tracking = false
    var focusedView: WinView?

    private func point(_ lParam: LPARAM) -> (Double, Double) {
        (Double(Win32.xParam(lParam)) / scale, Double(Win32.yParam(lParam)) / scale)
    }

    private func hit(_ x: Double, _ y: Double) -> WinView? {
        layoutIfNeeded()
        return root?.hitTest(x, y)
    }

    /// The nearest view from `view` up that answers `has`, and isn't disabled.
    private func handler(from view: WinView?, _ has: (WinView) -> Bool) -> WinView? {
        var v = view
        while let current = v {
            if current.disabled == true { return nil }
            if has(current) { return current }
            v = current.parent
        }
        return nil
    }

    private func isPressable(_ v: WinView) -> Bool {
        v.onTap != nil || v.onPress != nil || v.onTapLocation != nil || v.onDrag != nil || v.onKey != nil
    }

    private func mouseDown(_ x: Double, _ y: Double) {
        let target = handler(from: hit(x, y), isPressable)
        if let focusable = handler(from: hit(x, y), { $0.onKey != nil }) {
            focus(focusable)
        } else if GetFocus() != hwnd {
            // A click outside a text field takes the focus from it, as on macOS.
            SetFocus(hwnd)
        }
        guard let target else { return }
        pressed = target
        pressStart = (x, y)
        pressInside = true
        dragging = false
        SetCapture(hwnd)
        target.onPress?(true)
    }

    private func mouseMove(_ x: Double, _ y: Double) {
        if !tracking {
            var event = TRACKMOUSEEVENT()
            event.cbSize = DWORD(MemoryLayout<TRACKMOUSEEVENT>.size)
            event.dwFlags = DWORD(TME_LEAVE)
            event.hwndTrack = hwnd
            TrackMouseEvent(&event)
            tracking = true
        }
        if let pressed {
            let dx = x - pressStart.x, dy = y - pressStart.y
            if pressed.onDrag != nil, dragging || abs(dx) > 3 || abs(dy) > 3 {
                dragging = true
                pressed.onDrag?(dx, dy)
            }
            let f = pressed.windowFrame
            let inside = x >= f.x - pressSlop && x <= f.maxX + pressSlop && y >= f.y - pressSlop && y <= f.maxY + pressSlop
            if inside != pressInside {
                pressInside = inside
                pressed.onPress?(inside)
            }
            return
        }
        updateHover(hit(x, y))
    }

    private func mouseUp(_ x: Double, _ y: Double) {
        // Taken before the capture goes: ReleaseCapture sends WM_CAPTURECHANGED
        // at once, which ends a press it finds still in progress.
        let target = pressed
        pressed = nil
        ReleaseCapture()
        guard let target else { return }
        let dx = x - pressStart.x, dy = y - pressStart.y
        if pressInside { target.onPress?(false) }
        if dragging {
            target.onDragEnded?(dx, dy)
            dragging = false
            return
        }
        let f = target.windowFrame
        guard f.contains(x, y) || (pressInside && target.onPress != nil) else { return }
        if let onTapLocation = target.onTapLocation {
            onTapLocation(x - f.x, y - f.y)
        }
        target.onTap?()
        updateHover(hit(x, y))
    }

    private func updateHover(_ view: WinView?) {
        let next = handler(from: view) { $0.onHover != nil }
        guard next !== hovered else { return }
        hovered?.onHover?(false)
        hovered = next
        next?.onHover?(true)
    }

    private func wheel(_ delta: Double, horizontal: Bool, at x: Double, _ y: Double) {
        // A notch is 120: about three lines of body text, as Windows scrolls.
        let points = -delta / 120 * 48
        var v = hit(x, y)
        while let current = v {
            if let onScrollWheel = current.onScrollWheel {
                onScrollWheel(horizontal ? points : 0, horizontal ? 0 : points)
                return
            }
            if case .scroll(let axis) = current.layout, current.isScrollEnabled {
                let wantsHorizontal = horizontal || axis == .horizontal
                if current.scroll(by: wantsHorizontal ? points : 0, wantsHorizontal ? 0 : points) { return }
            }
            v = current.parent
        }
    }

    // MARK: Focus

    /// A view that takes keys (not a control): focus goes to the window, and its keys to the view.
    func focus(_ view: WinView?) {
        guard focusedView !== view else { return }
        let previous = focusedView
        focusedView = view
        previous?.onFocusChange?(false)
        if view != nil { SetFocus(hwnd) }
        view?.onFocusChange?(true)
    }

    /// Tab: the next control in the window, in the order the views are in.
    func moveFocus(from control: WinControl, backwards: Bool) {
        var controls: [WinControl] = []
        root?.forEachInSubtree { view in
            if let c = view.control, c.hwnd != nil, IsWindowVisible(c.hwnd), IsWindowEnabled(c.hwnd) {
                controls.append(c)
            }
        }
        guard let index = controls.firstIndex(where: { $0 === control }), controls.count > 1 else { return }
        let next = controls[(index + (backwards ? controls.count - 1 : 1)) % controls.count]
        SetFocus(next.hwnd)
        next.scrollIntoView()
    }

    // MARK: Messages

    func handle(_ message: UINT, _ wParam: WPARAM, _ lParam: LPARAM) -> LRESULT? {
        switch Int32(message) {
        case WM_PAINT:
            paint()
            return 0
        case WM_ERASEBKGND:
            return 1
        case WM_SIZE:
            var rect = RECT()
            GetClientRect(hwnd, &rect)
            if let target { omni_r_target_resize(target, UInt32(rect.right - rect.left), UInt32(rect.bottom - rect.top)) }
            setNeedsLayout()
            // Drawn now, not when the loop next idles: a live resize shows each size.
            layoutIfNeeded()
            UpdateWindow(hwnd)
            sheets.forEach { $0.resize() }
            return 0
        case WM_MOVE:
            sheets.forEach { $0.resize() }
            return nil
        case WM_DPICHANGED:
            scale = Double(Win32.hiword(UInt64(wParam))) / 96
            if let suggested = UnsafePointer<RECT>(bitPattern: Int(lParam))?.pointee {
                SetWindowPos(hwnd, nil, suggested.left, suggested.top, suggested.right - suggested.left,
                             suggested.bottom - suggested.top, UINT(SWP_NOZORDER | SWP_NOACTIVATE))
            }
            root?.forEachInSubtree { $0.control?.refreshFont() }
            setNeedsLayout()
            return 0
        case WM_GETMINMAXINFO:
            if let minSize, let info = UnsafeMutablePointer<MINMAXINFO>(bitPattern: Int(lParam)) {
                var rect = RECT(left: 0, top: 0, right: LONG(minSize.width * scale), bottom: LONG(minSize.height * scale))
                _ = AdjustWindowRectExForDpi(&rect, DWORD(GetWindowLongW(hwnd, GWL_STYLE)), false,
                                             DWORD(GetWindowLongW(hwnd, GWL_EXSTYLE)), GetDpiForWindow(hwnd))
                info.pointee.ptMinTrackSize = POINT(x: rect.right - rect.left, y: rect.bottom - rect.top)
            }
            return 0
        case WM_TIMER:
            if wParam == 1 {
                KillTimer(hwnd, frameTimer)
                frameTimer = 0
                setNeedsDisplay()
                return 0
            }
            return WinTimers.fire(UInt(wParam)) ? 0 : nil
        case WM_LBUTTONDOWN, WM_LBUTTONDBLCLK:
            let (x, y) = point(lParam)
            mouseDown(x, y)
            return 0
        case WM_MOUSEMOVE:
            let (x, y) = point(lParam)
            mouseMove(x, y)
            return 0
        case WM_LBUTTONUP:
            let (x, y) = point(lParam)
            mouseUp(x, y)
            return 0
        case WM_RBUTTONUP:
            let (x, y) = point(lParam)
            if let target = handler(from: hit(x, y), { $0.onSecondaryClick != nil }) {
                let f = target.windowFrame
                target.onSecondaryClick?(x - f.x, y - f.y)
            }
            return 0
        case WM_MOUSELEAVE:
            tracking = false
            updateHover(nil)
            return 0
        case WM_CAPTURECHANGED:
            if let pressed, HWND(bitPattern: Int(lParam)) != hwnd {
                if pressInside { pressed.onPress?(false) }
                self.pressed = nil
                dragging = false
            }
            return 0
        case WM_MOUSEWHEEL, WM_MOUSEHWHEEL:
            var pt = POINT(x: LONG(Win32.xParam(lParam)), y: LONG(Win32.yParam(lParam)))
            ScreenToClient(hwnd, &pt)
            let delta = Double(Int16(truncatingIfNeeded: wParam >> 16))
            let horizontal = Int32(message) == WM_MOUSEHWHEEL || (Win32.loword(UInt64(wParam)) & 0x0004) != 0 // MK_SHIFT
            wheel(Int32(message) == WM_MOUSEHWHEEL ? -delta : delta, horizontal: horizontal,
                  at: Double(pt.x) / scale, Double(pt.y) / scale)
            return 0
        case WM_SETCURSOR:
            guard Win32.loword(UInt64(lParam)) == 1 else { return nil } // HTCLIENT
            var pt = POINT()
            GetCursorPos(&pt)
            ScreenToClient(hwnd, &pt)
            let view = hit(Double(pt.x) / scale, Double(pt.y) / scale)
            let named = handler(from: view) { $0.cursor != nil }?.cursor
            SetCursor(Win32.cursor(named: named))
            return 1
        case WM_KEYDOWN where wParam == WPARAM(VK_F12):
            #if DEBUG
            // Debug builds: the view tree as laid out, for finding a layout's mistakes.
            dumpTree()
            return 0
            #else
            return nil
            #endif
        case WM_KEYDOWN, WM_SYSKEYDOWN:
            if let focusedView, let onKey = focusedView.onKey, onKey(UInt32(wParam), true) { return 0 }
            if Int32(wParam) == VK_ESCAPE, let onEscape { onEscape(); return 0 }
            return nil
        case WM_KEYUP:
            if let focusedView, let onKey = focusedView.onKey, onKey(UInt32(wParam), false) { return 0 }
            return nil
        case WM_COMMAND:
            if lParam != 0, let control = WinControl.byHwnd[HWND(bitPattern: Int(lParam))!] {
                control.command(Win32.hiword(UInt64(wParam)))
                return 0
            }
            if lParam == 0 {
                // A menu item or an accelerator.
                if WinMenus.perform(Win32.loword(UInt64(wParam))) { return 0 }
            }
            return nil
        case WM_NOTIFY:
            if let header = UnsafeMutablePointer<NMHDR>(bitPattern: Int(lParam)), let from = header.pointee.hwndFrom,
               let control = WinControl.byHwnd[from] {
                return control.notify(header)
            }
            return nil
        case WM_CTLCOLOREDIT, WM_CTLCOLORSTATIC, WM_CTLCOLORLISTBOX, WM_CTLCOLORBTN:
            if let from = HWND(bitPattern: Int(lParam)), let control = WinControl.byHwnd[from],
               let hdc = HDC(bitPattern: UInt(wParam)), let brush = control.colors(hdc) {
                return LRESULT(Int(bitPattern: brush))
            }
            return nil
        case WM_SETTINGCHANGE:
            Appearance.windowsSettingChanged()
            return nil
        case WM_ACTIVATEAPP:
            AppLifecycle.enter(wParam != 0 ? .foreground : .background)
            return nil
        case WM_CLOSE:
            if let onClose { onClose(); return 0 }
            return nil
        case WM_DESTROY:
            if self === WinSurface.main { PostQuitMessage(0) }
            return 0
        case WM_COPYDATA:
            return WinDeepLinks.received(lParam) ? 1 : 0
        default:
            return nil
        }
    }

    /// Escape: a sheet's dismissal.
    var onEscape: (() -> Void)?

    #if DEBUG
    /// Writes the tree, with each view's frame in the window, its expand flags,
    /// its alignment and what it handles, to %TEMP%\omni-tree.txt.
    func dumpTree() {
        layoutIfNeeded()
        var lines: [String] = ["window \(size.width)x\(size.height) scale \(scale)"]
        func visit(_ v: WinView, _ depth: Int) {
            let f = v.windowFrame
            var flags: [String] = []
            if v.expandsH { flags.append("H") }
            if v.expandsV { flags.append("V") }
            if v.hexpandSet { flags.append("Hset") }
            if v.vexpandSet { flags.append("Vset") }
            if v.onTap != nil { flags.append("tap") }
            if v.onPress != nil { flags.append("press") }
            if !v.hitTesting { flags.append("nohit") }
            if v.isHidden { flags.append("hidden") }
            if case .scroll = v.layout { flags.append("scroll(\(v.scrollOffset.y))") }
            let p = v.padding
            let pad = p.top + p.leading + p.bottom + p.trailing > 0 ? " pad(\(p.top),\(p.leading),\(p.bottom),\(p.trailing))" : ""
            let fixed = (v.fixedWidth.map { " w=\($0)" } ?? "") + (v.fixedHeight.map { " h=\($0)" } ?? "")
            let natural = v.natural(width: nil).width
            let least = v.minimum(along: .horizontal, natural: natural)
            let sizes = " nat=\(Int(natural)) min=\(Int(least))"
            lines.append(String(repeating: "  ", count: depth)
                + "\(v.kind) [\(Int(f.x)),\(Int(f.y)) \(Int(f.width))x\(Int(f.height))] \(v.halign)/\(v.valign)\(pad)\(fixed)\(sizes) \(flags.joined(separator: " "))")
            for child in v.children { visit(child, depth + 1) }
        }
        if let root { visit(root, 0) }
        // Views alive but in no window: a subtree that was detached and not put back.
        let orphans = WinView.live.values.filter { $0.parent == nil && $0.rootOf == nil }
        lines.append("--- \(WinView.live.count) live, \(orphans.count) without a parent")
        for orphan in orphans.prefix(20) { visit(orphan, 1) }
        lines.append("--- journal")
        lines += WinView.journal
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("omni-tree.txt")
        try? lines.joined(separator: "\n").write(to: path, atomically: true, encoding: .utf8)
    }
    #endif
}

extension WinControl {
    /// Scrolls the scroll views it's in so all of it is in sight.
    func scrollIntoView() {
        guard let view else { return }
        var v = view.parent
        while let current = v {
            if case .scroll = current.layout {
                let f = view.windowFrame, viewport = current.windowFrame
                if f.y < viewport.y { current.scroll(by: 0, f.y - viewport.y - 8) }
                else if f.maxY > viewport.maxY { current.scroll(by: 0, f.maxY - viewport.maxY + 8) }
            }
            v = current.parent
        }
        view.surface?.layoutIfNeeded()
    }
}

extension WinCanvas {
    /// The canvas being painted, and its window, for views that measure text as they draw.
    static var current: WinCanvas?
    static weak var currentSurface: WinSurface?
}

/// Timers a view starts (a TimelineView's ticks), fired by the main window's WM_TIMER.
@MainActor
enum WinTimers {
    private static var actions: [UInt: () -> Void] = [:]
    private static var next: UInt = 100

    static func start(interval: Double, _ action: @escaping () -> Void) -> UInt {
        guard let hwnd = WinSurface.main?.hwnd else { return 0 }
        next += 1
        actions[next] = action
        SetTimer(hwnd, UINT_PTR(next), UINT(max(1, interval * 1000)), nil)
        return next
    }

    static func stop(_ id: UInt) {
        actions[id] = nil
        if let hwnd = WinSurface.main?.hwnd { KillTimer(hwnd, UINT_PTR(id)) }
    }

    static func fire(_ id: UInt) -> Bool {
        guard let action = actions[id] else { return false }
        action()
        return true
    }
}
#endif
