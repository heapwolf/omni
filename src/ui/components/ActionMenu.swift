import Foundation

/// One action in an ActionMenu.
public struct ActionItem {
    public var title: String
    public var systemImage: String?
    /// Drawn as destructive: red on Apple, and a confirm is the caller's.
    public var isDestructive: Bool
    public var action: () -> Void

    public init(_ title: String, systemImage: String? = nil, isDestructive: Bool = false,
                action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.isDestructive = isDestructive
        self.action = action
    }
}

/// A visible "⋯" button that opens its actions: the one way to a row's or a
/// screen's actions, never a right-click (docs: "everything visible"). Native
/// where the platform has a menu for a button (macOS NSMenu, iOS UIMenu);
/// elsewhere the actions open in place below the button.
public struct ActionMenu: View {
    public var items: [ActionItem]
    /// The button's symbol; "ellipsis" by default.
    public var systemImage: String
    /// Read aloud, and the tooltip on desktop.
    public var label: String

    public init(_ items: [ActionItem], systemImage: String = "ellipsis", label: String = "Actions") {
        self.items = items
        self.systemImage = systemImage
        self.label = label
    }

    public var body: some View {
        #if os(macOS) || os(iOS)
        return ActionMenuNative(items: items, systemImage: systemImage, label: label)
        #else
        return ActionMenuInPlace(items: items, systemImage: systemImage)
        #endif
    }
}

/// The actions under the button, shown and hidden by it: for platforms whose
/// buttons carry no menu.
struct ActionMenuInPlace: View {
    let items: [ActionItem]
    let systemImage: String
    @State private var isOpen = false

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            Image(systemName: systemImage).frame(width: 20, height: 20)
                .onTapGesture { isOpen.toggle() }
            if isOpen {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    Text(item.title).foregroundColor(item.isDestructive ? .red : .primaryText)
                        .padding(.vertical, 4)
                        .onTapGesture {
                            isOpen = false
                            item.action()
                        }
                }
            }
        }
    }
}
