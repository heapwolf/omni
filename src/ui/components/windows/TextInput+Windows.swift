// src/ui/components/windows/TextInput+Windows.swift
//
// TextField, SecureField and TextEditor: Win32 EDIT controls, so typing,
// IME, selection, the clipboard, undo and screen readers are Windows' own,
// inside a box omni draws as Windows 11's text box is drawn (a rounded fill,
// a hairline border, an accent underline while it has the focus). The edit
// itself has no border; it sits inside the box's padding.

#if os(Windows)
import Foundation
import WinSDK

@MainActor
final class WinEdit: WinControl {
    enum Kind { case line, secure, multiline }
    let kind: Kind
    var text = "" { didSet { if text != oldValue { applyText() } } }
    var placeholder = "" { didSet { if placeholder != oldValue { applyPlaceholder() } } }
    var maxLength: Int? { didSet { if maxLength != oldValue { applyLimit() } } }
    var digitsOnly = false
    var onChange: ((String) -> Void)?
    var onSubmit: (() -> Void)?
    var onFocus: ((Bool) -> Void)?
    private(set) var isFocused = false
    /// Our own SetWindowText: its EN_CHANGE isn't the user typing.
    private var isSetting = false

    init(_ kind: Kind) {
        self.kind = kind
        super.init()
    }

    override var className: String { "EDIT" }
    override var style: DWORD {
        var s = DWORD(WS_CHILD) | DWORD(WS_TABSTOP)
        switch kind {
        case .line: s |= DWORD(ES_AUTOHSCROLL)
        case .secure: s |= DWORD(ES_AUTOHSCROLL) | DWORD(ES_PASSWORD)
        case .multiline: s |= DWORD(ES_MULTILINE) | DWORD(ES_AUTOVSCROLL) | DWORD(ES_WANTRETURN) | DWORD(WS_VSCROLL)
        }
        if digitsOnly { s |= DWORD(ES_NUMBER) }
        return s
    }
    override var scrollsItself: Bool { kind == .multiline }

    override func created() {
        applyText()
        applyPlaceholder()
        applyLimit()
        if kind == .secure, let hwnd { SendMessageW(hwnd, UINT(EM_SETPASSWORDCHAR), WPARAM(0x25CF), 0) }
    }

    private func applyText() {
        guard hwnd != nil, windowText != text else { return }
        isSetting = true
        setWindowText(text)
        isSetting = false
    }

    private func applyPlaceholder() {
        guard let hwnd, kind != .multiline else { return }
        // EM_SETCUEBANNER, shown while focused too (wParam TRUE), as macOS shows it.
        let wide = Win32.wide(placeholder)
        wide.withUnsafeBufferPointer { buffer in
            _ = SendMessageW(hwnd, UINT(0x1501), 1, LPARAM(Int(bitPattern: buffer.baseAddress)))
        }
    }

    private func applyLimit() {
        guard let hwnd else { return }
        SendMessageW(hwnd, UINT(EM_LIMITTEXT), WPARAM(maxLength ?? 0), 0)
    }

    override func command(_ code: Int) {
        if code == Int(EN_CHANGE), !isSetting {
            let typed = windowText
            text = typed
            onChange?(typed)
        }
    }

    override func keyDown(_ key: Int) -> Bool {
        if key == Int(VK_RETURN), kind != .multiline {
            onSubmit?()
            return true
        }
        if key == Int(VK_ESCAPE), let surface = surface, let onEscape = surface.onEscape {
            onEscape()
            return true
        }
        return false
    }

    override func focusChanged(_ focused: Bool) {
        isFocused = focused
        view?.setNeedsDisplay()
        onFocus?(focused)
    }

    override func colors(_ hdc: HDC) -> HBRUSH? {
        let text = view?.inheritedForeground ?? (Appearance.current == .dark ? .white : .black)
        SetTextColor(hdc, Win32.rgb(text))
        let back = boxFill
        SetBkColor(hdc, Win32.rgb(back))
        return WinControl.brush(for: back)
    }

    /// The box's fill, which the edit's background must match.
    var boxFill: Color = WinStyle.textFieldFill

    func focus() {
        guard let hwnd, GetFocus() != hwnd else { return }
        SetFocus(hwnd)
        // A click into a field selects nothing; Tab to it selects all, as Windows does.
        SendMessageW(hwnd, UINT(EM_SETSEL), WPARAM(bitPattern: -1), 0)
    }

    override func naturalSize(width: Double?) -> WinSize? {
        WinSize(width: 0, height: lineHeight)
    }
}

/// The box around an edit, its padding, and what a click in it does.
@MainActor
enum WinTextBox {
    static let padding = EdgeInsets(top: 5, leading: 10, bottom: 6, trailing: 10)

