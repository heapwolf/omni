// src/lib/components/linux/GeometryReader+Linux.swift
import Foundation

#if os(Linux)
import Glibc

// We use a proxy to hold our resize callback and last known dimensions
class ResizeProxy {
    var onResize: ((GeometryProxy) -> Void)?
    var lastWidth: Double = -1
    var lastHeight: Double = -1
}

/// Runs `function` on the next turn of GTK's own main loop. Returning 0 from it
/// removes the source, making it a one-shot.
nonisolated(unsafe) let g_idle_add: @convention(c) (@convention(c) (UnsafeMutableRawPointer?) -> Int32, UnsafeMutableRawPointer?) -> UInt32 =
    fn(libgtk, "g_idle_add")

extension GeometryReaderPrimitive {
    @MainActor public func makeNative() -> NativeView {
        // A standard box works perfectly as an invisible container to track dimensions
        let view = gtk_box_new(1, 0)

        let proxy = ResizeProxy()
        let ptr = Unmanaged.passRetained(proxy).toOpaque()
        g_object_set_data_full(view, "proxy_resize", ptr) { pPtr in if let p = pPtr { Unmanaged<ResizeProxy>.fromOpaque(p).release() } }

        // Listen to GTK's size-allocate signal which fires during layout calculations
        let cb: @convention(c) (NativeView, UnsafeMutableRawPointer, UnsafeMutableRawPointer) -> Void = { _, allocPtr, pPtr in
            let storedProxy = Unmanaged<ResizeProxy>.fromOpaque(pPtr).takeUnretainedValue()
            // allocPtr points to a GdkRectangle (x, y, width, height as Int32)
            let alloc = allocPtr.assumingMemoryBound(to: Int32.self)
            let w = Double(alloc[2])
            let h = Double(alloc[3])

            if storedProxy.lastWidth != w || storedProxy.lastHeight != h {
                storedProxy.lastWidth = w
                storedProxy.lastHeight = h

                let hop = Unmanaged.passRetained(storedProxy).toOpaque()
                g_idle_add({ pointer in
                    guard let pointer else { return 0 }
                    let proxy = Unmanaged<ResizeProxy>.fromOpaque(pointer).takeRetainedValue()
                    MainActor.assumeIsolated {
                        proxy.onResize?(GeometryProxy(width: proxy.lastWidth,
                                                      height: proxy.lastHeight))
                    }
                    return 0 // G_SOURCE_REMOVE — a one-shot
                }, hop)
            }
        }
        g_signal_connect_data(view, "size-allocate", unsafeBitCast(cb, to: UnsafeMutableRawPointer.self), ptr, nil, 0)

        return view
    }

    @MainActor public func updateNative(_ view: NativeView) {
        if let ptr = g_object_get_data(view, "proxy_resize") {
            let proxy = Unmanaged<ResizeProxy>.fromOpaque(ptr).takeUnretainedValue()
            proxy.onResize = onResize
        }
    }

    @MainActor public func insertChild(_ child: NativeView, into parent: NativeView) {
        packFill(child, into: parent)
    }
}
#endif
