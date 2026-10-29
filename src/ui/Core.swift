// src/ui/Core.swift
// Swift 6 only. Swift 5 is not a compatibility surface here.
import Foundation

#if os(macOS)
    import AppKit
    public typealias NativeView = NSView; public typealias NativeStack = NSStackView
    public typealias NativeButton = NSButton; public typealias NativeControl = NSControl
    public typealias NativeRect = NSRect; public typealias NativeApp = NSApplication
    public typealias NativeTextField = NSTextField; public typealias NativeScrollView = NSScrollView
    public typealias NativeFont = NSFont; public typealias NativeColor = NSColor
#elseif os(iOS)
    import UIKit
    public typealias NativeView = UIView; public typealias NativeStack = UIStackView
    public typealias NativeButton = UIButton; public typealias NativeControl = UIControl
    public typealias NativeRect = CGRect; public typealias NativeApp = UIApplication
    public typealias NativeTextField = UITextField; public typealias NativeScrollView = UIScrollView
    public typealias NativeFont = UIFont; public typealias NativeColor = UIColor
#elseif os(Linux)
    import Glibc
    public typealias NativeView = UnsafeMutableRawPointer; public typealias NativeStack = UnsafeMutableRawPointer
    public typealias NativeButton = UnsafeMutableRawPointer; public typealias NativeControl = UnsafeMutableRawPointer
    public typealias NativeTextField = UnsafeMutableRawPointer; public typealias NativeScrollView = UnsafeMutableRawPointer
    public struct NativeRect { var x, y, width, height: Double }

    nonisolated(unsafe) let libgtk = dlopen("libgtk-3.so.0", RTLD_LAZY | RTLD_GLOBAL)
    nonisolated(unsafe) let libgobj = dlopen("libgobject-2.0.so.0", RTLD_LAZY | RTLD_GLOBAL)
    func fn<T>(_ h: UnsafeMutableRawPointer?, _ n: String) -> T { unsafeBitCast(dlsym(h, n), to: T.self) }

    let gtk_init: @convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?) -> Void = fn(libgtk, "gtk_init")
    let gtk_window_set_title: @convention(c) (NativeView, UnsafePointer<CChar>) -> Void = fn(libgtk, "gtk_window_set_title")
    let gtk_window_set_decorated: @convention(c) (NativeView, Int32) -> Void = fn(libgtk, "gtk_window_set_decorated")
    let gtk_window_present: @convention(c) (NativeView) -> Void = fn(libgtk, "gtk_window_present")
    let gtk_container_add: @convention(c) (NativeView, NativeView) -> Void = fn(libgtk, "gtk_container_add")
    let gtk_container_remove: @convention(c) (NativeView, NativeView) -> Void = fn(libgtk, "gtk_container_remove")
    let gtk_widget_show_all: @convention(c) (NativeView) -> Void = fn(libgtk, "gtk_widget_show_all")
    let gtk_widget_hide: @convention(c) (NativeView) -> Void = fn(libgtk, "gtk_widget_hide")
    let gtk_widget_get_visible: @convention(c) (NativeView) -> Int32 = fn(libgtk, "gtk_widget_get_visible")
    let gtk_main: @convention(c) () -> Void = fn(libgtk, "gtk_main")
    let gtk_main_quit: @convention(c) () -> Void = fn(libgtk, "gtk_main_quit")
    let gtk_widget_destroy: @convention(c) (NativeView) -> Void = fn(libgtk, "gtk_widget_destroy")
    let gtk_box_new: @convention(c) (Int32, Int32) -> NativeView = fn(libgtk, "gtk_box_new")
    let gtk_box_pack_start: @convention(c) (NativeView, NativeView, Int32, Int32, UInt32) -> Void = fn(libgtk, "gtk_box_pack_start")
    let gtk_scrolled_window_new: @convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?) -> NativeView = fn(libgtk, "gtk_scrolled_window_new")
#elseif os(Android)
    import CAndroid
    public typealias NativeView = UnsafeMutableRawPointer // Maps to a JNI jobject reference
#elseif os(Windows)
    import CWindows
    public typealias NativeView = UnsafeMutableRawPointer
    public typealias NativeStack = UnsafeMutableRawPointer
    public typealias NativeButton = UnsafeMutableRawPointer
    public typealias NativeControl = UnsafeMutableRawPointer
    public typealias NativeTextField = UnsafeMutableRawPointer
    public typealias NativeScrollView = UnsafeMutableRawPointer
    public struct NativeRect { var x, y, width, height: Double }
#endif

public struct Omni {
    @MainActor public static func unpackViews(_ view: any View) -> [any View] {
        if view is IdentifiedView { return [view] }
        // Kept as a node, not flattened: its modifier is applied to its kids'
        // environment when the node renders, and flattening skips that. A stack
        // would drop .keyboardType, .textFieldStyle and every other one.
        if view is EnvironmentModifierView { return [view] }
        // Likewise: the enclosing sheet looks for it among its nodes.
        if view is PresentationModifierView { return [view] }
        // And the transition, which the engine reads off the view it swaps.
        if view is TransitionModifierView { return [view] }
        // And the identifier, which a path reads off the node.
        if view is AccessibilityIdentifierView { return [view] }
        if view is AccessibilityHiddenView { return [view] }
        if view is AccessibilityAttributesView { return [view] }
        // And .animation(_:value:), whose node remembers the value it last saw.
        if view is ImplicitAnimationView { return [view] }

        if let structural = view as? any OmniStructuralView {
            return structural.unpacked.flatMap { unpackViews($0) }
        }
        return [view]
    }
}

public struct IdentifiedView: OmniStructuralView {
    public var identity: AnyHashable
    public var content: any View

    public init(identity: AnyHashable, content: any View) {
        self.identity = identity
        self.content = content
    }

    public typealias Body = Never
    public var body: Never { fatalError("Engine unpacks IdentifiedView dynamically") }

    public var type: String { content.type }
    public var id: AnyHashable { identity }
    public var unpacked: [any View] { [content] }
}

public struct SafeArea {
    public var top: Double
    public var bottom: Double

    public init(top: Double = 0, bottom: Double = 0) {
        self.top = top
        self.bottom = bottom
    }
}

public struct TitleBarConfig {
    public var isHidden: Bool
    public var isTransparent: Bool
    public var hideTitleText: Bool
    public var height: Double?
    public var trafficLightOffset: (x: Double, y: Double)?

    public init(
        isHidden: Bool = false,
        isTransparent: Bool = false,
        hideTitleText: Bool = false,
        height: Double? = nil,
        trafficLightOffset: (x: Double, y: Double)? = nil
    ) {
        self.isHidden = isHidden
        self.isTransparent = isTransparent
        self.hideTitleText = hideTitleText
        self.height = height
        self.trafficLightOffset = trafficLightOffset
    }
}

public struct WindowConfig {
    public var title: String
    public var width: Double
    public var height: Double
    public var titleBar: TitleBarConfig
    /// The window's least size, in points: content never sets it (macOS).
    public var minWidth: Double?
    public var minHeight: Double?
    /// False: the window keeps its size (macOS, Linux, Windows).
    public var isResizable: Bool
    public var isVisible: Bool
    public var onAppear: (() -> Void)?
    public var onClose: (() -> Void)?
    public var onOpenURL: ((URL) -> Void)?

    public init(
        title: String = "Omni App",
        width: Double = 400,
        height: Double = 300,
        titleBar: TitleBarConfig = TitleBarConfig(),
        minWidth: Double? = nil,
        minHeight: Double? = nil,
        isResizable: Bool = true,
        isVisible: Bool = true,
        onAppear: (() -> Void)? = nil,
        onClose: (() -> Void)? = nil,
        onOpenURL: ((URL) -> Void)? = nil
    ) {
        self.title = title
        self.width = width
        self.height = height
        self.titleBar = titleBar
        self.minWidth = minWidth
        self.minHeight = minHeight
        self.isResizable = isResizable
        self.isVisible = isVisible
        self.onAppear = onAppear
        self.onClose = onClose
        self.onOpenURL = onOpenURL
    }
}

public struct TrayConfig {
    public var icon: String
    public var menu: () -> any View

    public init<Content: View>(icon: String, @ViewBuilder menu: @escaping () -> Content) {
        self.icon = icon
        self.menu = { menu() }
    }
}

@MainActor public class Tracker {
    static var current: Node?
    static var deps: [ObjectIdentifier: [ObjectIdentifier: () -> Void]] = [:]
    static var linuxMenuBars: [ObjectIdentifier: NativeView] = [:]
    static var linuxMenuPacked: Set<ObjectIdentifier> = []
}

