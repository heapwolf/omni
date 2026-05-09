// src/lib/Animation.swift
import Foundation

#if os(macOS) || os(iOS)
import QuartzCore
#endif

#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#elseif os(Android)
import CAndroid
#endif

public enum AnimationCurve: Equatable, Sendable {
    case linear
    case easeIn
    case easeOut
    case easeInOut
    /// SwiftUI's spring: `response` is the period of one oscillation, in
    /// seconds; `dampingFraction` 1 settles without overshoot, lower bounces.
    case spring(response: Double, dampingFraction: Double)
}

public struct Animation: Equatable, Sendable {
    /// How long it runs. For a spring, until it has settled.
    public var duration: Double
    public var curve: AnimationCurve

    public static let `default` = Animation(duration: 0.3, curve: .easeInOut)
    public static let linear = Animation(duration: 0.3, curve: .linear)

    public static func easeInOut(duration: Double = 0.3) -> Animation { Animation(duration: duration, curve: .easeInOut) }
    public static func easeIn(duration: Double = 0.3) -> Animation { Animation(duration: duration, curve: .easeIn) }
    public static func easeOut(duration: Double = 0.3) -> Animation { Animation(duration: duration, curve: .easeOut) }

    /// SwiftUI's `spring(response:dampingFraction:blendDuration:)`. The blend
    /// is accepted and ignored: omni does not blend one animation into the next.
    public static func spring(response: Double = 0.5, dampingFraction: Double = 0.825,
                              blendDuration: Double = 0) -> Animation {
        let response = max(response, 0.01)
        let damping = min(max(dampingFraction, 0.01), 1)
        return Animation(duration: settlingTime(response: response, damping: damping),
                         curve: .spring(response: response, dampingFraction: damping))
    }

    /// SwiftUI's `spring(duration:bounce:)`: bounce 0 settles without overshoot.
    public static func spring(duration: Double = 0.5, bounce: Double = 0) -> Animation {
        spring(response: duration, dampingFraction: 1 - min(max(bounce, 0), 1))
    }

    public static let spring = spring()
    public static let smooth = spring(duration: 0.5, bounce: 0)
    public static let snappy = spring(duration: 0.5, bounce: 0.15)
    public static let bouncy = spring(duration: 0.5, bounce: 0.3)

    /// Six time constants of the envelope: within 0.25% of the target even
    /// critically damped, which at four was still 9% short and then snapped.
    /// OmniEventBridge.spring takes the same six: change them together.
    static let settlingTimeConstants = 6.0

    static func settlingTime(response: Double, damping: Double) -> Double {
        let omega = 2 * Double.pi / response
        return settlingTimeConstants / (damping * omega)
    }

    /// The curve as OmniEventBridge.interpolator numbers it: 0-3 the eases;
    /// a spring is 1000 plus its damping in thousandths. Its duration is its
    /// settling time, so damping alone fixes its shape.
    var androidCurve: Int32 {
        switch curve {
        case .linear: return 0
        case .easeIn: return 1
        case .easeOut: return 2
        case .easeInOut: return 3
        case .spring(_, let damping): return 1000 + Int32((damping * 1000).rounded())
        }
    }
}

#if os(macOS)
extension Animation {
    /// AppKit has no spring for a block of changes: an ease out stands in.
    var timingFunction: CAMediaTimingFunction {
        switch curve {
        case .linear: return CAMediaTimingFunction(name: .linear)
        case .easeIn: return CAMediaTimingFunction(name: .easeIn)
        case .easeOut: return CAMediaTimingFunction(name: .easeOut)
        case .easeInOut: return CAMediaTimingFunction(name: .easeInEaseOut)
        case .spring: return CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.25, 1)
        }
    }
}
#elseif os(iOS)
extension Animation {
    var uiOptions: UIView.AnimationOptions {
        switch curve {
        case .linear: return .curveLinear
        case .easeIn: return .curveEaseIn
        case .easeOut, .spring: return .curveEaseOut
        case .easeInOut: return .curveEaseInOut
        }
    }

