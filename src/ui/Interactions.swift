// src/ui/Interactions.swift
import Foundation
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// Every tap and swipe on the app's views, reported with the path to the view
/// it landed on. For instrumentation: an app counts or logs them; omni keeps
/// nothing. SwiftUI has no equivalent. This only watches: a gesture is handled
/// exactly as it would be without an observer.
///
/// A path is the chain of the app's own view types down to the element:
/// `HomeScreen/PrimaryButton/Button`. Omni's layout types (stacks, padding,
/// frames) are left out, so restyling a screen keeps its paths. An element that
/// is one of several of its kind under the same segment gets its position,
/// `ProfileRow[2]`. `.accessibilityIdentifier` replaces a segment with a name
/// that survives any change to the layout.
///
/// A tap is attributed to the control it lands in (a Button, an onTapGesture,
/// a field), a swipe to the scroll view it lands in, and either to the view
/// under the finger when there is none.
///
/// Reported on macOS and iOS. Android, Linux and Windows report nothing yet.
/// Activity (`addActivityObserver`) is reported on Android too.
@MainActor public enum Interactions {
    public enum Kind: String, CaseIterable, Sendable {
        case tap, longPress, swipeLeft, swipeRight, swipeUp, swipeDown
    }

    public struct Event: Sendable, Equatable {
        public let kind: Kind
        public let path: String

        public init(kind: Kind, path: String) {
            self.kind = kind
            self.path = path
        }
    }

    /// A registration, for removeObserver.
    public struct ObserverID: Hashable, Sendable { let raw: Int }

    private static var observers: [(id: ObserverID, handler: (Event) -> Void)] = []
    private static var nextID = 0

    /// Calls `handler` for each gesture, on the main actor, until removed.
    /// Any number may listen: usage counting and an idle timer, say.
    @discardableResult
    public static func addObserver(_ handler: @escaping (Event) -> Void) -> ObserverID {
        nextID += 1
        let id = ObserverID(raw: nextID)
        observers.append((id, handler))
        #if os(macOS)
        MouseMonitor.install()
        #endif
        return id
    }

    public static func removeObserver(_ id: ObserverID) {
        observers.removeAll { $0.id == id }
        activityObservers.removeAll { $0.id == id }
    }

    private static var activityObservers: [(id: ObserverID, handler: () -> Void)] = []

    /// Calls `handler` each time a finger goes down on the app, or a mouse
    /// button or key is pressed: anything a person does, with nothing about
    /// what. For an idle timer. Until removed with removeObserver.
    ///   iOS      every touch
    ///   macOS    mouse-downs and key-downs
    ///   Android  every touch
    ///   Linux and Windows report nothing yet.
    @discardableResult
    public static func addActivityObserver(_ handler: @escaping () -> Void) -> ObserverID {
        nextID += 1
        let id = ObserverID(raw: nextID)
        activityObservers.append((id, handler))
        #if os(macOS)
        MouseMonitor.install()
        #endif
        return id
    }

    static func noteActivity() {
        for observer in activityObservers { observer.handler() }
    }

    static var isObserved: Bool { !observers.isEmpty }

    // MARK: What a touch was

    /// A single touch, from how far it moved (points, y down) and how long it
    /// was held. nil for a drag too short to be a swipe and too long to be a tap.
    nonisolated static func classify(dx: Double, dy: Double, duration: Double) -> Kind? {
        let distance = (dx * dx + dy * dy).squareRoot()
        if distance < 10 { return duration >= 0.5 ? .longPress : .tap }
        guard distance >= 30 else { return nil }
        if abs(dx) >= abs(dy) { return dx < 0 ? .swipeLeft : .swipeRight }
        return dy < 0 ? .swipeUp : .swipeDown
    }

    static func report(_ kind: Kind, on hit: Node) {
        guard isObserved else { return }
        let event = Event(kind: kind, path: path(of: hit, for: kind))
        for observer in observers { observer.handler(event) }
    }

