// src/lib/components/apple/Divider+Apple.swift
import Foundation

#if os(macOS) || os(iOS)

#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

extension Divider {
    @MainActor public func makeNative() -> NativeView {
        #if os(macOS)
        let box = NSBox()
        box.boxType = .separator
        box.translatesAutoresizingMaskIntoConstraints = false
        return box

        #elseif os(iOS)
        // iOS Fallback
        let v = UIView()
        v.backgroundColor = .separator
        v.translatesAutoresizingMaskIntoConstraints = false

        // CRITICAL FIX: True native iOS dividers are 1 physical pixel, not 1 logic point.
        let thickness = 1.0 / UIScreen.main.scale
        let priority = UILayoutPriority(250)

        if resolvedIsVertical {
            let c = v.widthAnchor.constraint(equalToConstant: thickness)
            c.priority = priority
            c.isActive = true
        } else {
            let c = v.heightAnchor.constraint(equalToConstant: thickness)
            c.priority = priority
            c.isActive = true
        }
        return v
        #endif
    }

    @MainActor public func updateNative(_ view: NativeView) {
        // Static view, no updates needed
    }
}
#endif
