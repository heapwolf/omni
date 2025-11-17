// src/ui/Observable.swift
import Foundation
#if canImport(Combine)
import Combine
#endif

// MARK: - ObservableObject Protocol / @Published
//
// On Apple platforms, Foundation itself re-exports Combine's ObservableObject
// and Published as top-level names. The tempting fix — `public typealias
// ObservableObject = Combine.ObservableObject` here too — does not work:
// Swift's ambiguous-lookup check is syntactic, not semantic. Two distinct
// public declarations sharing a name are ambiguous to unqualified lookup
// even when both alias the identical underlying type, so re-exporting the
// name at all keeps every `import Foundation` + `import OmniUI` file that
// writes `class X: ObservableObject { @Published var y }` broken.
//
// The only fix is for OmniUI to not export a symbol named `ObservableObject`
// or `Published` on Apple at all, so Foundation's own re-export is the only
// candidate app code ever sees — genuine SwiftUI compatibility, not a
// look-alike. `OmniObservableObject` below is OmniUI's own, differently-named
// public alias to the same real Combine.ObservableObject, used only as the
// constraint bound for StateObject/ObservedObject/EnvironmentObject further
// down: constraint *satisfaction* is checked by underlying protocol identity,
// not by which name spelled it, so `Counter: ObservableObject` (Foundation's
// name) still satisfies `ObjectType: OmniObservableObject` here.
//
// Non-Apple platforms have no Combine, so they keep Omni's own minimal
// reimplementation — there, `ObservableObject` is the one and only
// declaration of that name, so no collision is possible, and
// `OmniObservableObject` is just another name for the same protocol.
#if canImport(Combine)
public typealias OmniObservableObject = Combine.ObservableObject
#else
public protocol ObservableObject: AnyObject {}
public typealias OmniObservableObject = ObservableObject

@propertyWrapper @MainActor public class Published<Value> {
    var val: Value
    public var wrappedValue: Value {
        get {
            // Track dependencies just like @State
            if let node = Tracker.current {
                var nodeDeps = Tracker.deps[ObjectIdentifier(self)] ?? [:]
                nodeDeps[ObjectIdentifier(node)] = { [weak node] in if let n = node { Engine.request(n) } }
                Tracker.deps[ObjectIdentifier(self)] = nodeDeps
            }
            return val
        }
        set {
            val = newValue
            // Every dependent node, outermost first; see Engine.renderOutermost.
            let renders = Tracker.deps[ObjectIdentifier(self)]?.values.map { $0 } ?? []
            Engine.renderOutermost { renders.forEach { $0() } }
        }
    }

    public var projectedValue: Binding<Value> {
        Binding(get: { self.wrappedValue }, set: { self.wrappedValue = $0 })
    }

    public init(wrappedValue: Value) {
        self.val = wrappedValue
    }
}
#endif

// MARK: - Re-render on change (Apple)
//
// Non-Apple's @Published registers its own dependency directly, per property
// (above). On Apple, Published is the real Combine one and knows nothing
// about Omni's engine, so StateObject/ObservedObject/EnvironmentObject
// subscribe to the object's own objectWillChange instead. That's object-level
// granularity rather than Omni's usual per-property tracking, but it is
// exactly what real SwiftUI does too: any @Published change on an observed
// object re-renders the whole view, not just whichever property was read.
#if canImport(Combine)
@MainActor private enum ObservableObjectBridge {
    /// One subscription, and the node it renders: held weakly, and checked,
    /// because a node's address is reused once it is gone.
    private struct Subscription {
        weak var node: Node?
        let cancellable: AnyCancellable
    }

    // [object][node]: one live subscription per pair, so re-reading
    // wrappedValue on every render doesn't keep piling up subscriptions.
    private static var subscriptions: [ObjectIdentifier: [ObjectIdentifier: Subscription]] = [:]