@propertyWrapper @dynamicMemberLookup
public struct Binding<V> {
    public var get: () -> V; public var set: (V) -> Void
    public var wrappedValue: V { get { get() } nonmutating set { set(newValue) } }

    public var projectedValue: Binding<V> { self }

    public init(get: @escaping () -> V, set: @escaping (V) -> Void) {
        self.get = get
        self.set = set
    }

    public init(projectedValue: Binding<V>) {
        self = projectedValue
    }

    /// A binding that never changes. Previews and read-only rows depend on it.
    public static func constant(_ value: V) -> Binding<V> {
        Binding(get: { value }, set: { _ in })
    }

    /// SwiftUI's: `$account.name` binds one property of a bound value.
    public subscript<T>(dynamicMember keyPath: WritableKeyPath<V, T>) -> Binding<T> {
        Binding<T>(get: { self.wrappedValue[keyPath: keyPath] },
                   set: { value in
                       var copy = self.wrappedValue
                       copy[keyPath: keyPath] = value
                       self.wrappedValue = copy
                   })
    }
}

@MainActor protocol StateStorage: AnyObject {
    func adoptValue(from other: any StateStorage)
}

/// What a @State holds. Shared, not copied, from one rebuild of a view to the
/// next: a closure or task still holding an earlier copy of the view (a
/// `.task` started on first render, a sheet's callback) reads and writes the
/// value on screen, as in SwiftUI, rather than a box nothing renders from.
@MainActor final class StateBox<V> {
    var val: V
    init(_ val: V) { self.val = val }
}

@propertyWrapper @MainActor public class State<V> {
    var box: StateBox<V>
    var val: V { box.val }
    public var wrappedValue: V {
        get {
            if let node = Tracker.current {
                var nodeDeps = Tracker.deps[ObjectIdentifier(box)] ?? [:]
                nodeDeps[ObjectIdentifier(node)] = { [weak node] in if let n = node { Engine.request(n) } }
                Tracker.deps[ObjectIdentifier(box)] = nodeDeps
            }
            return box.val
        }
        set {
            box.val = newValue
            let renders = Tracker.deps[ObjectIdentifier(box)]?.values.map { $0 } ?? []
            Engine.renderOutermost { renders.forEach { $0() } }
        }
    }
    public var projectedValue: Binding<V> { Binding(get: { self.wrappedValue }, set: { self.wrappedValue = $0 }) }
    public init(wrappedValue: V) { self.box = StateBox(wrappedValue) }
}

extension State: StateStorage {
    func adoptValue(from other: any StateStorage) {
        guard let other = other as? State<V> else { return }
        box = other.box
    }
}

// MARK: - Core SwiftUI Protocols

@MainActor
public protocol View {
    associatedtype Body: View
    @MainActor @ViewBuilder var body: Self.Body { get }
    var type: String { get }
    var id: AnyHashable { get }
}

public extension View {
    var type: String { String(describing: Self.self) }
    var id: AnyHashable { AnyHashable(type) }
}

extension Never: View {
    public typealias Body = Never
    public var body: Never { fatalError("Primitive views have no body") }
}

// Native Component Protocol
public protocol NativeComponent: View where Body == Never {
    @MainActor var children: [any View] { get }
    @MainActor func makeNative() -> NativeView
    @MainActor func updateNative(_ view: NativeView)
    @MainActor func unmountNative(_ view: NativeView)
    @MainActor func insertChild(_ child: NativeView, into parent: NativeView)
}

public extension NativeComponent {
    var children: [any View] { [] }

    @MainActor func unmountNative(_ view: NativeView) {}

    #if os(Android)
        @MainActor func insertChild(_ child: NativeView, into parent: NativeView) {
            OmniAndroid.addChild(child, to: parent)
        }
    #else
        @MainActor func insertChild(_ child: NativeView, into parent: NativeView) {}
    #endif

    var body: Never { fatalError("Native components use NativeView, not body") }
}

#if os(macOS) || os(iOS)
/// A component that keeps each child in a holder of its own (a split view's
/// panes). A replaced child is taken out of its holder by `detach`, and
/// insertChild puts the new one in the holder it left. Otherwise the old
/// child stayed (it isn't the parent's subview) and the new one was moved
/// out of its holder into the parent: a split gained a pane every time.
public protocol NativePanes {
    @MainActor func detach(_ child: NativeView, from parent: NativeView)
}
#endif

// Structural Types for ViewBuilder
public protocol OmniStructuralView: View {
    @MainActor var unpacked: [any View] { get }
}

public struct TupleView<T>: OmniStructuralView {
    public var value: T
    public init(_ value: T) { self.value = value }

    public typealias Body = Never
    public var body: Never { fatalError("Engine unpacks TupleView dynamically") }

    public var unpacked: [any View] {
        if let arr = value as? [any View] { return arr } // Bridge for legacy array passing
        return Mirror(reflecting: value).children.compactMap { $0.value as? any View }
    }
}

public struct ForEach<Data: Sequence, Content: View>: OmniStructuralView {
    public var elements: [Data.Element]
    public var content: (Data.Element) -> Content
    var identify: ((Data.Element) -> AnyHashable)?

    public init(_ data: Data, @ViewBuilder content: @escaping (Data.Element) -> Content) {
        self.elements = Array(data)
        self.content = content
        self.identify = nil
    }

    /// SwiftUI's `ForEach(items) { ... }` over Identifiable elements.
    public init(
        _ data: Data,
        @ViewBuilder content: @escaping (Data.Element) -> Content
    ) where Data.Element: Identifiable {
        self.elements = Array(data)
        self.content = content
        self.identify = { AnyHashable($0.id) }
    }

    public init<ID: Hashable>(
        _ data: Data,
        id: KeyPath<Data.Element, ID>,
        @ViewBuilder content: @escaping (Data.Element) -> Content
    ) {
        self.elements = Array(data)
        self.content = content
        self.identify = { AnyHashable($0[keyPath: id]) }
    }

    init(
        _ data: Data,
        identity: @escaping (Data.Element) -> AnyHashable,
        @ViewBuilder content: @escaping (Data.Element) -> Content
    ) {
        self.elements = Array(data)
        self.content = content
        self.identify = identity
    }

    public typealias Body = Never
    public var body: Never { fatalError("Engine unpacks ForEach dynamically") }

    public var unpacked: [any View] {
        elements.enumerated().map { offset, element in
            let identity = identify?(element) ?? AnyHashable(offset)
            return IdentifiedView(identity: identity, content: content(element))
        }
    }
}

public struct _ConditionalContent<TrueContent: View, FalseContent: View>: OmniStructuralView {
    public enum Storage { case trueContent(TrueContent); case falseContent(FalseContent) }
    public let storage: Storage

    public typealias Body = Never
    public var body: Never { fatalError("Engine unpacks Conditional dynamically") }

    public var unpacked: [any View] {
        switch storage {
        case .trueContent(let v): return [v]
        case .falseContent(let v): return [v]
        }
    }
}

public struct EmptyView: OmniStructuralView {
    public init() {}
    public typealias Body = Never
    public var body: Never { fatalError("Empty") }
    public var unpacked: [any View] { [] }
}

@resultBuilder @MainActor public struct ViewBuilder {
    public static func buildBlock() -> EmptyView { EmptyView() }

    public static func buildBlock<Content: View>(_ content: Content) -> Content { content }

