#if os(macOS) || os(iOS)
import Foundation

#if os(macOS)
import AppKit

public class OmniClipView: NSView {
    var radius: Double = 0
    var isCircular: Bool = false

    public override func layout() {
        super.layout()
        wantsLayer = true
        layer?.masksToBounds = true
        // Clamped to half the short side, as SwiftUI's RoundedRectangle is;
        // beyond it the corners meet in a point.
        let half = min(bounds.width, bounds.height) / 2
        layer?.cornerRadius = isCircular ? half : min(CGFloat(radius), half)
    }
}
#elseif os(iOS)
import UIKit

public class OmniClipView: UIView {
    var radius: Double = 0
    var isCircular: Bool = false

    public override func layoutSubviews() {
        super.layoutSubviews()
        clipsToBounds = true
        // Clamped to half the short side, as SwiftUI's RoundedRectangle is;
        // beyond it the corners meet in a point.
        let half = min(bounds.width, bounds.height) / 2
        layer.cornerRadius = isCircular ? half : min(CGFloat(radius), half)

        layer.shouldRasterize = true
        layer.rasterizationScale = UIScreen.main.scale
    }
}
#endif

extension ClipModifierView {
    @MainActor public func makeNative() -> NativeView {
        let v = OmniClipView()
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }

    @MainActor public func updateNative(_ view: NativeView) {
        if let v = view as? OmniClipView {
            v.radius = radius
            v.isCircular = isCircular
            #if os(macOS)
            v.needsLayout = true
            #elseif os(iOS)
            v.setNeedsLayout()
            #endif
        }
    }

    @MainActor public func insertChild(_ child: NativeView, into parent: NativeView) {
        parent.addSubview(child)
        NSLayoutConstraint.activate([
            child.topAnchor.constraint(equalTo: parent.topAnchor),
            child.bottomAnchor.constraint(equalTo: parent.bottomAnchor),
            child.leadingAnchor.constraint(equalTo: parent.leadingAnchor),
            child.trailingAnchor.constraint(equalTo: parent.trailingAnchor)
        ])

        // A clip is cosmetic — it must not have a sizing opinion of its own.
        // Without this, a clipped view (e.g. Circle().fill(_:), which is a
        // Spacer under the mask) reports the default hugging of a bare
        // NSView instead of the Spacer's, so a ZStack/HStack/VStack never
        // learns this content wants to fill and it collapses to zero size.
        parent.setContentHuggingPriority(child.contentHuggingPriority(for: .horizontal), for: .horizontal)
        parent.setContentHuggingPriority(child.contentHuggingPriority(for: .vertical), for: .vertical)
    }
}
#endif
