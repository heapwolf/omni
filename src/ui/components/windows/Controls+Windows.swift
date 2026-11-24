// src/ui/components/windows/Controls+Windows.swift
//
// Button, Toggle, Slider, ProgressView and Divider, drawn as Windows 11's
// own are (WinUI's control templates: 4-point corners, a hairline border,
// the accent colour for what's on), rather than as Win32's common controls,
// which look as Windows did in 2006.

#if os(Windows)
import Foundation

@MainActor
enum WinStyle {
    static var dark: Bool { Appearance.current == .dark }
    static var controlFill: Color { dark ? .rgba(r: 1, g: 1, b: 1, a: 0.061) : .rgba(r: 1, g: 1, b: 1, a: 0.7) }
    static var controlFillHover: Color { dark ? .rgba(r: 1, g: 1, b: 1, a: 0.084) : .rgba(r: 0.976, g: 0.976, b: 0.976, a: 0.5) }
    static var controlFillPressed: Color { dark ? .rgba(r: 1, g: 1, b: 1, a: 0.033) : .rgba(r: 0.976, g: 0.976, b: 0.976, a: 0.3) }
    static var controlStroke: Color { dark ? .rgba(r: 1, g: 1, b: 1, a: 0.093) : .rgba(r: 0, g: 0, b: 0, a: 0.135) }
    static var strongStroke: Color { dark ? .rgba(r: 1, g: 1, b: 1, a: 0.54) : .rgba(r: 0, g: 0, b: 0, a: 0.45) }
    static var subtleFill: Color { dark ? .rgba(r: 1, g: 1, b: 1, a: 0.04) : .rgba(r: 0, g: 0, b: 0, a: 0.04) }
    static var separator: Color { dark ? .rgba(r: 1, g: 1, b: 1, a: 0.084) : .rgba(r: 0, g: 0, b: 0, a: 0.08) }
    static var textFieldFill: Color { dark ? .rgba(r: 0.17, g: 0.17, b: 0.17, a: 1) : .white }
    static var accent: Color { Win32.accent }
}

/// Hover and press, for a control that draws them.
@MainActor
final class WinPressState {
    var isHovered = false
    var isPressed = false
}

// MARK: - Button

public extension SystemButtonPrimitive {
    @MainActor func makeNative() -> NativeView {
        let native = WinView.make("Button", layout: .leaf)
        winView(native).state = WinPressState()
        return native
    }

    @MainActor func updateNative(_ view: NativeView) {
        let v = winView(view)
        let state = v.state(WinPressState.init)
        let style = WinTextStyle(font ?? Tracker.current?.environment.font ?? .body)
        let title = self.title
        let color = foregroundColor
        v.onTap = action
        v.onHover = { [weak v] on in state.isHovered = on; v?.setNeedsDisplay() }
        v.onPress = { [weak v] on in state.isPressed = on; v?.setNeedsDisplay() }
        v.measure = { _ in
            let layout = WinTextCache.shared.layout(title, style, maxWidth: nil)
            return WinSize(width: layout.width + 24, height: max(28, layout.height + 10))
        }
        v.minimumWidth = { 40 }
        v.draw = { [weak v] canvas, rect in
            guard let v else { return }
            let fill = state.isPressed ? WinStyle.controlFillPressed
                : state.isHovered ? WinStyle.controlFillHover : WinStyle.controlFill
            canvas.fill(rect, radius: 4, fill)
            canvas.stroke(rect, radius: 4, width: 1, WinStyle.controlStroke)
            let layout = WinTextCache.shared.layout(title, style, maxWidth: max(0, rect.width - 16))
            var ink = color ?? v.inheritedForeground ?? .primaryText
            if state.isPressed { ink = ink.opacity(0.62) }
            canvas.text(layout, at: ((rect.width - layout.width) / 2).rounded(), ((rect.height - layout.height) / 2).rounded(), ink)
        }
    }
}

// MARK: - Toggle

