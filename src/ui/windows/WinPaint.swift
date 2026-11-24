// src/ui/windows/WinPaint.swift
//
// Drawing a WinView tree: the canvas a view draws on (Direct2D, through
// CWinRender), text laid out by DirectWrite, and the painter that walks the
// tree.

#if os(Windows)
import Foundation
import CWindows

/// What a view draws on: the window's render target, at the view's origin.
@MainActor
public final class WinCanvas {
    let target: UnsafeMutableRawPointer
    /// Points to the target's points: a translation and a uniform scale.
    private(set) var tx = 0.0, ty = 0.0, s = 1.0
    private var stack: [(Double, Double, Double)] = []

    init(target: UnsafeMutableRawPointer) { self.target = target }

    private func apply() {
        omni_r_set_transform(target, Float(s), 0, 0, Float(s), Float(tx), Float(ty))
    }

    func save() { stack.append((tx, ty, s)) }
    func restore() {
        guard let last = stack.popLast() else { return }
        (tx, ty, s) = last
        apply()
    }
    func translate(_ x: Double, _ y: Double) {
        tx += x * s
        ty += y * s
        apply()
    }
    /// Scales about a point in the current coordinates.
    func scale(_ factor: Double, about cx: Double, _ cy: Double) {
        translate(cx, cy)
        s *= factor
        apply()
        translate(-cx, -cy)
    }

    public func clip(_ rect: WinRect, radius: Double = 0) {
        omni_r_push_clip(target, Float(rect.x), Float(rect.y), Float(rect.width), Float(rect.height), Float(radius))
    }
    public func popClip() { omni_r_pop_clip(target) }
    public func pushOpacity(_ value: Double) { omni_r_push_opacity(target, Float(value)) }
    public func popOpacity() { omni_r_pop_opacity(target) }

    public func fill(_ rect: WinRect, radius: Double = 0, _ color: Color) {
        let c = color.rgbaComponents
        omni_r_fill_rrect(target, Float(rect.x), Float(rect.y), Float(rect.width), Float(rect.height), Float(radius),
                          Float(c.r), Float(c.g), Float(c.b), Float(c.a))
    }

    public func stroke(_ rect: WinRect, radius: Double = 0, width: Double, _ color: Color) {
        let c = color.rgbaComponents
        omni_r_stroke_rrect(target, Float(rect.x), Float(rect.y), Float(rect.width), Float(rect.height),
                            Float(radius), Float(width), Float(c.r), Float(c.g), Float(c.b), Float(c.a))
    }

    public func fillEllipse(_ rect: WinRect, _ color: Color) {
        let c = color.rgbaComponents
        omni_r_fill_ellipse(target, Float(rect.x + rect.width / 2), Float(rect.y + rect.height / 2),
                            Float(rect.width / 2), Float(rect.height / 2), Float(c.r), Float(c.g), Float(c.b), Float(c.a))
    }

    public func strokeEllipse(_ rect: WinRect, width: Double, _ color: Color) {
        let c = color.rgbaComponents
        omni_r_stroke_ellipse(target, Float(rect.x + rect.width / 2), Float(rect.y + rect.height / 2),
                              Float(max(0, rect.width / 2 - width / 2)), Float(max(0, rect.height / 2 - width / 2)),
                              Float(width), Float(c.r), Float(c.g), Float(c.b), Float(c.a))
    }

    public func line(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double, width: Double, _ color: Color) {
        let c = color.rgbaComponents
        omni_r_line(target, Float(x1), Float(y1), Float(x2), Float(y2), Float(width),
                    Float(c.r), Float(c.g), Float(c.b), Float(c.a))
    }

    public func gradient(_ rect: WinRect, radius: Double = 0, stops: [(Double, Color)], from start: UnitPoint, to end: UnitPoint) {
        var flat: [Float] = []
        for (position, color) in stops {
            let c = color.rgbaComponents
            flat += [Float(position), Float(c.r), Float(c.g), Float(c.b), Float(c.a)]
        }
        flat.withUnsafeBufferPointer { buffer in
            omni_r_gradient_rrect(target, Float(rect.x), Float(rect.y), Float(rect.width), Float(rect.height), Float(radius),
                                  Float(rect.x + start.x * rect.width), Float(rect.y + start.y * rect.height),
                                  Float(rect.x + end.x * rect.width), Float(rect.y + end.y * rect.height),
                                  buffer.baseAddress, Int32(stops.count))
        }
    }

