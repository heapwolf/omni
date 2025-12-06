// src/lib/components/apple/Glass+Apple.swift
#if os(macOS) || os(iOS)
import Foundation

#if os(iOS)
import UIKit

/// The effect, in its shape. On iOS 26 glass takes the shape from
/// cornerConfiguration, which leaves room for the glass's own highlight;
/// a material is clipped to it.
final class OmniEffectView: UIVisualEffectView {
    var kind: EffectKind?
    var shape = EffectShape(Rectangle())
    var fade: Edge? {
        didSet { if fade != oldValue { setNeedsLayout() } }
    }
    private var fadeMask: FadeMaskView?

    override func layoutSubviews() {
        super.layoutSubviews()
        applyShape()
        applyFade()
    }

    /// A visual effect view takes a mask view, not a layer mask.
    private func applyFade() {
        guard let fade else {
            if fadeMask != nil { mask = nil; fadeMask = nil }
            return
        }
        let view = fadeMask ?? FadeMaskView()
        if fadeMask == nil { fadeMask = view; mask = view }
        view.frame = bounds
        view.gradient.configureFade(toward: fade)
    }

    func applyShape() {
        if #available(iOS 26.0, *), case .glass = kind {
            cornerConfiguration = shape.isCircular ? .capsule()
                                                   : .corners(radius: .fixed(CGFloat(shape.radius)))
            return
        }
        let radius = shape.isCircular ? min(bounds.width, bounds.height) / 2 : CGFloat(shape.radius)
        layer.cornerRadius = radius
        layer.cornerCurve = .continuous
        clipsToBounds = radius > 0
    }

    func apply(_ next: EffectKind) {
        // Setting an equal effect again restarts the glass's own animation.
        guard next != kind else { return }
        kind = next
        effect = Self.effect(for: next)
        applyShape()
    }

    static func effect(for kind: EffectKind) -> UIVisualEffect? {
        switch kind {
        case .glass(let glass):
            if glass.variant == .identity { return nil }
            if #available(iOS 26.0, *) {
                let effect = UIGlassEffect(style: glass.variant == .clear ? .clear : .regular)
                effect.isInteractive = glass.isInteractive
                effect.tintColor = glass.tint?.uiColor
                return effect
            }
            return UIBlurEffect(style: glass.variant == .clear ? .systemUltraThinMaterial : .systemThinMaterial)
        case .material(let material):
            let style: UIBlurEffect.Style
            switch material {
            case .ultraThinMaterial: style = .systemUltraThinMaterial
            case .thinMaterial: style = .systemThinMaterial
            case .regularMaterial: style = .systemMaterial
            case .thickMaterial: style = .systemThickMaterial
            case .ultraThickMaterial: style = .systemChromeMaterial
            }
            return UIBlurEffect(style: style)
        }
    }
}

final class OmniGlassContainerView: UIVisualEffectView {
    var spacing: Double?
}

private final class FadeMaskView: UIView {
    override class var layerClass: AnyClass { CAGradientLayer.self }
    var gradient: CAGradientLayer { layer as! CAGradientLayer }
}

extension EffectBackgroundView {
    @MainActor public func makeNative() -> NativeView {
        let view = OmniEffectView(effect: nil)
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }

    @MainActor public func updateNative(_ view: NativeView) {
        guard let view = view as? OmniEffectView else { return }
        view.shape = shape
        view.fade = fade
        view.contentView.backgroundColor = tint?.uiColor
        view.apply(kind)
        view.setNeedsLayout()
    }

    @MainActor public func insertChild(_ child: NativeView, into parent: NativeView) {
        // Content goes in contentView, where the effect gives it legibility.
        let host = (parent as? UIVisualEffectView)?.contentView ?? parent
        pin(child, in: host, sizing: parent)
    }
}

extension GlassEffectContainerView {
    @MainActor public func makeNative() -> NativeView {
        let view = OmniGlassContainerView(effect: nil)
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }

    @MainActor public func updateNative(_ view: NativeView) {
        guard let view = view as? OmniGlassContainerView, view.spacing != spacing else { return }
        view.spacing = spacing
        if #available(iOS 26.0, *) {
            let effect = UIGlassContainerEffect()
            effect.spacing = CGFloat(spacing)
            view.effect = effect
        }
    }

    @MainActor public func insertChild(_ child: NativeView, into parent: NativeView) {
        let host = (parent as? UIVisualEffectView)?.contentView ?? parent
        pin(child, in: host, sizing: parent)
    }
}