extension Toggle {
    @MainActor public func makeNative() -> NativeView {
        let native = WinView.make("Toggle", layout: .leaf)
        winView(native).state = WinPressState()
        return native
    }

    @MainActor public func updateNative(_ view: NativeView) {
        let v = winView(view)
        let state = v.state(WinPressState.init)
        let binding = isOnBinding
        let isOn = binding.wrappedValue
        let title = self.title
        let style = WinTextStyle(Tracker.current?.environment.font ?? .body)
        let track = WinSize(width: 40, height: 20)
        v.onTap = { binding.wrappedValue = !binding.wrappedValue }
        v.onHover = { [weak v] on in state.isHovered = on; v?.setNeedsDisplay() }
        v.onPress = { [weak v] on in state.isPressed = on; v?.setNeedsDisplay() }
        v.measure = { _ in
            guard !title.isEmpty else { return WinSize(width: track.width, height: 24) }
            let layout = WinTextCache.shared.layout(title, style, maxWidth: nil)
            return WinSize(width: layout.width + 12 + track.width, height: max(24, layout.height))
        }
        v.draw = { [weak v] canvas, rect in
            guard let v else { return }
            // The switch at the trailing edge, the label before it, as a Form row has them.
            let x = rect.width - track.width
            let y = ((rect.height - track.height) / 2).rounded()
            let box = WinRect(x: x, y: y, width: track.width, height: track.height)
            let accent = v.inheritedTint ?? WinStyle.accent
            if isOn {
                canvas.fill(box, radius: 10, state.isHovered ? accent.opacity(0.9) : accent)
            } else {
                canvas.fill(box, radius: 10, state.isHovered ? WinStyle.controlFillHover : WinStyle.subtleFill)
                canvas.stroke(box, radius: 10, width: 1, WinStyle.strongStroke)
            }
            let knob = state.isPressed ? 14.0 : state.isHovered ? 14.0 : 12.0
            let kx = isOn ? box.maxX - 4 - knob - (state.isPressed ? 2 : 0) : box.x + 4
            let knobRect = WinRect(x: kx, y: box.y + (box.height - knob) / 2, width: knob + (state.isPressed ? 2 : 0), height: knob)
            canvas.fill(knobRect, radius: knob / 2, isOn ? (WinStyle.dark ? .black : .white) : WinStyle.strongStroke)
            if !title.isEmpty {
                let layout = WinTextCache.shared.layout(title, style, maxWidth: max(0, x - 12))
                canvas.text(layout, at: 0, ((rect.height - layout.height) / 2).rounded(), v.inheritedForeground ?? .primaryText)
            }
        }
    }
}

// MARK: - Slider

extension Slider {
    @MainActor public func makeNative() -> NativeView {
        let native = WinView.make("Slider", layout: .leaf)
        let v = winView(native)
        v.state = WinPressState()
        v.hexpand = true
        return native
    }

