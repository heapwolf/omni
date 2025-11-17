// src/lib/Events.swift
import Foundation

#if os(Linux)
    import Glibc

    class Proxy { var act: () -> Void; init(_ act: @escaping () -> Void) { self.act = act } }

    func bindLinuxEvent(_ v: NativeView, _ event: String, _ act: @escaping () -> Void) {
        let key = "proxy_\(event)"

        // Bind once, then swap the closure: rebinding stacks handlers and frees a live Proxy.
        if let existing = g_object_get_data(v, key) {
            Unmanaged<Proxy>.fromOpaque(existing).takeUnretainedValue().act = act
            return
        }

        let p = Proxy(act)
        let ptr = Unmanaged.passRetained(p).toOpaque()
        g_object_set_data_full(v, key, ptr) { pPtr in if let p = pPtr { Unmanaged<Proxy>.fromOpaque(p).release() } }

        // Swapped: user data first, since each signal passes a different argument count.
        let cb: @convention(c) (UnsafeMutableRawPointer) -> Void = { pPtr in
            Unmanaged<Proxy>.fromOpaque(pPtr).takeUnretainedValue().act()
        }
        let G_CONNECT_SWAPPED: Int32 = 2
        g_signal_connect_data(v, event, unsafeBitCast(cb, to: UnsafeMutableRawPointer.self),
                              ptr, nil, G_CONNECT_SWAPPED)
    }
#elseif os(Windows)
    import CWindows

    @MainActor
    public class WindowsEventRegistry {
        // Maps the memory address of the HWND (NativeView) to its action closure
        public static var handlers: [Int: () -> Void] = [:]
    }

    @MainActor
    public func bindWindowsEvent(_ v: NativeView, _ event: String, _ act: @escaping () -> Void) {
        let handleKey = Int(bitPattern: v)
        WindowsEventRegistry.handlers[handleKey] = act
    }

    @MainActor
    public func handleWindowsCommand(lParam: Int64) {
        // For Win32 WM_COMMAND, lParam holds the HWND of the control (e.g., the Button)
        let handleKey = Int(lParam)
        WindowsEventRegistry.handlers[handleKey]?()
    }

    @MainActor
    public func unbindWindowsEvent(_ v: NativeView) {
        let handleKey = Int(bitPattern: v)
        WindowsEventRegistry.handlers.removeValue(forKey: handleKey)
    }
#elseif os(macOS) || os(iOS)
    import ObjectiveC

    #if os(macOS)
        import AppKit
    #elseif os(iOS)
        import UIKit
    #endif

    @MainActor
    class Proxy: NSObject {
        static var key: UInt8 = 0; var act: () -> Void
        init(_ act: @escaping () -> Void) { self.act = act }
        @objc func f() { act() }
    }

    @MainActor
    func bindAppleEvent(_ v: NativeView, _ event: String, _ act: @escaping () -> Void) {
        guard let ctrl = v as? NativeControl else { return }
        #if os(macOS)
        let p = Proxy(act); objc_setAssociatedObject(ctrl, &Proxy.key, p, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        if let tf = ctrl as? NSTextField { NotificationCenter.default.addObserver(p, selector: #selector(Proxy.f), name: NSControl.textDidChangeNotification, object: tf) }
        else { ctrl.target = p; ctrl.action = #selector(Proxy.f) }
        #elseif os(iOS)
        // One proxy per event, not per control: a field binds editingChanged
        // and editingDidEnd both, and one replacing the other stopped typing
        // from reaching the binding.
        var proxies = objc_getAssociatedObject(ctrl, &Proxy.key) as? [String: Proxy] ?? [:]
        if let existing = proxies[event] {
            existing.act = act
        } else {
            let p = Proxy(act)
            proxies[event] = p
            objc_setAssociatedObject(ctrl, &Proxy.key, proxies, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            let controlEvent: UIControl.Event
            switch event {
            case "editingChanged": controlEvent = .editingChanged
            case "editingDidBegin": controlEvent = .editingDidBegin
            case "editingDidEnd": controlEvent = .editingDidEnd
            case "editingDidEndOnExit": controlEvent = .editingDidEndOnExit
            case "touchUpInside": controlEvent = .touchUpInside
            default: controlEvent = .valueChanged
            }
            ctrl.addTarget(p, action: #selector(Proxy.f), for: controlEvent)
        }
        #endif
    }
#endif
