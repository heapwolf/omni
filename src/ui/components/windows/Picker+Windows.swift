// src/ui/components/windows/Picker+Windows.swift
//
// A Picker is Windows' drop-down list (a COMBOBOX), whose list is a popup of
// its own: it opens over anything, sheets included.

#if os(Windows)
import Foundation
import WinSDK

@MainActor
final class WinCombo: WinControl {
    var items: [String] = [] { didSet { if items != oldValue { applyItems() } } }
    var selected = -1 { didSet { if selected != oldValue { applySelection() } } }
    var onSelect: ((Int) -> Void)?

    override var className: String { "COMBOBOX" }
    override var style: DWORD {
        DWORD(WS_CHILD) | DWORD(WS_TABSTOP) | DWORD(CBS_DROPDOWNLIST) | DWORD(WS_VSCROLL)
    }

    override func created() {
        applyItems()
    }

    private func applyItems() {
        guard let hwnd else { return }
        SendMessageW(hwnd, UINT(CB_RESETCONTENT), 0, 0)
        for item in items {
            let wide = Win32.wide(item)
            wide.withUnsafeBufferPointer { buffer in
                _ = SendMessageW(hwnd, UINT(CB_ADDSTRING), 0, LPARAM(Int(bitPattern: buffer.baseAddress)))
            }
        }
        applySelection()
        view?.setNeedsLayout()
    }

    private func applySelection() {
        guard let hwnd else { return }
        SendMessageW(hwnd, UINT(CB_SETCURSEL), WPARAM(bitPattern: Int64(selected)), 0)
    }

    override func command(_ code: Int) {
        guard code == Int(CBN_SELCHANGE), let hwnd else { return }
        let index = Int(SendMessageW(hwnd, UINT(CB_GETCURSEL), 0, 0))
        selected = index
        onSelect?(index)
    }

    /// The field's height as Windows makes it for the font, in points. A
    /// drop-down list's window is its field only (the list is a window of
    /// its own), so its window rect is that height.
    var fieldHeight: Double {
        guard let hwnd, let surface else { return lineHeight + 10 }
        var rect = RECT()
        GetWindowRect(hwnd, &rect)
        let h = Double(rect.bottom - rect.top) / surface.scale
        return h > 4 ? h : lineHeight + 10
    }

    /// The widest item and the arrow, the field's own height.
    override func naturalSize(width: Double?) -> WinSize? {
        var widest = 0.0
        for item in items {
            widest = max(widest, WinTextCache.shared.layout(item, textStyle, maxWidth: nil).width)
        }
        return WinSize(width: widest + 44, height: fieldHeight)
    }

    /// Placed with room below for the list: the height a combo box is given
    /// is its field and its list together. The field keeps its own height.
    override func sized() {
        guard let hwnd, let view, let surface else { return }
        let f = contentRect(in: view.windowFrame)
        let s = surface.scale
        SetWindowPos(hwnd, nil, Int32((f.x * s).rounded()), Int32((f.y * s).rounded()), Int32((f.width * s).rounded()),
                     Int32(((f.height + 300) * s).rounded()), UINT(SWP_NOZORDER | SWP_NOACTIVATE))
    }

    override var scrollsItself: Bool { false }
}

extension NativePicker {
    @MainActor public func makeNative() -> NativeView {
        let native = WinView.make("Picker", layout: .leaf)
        // As wide as its frame, as a macOS pop-up button is; its own width otherwise.
        winView(native).fillsWidthOffered = true
        winView(native).control = WinCombo()
        return native
    }

    @MainActor public func updateNative(_ view: NativeView) {
        let v = winView(view)
        guard let combo = v.control as? WinCombo else { return }
        let options = self.options
        let binding = selection
        combo.textStyle = WinTextStyle(Tracker.current?.environment.font ?? .body)
        combo.items = options.map(\.label)
        combo.selected = options.firstIndex { $0.tag == binding.wrappedValue } ?? -1
        combo.onSelect = { index in
            guard options.indices.contains(index) else { return }
            binding.wrappedValue = options[index].tag
        }
    }
}
#endif