    public static func buildBlock<C0: View, C1: View>(_ c0: C0, _ c1: C1) -> TupleView<(C0, C1)> { TupleView((c0, c1)) }
    public static func buildBlock<C0: View, C1: View, C2: View>(_ c0: C0, _ c1: C1, _ c2: C2) -> TupleView<(C0, C1, C2)> { TupleView((c0, c1, c2)) }
    public static func buildBlock<C0: View, C1: View, C2: View, C3: View>(_ c0: C0, _ c1: C1, _ c2: C2, _ c3: C3) -> TupleView<(C0, C1, C2, C3)> { TupleView((c0, c1, c2, c3)) }
    public static func buildBlock<C0: View, C1: View, C2: View, C3: View, C4: View>(_ c0: C0, _ c1: C1, _ c2: C2, _ c3: C3, _ c4: C4) -> TupleView<(C0, C1, C2, C3, C4)> { TupleView((c0, c1, c2, c3, c4)) }
    public static func buildBlock<C0: View, C1: View, C2: View, C3: View, C4: View, C5: View>(_ c0: C0, _ c1: C1, _ c2: C2, _ c3: C3, _ c4: C4, _ c5: C5) -> TupleView<(C0, C1, C2, C3, C4, C5)> { TupleView((c0, c1, c2, c3, c4, c5)) }
    public static func buildBlock<C0: View, C1: View, C2: View, C3: View, C4: View, C5: View, C6: View>(_ c0: C0, _ c1: C1, _ c2: C2, _ c3: C3, _ c4: C4, _ c5: C5, _ c6: C6) -> TupleView<(C0, C1, C2, C3, C4, C5, C6)> { TupleView((c0, c1, c2, c3, c4, c5, c6)) }
    public static func buildBlock<C0: View, C1: View, C2: View, C3: View, C4: View, C5: View, C6: View, C7: View>(_ c0: C0, _ c1: C1, _ c2: C2, _ c3: C3, _ c4: C4, _ c5: C5, _ c6: C6, _ c7: C7) -> TupleView<(C0, C1, C2, C3, C4, C5, C6, C7)> { TupleView((c0, c1, c2, c3, c4, c5, c6, c7)) }
    public static func buildBlock<C0: View, C1: View, C2: View, C3: View, C4: View, C5: View, C6: View, C7: View, C8: View>(_ c0: C0, _ c1: C1, _ c2: C2, _ c3: C3, _ c4: C4, _ c5: C5, _ c6: C6, _ c7: C7, _ c8: C8) -> TupleView<(C0, C1, C2, C3, C4, C5, C6, C7, C8)> { TupleView((c0, c1, c2, c3, c4, c5, c6, c7, c8)) }
    public static func buildBlock<C0: View, C1: View, C2: View, C3: View, C4: View, C5: View, C6: View, C7: View, C8: View, C9: View>(_ c0: C0, _ c1: C1, _ c2: C2, _ c3: C3, _ c4: C4, _ c5: C5, _ c6: C6, _ c7: C7, _ c8: C8, _ c9: C9) -> TupleView<(C0, C1, C2, C3, C4, C5, C6, C7, C8, C9)> { TupleView((c0, c1, c2, c3, c4, c5, c6, c7, c8, c9)) }

    public static func buildEither<TrueContent, FalseContent>(first: TrueContent) -> _ConditionalContent<TrueContent, FalseContent> { _ConditionalContent(storage: .trueContent(first)) }
    public static func buildEither<TrueContent, FalseContent>(second: FalseContent) -> _ConditionalContent<TrueContent, FalseContent> { _ConditionalContent(storage: .falseContent(second)) }

    public static func buildOptional<Content: View>(_ content: Content?) -> _ConditionalContent<Content, EmptyView> {
        if let c = content { return _ConditionalContent(storage: .trueContent(c)) }
        return _ConditionalContent(storage: .falseContent(EmptyView()))
    }

    public static func buildLimitedAvailability<Content: View>(_ content: Content) -> AnyView {
        AnyView(content)
    }
}

@MainActor public class Node {
    var view: any View, native: NativeView?, kids: [Node] = []
    /// Set on first render. Weak: a parent owns its kids, not the reverse.
    weak var parent: Node?
    /// A sheet's root: it has a presenter but no parent in this tree, so a
    /// change of native view here never reaches into the screen behind it.
    var isDetachedRoot = false
    /// A detached root's holder (a sheet) told when its native is replaced
    /// by a render inside it: the holder shows the new one, moving the two
    /// with the removal and insertion read from the node that changed.
    var onRootNativeChange: ((_ native: NativeView?, _ removal: AnyTransition?, _ insertion: AnyTransition?) -> Void)?
    /// Carriers this node's body was, recorded as environmentModifier is: a
    /// structural body is unpacked into this node, so no node holds it.
    var transition: AnyTransition?
    var presentation: PresentationOptions?
    /// .accessibilityIdentifier, recorded like the carriers above.
    var accessibilityIdentifier: String?
    var accessibilityHidden: Bool?
    /// .accessibilityLabel and the rest, merged from every carrier this node was.
    var accessibility: AccessibilityAttributes?
    /// What .animation(_:value:) last saw here, to tell a change from a render.
    var implicitAnimationValue: Any?
    var environment = EnvironmentValues()

    var environmentModifier: ((inout EnvironmentValues) -> Void)?

    var nativeOwner: (any NativeComponent)?

    init(_ v: any View) { self.view = v }

    func adopt(_ newView: any View) {
        Node.carryStateOver(from: view, to: newView)
        view = newView
    }

    private static func carryStateOver(from old: any View, to new: any View) {
        let previous = Mirror(reflecting: old).children.compactMap { $0.value as? any StateStorage }
        guard !previous.isEmpty else { return }

        let incoming = Mirror(reflecting: new).children.compactMap { $0.value as? any StateStorage }
        guard previous.count == incoming.count else { return }

        for (old, new) in zip(previous, incoming) {
            new.adoptValue(from: old)
        }
    }

    func unmount() {
        // Before the native teardown: a component may need its view alive.
        notifyUnmount()

        #if os(Linux)
            if let n = native { gtk_widget_destroy(n) }
        #elseif os(Android)
            // A single-child container throws when a replacement arrives over the old one.
            if let n = native { omni_jni_remove_view(OmniAndroid.env, n) }
        #elseif os(Windows)
            if let n = native { omni_win_destroy(n) }
        #elseif os(macOS) || os(iOS)
            native?.removeFromSuperview()
        #else
            #error("no implementation for this platform")
        #endif

        forget()
    }

    private func notifyUnmount() {
        kids.forEach { $0.notifyUnmount() }
        if let owner = nativeOwner, let native { owner.unmountNative(native) }
        nativeOwner = nil
    }

    private func forget() {
        #if os(Linux)
            Tracker.linuxMenuBars.removeValue(forKey: ObjectIdentifier(self))
            Tracker.linuxMenuPacked.remove(ObjectIdentifier(self))
        #elseif os(Android)
            if let n = native {
                AndroidModifierState.clear(n)
                AndroidExpansion.clear(n)
            }
        #elseif os(Windows)
            if let n = native { unbindWindowsEvent(n) }
        #elseif os(macOS) || os(iOS)
            NativeOwners.forget(self)
        #else
            #error("no implementation for this platform")
        #endif

        let selfId = ObjectIdentifier(self)
        for stateId in Array(Tracker.deps.keys) {
            Tracker.deps[stateId]?.removeValue(forKey: selfId)
            if Tracker.deps[stateId]?.isEmpty ?? false {
                Tracker.deps.removeValue(forKey: stateId)
            }
        }

        kids.forEach { $0.forget() }
    }
}

@MainActor public struct Engine {
    public static var root: Node?
    /// Puts the root's native view in the window, whenever it changes: the
    /// first, and each one after, as when a root showing nothing until its
    /// session loads shows a screen. Set by each platform's launch.
    static var rootHost: ((NativeView?) -> Void)?
    public static var safeArea: SafeArea = SafeArea(top: 0, bottom: 0)
    /// The app's name, for its menus ("About ...", "Quit ..."): the window's title.
    public static var appName: String?

    private static var rendering: Set<ObjectIdentifier> = []
    private static var warnedAboutReentrancy = false

    /// Nodes asked for by one state change, while `renderOutermost` collects them.
    private static var requested: [Node]?

    /// A dependency firing: rendered now, or collected when a change is batched.
    static func request(_ node: Node) {
        if requested != nil { requested?.append(node) } else { render(node) }
    }

    /// Renders what `body` requests, outermost first, and none inside another:
    /// rendering a node renders its kids from fresh views. Rendered on its own
    /// first, a kid ran with the props its parent last gave it: an alert whose
    /// binding the change had just turned on presented the old, empty title,
    /// message and buttons, and the parent's render came too late to fix them.
    static func renderOutermost(_ body: () -> Void) {
        guard requested == nil else { return body() }
        requested = []
        body()
        let nodes = requested ?? []
        requested = nil
        let ids = Set(nodes.map(ObjectIdentifier.init))
        for node in nodes {
            var ancestor = node.parent
            var isInside = false
            while let a = ancestor, !isInside {
                isInside = ids.contains(ObjectIdentifier(a))
                ancestor = a.parent
            }
            if !isInside { render(node) }
        }
    }