    // MARK: Where it landed

    /// The path for a gesture of `kind` whose finger landed in `hit`'s view.
    static func path(of hit: Node, for kind: Kind) -> String {
        let target = self.target(from: hit, for: kind)

        // Built from the target up, then reversed. An identifier on a node
        // showing the same view as the newest segment renames that segment
        // instead of adding one.
        var segments: [Segment] = [Segment(name: elementName(of: target), node: target, kind: .element)]
        // A view of the app's whose body is the target's native hosts it on
        // its own node: it is a segment too.
        if isAppView(target.view) { segments.append(Segment(name: name(of: target.view), node: target, kind: .app)) }
        var current = target.parent
        while let node = current {
            if let identifier = node.accessibilityIdentifier {
                if let last = segments.last, last.node.native == node.native, last.kind != .identifier {
                    segments[segments.count - 1] = Segment(name: identifier, node: node, kind: .identifier)
                } else {
                    segments.append(Segment(name: identifier, node: node, kind: .identifier))
                }
            }
            // Both, for an app view whose body carries an identifier: it names
            // what the body shows, and the view keeps its own segment.
            if isAppView(node.view) {
                segments.append(Segment(name: name(of: node.view), node: node, kind: .app))
            }
            current = node.parent
        }

        // A typed segment's position among its namesakes under the next
        // segment up, or under the root.
        var root = target
        while let parent = root.parent { root = parent }
        var names: [String] = []
        for (index, segment) in segments.enumerated() {
            guard segment.kind != .identifier else { names.append(segment.name); continue }
            // Hosted on the app view's node: that segment carries the position.
            if index + 1 < segments.count, segments[index + 1].node === segment.node {
                names.append(segment.name)
                continue
            }
            let anchor = index + 1 < segments.count ? segments[index + 1].node : root
            let namesakes = self.namesakes(of: segment, under: anchor)
            if namesakes.count > 1, let position = namesakes.firstIndex(where: { $0 === segment.node }) {
                names.append("\(segment.name)[\(position)]")
            } else {
                names.append(segment.name)
            }
        }
        return names.reversed().joined(separator: "/")
    }

    /// Under `anchor`, the nodes `segment` is counted among. A whole subtree
    /// walked for each segment of each path: in a batch, each walk once.
    private static func namesakes(of segment: Segment, under anchor: Node) -> [Node] {
        let key = "\(ObjectIdentifier(anchor))|\(segment.kind)|\(segment.name)"
        let named: [Node]
        if let cached = namesakeCache?[key] {
            named = cached
        } else {
            named = descendants(of: anchor).filter { candidate in
                guard candidate !== anchor else { return false }
                switch segment.kind {
                case .app: return isAppView(candidate.view) && name(of: candidate.view) == segment.name
                default: return candidate.nativeOwner != nil && elementName(of: candidate) == segment.name
                }
            }
            namesakeCache?[key] = named
        }
        return named.filter { $0 === segment.node || !isIdentified($0) }
    }

    /// Namesakes found so far in a batch; nil outside one.
    private static var namesakeCache: [String: [Node]]?

    private struct Segment {
        enum Kind { case element, app, identifier }
        let name: String
        let node: Node
        let kind: Kind
    }

    /// The control a tap belongs to, or the scroll view a swipe belongs to:
    /// the first such up from where the finger landed. A node may host its
    /// body's native, so the native's component is checked as well as the view.
    private static func target(from hit: Node, for kind: Kind) -> Node {
        let isSwipe = kind != .tap && kind != .longPress
        var current: Node? = hit
        while let node = current {
            let candidates: [any View] = [node.view] + (node.nativeOwner.map { [$0] } ?? [])
            if candidates.contains(where: { isSwipe ? $0 is any SwipeTarget : $0 is any TapTarget }) { return node }
            current = node.parent
        }
        return hit
    }

    /// A node's element: the native component it made, else its view.
    static func elementName(of node: Node) -> String {
        name(of: node.nativeOwner ?? node.view)
    }