    public func text(_ layout: WinTextLayout, at x: Double, _ y: Double, _ color: Color) {
        guard let handle = layout.handle else { return }
        let c = color.rgbaComponents
        omni_t_draw(target, handle, Float(x), Float(y), Float(c.r), Float(c.g), Float(c.b), Float(c.a))
    }

    public func image(_ image: WinImage, in rect: WinRect, opacity: Double = 1, smooth: Bool = true) {
        guard let handle = image.handle else { return }
        omni_i_draw(target, handle, Float(rect.x), Float(rect.y), Float(rect.width), Float(rect.height),
                    Float(opacity), smooth ? 1 : 0)
    }

    public func fill(_ path: WinPath, _ color: Color) {
        let c = color.rgbaComponents
        omni_r_path_fill(target, path.handle, Float(c.r), Float(c.g), Float(c.b), Float(c.a))
    }

    public func stroke(_ path: WinPath, width: Double, _ color: Color) {
        let c = color.rgbaComponents
        omni_r_path_stroke(target, path.handle, Float(width), Float(c.r), Float(c.g), Float(c.b), Float(c.a))
    }
}

/// A Direct2D path, made for one draw.
public final class WinPath {
    let handle: UnsafeMutableRawPointer
    public init() { handle = omni_r_path_create() }
    deinit { omni_r_path_release(handle) }
    public func move(_ x: Double, _ y: Double) { omni_r_path_move(handle, Float(x), Float(y)) }
    public func line(_ x: Double, _ y: Double) { omni_r_path_line(handle, Float(x), Float(y)) }
    public func quad(_ cx: Double, _ cy: Double, _ x: Double, _ y: Double) {
        omni_r_path_quad(handle, Float(cx), Float(cy), Float(x), Float(y))
    }
    public func cubic(_ c1x: Double, _ c1y: Double, _ c2x: Double, _ c2y: Double, _ x: Double, _ y: Double) {
        omni_r_path_cubic(handle, Float(c1x), Float(c1y), Float(c2x), Float(c2y), Float(x), Float(y))
    }
    public func arc(to x: Double, _ y: Double, rx: Double, ry: Double, large: Bool, clockwise: Bool) {
        omni_r_path_arc(handle, Float(x), Float(y), Float(rx), Float(ry), 0, large ? 1 : 0, clockwise ? 1 : 0)
    }
    public func close() { omni_r_path_close(handle) }
}

// MARK: - Text

/// What a paragraph is laid out with.
public struct WinTextStyle: Hashable {
    public var family: String?
    public var size: Double
    public var weight: Int
    public var italic: Bool
    public var alignment: Int // 0 leading, 1 center, 2 trailing
    public var wraps: Bool
    public var lineLimit: Int
    public var trim: Int
    public var tracking: Double
    public var lineSpacing: Double
    public var strikethrough: Bool
    public var underline: Bool

    public init(family: String? = nil, size: Double, weight: Int = 400, italic: Bool = false, alignment: Int = 0,
                wraps: Bool = true, lineLimit: Int = 0, trim: Int = 1, tracking: Double = 0, lineSpacing: Double = 0,
                strikethrough: Bool = false, underline: Bool = false) {
        self.family = family
        self.size = size
        self.weight = weight
        self.italic = italic
        self.alignment = alignment
        self.wraps = wraps
        self.lineLimit = lineLimit
        self.trim = trim
        self.tracking = tracking
        self.lineSpacing = lineSpacing
        self.strikethrough = strikethrough
        self.underline = underline
    }

    /// omni's Font as DirectWrite takes it. Apple's text styles are a size
    /// smaller here, as Windows' own type ramp is (body is 14 in Fluent).
    @MainActor public init(_ font: Font, monospaced: Bool = false) {
        let family: String?
        if monospaced { family = "Cascadia Mono" }
        else if let f = font.family { family = Font.resolvedFamily(f) }
        else { family = nil }
        self.init(family: family, size: WinTextStyle.windowsSize(font), weight: font.weight.rawValue,
                  italic: font.isItalic)
    }

    /// SwiftUI's sizes are iOS's; macOS's are a step smaller, and Windows'
    /// UI text sits with macOS's: 13 for body.
    @MainActor static func windowsSize(_ font: Font) -> Double {
        guard let style = font.style, font.family == nil else { return font.size }
        switch style {
        case .largeTitle: return 26
        case .title: return 22
        case .title2: return 17
        case .title3: return 15
        case .headline: return 13
        case .subheadline: return 11
        case .body: return 13
        case .callout: return 12
        case .footnote: return 10
        case .caption: return 10
        case .caption2: return 10
        }
    }
}

