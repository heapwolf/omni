// src/ui/components/windows/Containers+Windows.swift
//
// ScrollView, clipping, materials, GeometryReader, SplitView, Canvas, Video
// and the swipe interceptor: the views that hold or shape other views.

#if os(Windows)
import Foundation

// MARK: - ScrollView

extension ScrollView {
    @MainActor public func makeNative() -> NativeView {
        let native = WinView.make("ScrollView", layout: .scroll(axis == .vertical ? .vertical : .horizontal))
        let v = winView(native)
        // Fills the space it's given, as SwiftUI's does.
        v.hexpand = true
        v.vexpand = true
        return native
    }

    @MainActor public func updateNative(_ view: NativeView) {
        let v = winView(view)
        let vertical = axis == .vertical
        v.layout = .scroll(vertical ? .vertical : .horizontal)
        v.isScrollEnabled = !isScrollDisabled
        let binding = offset
        v.onScrollOffsetChange = { x, y in
            let value = vertical ? y : x
            if let binding, abs(binding.wrappedValue - value) > 0.5 { binding.wrappedValue = value }
        }
        if let target = binding?.wrappedValue {
            let current = vertical ? v.scrollOffset.y : v.scrollOffset.x
            if abs(current - target) > 0.5 {
                v.scrollOffset = vertical ? (v.scrollOffset.x, target) : (target, v.scrollOffset.y)
            }
        }
        // Paging: a page is the viewport; the wheel moves a page at a time.
        if isPaging || page != nil {
            let pageBinding = page
            v.onScrollWheel = { [weak v] dx, dy in
                guard let v else { return }
                let size = vertical ? v.frame.height : v.frame.width
                guard size > 0 else { return }
                let delta = vertical ? dy : (dx != 0 ? dx : dy)
                let current = Int(((vertical ? v.scrollOffset.y : v.scrollOffset.x) / size).rounded())
                let next = max(0, current + (delta > 0 ? 1 : -1))
                let moved = vertical ? v.scroll(by: 0, Double(next) * size - v.scrollOffset.y)
                    : v.scroll(by: Double(next) * size - v.scrollOffset.x, 0)
                if moved, let pageBinding, pageBinding.wrappedValue != next { pageBinding.wrappedValue = next }
            }
            if let pageBinding {
                let size = vertical ? v.frame.height : v.frame.width
                if size > 0 {
                    let target = Double(pageBinding.wrappedValue) * size
                    let current = vertical ? v.scrollOffset.y : v.scrollOffset.x
                    if abs(current - target) > 0.5 {
                        v.scrollOffset = vertical ? (v.scrollOffset.x, target) : (target, v.scrollOffset.y)
                    }
                }
            }
            scrubber?.onGo = { [weak v] index in
                guard let v else { return }
                let size = vertical ? v.frame.height : v.frame.width
                v.scrollOffset = vertical ? (v.scrollOffset.x, Double(index) * size) : (Double(index) * size, v.scrollOffset.y)
                pageBinding?.wrappedValue = index
            }
        } else {
            v.onScrollWheel = nil
        }
    }

    @MainActor public func insertChild(_ child: NativeView, into parent: NativeView) {
        let c = winView(child)
        // The content spans the viewport across, and is its own length along.
        c.halign = .fill
        c.valign = .start
        winView(parent).add(c)
    }
}

// MARK: - Clipping

extension ClipModifierView {
    @MainActor public func makeNative() -> NativeView {
        WinView.make("Clip", layout: .bin)
    }

    @MainActor public func updateNative(_ view: NativeView) {
        let v = winView(view)
        v.clipsToBounds = true
        // A circle is a rectangle with a radius larger than it can use; the renderer clamps.
        v.cornerRadius = isCircular ? 1_000_000 : radius
    }

    @MainActor public func insertChild(_ child: NativeView, into parent: NativeView) {
        winPackFill(child, into: parent)
    }
}

// MARK: - Materials and glass

/// No blur behind a view on Windows' Direct2D target: a material is a
/// translucent fill of the window's colour, as Windows 11's acrylic falls
/// back to when transparency effects are off.
extension EffectBackgroundView {
    @MainActor public func makeNative() -> NativeView {
        WinView.make("Material", layout: .bin)
    }