    public static func render(_ node: Node) {
        // Re-entrant renders are dropped, not queued: a @Published write from
        // inside body lands back here, and queueing turns a crash into a hang.
        let identity = ObjectIdentifier(node)
        guard !rendering.contains(identity) else {
            if !warnedAboutReentrancy {
                warnedAboutReentrancy = true
                Omni.log("""
                    \(node.view.type) changed state from inside its own body, and the \
                    re-render that provoked was dropped. State belongs in an action or a \
                    callback, not in body.
                    """)
            }
            return
        }
        rendering.insert(identity)
        defer { rendering.remove(identity) }

        // A parent rendering its kid handles a changed native itself (the
        // adopt pass below). A node rendering on its own, because its @State
        // or observed object changed, has no one to do that, so it does it.
        let before = node.native
        // A node's first render comes from its parent building it; its parent
        // link is set during that render, so no parent yet means not its own.
        let isOwnRender = node.parent != nil && Tracker.current !== node.parent
        // How the view now shown leaves, as it last rendered: read before the
        // render replaces it, and only when there is an animation to run.
        let removal = Transaction.currentAnimation == nil ? nil : AnyTransition.on(node)
        renderBody(node)
        // The app's root has no parent to put a new native in its place: the
        // window does, through rootHost.
        if node === root, node.native != before { rootHost?(node.native) }
        if isOwnRender, node.native != before {
            // How the new one arrives, read from this node too, not from the
            // ancestor that places it: an outer .transition (App's, around the
            // screen) would otherwise win over this one (a screen's own, around
            // its step), and going back the step came in from the wrong side.
            let insertion = Transaction.currentAnimation == nil ? nil : AnyTransition.on(node)
            reattach(node, replacing: before, removal: removal, insertion: insertion)
        }

        #if os(macOS)
        // A node rendering on its own (its state changed) may now be taller or
        // shorter. A scroll view above it sizes its content in its own layout
        // pass only, which nothing else asks for: content loaded by a view
        // inside one was squeezed into the height it had before.
        if isOwnRender {
            var holder: Node? = node
            while let h = holder, h.native == nil { holder = h.parent }
            var view = holder?.native?.superview
            while let v = view {
                if let scroll = v as? OmniScrollView { scroll.needsLayout = true }
                view = v.superview
            }
        }
        #endif

        #if os(iOS)
        // The window's view mirrors the screen's background into the safe area.
        // Whichever root this node is under: the window's, or a sheet's.
        var top = node
        while let parent = top.parent { top = parent }
        // Not always the root's parent: the window's root sits in a host.
        var holder = top.native?.superview
        while let view = holder, !(view is OmniRootView) { holder = view.superview }
        (holder as? OmniRootView)?.scheduleBleedRefresh()
        #endif
    }

    /// `node`'s native changed during its own render. Non-native ancestors show
    /// their first kid's native as theirs, so they follow; the nearest native
    /// ancestor puts the new one where the old one was.
    private static func reattach(_ node: Node, replacing old: NativeView?, removal: AnyTransition?,
                                 insertion: AnyTransition?) {
        var child = node
        while let parent = child.parent {
            if let owner = parent.nativeOwner, parent.native != nil {
                #if os(macOS) || os(iOS)
                place(child, in: parent, owner: owner, replacing: old, removal: removal, insertion: insertion)
                #elseif os(Android)
                place(child, in: parent, owner: owner, replacing: old, removal: removal, insertion: insertion)
                #else
                // No positional insert here yet: rebuild the parent, which
                // inserts every kid. Its kids' state starts over.
                render(parent)
                #endif
                return
            }
            // This branch is not what the ancestor shows; nothing to move.
            guard parent.native == old else { return }
            parent.native = node.native
            child = parent
        }
        // A root (the window's, or a sheet's) holds its native directly. The
        // window's root is App's, whose native never changes; a sheet's is
        // put back in the sheet, or a screen that changed inside it (a
        // Profile row's) left the sheet blank. The transitions are the
        // changed node's, as place's are: read down from the sheet's root, an
        // outer screen's (Profile's, around a PIN step) won, and going back
        // played forward.
        child.onRootNativeChange?(child.native, removal, insertion)
    }

    #if os(macOS) || os(iOS)
    /// Swaps `child`'s new native in for `old`, at the same position among the
    /// parent's natives: insertChild appends, so the view is then moved.
    private static func place(_ child: Node, in parent: Node, owner: any NativeComponent,
                              replacing old: NativeView?, removal: AnyTransition?,
                              insertion: AnyTransition?) {
        guard let parentNative = parent.native else { return }
        // Its frame outlives its removal, which is what lets it animate out.
        let oldFrame = old?.frame ?? .zero
        let panes = owner as? NativePanes
        if let old {
            if let panes { panes.detach(old, from: parentNative) }
            else if old.superview === parentNative { old.removeFromSuperview() }
        }
        defer {
            #if os(iOS)
            if let animation = Transaction.currentAnimation {
                TransitionAnimator.run(animation, in: parentNative,
                                       new: child.native, insertion: insertion,
                                       old: old, oldFrame: oldFrame, removal: removal)
            }
            #endif
        }
        guard let new = child.native else { return }
        owner.insertChild(new, into: parentNative)
        // Its holder is where it goes: moved, it left the holder for the parent.
        if panes != nil { return }

        let position = parent.kids.prefix { $0 !== child }.filter { $0.native != nil }.count
        if let stack = parentNative as? NativeStack {
            // Still a subview, and its constraints to the stack stay.
            stack.removeArrangedSubview(new)
            stack.insertArrangedSubview(new, at: min(position, stack.arrangedSubviews.count))
        } else {
            #if os(iOS)
            parentNative.insertSubview(new, at: min(position, parentNative.subviews.count - 1))
            #else
            parentNative.addSubview(new, positioned: position == 0 ? .below : .above,
                                    relativeTo: position == 0 ? parentNative.subviews.first : nil)
            #endif
        }
    }
    #endif

    #if os(Android)
    /// Android's place: render(parent) can't do it, because the kid's native
    /// is already the new one, so the parent sees nothing to insert, and the
    /// old one was removed when it unmounted. The screen went blank.
    private static func place(_ child: Node, in parent: Node, owner: any NativeComponent,
                              replacing old: NativeView?, removal: AnyTransition?,
                              insertion: AnyTransition?) {
        guard let parentNative = parent.native else { return }
        let env = OmniAndroid.env
        // Usually gone already: unmounting removes it.
        if let old, old != child.native { omni_jni_remove_view(env, old) }
        if let new = child.native {
            // addView throws for a view that has a parent.
            omni_jni_remove_view(env, new)
            owner.insertChild(new, into: parentNative)

            let position = parent.kids.prefix { $0 !== child }.filter { $0.native != nil }.count
            omni_jni_move_child(env, parentNative, new, Int32(position))
        }

        // TransitionAnimator's defaults: a view with no transition fades.
        guard let animation = Transaction.currentAnimation else { return }
        let arriving = AndroidMotion(insertion?.insertion ?? .opacity)
        let leaving = AndroidMotion(removal?.removal ?? .opacity)
        omni_jni_animate_replacement(env, root?.native, parentNative, child.native,
                                     old == child.native ? nil : old,
                                     Int32(animation.duration * 1000), animation.androidCurve,
                                     arriving.x, arriving.y, arriving.fades ? 1 : 0,
                                     leaving.x, leaving.y, leaving.fades ? 1 : 0)
    }

    /// A transition as Android animates it: an offset, in fractions of the
    /// container's size, and whether it fades. Leading is left: no RTL yet.
    private struct AndroidMotion {
        var x: Float = 0
        var y: Float = 0
        var fades = false

        init(_ kind: AnyTransition.Kind) {
            switch kind {
            case .identity: break
            case .opacity, .scale: fades = true
            case .move(let edge):
                switch edge {
                case .leading: x = -1
                case .trailing: x = 1
                case .top: y = -1
                case .bottom: y = 1
                }
            case .combined(let a, let b):
                let first = AndroidMotion(a), second = AndroidMotion(b)
                x = first.x + second.x
                y = first.y + second.y
                fades = first.fades || second.fades
            case .asymmetric(let insertion, _):
                self = AndroidMotion(insertion)
            }
        }
    }
    #endif

