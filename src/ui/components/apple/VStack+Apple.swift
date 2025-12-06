#if os(macOS) || os(iOS)
import Foundation

#if os(macOS)
import AppKit

public class OmniStackView: NSStackView {
    nonisolated public override var isFlipped: Bool { true }
}
#elseif os(iOS)
import UIKit
#endif

extension VStack {
    #if os(macOS)
    @MainActor var nativeAlignment: NSLayoutConstraint.Attribute {
        switch alignment {
        case .leading: return .leading
        case .center: return .centerX
        case .trailing: return .trailing
        }
    }
    #elseif os(iOS)
    @MainActor var nativeAlignment: UIStackView.Alignment {
        switch alignment {
        case .leading: return .leading
        case .center: return .center
        case .trailing: return .trailing
        }
    }
    #endif

    @MainActor public func makeNative() -> NativeView {
        #if os(macOS)
            let v = OmniStackView()
            v.orientation = .vertical
            v.distribution = .fill
            v.alignment = nativeAlignment
            v.wantsLayer = true // 👈 Force Core Animation layer backing
            v.translatesAutoresizingMaskIntoConstraints = false
        #elseif os(iOS)
            let v = UIStackView()
            v.axis = .vertical
            v.distribution = .fill
            v.alignment = nativeAlignment
            v.translatesAutoresizingMaskIntoConstraints = false
        #endif

        // Above content's 750: a tie lets the solver pick, and it picks by insertion order.
        v.setContentHuggingPriority(.init(rawValue: 760), for: .horizontal)
        v.setContentHuggingPriority(.init(rawValue: 760), for: .vertical)
        return v
    }

    @MainActor public func updateNative(_ view: NativeView) {
        if let stack = view as? NativeStack {
            stack.spacing = resolvedSpacing
            stack.alignment = nativeAlignment
            Self.tieSpacerHeights(in: stack)
        }
    }

    @MainActor private static func tieSpacerHeights(in stack: NativeStack) {
        // Remove old constraints to avoid duplicates on re-render.
        let existingConstraints = stack.constraints.filter { $0.identifier == "omni-spacer-eq" }
        NSLayoutConstraint.deactivate(existingConstraints)

        // Find all spacers in this stack
        let spacers = stack.arrangedSubviews.filter { $0 is OmniSpacerView }

        // Tie spacer heights together.
        if spacers.count > 1 {
            let firstSpacer = spacers[0]
            for i in 1..<spacers.count {
                let constraint = firstSpacer.heightAnchor.constraint(equalTo: spacers[i].heightAnchor)
                constraint.identifier = "omni-spacer-eq" // Tag it so we can easily remove it later
                constraint.isActive = true
            }
        }
    }

    @MainActor public func insertChild(_ child: NativeView, into parent: NativeView) {
        guard let stack = parent as? NativeStack else { return }

        // Drop this stack's own filler before deciding whether it still needs one.
        stack.removeFiller()

        stack.addArrangedSubview(child)
        Self.tieSpacerHeights(in: stack)

        // Below 250 and above 50: above stretches plain Text, below loses to the alignment spanner.
        let childWantsToFillHorizontally = !(child is OmniSpacerView)
            && child.contentHuggingPriority(for: .horizontal).rawValue <= 1
        let fill = child.widthAnchor.constraint(equalTo: stack.widthAnchor)
        fill.priority = .init(rawValue: childWantsToFillHorizontally ? 900 : 100)
        fill.isActive = true

        let childVexpand = child.contentHuggingPriority(for: .vertical)
        if childVexpand.rawValue < stack.contentHuggingPriority(for: .vertical).rawValue {
            stack.setContentHuggingPriority(childVexpand, for: .vertical)
        }

        // The cross axis: a child that fills width (a row's own HStack, say)
        // has to carry that claim up, or this stack reports its own natural
        // (compressed) width to whatever wraps it, and a VStack of VStacks
        // never actually reaches full width — it just centers at its
        // narrowest fitting size instead.
        // A Spacer in a column grows it tall, never wide (see HStack's).
        let childHexpand = child.contentHuggingPriority(for: .horizontal)
        if !(child is OmniSpacerView), childHexpand.rawValue < stack.contentHuggingPriority(for: .horizontal).rawValue {
            stack.setContentHuggingPriority(childHexpand, for: .horizontal)
        }

        let anyoneWantsVerticalRoom = stack.arrangedSubviews.contains {
            $0.contentHuggingPriority(for: .vertical).rawValue <= 1
        }
        if !anyoneWantsVerticalRoom {
            stack.appendFiller()
        }
    }
}
#endif
