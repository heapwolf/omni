// src/ui/components/windows/Overlay+Windows.swift
//
// .overlay and .background(view) on Windows, as Apple's OverlayView is: the
// base alone sizes the view, and the decoration is fitted to it. Elsewhere
// they are a ZStack, where a shape in the overlay (a border's
// RoundedRectangle) expands the whole stack and every stack around it.
//
// ShapeStroke: a shape's outline, drawn on its edge (stroke) or inside it
// (strokeBorder), rounded corners and all.

#if os(Windows)
import Foundation

public struct OverlayView: NativeComponent {
    public var base: any View
    public var overlay: any View
    public var alignment: Alignment
    /// A background: drawn under the base, not over it.
    public var isBehind: Bool

    public var children: [any View] { isBehind ? [overlay, base] : [base, overlay] }

    public init(base: any View, overlay: any View, alignment: Alignment, isBehind: Bool = false) {
        self.base = base
        self.overlay = overlay
        self.alignment = alignment
        self.isBehind = isBehind
    }

    @MainActor public func makeNative() -> NativeView {
        WinView.make(isBehind ? "Background" : "Overlay", layout: .overlay)
    }

    @MainActor public func updateNative(_ view: NativeView) {
        winView(view).contentAlignment = alignment
    }

    @MainActor public func insertChild(_ child: NativeView, into parent: NativeView) {
        let p = winView(parent), c = winView(child)
        // The children are inserted in order: the decoration is first for a
        // background, second for an overlay.
        let isDecoration = isBehind ? p.children.isEmpty : !p.children.isEmpty
        c.isDecoration = isDecoration
        if isDecoration {
            c.halign = alignment.horizontal.winAlign
            c.valign = alignment.vertical.winAlign
        } else {
            c.halign = .fill
            c.valign = .fill
        }
        p.add(c)
    }
}

public struct ShapeStroke: NativeComponent {
    public var outline: ShapeOutline
    public var color: Color
    public var lineWidth: Double
    public var isInset: Bool

    @MainActor public func makeNative() -> NativeView {
        let native = WinView.make("Stroke", layout: .leaf)
        let v = winView(native)
        // A shape fills its frame; usually an overlay, the size of what it decorates.
        v.hexpand = true
        v.vexpand = true
        v.hitTesting = false
        return native
    }

    @MainActor public func updateNative(_ view: NativeView) {
        let outline = self.outline, color = self.color, width = lineWidth, inset = isInset
        winView(view).draw = { canvas, rect in
            // strokeBorder keeps the line inside; stroke centres it on the edge.
            let r = inset ? rect : WinRect(x: -width / 2, y: -width / 2, width: rect.width + width, height: rect.height + width)
            switch outline {
            case .rectangle(let cornerRadius):
                canvas.stroke(r, radius: inset ? cornerRadius : cornerRadius + width / 2, width: width, color)
            case .capsule:
                canvas.stroke(r, radius: min(r.width, r.height) / 2, width: width, color)
            case .ellipse:
                canvas.strokeEllipse(r, width: width, color)
            case .circle:
                let side = min(r.width, r.height)
                canvas.strokeEllipse(WinRect(x: r.x + (r.width - side) / 2, y: r.y + (r.height - side) / 2,
                                             width: side, height: side), width: width, color)
            }
        }
    }
}
#endif
