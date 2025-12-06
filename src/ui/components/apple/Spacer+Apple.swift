#if os(macOS) || os(iOS)
import Foundation

#if os(macOS)
    import AppKit
    typealias NativeLayoutPriority = NSLayoutConstraint.Priority
    public class OmniSpacerView: NSView {
        // Reports a zero size so hugging priority 1 has a baseline to beat.
        public override var intrinsicContentSize: NSSize { NSSize(width: 0, height: 0) }
    }
#elseif os(iOS)
    import UIKit
    typealias NativeLayoutPriority = UILayoutPriority
    public class OmniSpacerView: UIView {
        public override var intrinsicContentSize: CGSize { CGSize(width: 0, height: 0) }
    }
#endif

// An invisible stand-in for a Spacer the caller never wrote.
@MainActor func makeOmniAutoFillerView() -> OmniSpacerView {
    let v = OmniAutoFillerView()
    let lowPriority = NativeLayoutPriority(rawValue: 1)
    v.setContentHuggingPriority(lowPriority, for: .horizontal)
    // Above the 100 an HStack uses to match its children's heights to its own,
    // below every real fill (a frame, the screen, a stack that wants the room,
    // an overlay's 200). At 1, that weak match stretched a VStack in a row to
    // the row's height through this filler, packing its text at the top beside
    // a taller icon: SwiftUI centres it.
    v.setContentHuggingPriority(NativeLayoutPriority(rawValue: 150), for: .vertical)
    v.setContentCompressionResistancePriority(lowPriority, for: .horizontal)
    v.setContentCompressionResistancePriority(lowPriority, for: .vertical)
    v.translatesAutoresizingMaskIntoConstraints = false
    return v
}

final class OmniAutoFillerView: OmniSpacerView {}

#if os(macOS) || os(iOS)
extension NativeStack {
    /// The filler at the end, with no spacing before it. A stack view puts its
    /// spacing before every arranged view, the filler too: every stack ended
    /// in a gap of its own spacing, one more for each stack nested in it (a
    /// card's text with a band of nothing under it).
    @MainActor func appendFiller() {
        let last = arrangedSubviews.last
        addArrangedSubview(makeOmniAutoFillerView())
        if let last { setCustomSpacing(0, after: last) }
    }

    /// The filler at the end, if there is one, taken out; the view before it
    /// gets the stack's spacing back, for whatever comes after it next.
    @MainActor func removeFiller() {
        guard let filler = arrangedSubviews.last as? OmniAutoFillerView else { return }
        let views = arrangedSubviews
        if views.count >= 2 {
            #if os(macOS)
            setCustomSpacing(NSStackView.useDefaultSpacing, after: views[views.count - 2])
            #else
            setCustomSpacing(UIStackView.spacingUseDefault, after: views[views.count - 2])
            #endif
        }
        removeArrangedSubview(filler)
        filler.removeFromSuperview()
    }
}
#endif

extension Spacer {
    @MainActor public func makeNative() -> NativeView {
        let v = OmniSpacerView()

        let lowPriority = NativeLayoutPriority(rawValue: 1)

        v.setContentHuggingPriority(lowPriority, for: .horizontal)
        v.setContentHuggingPriority(lowPriority, for: .vertical)
        v.setContentCompressionResistancePriority(lowPriority, for: .horizontal)
        v.setContentCompressionResistancePriority(lowPriority, for: .vertical)
        v.translatesAutoresizingMaskIntoConstraints = false

        return v
    }

    @MainActor public func updateNative(_ view: NativeView) {
        // If an AI passes minLength, apply a greater-than-or-equal-to constraint.
        // We do this in updateNative so it applies after the view is created.
        guard let min = minLength else { return }

        if let v = view as? OmniSpacerView, v.constraints.isEmpty {
            NSLayoutConstraint.activate([
                v.widthAnchor.constraint(greaterThanOrEqualToConstant: CGFloat(min)),
                v.heightAnchor.constraint(greaterThanOrEqualToConstant: CGFloat(min))
            ])
        }
    }
}
#endif
