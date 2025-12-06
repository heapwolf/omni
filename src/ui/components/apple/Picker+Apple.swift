#if os(macOS) || os(iOS)
import Foundation

#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

extension NativePicker {
    @MainActor public func makeNative() -> NativeView {
        #if os(macOS)
            let pub = NSPopUpButton(frame: .zero, pullsDown: false)
            pub.translatesAutoresizingMaskIntoConstraints = false
            pub.removeAllItems()
            pub.addItems(withTitles: options.map { $0.label })

            bindAppleEvent(pub, "action") { [selection, options, weak pub] in
                guard let pub = pub else { return }
                let idx = pub.indexOfSelectedItem
                if idx >= 0 && idx < options.count {
                    selection.wrappedValue = options[idx].tag
                }
            }
            return pub

        #elseif os(iOS)
            // iOS 14+ standard uses a UIButton with a UIMenu for inline dropdowns
            let btn = UIButton(type: .system)
            btn.translatesAutoresizingMaskIntoConstraints = false
            btn.showsMenuAsPrimaryAction = true
            return btn
        #endif
    }

    @MainActor public func updateNative(_ view: NativeView) {
        let currentSelection = selection.wrappedValue
        let selectedIndex = options.firstIndex(where: { $0.tag == currentSelection }) ?? 0

        #if os(macOS)
            if let pub = view as? NSPopUpButton {
                if pub.indexOfSelectedItem != selectedIndex {
                    pub.selectItem(at: selectedIndex)
                }
            }

        #elseif os(iOS)
            if let btn = view as? UIButton {
                // Rebuild the menu to reflect the active checkmark state
                let actions = options.enumerated().map { (idx, opt) in
                    UIAction(title: opt.label, state: idx == selectedIndex ? .on : .off) { _ in
                        selection.wrappedValue = opt.tag
                    }
                }
                btn.menu = UIMenu(title: "", children: actions)

                // Set the button title to the active selection
                if !options.isEmpty {
                    btn.setTitle(options[selectedIndex].label + " ▼", for: .normal)
                }
            }
        #endif
    }
}
#endif