    private static func renderBody(_ node: Node) {
        if let parent = Tracker.current {
            if !node.isDetachedRoot { node.parent = parent }
            node.environment = parent.environment
            parent.environmentModifier?(&node.environment)
            // A sheet's root (the only detached one) is rendered from inside
            // the view that presents it, whose environment it takes; it is
            // still presented, which the copy would otherwise undo.
            if node.isDetachedRoot { node.environment.isPresented = true }
            // onScrollGeometryChange and refreshable belong to the scroll view
            // they are applied to, not to one nested inside it.
            if parent.nativeOwner is ScrollView {
                node.environment.scrollGeometryObservers = []
                node.environment.refresh = nil
            }
        }

        let old = Tracker.current
        Tracker.current = node

        let bodyView: any View
        if let native = node.view as? any NativeComponent {
            bodyView = native
        } else if let structural = node.view as? any OmniStructuralView {
            bodyView = structural
        } else {
            bodyView = node.view.body
        }

        // .animation(_:value:): a changed value renders this subtree again,
        // inside the animation, unless one is running already.
        if let implicit = bodyView as? ImplicitAnimationView {
            let last = node.implicitAnimationValue
            node.implicitAnimationValue = implicit.value
            if let last, implicit.differs(last), let animation = implicit.animation,
               Transaction.currentAnimation == nil {
                Tracker.current = old
                withAnimation(animation) { renderBody(node) }
                return
            }
        }

        node.environmentModifier = (bodyView as? EnvironmentModifierView)?.modifier
        node.transition = (bodyView as? TransitionModifierView)?.transition
        node.presentation = (bodyView as? PresentationModifierView)?.options
        node.accessibilityIdentifier = (bodyView as? AccessibilityIdentifierView)?.identifier
        node.accessibilityHidden = (bodyView as? AccessibilityHiddenView)?.isHidden
        node.accessibility = (bodyView as? AccessibilityAttributesView)?.attributes

        if let nativeComp = bodyView as? any NativeComponent {
            if node.native == nil { node.native = nativeComp.makeNative() }
            #if os(macOS) || os(iOS)
            NativeOwners.register(node)
            #endif
            node.nativeOwner = nativeComp

            nativeComp.updateNative(node.native!)

            let children = nativeComp.children
            var needsRebuild = children.count != node.kids.count
            if !needsRebuild {
                for (i, cv) in children.enumerated() where node.kids[i].view.type != cv.type || node.kids[i].view.id != cv.id {
                    needsRebuild = true; break
                }
            }

            if !needsRebuild {
                // Same kids, but one can still resolve to a different native:
                // an AnyView going from EmptyView (no native) to a screen.
                // It is put in the old one's place, so no kid loses its state.
                for (i, cv) in children.enumerated() {
                    let before = node.kids[i].native
                    let removal = Transaction.currentAnimation == nil ? nil : AnyTransition.on(node.kids[i])
                    node.kids[i].adopt(cv); render(node.kids[i])
                    if node.kids[i].native != before {
                        #if os(macOS) || os(iOS) || os(Android)
                        place(node.kids[i], in: node, owner: nativeComp, replacing: before, removal: removal,
                              insertion: Transaction.currentAnimation == nil ? nil : AnyTransition.on(node.kids[i]))
                        #else
                        needsRebuild = true
                        #endif
                    }
                }
            }

            if needsRebuild {
                #if os(iOS)
                var navTransitionSnapshot: (UIView, NavigationTransitionDirection)?
                if let z = nativeComp as? ZStack, z.isNavigationContainer, !Transaction.animationsDisabled,
                   let direction = Transaction.navigationTransition,
                   let native = node.native, native.bounds.width > 0,
                   let snap = native.snapshotView(afterScreenUpdates: false) {
                    snap.frame = native.bounds
                    native.addSubview(snap)
                    navTransitionSnapshot = (snap, direction)
                }
                #endif

                // A kid still there (same type and id, in order) keeps its node,
                // and so its state: an `if` beside it going false unpacks to
                // nothing and shortens the list, as when App hides the tab bar
                // for a card flow, which rebuilt Cards back to its dashboard.
                // Its native is taken out and put back in order below. Not
                // for a navigation container, whose screens are replaced.
                #if os(macOS) || os(iOS)
                let keepsKids = !((nativeComp as? ZStack)?.isNavigationContainer ?? false)
                #else
                let keepsKids = false
                #endif
                // Kept kids' natives come out and go back in below; a text
                // input among them that's being typed into would lose focus,
                // and on iOS the keyboard would go, a second after typing in a
                // search whose results added or took away a section beside it.
                #if os(macOS) || os(iOS)
                let keptFocus = keepsKids ? KeptFocus.inside(node.native) : nil
                #endif
                var remaining = keepsKids ? node.kids : []
                if !keepsKids { node.kids.forEach { $0.unmount() } }
                var next: [Node] = []
                for cv in children {
                    if let i = remaining.firstIndex(where: { $0.view.type == cv.type && $0.view.id == cv.id }) {
                        remaining[..<i].forEach { $0.unmount() }
                        let kept = remaining[i]
                        remaining.removeFirst(i + 1)
                        #if os(macOS) || os(iOS)
                        kept.native?.removeFromSuperview()
                        #endif
                        kept.adopt(cv)
                        next.append(kept)
                    } else {
                        next.append(Node(cv))
                    }
                }
                remaining.forEach { $0.unmount() }
                node.kids = next
                node.kids.forEach { kidNode in
                    render(kidNode)
                    if let childNative = kidNode.native {
                        nativeComp.insertChild(childNative, into: node.native!)

                        #if os(Linux)
                            // GTK: anything added after the initial show_all stays invisible without this.
                            gtk_widget_show_all(childNative)
                        #endif
                    }
                }
                #if os(macOS) || os(iOS)
                keptFocus?.restore()
                #endif

                #if os(iOS)
                if let (snap, direction) = navTransitionSnapshot,
                   let native = node.native, let newChild = node.kids.first?.native {
                    native.bringSubviewToFront(snap)
                    native.layoutIfNeeded()
                    let width = native.bounds.width
                    newChild.transform = CGAffineTransform(translationX: direction == .push ? width : -width, y: 0)
                    UIView.animate(withDuration: 0.35, delay: 0, options: [.curveEaseInOut, .allowUserInteraction], animations: {
                        newChild.transform = .identity
                        snap.transform = CGAffineTransform(translationX: direction == .push ? -width : width, y: 0)
                    }, completion: { _ in
                        snap.removeFromSuperview()
                    })
                }
                Transaction.navigationTransition = nil
                #endif
            }
        } else {
            if let cmdWrapper = bodyView as? CommandWrapper {
                if node.kids.isEmpty { node.kids = [Node(cmdWrapper.content)] }
                else { node.kids[0].adopt(cmdWrapper.content) }

                let childNode = node.kids[0]
                render(childNode)

                #if os(macOS)
                    updateMacOSMenu(menus: cmdWrapper.menus)
                    node.native = childNode.native
                #elseif os(Linux)
                    if node.native == nil {
                        node.native = gtk_box_new(1, 0)
                    }

                    updateLinuxMenu(box: node.native!, menus: cmdWrapper.menus, nodeId: ObjectIdentifier(node))

                    if !Tracker.linuxMenuPacked.contains(ObjectIdentifier(childNode)) {
                        packFill(childNode.native!, into: node.native!)
                        Tracker.linuxMenuPacked.insert(ObjectIdentifier(childNode))
                    }
                #else
                    // No menu bar to put them in: the content alone. Without
                    // this the app's root had no native, and showed nothing.
                    node.native = childNode.native
                #endif

            } else if let structural = bodyView as? any OmniStructuralView {
                let unwrappedViews = structural.unpacked
                var needsRebuild = unwrappedViews.count != node.kids.count
                if !needsRebuild {
                    for (i, v) in unwrappedViews.enumerated() where node.kids[i].view.type != v.type || node.kids[i].view.id != v.id {
                        needsRebuild = true; break
                    }
                }

                if needsRebuild {
                    node.kids.forEach { $0.unmount() }
                    node.kids = unwrappedViews.map { Node($0) }
                } else {
                    for (i, v) in unwrappedViews.enumerated() { node.kids[i].adopt(v) }
                }

                node.kids.forEach { render($0) }
                node.native = node.kids.first?.native

            } else {
                if node.kids.isEmpty { node.kids = [Node(bodyView)] }
                else { node.kids[0].adopt(bodyView) }
                render(node.kids[0])
                node.native = node.kids[0].native
            }
        }

        applyAccessibility(node)
        Tracker.current = old
    }
}

public struct Window {
    #if os(Linux) || os(Windows)
    @MainActor public static var mainWindow: NativeView?
    @MainActor public static var isVisible: Bool = false
    #endif

    @MainActor public static func toggle() {
        #if os(macOS)
        if let win = NativeApp.shared.windows.first {
            if win.isVisible {
                win.orderOut(nil)
            } else {
                win.makeKeyAndOrderFront(nil)
                NativeApp.shared.activate(ignoringOtherApps: true)
            }
        }
        #elseif os(Linux)
        if let win = mainWindow {
            if gtk_widget_get_visible(win) != 0 {
                gtk_widget_hide(win)
            } else {
                gtk_widget_show_all(win)
                gtk_window_present(win)
            }
        }
        #elseif os(Windows)
        if let win = mainWindow {
            if isVisible { omni_win_hide(win) }
            else { omni_win_show(win) }
            isVisible.toggle()
        }
        #elseif os(iOS)
        #endif
    }

