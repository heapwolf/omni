#if os(macOS) || os(iOS)
import Foundation

#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

extension Toggle {
    @MainActor public func makeNative() -> NativeView {
        #if os(macOS)
        let btn = NSButton(checkboxWithTitle: "", target: nil, action: nil)
        btn.translatesAutoresizingMaskIntoConstraints = false
        return btn
        #elseif os(iOS)
        let sw = UISwitch()
        sw.translatesAutoresizingMaskIntoConstraints = false
        return sw
        #endif
    }

    @MainActor public func updateNative(_ view: NativeView) {
        let binding = isOnBinding // Capture the struct locally to safely use inside escaping closures

        #if os(macOS)
        if let btn = view as? NSButton {
            btn.title = title
            btn.state = binding.wrappedValue ? .on : .off
        }
        bindAppleEvent(view, "action") { [weak view] in
            if let btn = view as? NSButton {
                binding.wrappedValue = (btn.state == .on)
            }
        }
        #elseif os(iOS)
        if let sw = view as? UISwitch, sw.isOn != binding.wrappedValue {
            sw.isOn = binding.wrappedValue
        }
        bindAppleEvent(view, "valueChanged") { [weak view] in
            if let sw = view as? UISwitch {
                binding.wrappedValue = sw.isOn
            }
        }
        #endif
    }
}
#endif
