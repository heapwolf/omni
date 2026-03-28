// src/lib/components/android/GeometryReader+Android.swift
#if os(Android)
import Foundation
import CAndroid

@MainActor
private final class ResizeProxy {
    var onResize: ((GeometryProxy) -> Void)?
    var lastWidth: Double = -1
    var lastHeight: Double = -1
}

extension GeometryReaderPrimitive {
    @MainActor public func makeNative() -> NativeView {
        let env = OmniAndroid.env
        let view = OmniAndroid.createView(env, "android/widget/FrameLayout")

        let proxy = ResizeProxy()
        proxy.onResize = onResize
        AndroidModifierState.set(proxy, for: view)

        // The Java listener keeps the pointer, so the handler is retained for the
        // lifetime of the view. EventHandlerFloat2 receives (width, height).
        let handler = EventHandlerFloat2 { width, height in
            let w = Double(width)
            let h = Double(height)
            guard proxy.lastWidth != w || proxy.lastHeight != h else { return }
            proxy.lastWidth = w
            proxy.lastHeight = h
            proxy.onResize?(GeometryProxy(width: w, height: h))
        }
        omni_jni_attach_on_layout_change(env, view, Unmanaged.passRetained(handler).toOpaque())

        omni_jni_set_layout_params(env, view, Int32(MATCH_PARENT), Int32(MATCH_PARENT))
        AndroidExpansion.claim(view, horizontal: true, vertical: true)
        return view
    }

    @MainActor public func updateNative(_ view: NativeView) {
        // Swap in the newest closure; the listener itself stays bound.
        AndroidModifierState.get(ResizeProxy.self, for: view)?.onResize = onResize
    }

    @MainActor public func insertChild(_ child: NativeView, into parent: NativeView) {
        OmniAndroid.addChild(child, to: parent)
    }
}
#endif
