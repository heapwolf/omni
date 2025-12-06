// src/lib/components/apple/Stack+Apple.swift
#if os(macOS) || os(iOS)
import Foundation

#if os(macOS)
    import AppKit
#elseif os(iOS)
    import UIKit
#endif

public extension Stack {
    @MainActor func applyAxis(_ view: NativeView) {
        #if os(macOS)
            (view as? NSStackView)?.orientation = axis == .vertical ? .vertical : .horizontal
        #elseif os(iOS)
            (view as? UIStackView)?.axis = axis == .vertical ? .vertical : .horizontal
        #endif
    }

    @MainActor func recordChild(_ child: NativeView, of parent: NativeView) {}
}
#endif