@MainActor private func pin(_ child: UIView, in host: UIView, sizing parent: UIView) {
    host.addSubview(child)
    adoptSizing(of: child, into: parent)
    NSLayoutConstraint.activate([
        child.topAnchor.constraint(equalTo: host.topAnchor),
        child.bottomAnchor.constraint(equalTo: host.bottomAnchor),
        child.leadingAnchor.constraint(equalTo: host.leadingAnchor),
        child.trailingAnchor.constraint(equalTo: host.trailingAnchor)
    ])
}

#elseif os(macOS)
import AppKit

/// macOS 26's glass when there, else a vibrant blur, in its shape.
final class OmniEffectView: NSView {
    var kind: EffectKind?
    var shape = EffectShape(Rectangle())
    /// Where the content goes: the glass's contentView, or the blur itself.
    private(set) var host: NSView = NSView()
    private var effect: NSView?

    var fade: Edge? {
        didSet { if fade != oldValue { needsLayout = true } }
    }
    var tint: Color? {
        didSet { needsLayout = true }
    }
    private let tintLayer = CALayer()

    override func layout() {
        super.layout()
        applyShape()
        applyFade()
        applyTint()
    }

    /// Over the blur, under the content.
    private func applyTint() {
        guard let effect, let layer = effect.layer else { return }
        // Above the blur's own backdrop, the first of its layers.
        if tintLayer.superlayer !== layer {
            layer.insertSublayer(tintLayer, at: UInt32(min(1, layer.sublayers?.count ?? 0)))
        }
        tintLayer.frame = effect.bounds
        tintLayer.backgroundColor = tint?.nsColor.cgColor
    }

    private func applyFade() {
        guard let effect else { return }
        guard let fade else { effect.layer?.mask = nil; return }
        effect.wantsLayer = true
        let gradient = effect.layer?.mask as? CAGradientLayer ?? CAGradientLayer()
        gradient.frame = effect.bounds
        // AppKit's y runs up: the edges swap.
        gradient.configureFade(toward: fade == .top ? .bottom : fade == .bottom ? .top : fade)
        effect.layer?.mask = gradient
    }

    private var radius: CGFloat {
        shape.isCircular ? min(bounds.width, bounds.height) / 2 : CGFloat(shape.radius)
    }

    func applyShape() {
        if #available(macOS 26.0, *), let glass = effect as? NSGlassEffectView {
            glass.cornerRadius = radius
            return
        }
        wantsLayer = true
        layer?.cornerRadius = radius
        layer?.masksToBounds = radius > 0
    }

    func apply(_ next: EffectKind) {
        guard next != kind else { return }
        let wasGlass = kind.map { if case .glass = $0 { return true } else { return false } }
        kind = next
        let isGlass: Bool
        if case .glass = next { isGlass = true } else { isGlass = false }
        if effect == nil || wasGlass != isGlass { rebuild(isGlass: isGlass) }
        configure()
        applyShape()
    }

    /// The effect view, made once per kind and the content moved into it.
    private func rebuild(isGlass: Bool) {
        let content = host.subviews
        effect?.removeFromSuperview()
        let made: NSView
        if #available(macOS 26.0, *), isGlass {
            let glass = NSGlassEffectView()
            let inner = NSView()
            glass.contentView = inner
            host = inner
            made = glass
        } else {
            let blur = NSVisualEffectView()
            blur.blendingMode = .withinWindow
            blur.state = .active
            host = blur
            made = blur
        }
        made.translatesAutoresizingMaskIntoConstraints = false
        addSubview(made)
        NSLayoutConstraint.activate([
            made.topAnchor.constraint(equalTo: topAnchor),
            made.bottomAnchor.constraint(equalTo: bottomAnchor),
            made.leadingAnchor.constraint(equalTo: leadingAnchor),
            made.trailingAnchor.constraint(equalTo: trailingAnchor)
        ])
        effect = made
        content.forEach { host.addSubview($0) }
    }

    private func configure() {
        guard let kind else { return }
        if #available(macOS 26.0, *), let glass = effect as? NSGlassEffectView, case .glass(let g) = kind {
            glass.style = g.variant == .clear ? .clear : .regular
            glass.tintColor = g.tint?.nsColor
            glass.isHidden = g.variant == .identity
            return
        }
        guard let blur = effect as? NSVisualEffectView else { return }
        switch kind {
        case .glass(let g):
            blur.material = .hudWindow
            blur.isHidden = g.variant == .identity
        case .material(let m):
            blur.isHidden = false
            switch m {
            case .ultraThinMaterial, .thinMaterial: blur.material = .hudWindow
            case .regularMaterial: blur.material = .menu
            case .thickMaterial, .ultraThickMaterial: blur.material = .sidebar
            }
        }
    }
}

