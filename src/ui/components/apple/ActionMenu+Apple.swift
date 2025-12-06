#if os(macOS) || os(iOS)
import Foundation

#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

/// ActionMenu on Apple: a borderless symbol button whose click opens a native
/// menu (NSMenu under the button on macOS; UIMenu as the button's primary
/// action on iOS).
struct ActionMenuNative: NativeComponent {
    let items: [ActionItem]
    let systemImage: String
    let label: String

    @MainActor func makeNative() -> NativeView {
        #if os(macOS)
        let button = ActionMenuButton()
        button.isBordered = false
        button.bezelStyle = .inline
        button.imagePosition = .imageOnly
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setContentHuggingPriority(.required, for: .horizontal)
        button.setContentHuggingPriority(.required, for: .vertical)
        return button
        #else
        let button = UIButton(type: .system)
        button.showsMenuAsPrimaryAction = true
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setContentHuggingPriority(.required, for: .horizontal)
        return button
        #endif
    }

    @MainActor func updateNative(_ view: NativeView) {
        #if os(macOS)
        guard let button = view as? ActionMenuButton else { return }
        button.image = NSImage(systemSymbolName: systemImage, accessibilityDescription: label)
        button.toolTip = label
        button.setAccessibilityLabel(label)
        button.items = items
        #else
        guard let button = view as? UIButton else { return }
        button.setImage(UIImage(systemName: systemImage), for: .normal)
        button.accessibilityLabel = label
        button.menu = UIMenu(title: "", children: items.map { item in
            UIAction(title: item.title, image: item.systemImage.flatMap { UIImage(systemName: $0) },
                     attributes: item.isDestructive ? .destructive : []) { _ in item.action() }
        })
        #endif
    }
}

#if os(macOS)
/// Opens its menu under itself, on click, as a pull-down would.
final class ActionMenuButton: NSButton {
    var items: [ActionItem] = []
    /// Asked when the menu opens, for a button whose items can change after
    /// it's made (a table row's, kept across renders): the latest, not those
    /// it was made with.
    var provide: (() -> [ActionItem])?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        target = self
        action = #selector(open)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    @objc private func open() {
        if let provide { items = provide() }
        let menu = NSMenu()
        menu.autoenablesItems = false
        for (index, item) in items.enumerated() {
            let entry = NSMenuItem(title: item.title, action: #selector(choose(_:)), keyEquivalent: "")
            entry.target = self
            entry.tag = index
            if let symbol = item.systemImage {
                entry.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
            }
            if item.isDestructive {
                entry.attributedTitle = NSAttributedString(string: item.title,
                                                           attributes: [.foregroundColor: NSColor.systemRed])
            }
            menu.addItem(entry)
        }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: bounds.height + 4), in: self)
    }

    @objc private func choose(_ sender: NSMenuItem) {
        guard items.indices.contains(sender.tag) else { return }
        items[sender.tag].action()
    }
}
#endif
#endif