    @MainActor public static func show() {
        #if os(macOS)
        if let win = NativeApp.shared.windows.first {
            win.makeKeyAndOrderFront(nil)
            NativeApp.shared.activate(ignoringOtherApps: true)
        }
        #elseif os(Linux)
        if let win = mainWindow {
            gtk_widget_show_all(win)
            gtk_window_present(win)
        }
        #elseif os(Windows)
        if let win = mainWindow {
            omni_win_show(win)
            isVisible = true
        }
        #elseif os(iOS)
        #endif
    }

    @MainActor public static func hide() {
        #if os(macOS)
        NativeApp.shared.windows.first?.orderOut(nil)
        #elseif os(Linux)
        if let win = mainWindow {
            gtk_widget_hide(win)
        }
        #elseif os(Windows)
        if let win = mainWindow {
            omni_win_hide(win)
            isVisible = false
        }
        #elseif os(iOS)
        #endif
    }
}

@MainActor
public protocol App: View {
    init()
    var window: WindowConfig { get }
    var tray: TrayConfig? { get }
}
public extension App {
    var window: WindowConfig { WindowConfig() }
    var tray: TrayConfig? { nil }
}

#if os(macOS)
    class OmniWindow: NSWindow {
        var trafficLightOffset: (x: Double, y: Double)?
        var customDragHeight: Double?

        /// The window's content view, holding the app's root. The root never
        /// sizes the window: its edges are held below the window's own size
        /// (windowSizeStayPut, 500, which anything above beats by resizing the
        /// window). A page taller or wider than the window (a row's detail, a
        /// screen with a least width) is cut until the window is made bigger,
        /// and one with a most width leaves room, rather than the window
        /// jumping to fit it the moment it appears. The window's least size
        /// is WindowConfig's minWidth and minHeight.
        static func contentHost(for root: NSView) -> NSView {
            let host = NSView()
            place(root, in: host)
            return host
        }

        /// The root in the window's content view, held as contentHost describes.
        static func place(_ root: NSView, in host: NSView) {
            root.translatesAutoresizingMaskIntoConstraints = false
            host.addSubview(root)
            let held = NSLayoutConstraint.Priority(rawValue: NSLayoutConstraint.Priority.windowSizeStayPut.rawValue - 10)
            let bottom = root.bottomAnchor.constraint(equalTo: host.bottomAnchor)
            let trailing = root.trailingAnchor.constraint(equalTo: host.trailingAnchor)
            bottom.priority = held
            trailing.priority = held
            NSLayoutConstraint.activate([
                root.topAnchor.constraint(equalTo: host.topAnchor),
                root.leadingAnchor.constraint(equalTo: host.leadingAnchor),
                bottom, trailing,
                // Never shorter than the window: it fills it, whatever its least height.
                root.heightAnchor.constraint(greaterThanOrEqualTo: host.heightAnchor)
            ])
        }

        override func layoutIfNeeded() {
            super.layoutIfNeeded()

            guard let offset = trafficLightOffset,
                  let close = standardWindowButton(.closeButton),
                  let min = standardWindowButton(.miniaturizeButton),
                  let zoom = standardWindowButton(.zoomButton),
                  let container = close.superview else { return }

            let buttons = [close, min, zoom]
            var currentX = CGFloat(offset.x)

            for btn in buttons {
                let newY = container.bounds.height - btn.frame.height - CGFloat(offset.y)
                btn.setFrameOrigin(NSPoint(x: currentX, y: newY))
                currentX += btn.frame.width + 8
            }
        }

        override func sendEvent(_ event: NSEvent) {
            if event.type == .leftMouseDown {
                let point = event.locationInWindow
                let dragAreaHeight = CGFloat(customDragHeight ?? 28.0)
                let resizeBorder: CGFloat = 4.0

                let isTopResizeArea = point.y >= self.frame.height - resizeBorder
                let isSideResizeArea = point.x <= resizeBorder || point.x >= self.frame.width - resizeBorder

                if point.y >= self.frame.height - dragAreaHeight && !isTopResizeArea && !isSideResizeArea {
                    var isInteractive = false
                    var hitView = self.contentView?.superview?.hitTest(point)

                    while let v = hitView {
                        // A composed Button or an onTapGesture is a view with a
                        // click recognizer, not a control: it clicks too.
                        if v is NSControl || !v.gestureRecognizers.isEmpty
                            || (v !== self.contentView && v.acceptsFirstResponder) {
                            isInteractive = true
                            break
                        }
                        hitView = v.superview
                    }

                    if !isInteractive {
                        self.performDrag(with: event)
                        return
                    }
                }
            }
            super.sendEvent(event)
        }
    }

    @MainActor
    class MacDel: NSObject, NSApplicationDelegate {
        static let shared = MacDel()
        var onClose: (() -> Void)?
        var hasTray: Bool = false
        /// The system going light or dark; see Appearance.swift.
        var appearanceObservation: NSKeyValueObservation?

        func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
            return !hasTray
        }

        func applicationWillTerminate(_ notification: Notification) {
            onClose?()
        }

        func application(_ application: NSApplication, open urls: [URL]) {
            urls.forEach { DeepLink.receive($0) }
        }
    }
