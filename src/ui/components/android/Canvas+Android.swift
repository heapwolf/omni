#if os(Android)
import Foundation
import CAndroid

@MainActor private var canvasCommandRegistry: [UnsafeMutableRawPointer: [DrawCommand]] = [:]

extension Canvas {
    @MainActor public func makeNative() -> NativeView {
        let env = OmniAndroid.env

        // Instantiate custom Java view that overrides onDraw(Canvas canvas)
        let view = OmniAndroid.createView(env, "com/omni/OmniCanvasView")
        canvasCommandRegistry[view] = []
        return view
    }

    @MainActor public func unmountNative(_ view: NativeView) {
        canvasCommandRegistry.removeValue(forKey: view)
    }

    @MainActor public func updateNative(_ view: NativeView) {
        let env = OmniAndroid.env

        let ctx = DrawContext()
        drawClosure(ctx)

        canvasCommandRegistry[view] = ctx.commands

        // Clear existing commands on the Java side
        omni_jni_canvas_reset(env, view)

        // Stream commands over JNI to the Java render pipeline
        for cmd in ctx.commands {
            switch cmd {
            case .beginPath:
                omni_jni_canvas_begin_path(env, view)
            case .moveTo(let x, let y):
                omni_jni_canvas_move_to(env, view, Float(x), Float(y))
            case .lineTo(let x, let y):
                omni_jni_canvas_line_to(env, view, Float(x), Float(y))
            case .addCurve(let c1x, let c1y, let c2x, let c2y, let x, let y):
                omni_jni_canvas_cubic_to(env, view, Float(c1x), Float(c1y), Float(c2x), Float(c2y), Float(x), Float(y))
            case .setStrokeColor(let color):
                let c = color.rgbaComponents
                omni_jni_canvas_set_stroke_color(
                    env, view,
                    Int32(c.a * 255),
                    Int32(c.r * 255),
                    Int32(c.g * 255),
                    Int32(c.b * 255)
                )
            case .setFillColor(let color):
                let c = color.rgbaComponents
                omni_jni_canvas_set_fill_color(
                    env, view,
                    Int32(c.a * 255),
                    Int32(c.r * 255),
                    Int32(c.g * 255),
                    Int32(c.b * 255)
                )
            case .setLineWidth(let width):
                omni_jni_canvas_set_stroke_width(env, view, Float(width))
            case .stroke:
                omni_jni_canvas_stroke(env, view)
            case .fill:
                omni_jni_canvas_fill(env, view)
            }
        }

        // Trigger a view redraw in Android (equivalent to setNeedsDisplay)
        omni_jni_canvas_invalidate(env, view)
    }
}
#endif