/// A laid-out paragraph; made again when its text, style or width changes.
/// Not main-actor bound: it's a DirectWrite object, made and let go on any thread.
public final class WinTextLayout: @unchecked Sendable {
    let handle: UnsafeMutableRawPointer?
    public let width: Double
    public let height: Double
    public let baseline: Double

    init(_ text: String, style: WinTextStyle, maxWidth: Double?) {
        // An empty text is still a line tall, as a label is on Apple: measured
        // as a space, drawn as nothing.
        let measured = text.isEmpty ? " " : text
        let utf16 = Array(measured.utf16)
        let family = style.family.map { Array($0.utf16) + [0] } ?? [0]
        let made = utf16.withUnsafeBufferPointer { chars in
            family.withUnsafeBufferPointer { fam in
                omni_t_layout(chars.baseAddress, Int32(utf16.count), style.family == nil ? nil : fam.baseAddress,
                              Float(style.size), Int32(style.weight), style.italic ? 1 : 0,
                              Float(maxWidth ?? 0), Int32(style.alignment),
                              style.wraps && maxWidth != nil ? 1 : 0,
                              Int32(style.lineLimit), Int32(style.trim), Float(style.tracking),
                              Float(style.lineSpacing), style.strikethrough ? 1 : 0, style.underline ? 1 : 0)
            }
        }
        var w: Float = 0, h: Float = 0, b: Float = 0
        if let made { omni_t_metrics(made, &w, &h, &b) }
        if text.isEmpty {
            if let made { omni_t_release(made) }
            handle = nil
            width = 0
        } else {
            handle = made
            width = Double(w).rounded(.up)
        }
        height = Double(h).rounded(.up)
        baseline = Double(b)
    }

    deinit {
        if let handle { omni_t_release(handle) }
    }
}

/// Layouts by text, style and width, so measuring and drawing the same text
/// lays it out once.
@MainActor
final class WinTextCache {
    static let shared = WinTextCache()
    struct Key: Hashable {
        let text: String
        let style: WinTextStyle
        let width: Int
    }
    private var entries: [Key: WinTextLayout] = [:]

    func layout(_ text: String, _ style: WinTextStyle, maxWidth: Double?) -> WinTextLayout {
        let key = Key(text: text, style: style, width: maxWidth.map { Int(($0 * 4).rounded(.down)) } ?? -1)
        if let found = entries[key] { return found }
        if entries.count > 64 { entries.removeAll(keepingCapacity: true) }
        let made = WinTextLayout(text, style: style, maxWidth: maxWidth.map { _ in Double(key.width) / 4 })
        entries[key] = made
        return made
    }
}

// MARK: - Images

/// A decoded image, drawn by any window.
public final class WinImage {
    let handle: UnsafeMutableRawPointer?
    public let width: Double
    public let height: Double

    public init?(path: String) {
        var w: UInt32 = 0, h: UInt32 = 0
        let wide = Array(path.utf16) + [0]
        guard let made = wide.withUnsafeBufferPointer({ omni_i_load_file($0.baseAddress, &w, &h) }) else { return nil }
        handle = made
        width = Double(w)
        height = Double(h)
    }

    public init?(data: Data) {
        var w: UInt32 = 0, h: UInt32 = 0
        guard let made = data.withUnsafeBytes({ omni_i_load_memory($0.baseAddress, UInt32(data.count), &w, &h) }) else {
            return nil
        }
        handle = made
        width = Double(w)
        height = Double(h)
    }

    public init?(rgba: [UInt8], width: Int, height: Int) {
        guard let made = rgba.withUnsafeBytes({ omni_i_from_rgba($0.baseAddress, UInt32(width), UInt32(height)) }) else {
            return nil
        }
        handle = made
        self.width = Double(width)
        self.height = Double(height)
    }

    deinit { if let handle { omni_i_release(handle) } }
}

// MARK: - The painter