    /// UIView.animate with this curve: a spring as UIKit's own, which takes
    /// SwiftUI's numbers, the eases as options.
    @MainActor func perform(options: UIView.AnimationOptions = [], _ animations: @escaping () -> Void,
                            completion: ((Bool) -> Void)? = nil) {
        let options = options.union(.allowUserInteraction)
        if case .spring(let response, let damping) = curve {
            if #available(iOS 17.0, *) {
                UIView.animate(springDuration: response, bounce: 1 - damping, initialSpringVelocity: 0,
                               delay: 0, options: options, animations: animations, completion: completion)
            } else {
                UIView.animate(withDuration: duration, delay: 0, usingSpringWithDamping: damping,
                               initialSpringVelocity: 0, options: options, animations: animations,
                               completion: completion)
            }
            return
        }
        UIView.animate(withDuration: duration, delay: 0, options: options.union(uiOptions),
                       animations: animations, completion: completion)
    }
}
#endif

// MARK: - Implicit animation

/// SwiftUI's `.animation(_:value:)`: what changes under it animates, when
/// `value` changes. Structural: it draws nothing; the engine sees it and
/// renders its content inside the animation (Engine.renderBody).
public struct ImplicitAnimationView: OmniStructuralView {
    let animation: Animation?
    let value: Any
    /// Whether `value` differs from one seen before.
    let differs: (Any) -> Bool
    public var content: any View

    public typealias Body = Never
    public var body: Never { fatalError("Engine unpacks this") }
    public var unpacked: [any View] { [content] }
}

public extension View {
    /// Animates the changes under this view with `animation` whenever `value`
    /// changes. nil turns it off, as in SwiftUI.
    func animation<V: Equatable>(_ animation: Animation?, value: V) -> some View {
        ImplicitAnimationView(animation: animation, value: value,
                              differs: { ($0 as? V) != value }, content: self)
    }
}

public enum NavigationTransitionDirection {
    case push, pop
}

@MainActor public struct Transaction {
    // Whether we are inside an animation block.
    public static var currentAnimation: Animation?

    public static var navigationTransition: NavigationTransitionDirection?

    /// Every change lands at once, unanimated: SwiftUI's disablesAnimations,
    /// for the whole app. For OmniProbe's in-process host, whose window draws
    /// no frames, so an AppKit animation never finishes and leaves views at
    /// their starting frames (and on a Mac whose display sleeps, as CI's do).
    @_spi(Probe) public static var animationsDisabled = false
}

@MainActor public func withAnimation(_ animation: Animation = .default, _ body: () -> Void) {
    // A test's app, settled at once: see Transaction.animationsDisabled.
    if Transaction.animationsDisabled { return body() }
    let oldAnimation = Transaction.currentAnimation
    Transaction.currentAnimation = animation

    #if os(macOS)
    NSAnimationContext.runAnimationGroup { context in
        context.duration = animation.duration
        context.allowsImplicitAnimation = true // CRITICAL: Allows layers (opacity, scale) to animate

        context.timingFunction = animation.timingFunction

        // Mutating state triggers Engine.render synchronously.
        body()

        // Lay out before the block ends so AppKit can interpolate.
        if let rootNative = Engine.root?.native {
            rootNative.layoutSubtreeIfNeeded()
        }
    }
    #elseif os(iOS)
    // UIView.animate's closure is @escaping though it runs synchronously;
    // withoutActuallyEscaping keeps withAnimation's own parameter non-escaping.
    withoutActuallyEscaping(body) { escapableBody in
        animation.perform {
            // Mutating state triggers Engine.render synchronously.
            escapableBody()

            // Force layout pass for UIKit
            if let rootNative = Engine.root?.native {
                rootNative.layoutIfNeeded()
            }
        }
    }
    #elseif os(Android)
    // Android's equivalent is inverted: TransitionManager snapshots first and
    // animates the difference at the next layout pass.
    if let root = Engine.root?.native {
        omni_jni_begin_transition(OmniAndroid.env, root,
                                  Int(animation.duration * 1000), animation.androidCurve)
    }
    body()

    #elseif os(Linux) || os(Windows)
    // No block-based geometry animation on these backends, so apply the change
    // instantly.
    body()
    #endif

    Transaction.currentAnimation = oldAnimation
}
