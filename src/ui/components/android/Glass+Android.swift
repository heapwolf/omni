// src/lib/components/android/Glass+Android.swift
#if os(Android)
import Foundation
import CAndroid

/// Android cannot blur what lies behind a view, so glass and materials are a
/// translucent fill and a hairline, lighter or darker with the scheme. Every
/// view renders again when the scheme changes, which re-picks them.
extension EffectBackgroundView {
    @MainActor public func makeNative() -> NativeView {
        OmniAndroid.makeContainer()
    }

    @MainActor public func updateNative(_ view: NativeView) {
        let isDark = Appearance.current == .dark
        var fill: Color
        switch kind {
        case .glass(let glass):
            switch glass.variant {
            case .identity: fill = .rgba(r: 0, g: 0, b: 0, a: 0)
            case .clear: fill = isDark ? .rgba(r: 1, g: 1, b: 1, a: 0.06) : .rgba(r: 1, g: 1, b: 1, a: 0.30)
            // Nearly opaque: with no blur, content showed through it legibly (a list
            // under the tab bar read through the tabs).
            case .regular: fill = isDark ? .rgba(r: 0.17, g: 0.17, b: 0.19, a: 0.94) : .rgba(r: 0.98, g: 0.98, b: 0.99, a: 0.94)
            }
            if let tint = glass.tint, glass.variant != .identity {
                let t = tint.rgbaComponents
                fill = .rgba(r: t.r, g: t.g, b: t.b, a: 0.35)
            }
        case .material(let material):
            let level: Double
            switch material {
            case .ultraThinMaterial: level = 0
            case .thinMaterial: level = 1
            case .regularMaterial: level = 2
            case .thickMaterial: level = 3
            case .ultraThickMaterial: level = 4
            }
            fill = isDark ? .rgba(r: 0, g: 0, b: 0, a: 0.30 + level * 0.14)
                          : .rgba(r: 1, g: 1, b: 1, a: 0.45 + level * 0.12)
        }
        // A tint given is the background it sits on: no blur here to tint.
        if let tint { fill = tint }
        // Fading toward an edge: the fill, clear at that edge, and no hairline, which
        // drew a box around what should recede (the strip behind a tab bar).
        if let fade {
            let clear = fill.opacity(0)
            let (sx, sy, ex, ey): (Float, Float, Float, Float)
            switch fade {
            case .top: (sx, sy, ex, ey) = (0, 1, 0, 0)
            case .bottom: (sx, sy, ex, ey) = (0, 0, 0, 1)
            case .leading: (sx, sy, ex, ey) = (1, 0, 0, 0)
            case .trailing: (sx, sy, ex, ey) = (0, 0, 1, 0)
            }
            let colors = [Self.argb(fill), Self.argb(clear)]
            colors.withUnsafeBufferPointer { buffer in
                omni_jni_set_linear_gradient(OmniAndroid.env, view, buffer.baseAddress, 2, sx, sy, ex, ey)
            }
            return
        }
        let stroke: Color = isDark ? .rgba(r: 1, g: 1, b: 1, a: 0.14) : .rgba(r: 0, g: 0, b: 0, a: 0.08)
        let isIdentity: Bool
        if case .glass(let glass) = kind { isIdentity = glass.variant == .identity } else { isIdentity = false }
        omni_jni_set_glass(OmniAndroid.env, view, Self.argb(fill), isIdentity ? 0 : Self.argb(stroke),
                           Float(shape.radius), shape.isCircular ? 1 : 0)
        // The faint shadow iOS's regular glass casts (under a tab bar).
        if case .glass(let glass) = kind, glass.variant == .regular {
            omni_jni_set_glass_shadow(OmniAndroid.env, view, 6)
        }
    }

    static func argb(_ color: Color) -> Int32 {
        let c = color.rgbaComponents
        func byte(_ v: Double) -> UInt32 { UInt32(max(0, min(255, (v * 255).rounded()))) }
        return Int32(bitPattern: byte(c.a) << 24 | byte(c.r) << 16 | byte(c.g) << 8 | byte(c.b))
    }
}

extension GlassEffectContainerView {
    @MainActor public func makeNative() -> NativeView {
        OmniAndroid.makeContainer()
    }

    @MainActor public func updateNative(_ view: NativeView) {}
}
#endif