    static func track<O: OmniObservableObject>(_ object: O) {
        guard let node = Tracker.current else { return }
        let objectId = ObjectIdentifier(object)
        let nodeId = ObjectIdentifier(node)
        // The same live node: subscribed already. An entry whose node has gone
        // is not this one, even at this address: a new node there was never
        // re-rendered by the object, and a session change left the app on the
        // screen it was on.
        if subscriptions[objectId]?[nodeId]?.node === node { return }
        subscriptions[objectId] = subscriptions[objectId]?.filter { $0.value.node != nil }
        // objectWillChange fires from @Published's willSet, before the new
        // value is stored. Rendering synchronously reads the old value and
        // nothing renders again, so the change is lost. receive(on:) defers
        // to the next main-queue turn, after the write, as SwiftUI does.
        //
        // The render happens a turn later, after withAnimation has returned, so
        // the animation in force at the change is carried across to it.
        let cancellable = object.objectWillChange
            .map { _ in MainActor.assumeIsolated { Transaction.currentAnimation } }
            .receive(on: DispatchQueue.main)
            .sink(
            receiveCompletion: { _ in },
            receiveValue: { [weak node] animation in
                guard let node else { return }
                if let animation { withAnimation(animation) { Engine.render(node) } }
                else { Engine.render(node) }
            }
        )
        subscriptions[objectId, default: [:]][nodeId] = Subscription(node: node, cancellable: cancellable)
    }
}
#endif

// MARK: - @StateObject

@dynamicMemberLookup
@propertyWrapper @MainActor public final class StateObject<ObjectType: OmniObservableObject> {
    private var object: ObjectType?
    private let makeObject: () -> ObjectType

    // Construction is deferred so that a view rebuilt by its parent can adopt the
    // previous node's object without ever allocating a replacement.
    public init(wrappedValue: @autoclosure @escaping () -> ObjectType) {
        self.makeObject = wrappedValue
    }

    public var wrappedValue: ObjectType {
        let value: ObjectType
        if let object {
            value = object
        } else {
            value = makeObject()
            object = value
        }
        #if canImport(Combine)
        ObservableObjectBridge.track(value)
        #endif
        return value
    }

    public var projectedValue: StateObject<ObjectType> { self }

    // Enables $model.myProperty to return a Binding
    public subscript<T>(dynamicMember keyPath: ReferenceWritableKeyPath<ObjectType, T>) -> Binding<T> {
        Binding(
            get: { self.wrappedValue[keyPath: keyPath] },
            set: { self.wrappedValue[keyPath: keyPath] = $0 }
        )
    }
}

extension StateObject: StateStorage {
    func adoptValue(from other: any StateStorage) {
        guard let other = other as? StateObject<ObjectType> else { return }
        object = other.object
    }
}

// MARK: - @ObservedObject

@dynamicMemberLookup
@propertyWrapper @MainActor public struct ObservedObject<ObjectType: OmniObservableObject> {
    private let object: ObjectType

    public init(wrappedValue: ObjectType) {
        self.object = wrappedValue
    }

    public var wrappedValue: ObjectType {
        #if canImport(Combine)
        ObservableObjectBridge.track(object)
        #endif
        return object
    }

    public var projectedValue: ObservedObject<ObjectType> { self }

    public subscript<T>(dynamicMember keyPath: ReferenceWritableKeyPath<ObjectType, T>) -> Binding<T> {
        Binding(
            get: { self.wrappedValue[keyPath: keyPath] },
            set: { self.wrappedValue[keyPath: keyPath] = $0 }
        )
    }
}

// MARK: - @EnvironmentObject

@dynamicMemberLookup
@propertyWrapper @MainActor public struct EnvironmentObject<ObjectType: OmniObservableObject> {
    public init() {}

    public var wrappedValue: ObjectType {
        // Dynamically resolve from the active Engine node tree
        guard let current = Tracker.current,
              let obj = current.environment.values[ObjectIdentifier(ObjectType.self)] as? ObjectType else {
            fatalError("No ObservableObject of type \(ObjectType.self) found in environment. Did you forget to apply .environmentObject()?")
        }
        #if canImport(Combine)
        ObservableObjectBridge.track(obj)
        #endif
        return obj
    }

    public var projectedValue: EnvironmentObject<ObjectType> { self }

    public subscript<T>(dynamicMember keyPath: ReferenceWritableKeyPath<ObjectType, T>) -> Binding<T> {
        Binding(
            get: { self.wrappedValue[keyPath: keyPath] },
            set: { self.wrappedValue[keyPath: keyPath] = $0 }
        )
    }
}
