#if os(macOS) || os(iOS)
import Foundation

#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

extension SplitView {
    @MainActor public func makeNative() -> NativeView {
        #if os(macOS)
        let sv = NSSplitView()
        sv.isVertical = isVertical
        sv.translatesAutoresizingMaskIntoConstraints = false
        return sv

        #elseif os(iOS)
        // iOS Fallback
        let sv = UIStackView()
        sv.axis = isVertical ? .horizontal : .vertical
        sv.distribution = .fillEqually
        sv.translatesAutoresizingMaskIntoConstraints = false
        return sv
        #endif
    }

    @MainActor public func updateNative(_ view: NativeView) {
        #if os(macOS)
        (view as? NSSplitView)?.isVertical = isVertical
        #elseif os(iOS)
        (view as? UIStackView)?.axis = isVertical ? .horizontal : .vertical
        #endif
    }

    @MainActor public func insertChild(_ child: NativeView, into parent: NativeView) {
        #if os(macOS)
        (parent as? NSSplitView)?.addArrangedSubview(child)
        #elseif os(iOS)
        (parent as? UIStackView)?.addArrangedSubview(child)
        #endif
    }
}
#endif