final class OmniGlassContainerView: NSView {
    var spacing: Double?
    private(set) var host: NSView = NSView()

    func apply(spacing next: Double) {
        guard spacing != next else { return }
        let firstTime = spacing == nil
        spacing = next
        if #available(macOS 26.0, *) {
            if firstTime {
                let container = NSGlassEffectContainerView()
                let inner = NSView()
                container.contentView = inner
                container.translatesAutoresizingMaskIntoConstraints = false
                addSubview(container)
                NSLayoutConstraint.activate([
                    container.topAnchor.constraint(equalTo: topAnchor),
                    container.bottomAnchor.constraint(equalTo: bottomAnchor),
                    container.leadingAnchor.constraint(equalTo: leadingAnchor),
                    container.trailingAnchor.constraint(equalTo: trailingAnchor)
                ])
                host = inner
            }
            (host.superview as? NSGlassEffectContainerView)?.spacing = CGFloat(next)
        } else if firstTime {
            host = self
        }
    }
}

extension EffectBackgroundView {
    @MainActor public func makeNative() -> NativeView {
        let view = OmniEffectView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }

    @MainActor public func updateNative(_ view: NativeView) {
        guard let view = view as? OmniEffectView else { return }
        view.shape = shape
        view.fade = fade
        view.tint = tint
        view.apply(kind)
        view.needsLayout = true
    }

    @MainActor public func insertChild(_ child: NativeView, into parent: NativeView) {
        let host = (parent as? OmniEffectView)?.host ?? parent
        pin(child, in: host, sizing: parent)
    }
}

extension GlassEffectContainerView {
    @MainActor public func makeNative() -> NativeView {
        let view = OmniGlassContainerView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }

    @MainActor public func updateNative(_ view: NativeView) {
        (view as? OmniGlassContainerView)?.apply(spacing: spacing)
    }

    @MainActor public func insertChild(_ child: NativeView, into parent: NativeView) {
        let host = (parent as? OmniGlassContainerView)?.host ?? parent
        pin(child, in: host, sizing: parent)
    }
}

@MainActor private func pin(_ child: NSView, in host: NSView, sizing parent: NSView) {
    host.addSubview(child)
    adoptSizing(of: child, into: parent)
    NSLayoutConstraint.activate([
        child.topAnchor.constraint(equalTo: host.topAnchor),
        child.bottomAnchor.constraint(equalTo: host.bottomAnchor),
        child.leadingAnchor.constraint(equalTo: host.leadingAnchor),
        child.trailingAnchor.constraint(equalTo: host.trailingAnchor)
    ])
}
#endif

extension CAGradientLayer {
    /// Opaque at the edge across from `edge`, clear at `edge`: full for the
    /// first third, then easing out, so the blur has no line where it ends.
    func configureFade(toward edge: Edge) {
        let alphas: [CGFloat] = [1, 1, 0.75, 0.4, 0.12, 0]
        colors = alphas.map { CGColor(gray: 0, alpha: $0) }
        locations = [0, 0.3, 0.5, 0.7, 0.88, 1]
        switch edge {
        case .bottom: startPoint = CGPoint(x: 0.5, y: 0); endPoint = CGPoint(x: 0.5, y: 1)
        case .top: startPoint = CGPoint(x: 0.5, y: 1); endPoint = CGPoint(x: 0.5, y: 0)
        case .trailing: startPoint = CGPoint(x: 0, y: 0.5); endPoint = CGPoint(x: 1, y: 0.5)
        case .leading: startPoint = CGPoint(x: 1, y: 0.5); endPoint = CGPoint(x: 0, y: 0.5)
        }
    }
}
#endif