    @MainActor public func updateNative(_ view: NativeView) {
        let v = winView(view)
        let dark = Appearance.current == .dark
        let alpha: Double
        switch kind {
        case .material(let material):
            switch material {
            case .ultraThinMaterial: alpha = 0.55
            case .thinMaterial: alpha = 0.7
            case .regularMaterial: alpha = 0.8
            case .thickMaterial: alpha = 0.9
            case .ultraThickMaterial: alpha = 0.96
            }
        case .glass(let glass):
            alpha = glass.variant == .identity ? 0 : glass.variant == .clear ? 0.35 : 0.7
        }
        let base: Color = dark ? .rgba(r: 0.16, g: 0.16, b: 0.16, a: alpha) : .rgba(r: 0.98, g: 0.98, b: 0.98, a: alpha)
        var glassTint: Color?
        if case .glass(let glass) = kind { glassTint = glass.tint }
        v.background = base
        if let tint = tint ?? glassTint {
            let t = tint.rgbaComponents
            v.gradient = nil
            v.background = .rgba(r: t.r, g: t.g, b: t.b, a: min(1, t.a * 0.35 + alpha * 0.5))
        }
        v.cornerRadius = shape.isCircular ? 1_000_000 : shape.radius
        v.borderColor = shape.radius > 0 || shape.isCircular ? WinStyle.controlStroke : nil
        v.borderWidth = shape.radius > 0 || shape.isCircular ? 1 : 0
        if let fade {
            // Fading toward an edge: the fill goes from solid to clear.
            let c = base.rgbaComponents
            let solid = Color.rgba(r: c.r, g: c.g, b: c.b, a: c.a), clear = Color.rgba(r: c.r, g: c.g, b: c.b, a: 0)
            let (start, end): (UnitPoint, UnitPoint)
            switch fade {
            case .top: (start, end) = (.bottom, .top)
            case .bottom: (start, end) = (.top, .bottom)
            case .leading: (start, end) = (.trailing, .leading)
            case .trailing: (start, end) = (.leading, .trailing)
            }
            v.background = nil
            v.gradient = (stops: [(0, solid), (1, clear)], start: start, end: end)
        }
    }

    @MainActor public func insertChild(_ child: NativeView, into parent: NativeView) {
        winPackFill(child, into: parent)
    }
}

extension GlassEffectContainerView {
    @MainActor public func makeNative() -> NativeView { WinView.make("GlassContainer", layout: .bin) }
    @MainActor public func updateNative(_ view: NativeView) {}
    @MainActor public func insertChild(_ child: NativeView, into parent: NativeView) { winPackFill(child, into: parent) }
}

extension NativeSwipeModifierView {
    @MainActor public func makeNative() -> NativeView { WinView.make("Swipe", layout: .bin) }

    /// A horizontal wheel (a trackpad's two-finger swipe) turns the page.
    @MainActor public func updateNative(_ view: NativeView) {
        let left = onSwipeLeft, right = onSwipeRight
        var accumulated = 0.0
        winView(view).onScrollWheel = { dx, _ in
            accumulated += dx
            if accumulated > 120 { accumulated = 0; left() }
            else if accumulated < -120 { accumulated = 0; right() }
        }
    }

    @MainActor public func insertChild(_ child: NativeView, into parent: NativeView) { winPackFill(child, into: parent) }
}

// MARK: - GeometryReader

extension GeometryReaderPrimitive {
    @MainActor public func makeNative() -> NativeView {
        // As flexible as its content, as omni's Apple one is (its content is
        // pinned to its edges there): a Responsive around a screen's header
        // is the header's height, not the screen's.
        WinView.make("GeometryReader", layout: .bin)
    }

    @MainActor public func updateNative(_ view: NativeView) {
        let report = onResize
        winView(view).onSizeChange = { size in report(GeometryProxy(width: size.width, height: size.height)) }
    }

    @MainActor public func insertChild(_ child: NativeView, into parent: NativeView) {
        winPackFill(child, into: parent)
    }
}

// MARK: - SplitView