#elseif os(iOS)
    /// The window's own view. SwiftUI extends a full-screen background under the
    /// status bar and home indicator; here the content is pinned to the safe
    /// area, so this view takes on the colour of any background that covers the
    /// whole content, and paints the insets with it.
    final class OmniRootView: UIView {
        private var isRefreshScheduled = false
        /// The bottom inset, painted apart from the top: a tab bar's white
        /// continues under the home indicator while the status bar keeps the
        /// screen's colour.
        private let bottomBand = UIView()

        override init(frame: CGRect) {
            super.init(frame: frame)
            // The system going light or dark; see Appearance.swift. omni
            // supports iOS 15: before 17, traitCollectionDidChange, below.
            if #available(iOS 17.0, *) {
                registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (_: OmniRootView, _: UITraitCollection) in
                    Appearance.refresh()
                }
                // The reader's text size: a font with a text style scales with it.
                registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (_: OmniRootView, _: UITraitCollection) in
                    if let root = Engine.root { Engine.render(root) }
                }
            }
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

        @available(iOS, deprecated: 17.0, message: "registerForTraitChanges, in init, from iOS 17")
        override func traitCollectionDidChange(_ previous: UITraitCollection?) {
            super.traitCollectionDidChange(previous)
            if #unavailable(iOS 17.0), previous?.userInterfaceStyle != traitCollection.userInterfaceStyle {
                Appearance.refresh()
            }
            if #unavailable(iOS 17.0), previous?.preferredContentSizeCategory != traitCollection.preferredContentSizeCategory,
               let root = Engine.root {
                Engine.render(root)
            }
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            refreshBleed()
        }

        /// The device's own insets, not the launch's guess (47 and 34, a phone
        /// with a notch): a Dynamic Island's top is 59, an iPhone SE's 20 with
        /// no bottom. A view reading Engine.safeArea renders again with them.
        override func safeAreaInsetsDidChange() {
            super.safeAreaInsetsDidChange()
            updateSafeArea()
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            updateSafeArea()
        }

        private func updateSafeArea() {
            // The window's: this view may itself sit inside the safe area,
            // and its own insets are then zero.
            guard let window else { return }
            let insets = SafeArea(top: Double(window.safeAreaInsets.top), bottom: Double(window.safeAreaInsets.bottom))
            guard insets.top != Engine.safeArea.top || insets.bottom != Engine.safeArea.bottom else { return }
            Engine.safeArea = insets
            if let root = Engine.root { Engine.render(root) }
        }

        /// After a render: one refresh per main-loop turn, once the tree settles.
        /// A change deep in the tree does not lay this view out again by itself.
        func scheduleBleedRefresh() {
            guard !isRefreshScheduled else { return }
            isRefreshScheduled = true
            DispatchQueue.main.async { [weak self] in
                self?.isRefreshScheduled = false
                self?.refreshBleed()
            }
        }

        /// A sheet's .presentationBackground: its colour, top and foot, rather
        /// than one read off the content. Read off, the strip under a list
        /// that runs past the safe area took the colour of a card there.
        var fixedBackground: UIColor? {
            didSet { scheduleBleedRefresh() }
        }

        private func refreshBleed() {
            guard let content = subviews.first(where: { $0 !== bottomBand }) else { return }
            if let fixedBackground {
                backgroundColor = fixedBackground
                if bottomBand.superview == nil { insertSubview(bottomBand, at: 0) }
                bottomBand.frame = CGRect(x: 0, y: content.frame.maxY,
                                          width: bounds.width, height: max(bounds.height - content.frame.maxY, 0))
                bottomBand.backgroundColor = fixedBackground
                return
            }
            // Deeper frames are not settled until the content lays itself out.
            content.layoutIfNeeded()
            // Nothing found: something laid over the screen, as a toast is in
            // a ZStack with it, ends the walk. The screen is still beneath, so
            // its colour stays; white here lit up the status bar in dark mode.
            let top = Self.fullBleedColor(under: content) ?? backgroundColor ?? .systemBackground
            backgroundColor = top

            if bottomBand.superview == nil { insertSubview(bottomBand, at: 0) }
            bottomBand.frame = CGRect(x: 0, y: content.frame.maxY,
                                      width: bounds.width, height: max(bounds.height - content.frame.maxY, 0))
            let edge = CGPoint(x: content.bounds.midX, y: content.bounds.maxY - 1)
            bottomBand.backgroundColor = Self.color(at: edge, in: content) ?? top
        }

        /// The opaque colour drawn at `point`: the topmost view there that has
        /// one. By frame, so it runs after the content is laid out.
        private static func color(at point: CGPoint, in view: UIView) -> UIColor? {
            guard !view.isHidden, view.alpha > 0.01, view.bounds.contains(point) else { return nil }
            for subview in view.subviews.reversed() {
                if let color = color(at: view.convert(point, to: subview), in: subview) { return color }
            }
            if let color = view.backgroundColor, color.cgColor.alpha >= 1 { return color }
            return nil
        }

        /// The first opaque background down the chain of single-child wrappers
        /// the screen's outermost view sits in. Structural, not by frame: frames
        /// are not settled when a render has just replaced the screen. A stack,
        /// or a view with several children, ends the walk, so a card's
        /// background is never taken for the screen's.
        private static func fullBleedColor(under view: UIView?) -> UIColor? {
            var current = view
            while let candidate = current {
                if let color = candidate.backgroundColor, color.cgColor.alpha > 0 { return color }
                guard !(candidate is UIStackView), candidate.subviews.count == 1 else { return nil }
                current = candidate.subviews[0]
            }
            return nil
        }
    }

    class Del: UIResponder, UIApplicationDelegate {
        /// The app's one window, made by its scene.
        var w: UIWindow? { OmniSceneDelegate.current?.window }
        static var config: WindowConfig?

        func application(_ a: UIApplication, didFinishLaunchingWithOptions o: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
            // The window comes with the scene: OmniSceneDelegate, below.
            true
        }

        /// The scene lifecycle, which iOS 27 requires of every app. Declared in
        /// Info.plist too (the CLI's UIApplicationSceneManifest); this answers
        /// for an app bundled without it.
        func application(_ application: UIApplication, configurationForConnecting session: UISceneSession,
                         options: UIScene.ConnectionOptions) -> UISceneConfiguration {
            let configuration = UISceneConfiguration(name: nil, sessionRole: session.role)
            configuration.delegateClass = OmniSceneDelegate.self
            return configuration
        }

        func applicationWillTerminate(_ application: UIApplication) {
            Del.config?.onClose?()
        }
    }

    /// The window and its root view, made when the system connects the app's
    /// scene. A fixed Objective-C name, so Info.plist can name it.
    @objc(OmniSceneDelegate)
    final class OmniSceneDelegate: UIResponder, UIWindowSceneDelegate {
        var window: UIWindow?
        /// One scene: omni apps do not declare multiple windows on iOS.
        static weak var current: OmniSceneDelegate?

        func scene(_ scene: UIScene, willConnectTo session: UISceneSession,
                   options connectionOptions: UIScene.ConnectionOptions) {
            guard let windowScene = scene as? UIWindowScene else { return }
            OmniSceneDelegate.current = self
            let w = OmniTouchWindow(windowScene: windowScene)
            window = w
            let vc = UIViewController()
            vc.view = OmniRootView()
            vc.view.backgroundColor = .systemBackground

            // The root goes in a host of its own: it can be nothing yet, and
            // change after launch.
            let host = UIView()
            host.translatesAutoresizingMaskIntoConstraints = false
            vc.view.addSubview(host)

            let guide = vc.view.safeAreaLayoutGuide
            // The keyboard's top, which is the safe area's bottom while it is
            // hidden: content moves up out of its way, as in SwiftUI. Unless a
            // view asks the keyboard to cover it (Keyboard.coversContent).
            let aboveKeyboard = host.bottomAnchor.constraint(equalTo: vc.view.keyboardLayoutGuide.topAnchor)
            let underKeyboard = host.bottomAnchor.constraint(equalTo: guide.bottomAnchor)
            NSLayoutConstraint.activate([
                host.topAnchor.constraint(equalTo: guide.topAnchor),
                Keyboard.coversContent ? underKeyboard : aboveKeyboard,
                host.leadingAnchor.constraint(equalTo: guide.leadingAnchor),
                host.trailingAnchor.constraint(equalTo: guide.trailingAnchor)
            ])
            Keyboard.onCoversContentChange = { [weak vc] covers in
                // One off before the other on, so the two never conflict.
                (covers ? aboveKeyboard : underKeyboard).isActive = false
                (covers ? underKeyboard : aboveKeyboard).isActive = true
                vc?.view.layoutIfNeeded()
            }
            Engine.rootHost = { [weak host] native in
                guard let host else { return }
                host.subviews.forEach { $0.removeFromSuperview() }
                guard let native else { return }
                native.translatesAutoresizingMaskIntoConstraints = false
                host.addSubview(native)
                NSLayoutConstraint.activate([
                    native.topAnchor.constraint(equalTo: host.topAnchor),
                    native.bottomAnchor.constraint(equalTo: host.bottomAnchor),
                    native.leadingAnchor.constraint(equalTo: host.leadingAnchor),
                    native.trailingAnchor.constraint(equalTo: host.trailingAnchor)
                ])
                (host.superview as? OmniRootView)?.scheduleBleedRefresh()
            }
            Engine.rootHost?(Engine.root?.native)

            installKeyboardDismiss(on: vc.view)

            w.rootViewController = vc
            w.makeKeyAndVisible()
            Appearance.windowDidAppear()

            Del.config?.onAppear?()

            // A link that launched the app arrives with the scene, not through
            // application(_:open:), which scene apps are never sent.
            for context in connectionOptions.urlContexts { DeepLink.receive(context.url) }
        }

        /// A link arriving at a running app.
        func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
            for context in URLContexts { DeepLink.receive(context.url) }
        }

        func sceneDidEnterBackground(_ scene: UIScene) { AppLifecycle.enter(.background) }
        func sceneWillEnterForeground(_ scene: UIScene) { AppLifecycle.enter(.foreground) }

        /// A tap outside a control puts the keyboard away: on the window's
        /// root, and on each sheet's view, which the root's doesn't reach.
        func installKeyboardDismiss(on view: UIView) {
            let tap = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard(_:)))
            tap.cancelsTouchesInView = false
            tap.delegate = self
            view.addGestureRecognizer(tap)
        }

        @objc func dismissKeyboard(_ tap: UITapGestureRecognizer) {
            // The sheet's own window when it has one; the app's otherwise.
            (tap.view?.window ?? window)?.endEditing(true)
        }
    }

    /// A tap on a control is its own: a button over the keyboard moved as
    /// the keyboard went, the touch ended outside it, and its action took a
    /// second tap.
    extension OmniSceneDelegate: UIGestureRecognizerDelegate {
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            var view = touch.view
            while let current = view {
                if current is UIControl { return false }
                view = current.superview
            }
            return true
        }
    }
#endif

