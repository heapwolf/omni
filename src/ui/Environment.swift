// src/ui/Environment.swift
// The Key Protocol & Storage
public protocol EnvironmentKey {
    associatedtype Value
    static var defaultValue: Value { get }
}

public struct EnvironmentValues {
    var values: [ObjectIdentifier: Any] = [:]

    public subscript<K: EnvironmentKey>(key: K.Type) -> K.Value {
        get { values[ObjectIdentifier(key)] as? K.Value ?? K.defaultValue }
        set { values[ObjectIdentifier(key)] = newValue }
    }

    /// The slot `.environmentObject(_:)` writes and @EnvironmentObject reads,
    /// so a module can publish a keypath onto the same object rather than
    /// cascading it twice.
    public func object<T: OmniObservableObject>(_ type: T.Type) -> T? {
        values[ObjectIdentifier(type)] as? T
    }
}

// The Property Wrapper
@propertyWrapper
public struct Environment<Value> {
    let keyPath: KeyPath<EnvironmentValues, Value>

    public init(_ keyPath: KeyPath<EnvironmentValues, Value>) {
        self.keyPath = keyPath
    }

    /// Resolved on access against the node being rendered, the same way
    /// @EnvironmentObject resolves. A struct property wrapper cannot be written
    /// to by the engine ahead of `body`, so there is nothing to inject: the
    /// cascade already lives on the node (see Node.environment).
    @MainActor public var wrappedValue: Value {
        guard let node = Tracker.current else {
            return EnvironmentValues()[keyPath: keyPath]
        }
        return node.environment[keyPath: keyPath]
    }
}

// A structural view that intercepts the render pass to mutate the environment for its children
public struct EnvironmentModifierView: OmniStructuralView {
    public var modifier: (inout EnvironmentValues) -> Void
    public var content: any View

    public init(modifier: @escaping (inout EnvironmentValues) -> Void, content: any View) {
        self.modifier = modifier
        self.content = content
    }

    public typealias Body = Never
    public var body: Never { fatalError("Engine unpacks this") }
    public var unpacked: [any View] { [content] }
}

public extension View {
    func environment<V>(_ keyPath: WritableKeyPath<EnvironmentValues, V>, _ value: V) -> some View {
        EnvironmentModifierView(
            modifier: { env in env[keyPath: keyPath] = value },
            content: self
        )
    }

    /// Injects an ObservableObject into the environment cascade
    func environmentObject<T: OmniObservableObject>(_ object: T) -> some View {
        EnvironmentModifierView(
            modifier: { env in
                // We use the ObjectIdentifier of the TYPE as the unique key
                env.values[ObjectIdentifier(T.self)] = object
            },
            content: self
        )
    }
}

// MARK: - isPresented

private struct IsPresentedKey: EnvironmentKey {
    static let defaultValue = false
}

public extension EnvironmentValues {
    /// SwiftUI's: true inside a sheet, for the screens it shows and all
    /// they hold. A screen used both as a page and in a sheet reads it to
    /// match where it is: the sheet's surface, say, not the page's.
    var isPresented: Bool {
        get { self[IsPresentedKey.self] }
        set { self[IsPresentedKey.self] = newValue }
    }
}
