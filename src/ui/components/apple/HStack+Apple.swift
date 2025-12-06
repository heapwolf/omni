#if os(macOS) || os(iOS) || os(tvOS) || os(visionOS)
import Foundation

#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

extension HStack {
    #if os(macOS)
    @MainActor var nativeAlignment: NSLayoutConstraint.Attribute {
        switch alignment {
        case .top: return .top
        case .center: return .centerY
        case .bottom: return .bottom
        }
    }
    #elseif os(iOS)
    @MainActor var nativeAlignment: UIStackView.Alignment {
        switch alignment {
        case .top: return .top
        case .center: return .center
        case .bottom: return .bottom
        }
    }
    #endif

    @MainActor public func makeNative() -> NativeView {
        #if os(macOS)
        let v = OmniStackView()
        v.orientation = .horizontal

        // Layer backing, so .offset() works immediately.
        v.wantsLayer = true
        // Match SwiftUI's native spacing distribution
        v.distribution = .fill
        v.alignment = nativeAlignment

        v.translatesAutoresizingMaskIntoConstraints = false
        #elseif os(iOS)
        let v = UIStackView()
        v.axis = .horizontal
        v.distribution = .fill
        v.alignment = nativeAlignment
        v.translatesAutoresizingMaskIntoConstraints = false
        #endif

        // See VStack+Apple's makeNative: strictly above content's default 750, so a
        // plain row never ties with real content for the enclosing stack's surplus.
        v.setContentHuggingPriority(.init(rawValue: 760), for: .horizontal)
        v.setContentHuggingPriority(.init(rawValue: 760), for: .vertical)
        return v
    }

    @MainActor public func updateNative(_ view: NativeView) {
        guard let stack = view as? NativeStack else { return }
        stack.spacing = resolvedSpacing
        stack.alignment = nativeAlignment
        Self.tieSpacerWidths(in: stack)
    }

    @MainActor private static func tieSpacerWidths(in stack: NativeStack) {
        let existingConstraints = stack.constraints.filter { $0.identifier == "omni-spacer-eq" }
        NSLayoutConstraint.deactivate(existingConstraints)

        let spacers = stack.arrangedSubviews.filter { $0 is OmniSpacerView }
        if spacers.count > 1 {
            let firstSpacer = spacers[0]
            for i in 1..<spacers.count {
                let constraint = firstSpacer.widthAnchor.constraint(equalTo: spacers[i].widthAnchor)
                constraint.identifier = "omni-spacer-eq"
                constraint.isActive = true
            }
        }

        // The other claims on the surplus (.frame(maxWidth: .infinity), a row
        // with a Spacer in it) share it evenly, as in SwiftUI. Untied, they all
        // hug at 1 and the solver gives the lot to one: a keypad row came out
        // as one wide key and two squeezed against the edge. 740, below a
        // label's compression resistance: content that needs more still gets it.
        // Only in a row without a Spacer: there the Spacer is what takes the
        // room, and a sibling that merely inherited a claim (a .background
        // colour, a Circle) must not be widened to split it.
        let hasSpacer = stack.arrangedSubviews.contains { $0 is OmniSpacerView && !($0 is OmniAutoFillerView) }
        let fills = hasSpacer ? [] : stack.arrangedSubviews.filter {
            !($0 is OmniSpacerView) && !($0 is OmniAutoFillerView)
                && $0.contentHuggingPriority(for: .horizontal).rawValue <= 1
        }
        if fills.count > 1 {
            for other in fills.dropFirst() {
                let constraint = fills[0].widthAnchor.constraint(equalTo: other.widthAnchor)
                constraint.priority = .init(rawValue: 740)
                constraint.identifier = "omni-spacer-eq"
                constraint.isActive = true
            }
        }
    }

    @MainActor public func insertChild(_ child: NativeView, into parent: NativeView) {
        guard let stack = parent as? NativeStack else { return }

        // Drop this stack's own filler before deciding whether it still needs one.
        stack.removeFiller()

        stack.addArrangedSubview(child)
        Self.tieSpacerWidths(in: stack)
        Self.holdFillerClosed(in: child)

        let childWantsToFillVertically = !(child is OmniSpacerView)
            && child.contentHuggingPriority(for: .vertical).rawValue <= 1
        let fill = child.heightAnchor.constraint(equalTo: stack.heightAnchor)
        // 740, below a label's compression resistance (750): filling must not
        // squash a column of text to a shorter sibling's height. The row grows
        // to fit it instead, as in SwiftUI.
        fill.priority = .init(rawValue: childWantsToFillVertically ? 740 : 100)
        fill.isActive = true

        let childHexpand = child.contentHuggingPriority(for: .horizontal)
        if childHexpand.rawValue < stack.contentHuggingPriority(for: .horizontal).rawValue {
            stack.setContentHuggingPriority(childHexpand, for: .horizontal)
        }

        // The cross axis: a child that fills height has to carry that claim
        // up, or this stack reports its own natural (compressed) height to
        // whatever wraps it instead of the fill it was just told to honor.
        // A Spacer is a row's to grow along, not across: as in SwiftUI, it
        // makes the row wide, never tall. Carried up, it made every row with a
        // Spacer claim its column's spare height.
        let childVexpand = child.contentHuggingPriority(for: .vertical)
        if !(child is OmniSpacerView), childVexpand.rawValue < stack.contentHuggingPriority(for: .vertical).rawValue {
            stack.setContentHuggingPriority(childVexpand, for: .vertical)
        }

        let anyoneWantsHorizontalRoom = stack.arrangedSubviews.contains {
            $0.contentHuggingPriority(for: .horizontal).rawValue <= 1
        }
        if !anyoneWantsHorizontalRoom {
            stack.appendFiller()
            if (stack.superview as? NativeStack)?.isHorizontalRow == true { Self.holdFillerClosed(in: stack) }
        }
    }

    /// A row that wants no room, in a row: its filler stays shut unless it is
    /// made to open (749, under a label's compression resistance and over
    /// every claim to fill), so the leftover goes to the enclosing row's own
    /// filler. Free, every filler was a candidate, and the first group in a
    /// filter bar took the bar's whole width, its neighbours pushed away.
    @MainActor private static func holdFillerClosed(in view: NativeView) {
        guard let row = view as? NativeStack, row.isHorizontalRow,
              let filler = row.arrangedSubviews.last as? OmniAutoFillerView,
              !filler.constraints.contains(where: { $0.identifier == "omni-filler-shut" }) else { return }
        let shut = filler.widthAnchor.constraint(equalToConstant: 0)
        shut.priority = .init(rawValue: 749)
        shut.identifier = "omni-filler-shut"
        shut.isActive = true
    }
}
#endif

#if os(macOS) || os(iOS) || os(tvOS) || os(visionOS)
extension NativeStack {
    var isHorizontalRow: Bool {
        #if os(macOS)
        return orientation == .horizontal
        #else
        return axis == .horizontal
        #endif
    }
}
#endif