@MainActor
enum WinPainter {
    static func paint(_ view: WinView, on canvas: WinCanvas) {
        if view.isHidden || view.opacity <= 0 { return }
        let f = view.frame
        canvas.save()
        canvas.translate(f.x + view.offsetX, f.y + view.offsetY)
        if view.scale != 1 { canvas.scale(view.scale, about: f.width / 2, f.height / 2) }
        let bounds = WinRect(x: 0, y: 0, width: f.width, height: f.height)
        let dimmed = view.disabled == true
        let opacity = view.opacity * (dimmed ? 0.45 : 1)
        if opacity < 1 { canvas.pushOpacity(opacity) }

        if let shadow = view.shadow, shadow.color.rgbaComponents.a > 0 {
            paintShadow(shadow, bounds: bounds, radius: shapeRadius(of: view), on: canvas)
        }
        if let gradient = view.gradient {
            canvas.gradient(bounds, radius: view.cornerRadius, stops: gradient.stops, from: gradient.start, to: gradient.end)
        }
        if let background = view.background, background.rgbaComponents.a > 0 {
            canvas.fill(bounds, radius: view.cornerRadius, background)
        }

        var isScroll = false
        if case .scroll = view.layout { isScroll = true }
        let clips = view.clipsToBounds || isScroll
        if clips { canvas.clip(bounds, radius: view.clipsToBounds ? view.cornerRadius : 0) }

        view.draw?(canvas, bounds)

        if isScroll {
            canvas.save()
            canvas.translate(-view.scrollOffset.x, -view.scrollOffset.y)
        }
        for child in view.paintOrder { paint(child, on: canvas) }
        if isScroll {
            canvas.restore()
            if view.showsIndicators { paintIndicators(view, bounds: bounds, on: canvas) }
        }
        if clips { canvas.popClip() }

        if let border = view.borderColor, view.borderWidth > 0 {
            canvas.stroke(bounds, radius: view.cornerRadius, width: view.borderWidth, border)
        }
        if opacity < 1 { canvas.popOpacity() }
        canvas.restore()
    }

    /// A soft shadow: the shape grown a fraction of a point at a time, each
    /// ring faint, so the alpha falls off smoothly from the edge outward.
    /// Direct2D's shadow effect needs a device context the window's target
    /// doesn't give.
    private static func paintShadow(_ shadow: (color: Color, radius: Double, x: Double, y: Double),
                                    bounds: WinRect, radius: Double, on canvas: WinCanvas) {
        let base = shadow.color.rgbaComponents
        let blur = max(0.5, shadow.radius)
        let steps = max(3, min(24, Int((blur * 3).rounded())))
        let each = base.a / Double(steps) * 1.4
        for i in stride(from: steps, through: 1, by: -1) {
            let grow = blur * Double(i) / Double(steps)
            let rect = WinRect(x: bounds.x + shadow.x - grow, y: bounds.y + shadow.y - grow,
                               width: bounds.width + grow * 2, height: bounds.height + grow * 2)
            canvas.fill(rect, radius: radius > 0 ? radius + grow : grow, .rgba(r: base.r, g: base.g, b: base.b, a: each))
        }
    }

    /// The corner radius of the shape a shadow belongs to: its own, or that of
    /// the view filling it (the shadow is around a .cornerRadius or a clip).
    private static func shapeRadius(of view: WinView) -> Double {
        var v: WinView? = view
        while let current = v {
            if current.cornerRadius > 0 { return min(current.cornerRadius, min(current.frame.width, current.frame.height) / 2) }
            guard let only = current.children.first(where: { !$0.isHidden && !$0.isDecoration }),
                  abs(only.frame.width - current.frame.width) < 1, abs(only.frame.height - current.frame.height) < 1 else { break }
            v = only
        }
        return 0
    }

    /// Thin overlay bars, as Windows 11's scroll bars are until hovered.
    private static func paintIndicators(_ view: WinView, bounds: WinRect, on canvas: WinCanvas) {
        let content = view.contentSize
        let ink: Color = Appearance.current == .dark ? .rgba(r: 1, g: 1, b: 1, a: 0.35) : .rgba(r: 0, g: 0, b: 0, a: 0.35)
        if content.height > bounds.height + 0.5 {
            let ratio = bounds.height / content.height
            let h = max(24, bounds.height * ratio)
            let travel = bounds.height - h
            let y = travel * (view.scrollOffset.y / max(1, content.height - bounds.height))
            canvas.fill(WinRect(x: bounds.width - 5, y: y + 2, width: 3, height: h - 4), radius: 1.5, ink)
        }
        if content.width > bounds.width + 0.5 {
            let ratio = bounds.width / content.width
            let w = max(24, bounds.width * ratio)
            let travel = bounds.width - w
            let x = travel * (view.scrollOffset.x / max(1, content.width - bounds.width))
            canvas.fill(WinRect(x: x + 2, y: bounds.height - 5, width: w - 4, height: 3), radius: 1.5, ink)
        }
    }
}
#endif