    /// Named by an identifier, which keeps it out of its namesakes' count:
    /// tagging one view does not move the others' positions.
    private static func isIdentified(_ node: Node) -> Bool {
        var current: Node? = node
        while let candidate = current, candidate.native == node.native {
            if candidate.accessibilityIdentifier != nil { return true }
            current = candidate.parent
        }
        return false
    }

    private static func descendants(of node: Node) -> [Node] {
        [node] + node.kids.flatMap { descendants(of: $0) }
    }

    static func name(of view: any View) -> String {
        if let target = view as? any TapTarget { return type(of: target).interactionName }
        if let target = view as? any SwipeTarget { return type(of: target).interactionName }
        let full = String(describing: type(of: view))
        return String(full.prefix { $0 != "<" })
    }

    /// A view the app wrote, not one of omni's, and not the App itself.
    static func isAppView(_ view: any View) -> Bool {
        !(view is any App) && !String(reflecting: type(of: view)).hasPrefix("OmniUI.")
    }
}

/// What a tap is attributed to, and its name in a path.
protocol TapTarget: View { static var interactionName: String { get } }
/// What a swipe is attributed to, and its name in a path.
protocol SwipeTarget: View { static var interactionName: String { get } }

extension SystemButtonPrimitive: TapTarget { static var interactionName: String { "Button" } }
extension TapGestureView: TapTarget { static var interactionName: String { "TapGesture" } }
extension TextField: TapTarget { static var interactionName: String { "TextField" } }
extension SecureField: TapTarget { static var interactionName: String { "SecureField" } }
extension TextEditor: TapTarget { static var interactionName: String { "TextEditor" } }
extension Toggle: TapTarget { static var interactionName: String { "Toggle" } }
extension Slider: TapTarget { static var interactionName: String { "Slider" } }
extension NativePicker: TapTarget { static var interactionName: String { "Picker" } }
extension ScrollView: SwipeTarget { static var interactionName: String { "ScrollView" } }

// MARK: - From a native view back to its node

#if os(macOS) || os(iOS)
/// Which node made each native view. A touch knows the view it landed on;
/// a path needs the node.
@MainActor enum NativeOwners {
    private struct Entry { weak var node: Node? }
    private static var table: [ObjectIdentifier: Entry] = [:]

    static func register(_ node: Node) {
        guard let native = node.native else { return }
        table[ObjectIdentifier(native)] = Entry(node: node)
        // Nodes that went without forget(): drop them now and then.
        if table.count > 4096 { table = table.filter { $0.value.node != nil } }
    }

    static func forget(_ node: Node) {
        guard let native = node.native else { return }
        let key = ObjectIdentifier(native)
        if table[key]?.node === node { table.removeValue(forKey: key) }
    }

    /// The node of `view`, or of the nearest view around it that omni made.
    /// Checked against the node's current native: an address can be reused.
    static func node(for view: NativeView) -> Node? {
        var current: NativeView? = view
        while let candidate = current {
            if let node = table[ObjectIdentifier(candidate)]?.node, node.native === candidate { return node }
            current = candidate.superview
        }
        return nil
    }
}

/// One finger at a time: where and when it went down, and what it went down on.
@MainActor enum TouchReporter {
    private static var start: (point: CGPoint, time: TimeInterval, view: NativeView)?

    static func began(at point: CGPoint, time: TimeInterval, on view: NativeView?) {
        guard Interactions.isObserved, let view else { start = nil; return }
        start = (point, time, view)
    }

    /// `dy` in points, y down.
    static func ended(at point: CGPoint, time: TimeInterval, yDown: Bool) {
        guard let began = start else { return }
        start = nil
        let dx = point.x - began.point.x
        let dy = yDown ? point.y - began.point.y : began.point.y - point.y
        guard let kind = Interactions.classify(dx: dx, dy: dy, duration: time - began.time),
              let node = NativeOwners.node(for: began.view) else { return }
        Interactions.report(kind, on: node)
    }