/// Panes along an axis with a divider between each pair that can be dragged.
/// Each pane but the last keeps the size it was dragged to.
@MainActor
final class WinSplitState {
    var sizes: [Int: Double] = [:]
}

extension SplitView {
    @MainActor public func makeNative() -> NativeView {
        let native = WinView.make("SplitView", layout: .box(isVertical ? .horizontal : .vertical))
        let v = winView(native)
        v.state = WinSplitState()
        v.hexpand = true
        v.vexpand = true
        return native
    }

    @MainActor public func updateNative(_ view: NativeView) {
        winView(view).layout = .box(isVertical ? .horizontal : .vertical)
    }

    @MainActor public func insertChild(_ child: NativeView, into parent: NativeView) {
        let p = winView(parent)
        let c = winView(child)
        let horizontal = isVertical
        if !p.children.isEmpty {
            // The divider before this pane.
            let divider = WinView("SplitDivider", layout: .leaf)
            divider.measure = { _ in WinSize(width: 1, height: 1) }
            divider.hexpandSet = true
            divider.vexpandSet = true
            divider.hexpand = !horizontal
            divider.vexpand = horizontal
            divider.cursor = horizontal ? "resizeLeftRight" : "resizeUpDown"
            divider.draw = { canvas, rect in canvas.fill(rect, WinStyle.separator) }
            let before = p.children.last
            var start = 0.0
            divider.onPress = { down in
                if down, let before { start = horizontal ? before.frame.width : before.frame.height }
            }
            divider.onDrag = { [weak before] dx, dy in
                guard let before else { return }
                let next = max(80, start + (horizontal ? dx : dy))
                if horizontal { before.fixedWidth = next } else { before.fixedHeight = next }
            }
            WinView.live[divider.pointer] = divider
            p.add(divider)
        }
        c.halign = .fill
        c.valign = .fill
        // The last pane takes what's left.
        if horizontal { c.hexpand = true } else { c.vexpand = true }
        p.add(c)
    }
}

// MARK: - Canvas

extension Canvas {
    @MainActor public func makeNative() -> NativeView {
        let native = WinView.make("Canvas", layout: .leaf)
        let v = winView(native)
        v.hexpand = true
        v.vexpand = true
        return native
    }

    @MainActor public func updateNative(_ view: NativeView) {
        let context = DrawContext()
        drawClosure(context)
        let commands = context.commands
        winView(view).draw = { canvas, _ in Canvas.execute(commands, on: canvas) }
    }

    @MainActor static func execute(_ commands: [DrawCommand], on canvas: WinCanvas) {
        var path = WinPath()
        var stroke: Color = .black, fill: Color = .black
        var width = 2.0
        var isEmpty = true
        for command in commands {
            switch command {
            case .beginPath:
                path = WinPath()
                isEmpty = true
            case .moveTo(let x, let y):
                path.move(x, y)
                isEmpty = false
            case .lineTo(let x, let y):
                path.line(x, y)
                isEmpty = false
            case .addCurve(let c1x, let c1y, let c2x, let c2y, let x, let y):
                path.cubic(c1x, c1y, c2x, c2y, x, y)
                isEmpty = false
            case .setStrokeColor(let color): stroke = color
            case .setFillColor(let color): fill = color
            case .setLineWidth(let w): width = w
            case .stroke:
                if !isEmpty { canvas.stroke(path, width: width, stroke) }
                path = WinPath()
                isEmpty = true
            case .fill:
                if !isEmpty { canvas.fill(path, fill) }
                path = WinPath()
                isEmpty = true
            }
        }
    }
}

// MARK: - Video

/// Not played on Windows yet (Media Foundation's player is the way): the
/// frame it would play in, so a layout around it holds.
extension Video {
    @MainActor public func makeNative() -> NativeView {
        WinView.make("Video", layout: .leaf)
    }

    @MainActor public func updateNative(_ view: NativeView) {
        let v = winView(view)
        v.hexpand = isResizable
        v.vexpand = isResizable
        v.measure = { proposed in
            let w = proposed ?? 320
            return WinSize(width: w, height: (w * 9 / 16).rounded())
        }
        v.draw = { canvas, rect in canvas.fill(rect, .black) }
    }
}
#endif