public extension App {
    @MainActor static func main() {
        let appInstance = self.init()
        let config = appInstance.window

        #if os(macOS)
            // What of the content the title bar covers: all of its height when
            // it's transparent and the content runs under it, else none.
            let topInset = config.titleBar.isHidden || !config.titleBar.isTransparent ? 0 : (config.titleBar.height ?? 28.0)
            Engine.safeArea = SafeArea(top: topInset, bottom: 0)
        #elseif os(iOS)
            Engine.safeArea = SafeArea(top: 47, bottom: 34)
        #elseif os(Linux)
            // Must precede Engine.render: GTK aborts if a widget is built before the
            // display connection exists.
            gtk_init(nil, nil)
            Engine.safeArea = SafeArea(top: 0, bottom: 0)
        #elseif os(Android)
            fatalError("On Android, the app is launched via the JVM, not App.main()")
        #elseif os(Windows)
            Engine.safeArea = SafeArea(top: 0, bottom: 0)
        #endif

        // Before the first render, so no text is laid out in a fallback face.
        Font.registerBundled()
        Engine.appName = config.title
        Engine.root = Node(appInstance)
        Engine.render(Engine.root!)
        #if os(macOS)
            // The standard menus for an app that declares none: without an
            // Edit menu, ⌘C and ⌘V do nothing in a text field.
            if !hasAppMenus { updateMacOSMenu(menus: []) }
        #endif

        DeepLink.install(config.onOpenURL)
        #if os(Linux) || os(Windows)
        if let launched = DeepLink.launchURL(in: CommandLine.arguments) {
            DeepLink.receive(launched)
        }
        #endif

        #if os(Linux)
            let w = gtk_window_new(0)
            Window.mainWindow = w

            gtk_window_set_title(w, config.title)
            gtk_window_set_default_size(w, Int32(config.width), Int32(config.height))
            if !config.isResizable {
                // A fixed window takes its content's size unless asked for one.
                let setSizeRequest: @convention(c) (NativeView, Int32, Int32) -> Void = fn(libgtk, "gtk_widget_set_size_request")
                setSizeRequest(w, Int32(config.width), Int32(config.height))
                gtk_window_set_resizable(w, 0)
            }

            let exeDir = (CommandLine.arguments[0] as NSString).deletingLastPathComponent
            let iconPath = "\(exeDir)/icon.png"
            if FileManager.default.fileExists(atPath: iconPath) {
                _ = gtk_window_set_icon_from_file(w, iconPath, nil)
            }

            if config.titleBar.isHidden {
                gtk_window_set_decorated(w, 0)
            }

            Engine.rootHost = { native in
                // A GtkWindow holds one child: the root, whichever it is now.
                if let current = gtk_bin_get_child(w) { gtk_container_remove(w, current) }
                if let native {
                    gtk_container_add(w, native)
                    gtk_widget_show_all(native)
                }
            }
            Engine.rootHost?(Engine.root?.native)

            bindLinuxEvent(w, "destroy") {
                config.onClose?()
                gtk_main_quit()
            }

            if config.isVisible {
                gtk_widget_show_all(w)
                gtk_window_present(w)
            }

            config.onAppear?()
            gtk_main()

        #elseif os(macOS)
            let rect = NativeRect(x: 0, y: 0, width: config.width, height: config.height)
            let w = OmniWindow(contentRect: rect, styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)

            if !config.isResizable { w.styleMask.remove(.resizable) }
            w.title = config.title
            w.trafficLightOffset = config.titleBar.trafficLightOffset
            w.customDragHeight = config.titleBar.height

            if config.titleBar.isHidden {
                w.styleMask.remove(.titled)
            } else {
                if config.titleBar.isTransparent {
                    w.styleMask.insert(.fullSizeContentView)
                    w.titlebarAppearsTransparent = true
                }
                if config.titleBar.hideTitleText {
                    w.titleVisibility = .hidden
                }
            }

            let content = NSView()
            w.contentView = content
            Engine.rootHost = { [weak content] native in
                guard let content else { return }
                content.subviews.forEach { $0.removeFromSuperview() }
                if let native { OmniWindow.place(native, in: content) }
            }
            Engine.rootHost?(Engine.root?.native)
            if config.minWidth != nil || config.minHeight != nil {
                w.contentMinSize = NSSize(width: config.minWidth ?? 0, height: config.minHeight ?? 0)
            }
            w.center()

            if config.isVisible {
                w.makeKeyAndOrderFront(nil)
            }

            MacDel.shared.onClose = config.onClose
            MacDel.shared.hasTray = appInstance.tray != nil

            let a = NativeApp.shared
            a.delegate = MacDel.shared
            a.setActivationPolicy(.regular)

            if let trayConfig = appInstance.tray {
                StatusBarManager.shared.setup(config: trayConfig)
            }

            a.activate(ignoringOtherApps: true)
            // The first render was light whatever the system is: redo it if
            // the system is dark, and again whenever it changes (as iOS does
            // from its root view's traits).
            Appearance.windowDidAppear()
            MacDel.shared.appearanceObservation = a.observe(\.effectiveAppearance) { _, _ in
                DispatchQueue.main.async { MainActor.assumeIsolated { Appearance.refresh() } }
            }
            config.onAppear?()
            a.run()

        #elseif os(Windows)
            let windowCallback: @convention(c) (UnsafeMutableRawPointer?, UInt32, UInt64, Int64) -> Void = { hwnd, msg, wParam, lParam in
                switch msg {
                case 1: // OMNI_WM_CLOSE
                    config.onClose?()
                    omni_win_quit_loop()
                case 2: // OMNI_WM_SIZE
                    if let targetHwnd = hwnd {
                        handleWindowsEvent(v: targetHwnd, event: "resize")
                    }
                case 4: // OMNI_WM_COMMAND
                    handleWindowsCommand(lParam: lParam)
                default:
                    break
                }
            }

            let w = config.title.withCString { titlePtr in
                omni_win_create_window(titlePtr, Int32(config.width), Int32(config.height), windowCallback)
            }
            Window.mainWindow = w
            if !config.isResizable { omni_win_set_resizable(w, 0) }

            if config.isVisible {
                omni_win_show(w)
                Window.isVisible = true
            }

            config.onAppear?()

            omni_win_run_loop()

        #elseif os(iOS)
            Del.config = config
            UIApplicationMain(CommandLine.argc, CommandLine.unsafeArgv, nil, NSStringFromClass(Del.self))
        #elseif os(Android)
            fatalError("On Android, the app is launched via the JVM, not App.main()")
        #else
        #error("no implementation for this platform")
        #endif
    }
}

// MARK: - Standard Structural Views

public struct AnyView: OmniStructuralView {
    public var content: any View
    public init(_ content: any View) { self.content = content }

    public typealias Body = Never
    public var body: Never { fatalError("Engine unpacks AnyView dynamically") }
    public var unpacked: [any View] { [content] }
}

public struct Group<Content: View>: OmniStructuralView {
    public var content: Content
    public init(@ViewBuilder content: () -> Content) { self.content = content() }

    public typealias Body = Never
    public var body: Never { fatalError("Engine unpacks Group dynamically") }
    public var unpacked: [any View] { Omni.unpackViews(content) }
}

#if os(iOS)
import UIKit

/// The text input being typed into, so a render that takes its view out and
/// puts it back can give it focus again (Engine.renderBody).
@MainActor struct KeptFocus {
    let input: UIView
    let selection: UITextRange?

    /// The focused field or editor, if it's inside `container`.
    static func inside(_ container: NativeView?) -> KeptFocus? {
        Tracking.start()
        guard let container, let input = Tracking.current, input.isFirstResponder,
              input.isDescendant(of: container) else { return nil }
        return KeptFocus(input: input, selection: (input as? UITextInput)?.selectedTextRange)
    }

    func restore() {
        guard input.window != nil, !input.isFirstResponder else { return }
        input.becomeFirstResponder()
        if let selection { (input as? UITextInput)?.selectedTextRange = selection }
    }

    /// Follows editing as it starts, rather than searching the views on each render.
    @MainActor enum Tracking {
        static weak var current: UIView?
        private static var started = false

        static func start() {
            guard !started else { return }
            started = true
            let center = NotificationCenter.default
            for name in [UITextField.textDidBeginEditingNotification, UITextView.textDidBeginEditingNotification] {
                center.addObserver(forName: name, object: nil, queue: .main) { note in
                    let view = note.object as? UIView
                    MainActor.assumeIsolated { current = view }
                }
            }
        }
    }
}
#elseif os(macOS)
import AppKit

/// The text input being typed into, so a render that takes its view out and
/// puts it back can give it focus again (Engine.renderBody).
@MainActor struct KeptFocus {
    let input: NSView
    let selection: NSRange?

    /// The field (through its field editor) or editor being typed into, if
    /// it's inside `container`.
    static func inside(_ container: NativeView?) -> KeptFocus? {
        guard let container, let editor = container.window?.firstResponder as? NSTextView else { return nil }
        // A field's editor is the window's, its delegate the field; an editor is itself.
        let input = (editor.delegate as? NSTextField) ?? editor
        guard input.isDescendant(of: container) else { return nil }
        return KeptFocus(input: input, selection: editor.selectedRange())
    }

    func restore() {
        guard let window = input.window else { return }
        if let editor = window.firstResponder as? NSTextView, editor === input || editor.delegate === input { return }
        window.makeFirstResponder(input)
        if let selection, let editor = window.firstResponder as? NSTextView,
           NSMaxRange(selection) <= (editor.string as NSString).length {
            editor.setSelectedRange(selection)
        }
    }
}
#endif
