// src/lib/components/linux/Canvas+Linux.swift
#if os(Linux)
    import Foundation
    import Glibc

    let gtk_drawing_area_new: @convention(c) () -> NativeView = fn(libgtk, "gtk_drawing_area_new")
    let gtk_widget_queue_draw: @convention(c) (NativeView) -> Void = fn(libgtk, "gtk_widget_queue_draw")

    nonisolated(unsafe) let libcairo = dlopen("libcairo.so.2", RTLD_LAZY | RTLD_GLOBAL)
    let cairo_new_path: @convention(c) (UnsafeMutableRawPointer) -> Void = fn(libcairo, "cairo_new_path")
    let cairo_move_to: @convention(c) (UnsafeMutableRawPointer, Double, Double) -> Void = fn(libcairo, "cairo_move_to")
    let cairo_curve_to: @convention(c) (UnsafeMutableRawPointer, Double, Double, Double, Double, Double, Double) -> Void = fn(libcairo, "cairo_curve_to")
    let cairo_set_source_rgba: @convention(c) (UnsafeMutableRawPointer, Double, Double, Double, Double) -> Void = fn(libcairo, "cairo_set_source_rgba")
    let cairo_set_line_width: @convention(c) (UnsafeMutableRawPointer, Double) -> Void = fn(libcairo, "cairo_set_line_width")
    let cairo_stroke: @convention(c) (UnsafeMutableRawPointer) -> Void = fn(libcairo, "cairo_stroke")
    let cairo_line_to: @convention(c) (UnsafeMutableRawPointer, Double, Double) -> Void = fn(libcairo, "cairo_line_to")
    let cairo_fill: @convention(c) (UnsafeMutableRawPointer) -> Void = fn(libcairo, "cairo_fill")

    class DrawProxy {
        var commands: [DrawCommand] = []
    }

    extension Canvas {
        public func makeNative() -> NativeView {
            let view = gtk_drawing_area_new()
            let proxy = DrawProxy()
            let ptr = Unmanaged.passRetained(proxy).toOpaque()

            g_object_set_data_full(view, "proxy_draw", ptr) { pPtr in
                if let p = pPtr {
                    Unmanaged<DrawProxy>.fromOpaque(p).release()
                }
            }

            let cb: @convention(c) (NativeView, UnsafeMutableRawPointer, UnsafeMutableRawPointer) -> Int32 = { _, cr, pPtr in
                let storedProxy = Unmanaged<DrawProxy>.fromOpaque(pPtr).takeUnretainedValue()
                Canvas.executeLinux(commands: storedProxy.commands, in: cr)
                return 0
            }

            g_signal_connect_data(view, "draw", unsafeBitCast(cb, to: UnsafeMutableRawPointer.self), ptr, nil, 0)
            return view
        }

        public func updateNative(_ view: NativeView) {
            let ctx = DrawContext()
            drawClosure(ctx)

            if let ptr = g_object_get_data(view, "proxy_draw") {
                let proxy = Unmanaged<DrawProxy>.fromOpaque(ptr).takeUnretainedValue()
                proxy.commands = ctx.commands
                gtk_widget_queue_draw(view)
            }
        }

        static func executeLinux(commands: [DrawCommand], in cr: UnsafeMutableRawPointer) {
            cairo_set_line_width(cr, 2.0)

            for cmd in commands {
                switch cmd {
                case .beginPath:
                    cairo_new_path(cr)
                case .moveTo(let x, let y):
                    cairo_move_to(cr, x, y)
                case .lineTo(let x, let y):
                    cairo_line_to(cr, x, y)
                case .addCurve(let c1x, let c1y, let c2x, let c2y, let x, let y):
                    cairo_curve_to(cr, c1x, c1y, c2x, c2y, x, y)
                case .setStrokeColor(let color):
                    let c = color.rgbaComponents
                    cairo_set_source_rgba(cr, c.r, c.g, c.b, c.a)
                case .setFillColor(let color):
                    let c = color.rgbaComponents
                    cairo_set_source_rgba(cr, c.r, c.g, c.b, c.a)
                case .setLineWidth(let width):
                    cairo_set_line_width(cr, width)
                case .stroke:
                    cairo_stroke(cr)
                case .fill:
                    cairo_fill(cr)
                }
            }
        }
    }
#endif