    static func configure(_ v: WinView, edit: WinEdit, plain: Bool, multiline: Bool) {
        v.padding = plain ? EdgeInsets() : padding
        v.cursor = "text"
        v.onTap = { [weak edit] in edit?.focus() }
        v.hexpand = true
        if multiline { v.vexpand = true }
        let fill = plain ? (v.background ?? .clear) : WinStyle.textFieldFill
        edit.boxFill = plain ? WinTextBox.backdrop(of: v) : fill
        v.measure = { [weak edit] _ in
            let line = edit?.lineHeight ?? 17
            return WinSize(width: 60, height: multiline ? max(line * 4, 72) : line)
        }
        v.minimumWidth = { 40 }
        v.draw = plain ? nil : { [weak edit] canvas, rect in
            let focused = edit?.isFocused ?? false
            canvas.fill(rect, radius: 4, fill)
            canvas.stroke(rect, radius: 4, width: 1, WinStyle.controlStroke)
            // The bottom edge: the accent and thicker while typing, as WinUI's.
            if focused {
                canvas.clip(WinRect(x: 0, y: rect.height - 2, width: rect.width, height: 2))
                canvas.fill(rect, radius: 4, WinStyle.accent)
                canvas.popClip()
            } else {
                canvas.clip(WinRect(x: 0, y: rect.height - 1, width: rect.width, height: 1))
                canvas.fill(rect, radius: 4, WinStyle.strongStroke)
                canvas.popClip()
            }
        }
    }

    /// The colour a plain field sits on: the nearest background around it.
    static func backdrop(of view: WinView) -> Color {
        var v: WinView? = view
        while let current = v {
            if let bg = current.background, bg.rgbaComponents.a > 0.99 { return bg }
            v = current.parent
        }
        return Appearance.current == .dark ? .rgba(r: 0.12, g: 0.12, b: 0.12, a: 1) : .white
    }
}

extension WinControl {
    /// The edit inside its box: the padding off each side, a single line centred.
    func contentRect(in frame: WinRect) -> WinRect {
        guard let view else { return frame }
        let p = view.padding
        var rect = WinRect(x: frame.x + p.leading, y: frame.y + p.top,
                           width: max(0, frame.width - p.leading - p.trailing),
                           height: max(0, frame.height - p.top - p.bottom))
        if let edit = self as? WinEdit, edit.kind != .multiline {
            let h = min(rect.height, lineHeight)
            rect.y = frame.y + ((frame.height - h) / 2).rounded()
            rect.height = h
        }
        // A drop-down's field, centred in whatever height its view was given.
        if let combo = self as? WinCombo {
            let h = min(rect.height, combo.fieldHeight)
            rect.y = frame.y + ((frame.height - h) / 2).rounded()
            rect.height = h
        }
        return rect
    }
}

extension TextField {
    @MainActor public func makeNative() -> NativeView {
        let native = WinView.make("TextField", layout: .leaf)
        winView(native).control = WinEdit(.line)
        return native
    }

    @MainActor public func updateNative(_ view: NativeView) {
        let v = winView(view)
        guard let edit = v.control as? WinEdit else { return }
        let field = self
        let configuration = self.configuration
        let limit = configuration.maxLength
        edit.textStyle = WinTextStyle(Tracker.current?.environment.font ?? .body)
        edit.digitsOnly = configuration.keyboardType == .numberPad
        edit.maxLength = limit
        edit.placeholder = placeholder
        edit.text = textBinding.wrappedValue
        edit.onChange = { typed in field.commit(typed, limit: limit) }
        edit.onSubmit = configuration.onSubmit
        let focus = focusBinding
        edit.onFocus = { focused in
            if let focus, focus.wrappedValue != focused { focus.wrappedValue = focused }
        }
        WinTextBox.configure(v, edit: edit, plain: configuration.style.isPlain, multiline: false)
        if focusBinding?.wrappedValue == true {
            DispatchQueue.main.async { MainActor.assumeIsolated { edit.focus() } }
        }
    }
}

extension SecureField {
    @MainActor public func makeNative() -> NativeView {
        let native = WinView.make("SecureField", layout: .leaf)
        winView(native).control = WinEdit(.secure)
        return native
    }

    @MainActor public func updateNative(_ view: NativeView) {
        let v = winView(view)
        guard let edit = v.control as? WinEdit else { return }
        let binding = text
        let configuration = self.configuration
        edit.textStyle = WinTextStyle(Tracker.current?.environment.font ?? .body)
        edit.maxLength = configuration.maxLength
        edit.placeholder = title
        edit.text = binding.wrappedValue
        edit.onChange = { typed in if binding.wrappedValue != typed { binding.wrappedValue = typed } }
        edit.onSubmit = configuration.onSubmit
        let focus = focusBinding
        edit.onFocus = { focused in
            if let focus, focus.wrappedValue != focused { focus.wrappedValue = focused }
        }
        WinTextBox.configure(v, edit: edit, plain: configuration.style.isPlain, multiline: false)
        if focusBinding?.wrappedValue == true {
            DispatchQueue.main.async { MainActor.assumeIsolated { edit.focus() } }
        }
    }
}

extension TextEditor {
    @MainActor public func makeNative() -> NativeView {
        let native = WinView.make("TextEditor", layout: .leaf)
        winView(native).control = WinEdit(.multiline)
        return native
    }

    @MainActor public func updateNative(_ view: NativeView) {
        let v = winView(view)
        guard let edit = v.control as? WinEdit else { return }
        let binding = text
        edit.textStyle = WinTextStyle(Tracker.current?.environment.font ?? .body)
        edit.text = binding.wrappedValue
        edit.onChange = { typed in if binding.wrappedValue != typed { binding.wrappedValue = typed } }
        let focus = focusBinding
        edit.onFocus = { focused in
            if let focus, focus.wrappedValue != focused { focus.wrappedValue = focused }
        }
        WinTextBox.configure(v, edit: edit, plain: style == .plain, multiline: true)
        if focusBinding?.wrappedValue == true {
            DispatchQueue.main.async { MainActor.assumeIsolated { edit.focus() } }
        }
    }
}
#endif