    @MainActor public func updateNative(_ view: NativeView) {
        let v = winView(view)
        let state = v.state(WinPressState.init)
        let binding = value, range = self.range
        let span = max(range.upperBound - range.lowerBound, .ulpOfOne)
        let fraction = min(max((binding.wrappedValue - range.lowerBound) / span, 0), 1)
        let thumb = 20.0
        func set(_ x: Double, width: Double) {
            let f = min(max((x - thumb / 2) / max(1, width - thumb), 0), 1)
            binding.wrappedValue = range.lowerBound + f * span
        }
        var startX = 0.0
        v.onTapLocation = { [weak v] x, _ in set(x, width: v?.frame.width ?? 1) }
        v.onPress = { [weak v] on in
            state.isPressed = on
            if on, let v { startX = fraction * (v.frame.width - thumb) + thumb / 2 }
            v?.setNeedsDisplay()
        }
        v.onDrag = { [weak v] dx, _ in set(startX + dx, width: v?.frame.width ?? 1) }
        v.onHover = { [weak v] on in state.isHovered = on; v?.setNeedsDisplay() }
        v.measure = { _ in WinSize(width: 120, height: 24) }
        v.draw = { [weak v] canvas, rect in
            guard let v else { return }
            let accent = v.inheritedTint ?? WinStyle.accent
            let y = rect.height / 2
            let usable = rect.width - thumb
            let cx = thumb / 2 + usable * fraction
            canvas.fill(WinRect(x: thumb / 2, y: y - 2, width: usable, height: 4), radius: 2, WinStyle.strongStroke)
            canvas.fill(WinRect(x: thumb / 2, y: y - 2, width: cx - thumb / 2, height: 4), radius: 2, accent)
            let knob = WinRect(x: cx - thumb / 2, y: y - thumb / 2, width: thumb, height: thumb)
            canvas.fillEllipse(knob, WinStyle.dark ? .rgba(r: 0.27, g: 0.27, b: 0.27, a: 1) : .white)
            canvas.strokeEllipse(knob, width: 1, WinStyle.controlStroke)
            let dot = state.isPressed ? 10.0 : state.isHovered ? 14.0 : 12.0
            canvas.fillEllipse(WinRect(x: cx - dot / 2, y: y - dot / 2, width: dot, height: dot), accent)
        }
    }
}

// MARK: - ProgressView

extension ProgressView {
    @MainActor public func makeNative() -> NativeView {
        let native = WinView.make("ProgressView", layout: .leaf)
        winView(native).hitTesting = false
        return native
    }

    @MainActor public func updateNative(_ view: NativeView) {
        let v = winView(view)
        if let fraction {
            // A bar across what it's given, as Windows' ProgressBar.
            v.hexpand = true
            v.measure = { _ in WinSize(width: 120, height: 4) }
            v.draw = { [weak v] canvas, rect in
                let accent = v?.inheritedTint ?? WinStyle.accent
                let y = ((rect.height - 3) / 2).rounded()
                canvas.fill(WinRect(x: 0, y: y + 1, width: rect.width, height: 1), radius: 0.5, WinStyle.strongStroke)
                canvas.fill(WinRect(x: 0, y: y, width: rect.width * fraction, height: 3), radius: 1.5, accent)
            }
            return
        }
        // A ring, as Windows' ProgressRing: an arc of the accent colour that
        // grows, shrinks and turns, redrawn while it's on screen.
        v.hexpand = false
        v.measure = { _ in WinSize(width: 20, height: 20) }
        v.draw = { [weak v] canvas, rect in
            let side = min(rect.width, rect.height)
            let r = side / 2 - 2
            let cx = rect.width / 2, cy = rect.height / 2
            let t = Date().timeIntervalSinceReferenceDate
            let start = (t * 2.2 * .pi).truncatingRemainder(dividingBy: 2 * .pi)
            let sweep = .pi * (0.5 + 0.35 * sin(t * 2.4))
            let path = WinPath()
            path.move(cx + r * cos(start), cy + r * sin(start))
            path.arc(to: cx + r * cos(start + sweep), cy + r * sin(start + sweep), rx: r, ry: r,
                     large: sweep > .pi, clockwise: true)
            canvas.stroke(path, width: 2.5, v?.inheritedTint ?? v?.inheritedForeground ?? WinStyle.accent)
            WinCanvas.currentSurface?.wantsFrame = true
        }
    }
}

// MARK: - Divider

extension Divider {
    @MainActor public func makeNative() -> NativeView {
        let native = WinView.make("Divider", layout: .leaf)
        winView(native).hitTesting = false
        return native
    }

    @MainActor public func updateNative(_ view: NativeView) {
        let v = winView(view)
        let vertical = resolvedIsVertical
        // A rule spans its container: it expands along its own axis only.
        v.hexpand = !vertical
        v.vexpand = vertical
        v.hexpandSet = true
        v.vexpandSet = true
        v.measure = { _ in WinSize(width: 1, height: 1) }
        v.draw = { canvas, rect in canvas.fill(rect, WinStyle.separator) }
    }
}
#endif
