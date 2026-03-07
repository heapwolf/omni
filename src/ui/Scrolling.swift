// src/ui/Scrolling.swift
// SwiftUI's scroll-view extras: onScrollGeometryChange and refreshable. Both
// travel down the environment to the ScrollView they are applied to, as
// SwiftUI's RefreshAction does.
import Foundation

/// SwiftUI's ScrollGeometry: where a scroll view is, and how big its content.
public struct ScrollGeometry: Equatable, Sendable {
    public var contentOffset: CGPoint
    public var contentSize: CGSize
    public var containerSize: CGSize

    public init(contentOffset: CGPoint, contentSize: CGSize, containerSize: CGSize) {
        self.contentOffset = contentOffset
        self.contentSize = contentSize
        self.containerSize = containerSize
    }

    public var visibleRect: CGRect { CGRect(origin: contentOffset, size: containerSize) }
}

/// One onScrollGeometryChange: turns a geometry into its value, and calls the
/// action when that value changes. The previous value lives on the native
/// scroll view, which outlives the modifier struct rebuilt on every render.
public struct ScrollGeometryObserver {
    let evaluate: @MainActor (ScrollGeometry, _ previous: Any?) -> Any
}

public struct ScrollGeometryObserversKey: EnvironmentKey {
    public static var defaultValue: [ScrollGeometryObserver] { [] }
}

/// SwiftUI's RefreshAction: `await refresh()` runs the refreshable's action.
public struct RefreshAction {
    let action: @MainActor () async -> Void
    @MainActor public func callAsFunction() async { await action() }
}

public struct RefreshActionKey: EnvironmentKey {
    public static var defaultValue: RefreshAction? { nil }
}

public extension EnvironmentValues {
    var scrollGeometryObservers: [ScrollGeometryObserver] {
        get { self[ScrollGeometryObserversKey.self] }
        set { self[ScrollGeometryObserversKey.self] = newValue }
    }

    /// SwiftUI's: the nearest refreshable's action, or nil.
    var refresh: RefreshAction? {
        get { self[RefreshActionKey.self] }
        set { self[RefreshActionKey.self] = newValue }
    }
}

public extension View {
    /// SwiftUI's: calls `action` with the old and new value whenever
    /// `transform` of the scroll view's geometry changes. Apply it to the
    /// ScrollView. Not called for the first value, as in SwiftUI.
    func onScrollGeometryChange<T: Equatable>(for type: T.Type,
                                              of transform: @escaping (ScrollGeometry) -> T,
                                              action: @escaping (T, T) -> Void) -> some View {
        let observer = ScrollGeometryObserver { geometry, previous in
            let value = transform(geometry)
            if let old = previous as? T, old != value { action(old, value) }
            return value
        }
        return environment(\.scrollGeometryObservers, [observer])
    }

    /// SwiftUI's: pulling the scroll view down runs `action`, with the spinner
    /// showing until it returns. Main-actor isolated rather than Sendable, so
    /// the action can use the view's state as written in SwiftUI.
    func refreshable(action: @escaping @MainActor () async -> Void) -> some View {
        environment(\.refresh, RefreshAction(action: action))
    }
}
