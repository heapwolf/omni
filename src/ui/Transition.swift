// SwiftUI's transitions: how a view arrives and leaves when a change inside
// withAnimation swaps it for another.
//
//   content(for: step)
//       .transition(.push(from: forward ? .trailing : .leading))
//   ...
//   withAnimation(.easeInOut) { step = .next }
//
// As in SwiftUI, the arriving view animates with its own transition's
// insertion, the leaving view with its own transition's removal, as that view
// last rendered. With no .transition, both fade.
//
// The engine swaps natives in one place, Engine.place (Core.swift); that is
// where this runs. Animated on iOS; the other backends swap instantly for now.

import Foundation

#if os(iOS)
import UIKit
#endif

public struct AnyTransition: Sendable {
    indirect enum Kind: Sendable {
        case identity
        case opacity
        case move(Edge)
        case offset(x: Double, y: Double)
        case scale(Double)
        case asymmetric(insertion: Kind, removal: Kind)
        case combined(Kind, Kind)
    }
    let kind: Kind

    public static let identity = AnyTransition(kind: .identity)
    public static let opacity = AnyTransition(kind: .opacity)
    /// In from the leading edge, out to the trailing one.
    public static let slide = AnyTransition(kind: .asymmetric(insertion: .move(.leading),
                                                              removal: .move(.trailing)))

    public static func move(edge: Edge) -> AnyTransition { AnyTransition(kind: .move(edge)) }

    /// SwiftUI's: arrives from, and leaves to, this far from its place, in points. A short
    /// roll where .move would carry it the container's whole size.
    public static func offset(x: Double = 0, y: Double = 0) -> AnyTransition {
        AnyTransition(kind: .offset(x: x, y: y))
    }

    /// SwiftUI's: grows in from, and shrinks out to, `scale` of its size.
    /// Android fades it instead, for now.
    public static func scale(_ scale: Double) -> AnyTransition { AnyTransition(kind: .scale(scale)) }
    public static let scale = AnyTransition(kind: .scale(0))

    /// In from `edge`, out to the opposite one: a navigation push.
    public static func push(from edge: Edge) -> AnyTransition {
        AnyTransition(kind: .asymmetric(insertion: .move(edge), removal: .move(edge.opposite)))
    }

    public static func asymmetric(insertion: AnyTransition, removal: AnyTransition) -> AnyTransition {
        AnyTransition(kind: .asymmetric(insertion: insertion.kind, removal: removal.kind))
    }

    public func combined(with other: AnyTransition) -> AnyTransition {
        AnyTransition(kind: .combined(kind, other.kind))
    }

    var insertion: Kind {
        if case .asymmetric(let insertion, _) = kind { return insertion }
        return kind
    }

    var removal: Kind {
        if case .asymmetric(_, let removal) = kind { return removal }
        return kind
    }
}

extension Edge {
    var opposite: Edge {
        switch self {
        case .top: return .bottom
        case .bottom: return .top
        case .leading: return .trailing
        case .trailing: return .leading
        }
    }
}

/// Carries a transition on the view it wraps; draws nothing. Kept as a node
/// by Omni.unpackViews, so the engine can find it on the view being swapped.
public struct TransitionModifierView: OmniStructuralView {
    let transition: AnyTransition
    public var content: any View

    public typealias Body = Never
    public var body: Never { fatalError("Engine unpacks this") }
    public var unpacked: [any View] { [content] }
}

public extension View {
    /// How this view arrives and leaves in an animated change.
    func transition(_ transition: AnyTransition) -> some View {
        TransitionModifierView(transition: transition, content: self)
    }
}

extension AnyTransition {
    /// The transition on the view a node shows: the first one down the chain of
    /// nodes that share its native.
    @MainActor static func on(_ node: Node) -> AnyTransition? {
        var current: Node? = node
        while let candidate = current {
            if let transition = candidate.transition { return transition }
            if candidate.nativeOwner != nil { return nil }
            current = candidate.kids.first
        }
        return nil
    }
}

#if os(iOS)
extension AnyTransition.Kind {
    /// The state a view animates from (insertion) or to (removal), in a
    /// container of `size`.
    func apply(to view: UIView, in size: CGSize) {
        switch self {
        case .identity: break
        case .opacity: view.alpha = 0
        case .move(let edge):
            switch edge {
            case .leading: view.transform = CGAffineTransform(translationX: -size.width, y: 0)
            case .trailing: view.transform = CGAffineTransform(translationX: size.width, y: 0)
            case .top: view.transform = CGAffineTransform(translationX: 0, y: -size.height)
            case .bottom: view.transform = CGAffineTransform(translationX: 0, y: size.height)
            }
        case .offset(let x, let y):
            view.transform = CGAffineTransform(translationX: CGFloat(x), y: CGFloat(y))
        case .scale(let scale):
            // Never quite zero: a singular transform draws nothing to animate from.
            let s = CGFloat(max(scale, 0.001))
            view.transform = CGAffineTransform(scaleX: s, y: s)
        case .asymmetric(let insertion, _): insertion.apply(to: view, in: size)
        case .combined(let first, let second):
            first.apply(to: view, in: size)
            let transform = view.transform
            view.transform = .identity
            second.apply(to: view, in: size)
            view.transform = view.transform.concatenating(transform)
        }
    }
}

enum TransitionAnimator {
    /// `new` has just replaced `old` in `container`. Brings `old` back where it
    /// was, above nothing and inert, animates both, then lets `old` go.
    @MainActor static func run(_ animation: Animation, in container: UIView,
                               new: UIView?, insertion: AnyTransition?,
                               old: UIView?, oldFrame: CGRect, removal: AnyTransition?) {
        let size = container.bounds.size
        guard size.width > 0 else { return }

        if let old {
            old.translatesAutoresizingMaskIntoConstraints = true
            old.frame = oldFrame
            old.isUserInteractionEnabled = false
            container.addSubview(old)
        }
        // Where each ends up is its own: an .opacity(0) or .scaleEffect on the view stays.
        // Brought to 1 and identity, a view meant to be unseen (a placeholder holding its
        // place) showed once its transition ran.
        let alpha = new?.alpha ?? 1, transform = new?.transform ?? .identity
        let oldAlpha = old?.alpha ?? 1, oldTransform = old?.transform ?? .identity
        UIView.performWithoutAnimation {
            container.layoutIfNeeded()
            if let new { (insertion?.insertion ?? .opacity).apply(to: new, in: size) }
        }
        // apply sets a transform outright; keep the view's own under it.
        if let new { new.transform = transform.concatenating(new.transform) }

        animation.perform(options: .beginFromCurrentState, {
            new?.transform = transform
            new?.alpha = alpha
            if let old {
                (removal?.removal ?? .opacity).apply(to: old, in: size)
                old.transform = oldTransform.concatenating(old.transform)
            }
        }, completion: { finished in
            // Whole, however it ended: an animation cut short by another left
            // the new view part-scaled, part-faded. Only then: once finished it
            // is where it should be, and a later render may since have moved it.
            if !finished {
                new?.transform = transform
                new?.alpha = alpha
            }
            old?.removeFromSuperview()
            old?.transform = oldTransform
            old?.alpha = oldAlpha
        })
    }
}
#endif
