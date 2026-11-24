// src/ui/windows/Win32.swift
//
// What the Windows backend needs of Win32 that WinSDK doesn't import as Swift
// can use it: the macros, wide strings, and the process's setup (DPI
// awareness, the common controls' visual styles).

#if os(Windows)
import Foundation
import WinSDK
import CWindows

@MainActor
enum Win32 {
    static let instance: HINSTANCE? = GetModuleHandleW(nil)

    /// UTF-16, NUL-terminated, for the W functions.
    static func wide(_ string: String) -> [WCHAR] { Array(string.utf16) + [0] }

    static func string(_ buffer: UnsafePointer<WCHAR>?) -> String {
        guard let buffer else { return "" }
        return String(decodingCString: buffer, as: UTF16.self)
    }

    static func loword(_ value: UInt64) -> Int { Int(UInt16(truncatingIfNeeded: value)) }
    static func hiword(_ value: UInt64) -> Int { Int(UInt16(truncatingIfNeeded: value >> 16)) }
    /// GET_X_LPARAM / GET_Y_LPARAM: signed, for points off a monitor's left or top.
    static func xParam(_ l: LPARAM) -> Int { Int(Int16(truncatingIfNeeded: l)) }
    static func yParam(_ l: LPARAM) -> Int { Int(Int16(truncatingIfNeeded: l >> 16)) }
    /// MAKEINTRESOURCEW.
    static func resource(_ id: Int) -> UnsafePointer<WCHAR>? { UnsafePointer<WCHAR>(bitPattern: id) }

    static func cursor(_ id: Int) -> HCURSOR? { LoadCursorW(nil, resource(id)) }
    static let arrowCursor = cursor(32512)
    static let ibeamCursor = cursor(32513)
    static let handCursor = cursor(32649)
    static let sizeWECursor = cursor(32644)
    static let sizeNSCursor = cursor(32645)

    static func cursor(named name: String?) -> HCURSOR? {
        switch name {
        case "pointer", "pointingHand", "link": return handCursor
        case "text", "iBeam": return ibeamCursor
        case "resizeLeftRight", "columnResize", "ew-resize": return sizeWECursor
        case "resizeUpDown", "rowResize", "ns-resize": return sizeNSCursor
        default: return arrowCursor
        }
    }

    static func rgb(_ color: Color) -> COLORREF {
        let c = color.rgbaComponents
        // Over the window's own background when translucent: GDI has no alpha.
        let base: (Double, Double, Double) = Appearance.current == .dark ? (0.12, 0.12, 0.12) : (1, 1, 1)
        func mix(_ v: Double, _ b: Double) -> DWORD { DWORD(max(0, min(255, (v * c.a + b * (1 - c.a)) * 255)).rounded()) }
        return mix(c.r, base.0) | (mix(c.g, base.1) << 8) | (mix(c.b, base.2) << 16)
    }

    private static var didSetUp = false

    /// Once, before the first window: per-monitor DPI, visual styles for the
    /// common controls, COM for WIC and WebView2.
    static func setUp() {
        guard !didSetUp else { return }
        didSetUp = true
        _ = SetProcessDpiAwarenessContext(DPI_AWARENESS_CONTEXT(bitPattern: -4)) // PER_MONITOR_AWARE_V2
        activateVisualStyles()
        var controls = INITCOMMONCONTROLSEX()
        controls.dwSize = DWORD(MemoryLayout<INITCOMMONCONTROLSEX>.size)
        controls.dwICC = DWORD(ICC_STANDARD_CLASSES | ICC_BAR_CLASSES | ICC_PROGRESS_CLASS | ICC_LISTVIEW_CLASSES
                               | ICC_TAB_CLASSES | ICC_DATE_CLASSES | ICC_UPDOWN_CLASS)
        _ = InitCommonControlsEx(&controls)
        _ = CoInitializeEx(nil, DWORD(COINIT_APARTMENTTHREADED.rawValue))
    }

    /// Common Controls 6, which is what gives edits and combo boxes Windows'
    /// current look. An app's manifest would ask for it; a SwiftPM executable
    /// has none, so it is asked for here, with a manifest written beside the
    /// process's temporary files and an activation context made from it.
    private static func activateVisualStyles() {
        let manifest = """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <assembly xmlns="urn:schemas-microsoft-com:asm.v1" manifestVersion="1.0">
              <dependency><dependentAssembly>
                <assemblyIdentity type="win32" name="Microsoft.Windows.Common-Controls" version="6.0.0.0"
                  processorArchitecture="*" publicKeyToken="6595b64144ccf1df" language="*"/>
              </dependentAssembly></dependency>
            </assembly>
            """
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("omni-common-controls.manifest")
        try? manifest.write(to: path, atomically: true, encoding: .utf8)
        var source = wide(path.withUnsafeFileSystemRepresentation { String(cString: $0!) })
        source.withUnsafeMutableBufferPointer { buffer in
            var context = ACTCTXW()
            context.cbSize = ULONG(MemoryLayout<ACTCTXW>.size)
            context.lpSource = UnsafePointer(buffer.baseAddress)
            let handle = CreateActCtxW(&context)
            guard let handle, handle != INVALID_HANDLE_VALUE else { return }
            var cookie: ULONG_PTR = 0
            _ = ActivateActCtx(handle, &cookie)
        }
    }

    /// Windows' accent colour (Settings > Personalization > Colors), as its
    /// own controls draw with it. Read once; Windows 11's default blue if unset.
    static let accent: Color = {
        var value: DWORD = 0
        var size = DWORD(MemoryLayout<DWORD>.size)
        let status = RegGetValueW(HKEY_CURRENT_USER, wide("Software\\Microsoft\\Windows\\DWM"), wide("AccentColor"),
                                  DWORD(RRF_RT_REG_DWORD), nil, &value, &size)
        guard status == ERROR_SUCCESS else { return .rgba(r: 0, g: 0.373, b: 0.722, a: 1) }
        // ABGR.
        return .rgba(r: Double(value & 0xFF) / 255, g: Double((value >> 8) & 0xFF) / 255,
                     b: Double((value >> 16) & 0xFF) / 255, a: 1)
    }()

    /// The system's light/dark choice for apps.
    static var systemIsDark: Bool {
        var value: DWORD = 1
        var size = DWORD(MemoryLayout<DWORD>.size)
        let key = wide("Software\\Microsoft\\Windows\\CurrentVersion\\Themes\\Personalize")
        let name = wide("AppsUseLightTheme")
        let status = RegGetValueW(HKEY_CURRENT_USER, key, name, DWORD(RRF_RT_REG_DWORD), nil, &value, &size)
        return status == ERROR_SUCCESS && value == 0
    }

    /// A dark title bar for a dark app, as Windows 11's own apps have.
    static func applyTitleBarAppearance(_ hwnd: HWND, dark: Bool) {
        var flag: Int32 = dark ? 1 : 0
        _ = DwmSetWindowAttribute(hwnd, DWORD(20), &flag, DWORD(MemoryLayout<Int32>.size)) // DWMWA_USE_IMMERSIVE_DARK_MODE
    }
}
#endif
