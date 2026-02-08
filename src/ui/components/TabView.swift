import Foundation

// MARK: - Styles & Environment

public protocol TabViewStyle: Sendable {}
public struct DefaultTabViewStyle: TabViewStyle { public init() {} }
public struct PageTabViewStyle: TabViewStyle { public init() {} }

public struct TabViewStyleKey: EnvironmentKey {
    public static let defaultValue: any TabViewStyle = DefaultTabViewStyle()
}

public extension EnvironmentValues {
    var tabViewStyle: any TabViewStyle {
        get { self[TabViewStyleKey.self] }
        set { self[TabViewStyleKey.self] = newValue }
    }
}

public extension View {
    func tabViewStyle<S: TabViewStyle>(_ style: S) -> some View {
        self.environment(\.tabViewStyle, style)
    }
}

// MARK: - Type Erasure

/// @MainActor: its conformers wrap View content, so the conformance would
/// otherwise cross the actor boundary the View protocol now draws.
@MainActor
public protocol AnyTabItem {
    var anyLabel: any View { get }
    var anyContent: any View { get }
    var anyTag: AnyHashable? { get }
}

public struct TabItemWrapper<Content: View, Label: View>: View, AnyTabItem {
    public var content: Content
    public var label: Label
    public var tag: AnyHashable?

    public init(content: Content, label: Label, tag: AnyHashable? = nil) {
        self.content = content
        self.label = label
        self.tag = tag
    }

    public var anyLabel: any View { label }
    public var anyContent: any View { content }
    public var anyTag: AnyHashable? { tag }

    public var body: some View { content }
}

public extension View {
    func tabItem<Label: View>(@ViewBuilder _ label: () -> Label) -> TabItemWrapper<Self, Label> {
        TabItemWrapper(content: self, label: label())
    }
}

public extension TabItemWrapper {
    func tag<V: Hashable>(_ tag: V) -> TabItemWrapper<Content, Label> {
        var copy = self
        copy.tag = tag
        return copy
    }
}

// MARK: - Native Swipe Interceptor Base

// A structural modifier that intercepts physical swipes and passes them up as closures
public struct NativeSwipeModifierView: NativeComponent {
    public var content: any View
    public var onSwipeLeft: () -> Void
    public var onSwipeRight: () -> Void

    public var children: [any View] { [content] }

    public init(content: any View, onSwipeLeft: @escaping () -> Void, onSwipeRight: @escaping () -> Void) {
        self.content = content
        self.onSwipeLeft = onSwipeLeft
        self.onSwipeRight = onSwipeRight
    }
}

// MARK: - The Main TabView Component

public struct TabView<SelectionValue: Hashable, Content: View>: View {
    public var selection: Binding<SelectionValue>?

    @State private var internalSelection: Int = 0
    /// Which way the pages slide: set a render before the page changes, as a
    /// leaving view goes the way it last rendered with.
    @State private var isForward = true
    public var content: Content

    @MainActor public init(selection: Binding<SelectionValue>? = nil, @ViewBuilder content: () -> Content) {
        self.selection = selection
        self.content = content()
    }

    public var body: some View {
        let views = Omni.unpackViews(content)
        var tabs: [(content: any View, label: any View, tag: AnyHashable?)] = []

        for v in views {
            if let tab = v as? AnyTabItem {
                tabs.append((content: tab.anyContent, label: tab.anyLabel, tag: tab.anyTag))
            } else {
                tabs.append((content: v, label: Text("Tab"), tag: nil))
            }
        }

        var activeIndex = 0
        if let boundSelection = selection?.wrappedValue {
            if let idx = tabs.firstIndex(where: { $0.tag == AnyHashable(boundSelection) }) {
                activeIndex = idx
            }
        } else {
            activeIndex = internalSelection
        }

        let safeIndex = max(0, min(activeIndex, max(0, tabs.count - 1)))

        let goNext = {
            let next = min(safeIndex + 1, tabs.count - 1)
            updateSelection(to: next, tabs: tabs)
        }

        let goPrev = {
            let prev = max(safeIndex - 1, 0)
            updateSelection(to: prev, tabs: tabs)
        }

        let style = Tracker.current?.environment.tabViewStyle
        let isPageStyle = style is PageTabViewStyle

        if isPageStyle {
            // PAGE STYLE: Overlay dots, hide button bar, enable swipe gestures
            return AnyView(NativeSwipeModifierView(content: AnyView(
                ZStack {
                    if !tabs.isEmpty {
                        // The page is keyed, so a swipe makes a new view
                        // rather than reshaping the old one in place (which
                        // grew out of the top-left corner). The key is inside
                        // a stable AnyView: the ZStack keeps the same kid, and
                        // that kid's view being swapped is what runs its
                        // transition. A key on the ZStack's kid itself rebuilt
                        // the ZStack, which inserts without one.
                        AnyView(IdentifiedView(identity: safeIndex, content: AnyView(tabs[safeIndex].content)))
                            .transition(.push(from: isForward ? .trailing : .leading))
                    }

                    VStack {
                        Spacer()
                        HStack(spacing: 8) {
                            Spacer()
                            ForEach(Array(tabs.enumerated())) { item in
                                // Filled: an unfilled Circle is a clear Spacer, so
                                // the dots never showed. The text colour reads on
                                // either theme; the current page at full strength.
                                Circle().fill(Color.primaryText)
                                    .opacity(item.offset == safeIndex ? 1.0 : 0.3)
                                    // UIPageControl's: 7 points, 9 apart.
                                    .frame(width: 7, height: 7)
                            }
                            Spacer()
                        }
                        .padding(horizontal: 0, vertical: 16)
                    }
                }
            ), onSwipeLeft: goNext, onSwipeRight: goPrev)) // <-- Wrapped NativeSwipeModifierView in AnyView

        } else {
            // DEFAULT STYLE: Standard bottom bar
            return AnyView(
                VStack {
                    if !tabs.isEmpty {
                        AnyView(tabs[safeIndex].content)
                    }
                    Spacer()
                    Divider()
                    HStack {
                        Spacer()
                        ForEach(Array(tabs.enumerated())) { item in
                            Button(action: {
                                updateSelection(to: item.offset, tabs: tabs)
                            }) {
                                VStack {
                                    AnyView(item.element.label)
                                }
                            }
                            Spacer()
                        }
                    }
                    .padding(horizontal: 0, vertical: 8)
                }
            )
        }
    }

    @MainActor private func updateSelection(to index: Int, tabs: [(content: any View, label: any View, tag: AnyHashable?)]) {
        let current = currentIndex(tabs)
        guard index != current else { return }
        isForward = index > current
        // The direction renders first; the page changes on the next turn.
        DispatchQueue.main.async { applySelection(index, tabs) }
    }

    @MainActor private func currentIndex(_ tabs: [(content: any View, label: any View, tag: AnyHashable?)]) -> Int {
        if let bound = selection?.wrappedValue,
           let index = tabs.firstIndex(where: { $0.tag == AnyHashable(bound) }) { return index }
        return selection == nil ? internalSelection : 0
    }

    @MainActor private func applySelection(_ index: Int, _ tabs: [(content: any View, label: any View, tag: AnyHashable?)]) {
        withAnimation(.easeInOut(duration: 0.3)) {
            if let bound = selection, let tag = tabs[index].tag?.base as? SelectionValue {
                bound.wrappedValue = tag
            } else {
                internalSelection = index
            }
        }
    }
}

public extension TabView where SelectionValue == Int {
    @MainActor init(@ViewBuilder content: () -> Content) {
        self.selection = nil
        self.content = content()
    }
}
