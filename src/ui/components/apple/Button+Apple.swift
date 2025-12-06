// src/lib/components/apple/Button.swift
#if os(macOS) || os(iOS)
import Foundation

#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

extension SystemButtonPrimitive {
    @MainActor public func makeNative() -> NativeView {
        #if os(macOS)
        let btn = NSButton(title: "", target: nil, action: nil)
        btn.translatesAutoresizingMaskIntoConstraints = false
        return btn
        #elseif os(iOS)
        let btn = UIButton(type: .system)
        btn.translatesAutoresizingMaskIntoConstraints = false
        // Do not set automaticallyUpdatesConfiguration: it zeroes intrinsic height.
        return btn
        #endif
    }

    @MainActor public func updateNative(_ view: NativeView) {
        if let btn = view as? NativeButton {
            #if os(macOS)
            btn.title = title

            // NSButton has no textColor; an attributed title is the only way to colour it.
            if let color = foregroundColor {
                let attributed = NSMutableAttributedString(string: title)
                attributed.addAttribute(.foregroundColor, value: color.nsColor,
                                         range: NSRange(location: 0, length: attributed.length))
                btn.attributedTitle = attributed
            }
            #elseif os(iOS)
            if btn.title(for: .normal) != title {
                btn.setTitle(title, for: .normal)
            }

            if let font { btn.titleLabel?.font = font.uiFont }

            if let color = foregroundColor {
                btn.tintColor = color.uiColor
                btn.setTitleColor(color.uiColor, for: .normal)
                btn.setTitleColor(color.uiColor, for: .highlighted)
            }
            #endif

            // Assuming bindAppleEvent is defined in your Apple-specific utility files
            bindAppleEvent(view, "touchUpInside", action)
        }
    }
}
#endif