    static func cancel() { start = nil }
}
#endif

#if os(iOS)
/// The app's window. Sees every touch before any view does, which is the only
/// place a tap on a UIButton is visible: a control keeps its taps from the
/// gesture recognizers around it.
final class OmniTouchWindow: UIWindow {
    override func sendEvent(_ event: UIEvent) {
        // Before super: a tap's action can change the screen, and the path
        // is of the view that was tapped.
        if event.type == .touches, let touches = event.allTouches {
            if touches.contains(where: { $0.phase == .began }) { Interactions.noteActivity() }
            if touches.count > 1 {
                TouchReporter.cancel()
            } else if let touch = touches.first {
                switch touch.phase {
                case .began:
                    TouchReporter.began(at: touch.location(in: self), time: touch.timestamp, on: touch.view)
                case .ended, .cancelled:
                    TouchReporter.ended(at: touch.location(in: self), time: touch.timestamp, yDown: true)
                default:
                    break
                }
            }
        }
        super.sendEvent(event)
    }
}
#endif

#if os(macOS)
/// A click is a tap, a drag a swipe. A local monitor, not the window's
/// sendEvent: a button tracks the mouse in its own loop, and its mouse-up
/// never reaches sendEvent.
@MainActor enum MouseMonitor {
    private static var token: Any?

    static func install() {
        guard token == nil else { return }
        token = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseUp, .rightMouseDown, .keyDown]) { event in
            MainActor.assumeIsolated { handle(event) }
            return event
        }
    }

    static func handle(_ event: NSEvent) {
        if event.type != .leftMouseUp { Interactions.noteActivity() }
        guard let window = event.window else { return }
        let point = event.locationInWindow
        switch event.type {
        case .leftMouseDown:
            // The frame view's coordinates are the window's.
            let hit = window.contentView?.superview?.hitTest(point)
            TouchReporter.began(at: point, time: event.timestamp, on: hit)
        case .leftMouseUp:
            TouchReporter.ended(at: point, time: event.timestamp, yDown: false)
        default:
            break
        }
    }
}
#endif

// MARK: - For OmniProbe

@_spi(Probe) public extension Interactions {
    /// Many paths of one unchanging tree: each subtree's namesakes are found
    /// once, not once a path. OmniProbe's look at a screen of a few hundred
    /// elements took three seconds, and a wait for it to settle timed out.
    static func batch<T>(_ body: () -> T) -> T {
        let outer = namesakeCache == nil
        if outer { namesakeCache = [:] }
        defer { if outer { namesakeCache = nil } }
        return body()
    }

    #if os(macOS) || os(iOS)
    /// The path a tap on `view` would report: the control it lands in, by the
    /// same rules. nil for a view omni did not make.
    static func path(of view: NativeView) -> String? {
        NativeOwners.node(for: view).map { path(of: $0, for: .tap) }
    }
    #endif
}

/// A view tree rendered outside App.main: OmniProbe's host for tests that
/// drive a screen, or a whole app, in the test's own process.
@_spi(Probe) @MainActor public final class HostedTree {
    let node: Node

    /// The tree's native view, to put in a window.
    public var native: NativeView? { node.native }

    /// Renders `view`. As the app's root, it is what Appearance and the
    /// engine render again, as App.main's is.
    /// `onNativeChange` hears each native the tree shows, the first included,
    /// as a window does the app's root.
    public init(_ view: any View, asRoot: Bool, onNativeChange: ((NativeView?) -> Void)? = nil) {
        node = Node(view)
        if asRoot { Engine.root = node }
        Engine.render(node)
        // As a window's launch does: the first native now, the rest as they come.
        if asRoot { Engine.rootHost = onNativeChange }
        onNativeChange?(node.native)
    }

    /// Unmounts it, so its tasks stop.
    public func tearDown() {
        node.unmount()
        if Engine.root === node {
            Engine.root = nil
            Engine.rootHost = nil
        }
    }
}
