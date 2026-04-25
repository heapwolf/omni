#if os(Windows)
    import Foundation
    import CWindows

    public struct GraphicsContext {
        let hwnd: NativeView

        public func fill(rect: NativeRect, color: (r: Float, g: Float, b: Float, a: Float)) {
            omni_win2d_fill_rect(
                hwnd,
                Float(rect.x), Float(rect.y), Float(rect.width), Float(rect.height),
                color.r, color.g, color.b, color.a
            )
        }

        public func stroke(rect: NativeRect, color: (r: Float, g: Float, b: Float, a: Float), lineWidth: Float = 1.0) {
            omni_win2d_draw_rect(
                hwnd,
                Float(rect.x), Float(rect.y), Float(rect.width), Float(rect.height),
                color.r, color.g, color.b, color.a,
                lineWidth
            )
        }
    }

    public extension SystemCanvasPrimitive {
        @MainActor
        func makeWindowsNative() -> NativeView {
            // Create a dedicated child HWND for this canvas layer
            let canvas = omni_win_create_canvas(nil, 0, 0, 100, 100, 0)
            omni_win2d_attach(canvas)
            return canvas
        }

        @MainActor
        func updateWindowsNative(_ view: NativeView) {
            // Bind the draw block to the WM_PAINT event routed from WndProc
            bindWindowsEvent(view, "paint") {
                omni_win2d_begin_draw(view)

                // Clear the canvas to white (or transparent if layered)
                omni_win2d_clear(view, 1.0, 1.0, 1.0, 1.0)

                // Expose our context for the user's declarative UI drawing block
                let ctx = GraphicsContext(hwnd: view)
                self.onDraw(ctx)

                omni_win2d_end_draw(view)
            }
        }

        // Memory safety: Ensure D2D targets are dropped when views are removed
        @MainActor
        func unmountWindowsNative(_ view: NativeView) {
            omni_win2d_detach(view)
        }
    }
#endif
