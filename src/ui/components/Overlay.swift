import Foundation

#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

// .overlay, sized by the view it decorates, as in SwiftUI. A ZStack sizes to
// its largest child, so a RoundedRectangle stroke over a card made the card
// claim all the room a Spacer should have had.
//
// Apple only for now; the other backends still build .overlay as a ZStack.
#if os(macOS) || os(iOS)
public struct OverlayView: NativeComponent {
    public var base: any View
    public var overlay: any View
    public var alignment: Alignment

    public var children: [any View] { [base, overlay] }

    public init(base: any View, overlay: any View, alignment: Alignment) {
        self.base = base
        self.overlay = overlay
        self.alignment = alignment
    }

    @MainActor public func makeNative() -> NativeView {
        let view = OmniOverlayHostView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }

    @MainActor public func updateNative(_ view: NativeView) {}

    @MainActor public func insertChild(_ child: NativeView, into parent: NativeView) {
        let isBase = parent.subviews.isEmpty
        parent.addSubview(child)

        if isBase {
            adoptSizing(of: child, into: parent)
            NSLayoutConstraint.activate([
                child.topAnchor.constraint(equalTo: parent.topAnchor),
                child.bottomAnchor.constraint(equalTo: parent.bottomAnchor),
                child.leadingAnchor.constraint(equalTo: parent.leadingAnchor),
                child.trailingAnchor.constraint(equalTo: parent.trailingAnchor)
            ])
            return
        }

        // Inside the base, never pushing on it.
        var constraints = [
            child.topAnchor.constraint(greaterThanOrEqualTo: parent.topAnchor),
            child.bottomAnchor.constraint(lessThanOrEqualTo: parent.bottomAnchor),
            child.leadingAnchor.constraint(greaterThanOrEqualTo: parent.leadingAnchor),
            child.trailingAnchor.constraint(lessThanOrEqualTo: parent.trailingAnchor)
        ]
        // Offered the base's whole size below every hugging priority that matters:
        // a shape (hugging 1) fills it, a Text (250) keeps its own size.
        let fillWidth = child.widthAnchor.constraint(equalTo: parent.widthAnchor)
        let fillHeight = child.heightAnchor.constraint(equalTo: parent.heightAnchor)
        fillWidth.priority = .init(rawValue: 200)
        fillHeight.priority = .init(rawValue: 200)
        constraints += [fillWidth, fillHeight]

        switch alignment.horizontal {
        case .leading: constraints.append(child.leadingAnchor.constraint(equalTo: parent.leadingAnchor))
        case .center: constraints.append(child.centerXAnchor.constraint(equalTo: parent.centerXAnchor))
        case .trailing: constraints.append(child.trailingAnchor.constraint(equalTo: parent.trailingAnchor))
        }
        switch alignment.vertical {
        case .top: constraints.append(child.topAnchor.constraint(equalTo: parent.topAnchor))
        case .center: constraints.append(child.centerYAnchor.constraint(equalTo: parent.centerYAnchor))
        case .bottom: constraints.append(child.bottomAnchor.constraint(equalTo: parent.bottomAnchor))
        }
        NSLayoutConstraint.activate(constraints)
    }
}
#endif

#if os(macOS) || os(iOS)
/// Touches go through the overlay to the base, as in SwiftUI, unless they land
/// on something in the overlay that takes them: a control, a text view, a view
/// with a gesture. A border stroked over a text field must not swallow its taps.
public final class OmniOverlayHostView: NativeView {
    #if os(iOS)
    public override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard isUserInteractionEnabled, !isHidden, alpha > 0.01,
              self.point(inside: point, with: event) else { return nil }
        if subviews.count > 1, let hit = subviews[1].hitTest(convert(point, to: subviews[1]), with: event),
           Self.takesTouches(hit, within: subviews[1]) {
            return hit
        }
        guard let base = subviews.first else { return self }
        return base.hitTest(convert(point, to: base), with: event) ?? self
    }

    private static func takesTouches(_ view: UIView, within root: UIView) -> Bool {
        var current: UIView? = view
        while let candidate = current {
            if candidate is UIControl || candidate is UITextView
                || !(candidate.gestureRecognizers ?? []).isEmpty { return true }
            if candidate === root { return false }
            current = candidate.superview
        }
        return false
    }
    #else
    public override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        guard !isHidden, bounds.contains(local) else { return nil }
        if subviews.count > 1, let hit = subviews[1].hitTest(local),
           Self.takesTouches(hit, within: subviews[1]) {
            return hit
        }
        return subviews.first?.hitTest(local) ?? self
    }

    private static func takesTouches(_ view: NSView, within root: NSView) -> Bool {
        var current: NSView? = view
        while let candidate = current {
            if candidate is NSControl || !candidate.gestureRecognizers.isEmpty { return true }
            if candidate === root { return false }
            current = candidate.superview
        }
        return false
    }
    #endif
}
#endif
