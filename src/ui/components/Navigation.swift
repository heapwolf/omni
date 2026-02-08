// src/lib/components/Navigation.swift
import Foundation

// MARK: - 1. Navigation Environment

// A generic context we pass down via Environment
public class NavigationContext {
    public var path: [AnyView] = []
    public var push: ((AnyView) -> Void)?
    public var pop: (() -> Void)?

    /// Destination builders registered by .navigationDestination(for:), keyed
    /// by the value's type. The context is a reference type shared down the
    /// tree, so a modifier nested inside the stack can register into the very
    /// object the stack reads back — Omni has no upward preference pass.
    var destinationBuilders: [ObjectIdentifier: (AnyHashable) -> AnyView?] = [:]

    /// Set by NavigationStack; resolves a value through the registry and pushes.
    public var pushValue: ((AnyHashable) -> Void)?

    func resolve(_ value: AnyHashable) -> AnyView? {
        destinationBuilders[ObjectIdentifier(Swift.type(of: value.base))]?(value)
    }
}

public struct NavigationContextKey: EnvironmentKey {
    /// A placeholder, replaced when a NavigationStack mounts. Never written:
    /// a stack installs its own, and a view outside one gets nil push and pop.
    nonisolated(unsafe) public static let defaultValue = NavigationContext()
}

public extension EnvironmentValues {
    var navigationContext: NavigationContext {
        get { self[NavigationContextKey.self] }
        set { self[NavigationContextKey.self] = newValue }
    }
}

// Distinct types so NavigationStack's two branches always report different
// types to the reconciler; see NavigationStack.body.
public struct NavigationRootContent<Content: View>: View {
    public var content: Content
    public var body: some View { content }
}

public struct NavigationDestinationContent<Content: View>: View {
    public var content: Content
    public var body: some View { content }
}

// MARK: - 2. NavigationStack

public struct NavigationStack<Content: View>: View {
    public var content: Content
    @State private var path: [AnyView] = []

    @MainActor public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        let context = NavigationContext()
        context.path = path

        // Not withAnimation: its layout animation beats the CATransition.
        context.push = { view in
            Transaction.navigationTransition = .push
            path.append(view)
            Transaction.navigationTransition = nil // safety net if nothing consumed it
        }

        context.pushValue = { [weak context] value in
            guard let context, let view = context.resolve(value) else {
                Omni.log("navigationDestination(for:) is missing for \(Swift.type(of: value.base))")
                return
            }
            context.push?(view)
        }

        context.pop = {
            Transaction.navigationTransition = .pop
            if !path.isEmpty { path.removeLast() }
            Transaction.navigationTransition = nil
        }

        // Wrapped in marker types rather than left bare: the root content is
        // frequently itself a VStack, and so is the destination.
        var container = ZStack {
            if path.isEmpty {
                NavigationRootContent(content: content)
            } else {
                NavigationDestinationContent(content: VStack {
                    // Standard cross-platform Back button injection
                    HStack {
                        Button("Back", action: { context.pop?() })
                            .padding(8)
                        Spacer()
                    }
                    Divider()
                    path.last!

                    Spacer()
                })
            }
        }
        container.isNavigationContainer = true
        return container
            .environment(\.navigationContext, context)
    }
}

// MARK: - 3. NavigationLink

public struct NavigationLink<Label: View, Destination: View>: View {
    public var destination: Destination?
    /// SwiftUI's value-based form; resolved by .navigationDestination(for:).
    public var value: AnyHashable?
    public var label: Label

    public init(destination: Destination, @ViewBuilder label: () -> Label) {
        self.destination = destination
        self.value = nil
        self.label = label()
    }

    public init(_ title: String, destination: Destination) where Label == Text {
        self.destination = destination
        self.value = nil
        self.label = Text(title)
    }

    /// SwiftUI's `NavigationLink(value:) { label }`.
    public init<V: Hashable>(value: V, @ViewBuilder label: () -> Label) where Destination == EmptyView {
        self.destination = nil
        self.value = AnyHashable(value)
        self.label = label()
    }

    /// SwiftUI's `NavigationLink("Title", value: v)`.
    public init<V: Hashable>(_ title: String, value: V) where Destination == EmptyView, Label == Text {
        self.destination = nil
        self.value = AnyHashable(value)
        self.label = Text(title)
    }

    // Explicitly isolated to MainActor to safely read Tracker.current
    @MainActor public var body: some View {
        // Reads from the environment context to push the destination onto the stack
        let context = Tracker.current?.environment.navigationContext

        return Button(action: {
            if let destination {
                context?.push?(AnyView(destination))
            } else if let value {
                context?.pushValue?(value)
            }
        }, label: {
            label
        })
    }
}


// MARK: - 4. Value-based destinations

/// Registers its builder into the shared NavigationContext as it renders, then
/// gets out of the way. Registration happens while the stack's content is being
/// evaluated, which is strictly before any NavigationLink inside it can be
/// tapped — so the registry is always populated by the time a push resolves.
public struct NavigationDestinationRegistrar<Content: View>: View {
    public var key: ObjectIdentifier
    public var build: (AnyHashable) -> AnyView?
    public var content: Content

    @MainActor public var body: some View {
        Tracker.current?.environment.navigationContext.destinationBuilders[key] = build
        return content
    }
}

public extension View {
    /// SwiftUI's `.navigationDestination(for:destination:)`.
    ///
    /// Note the one behavioural gap against SwiftUI: this resolves a value when
    /// the link is tapped, not when the path changes, so it does not yet serve
    /// a programmatic `NavigationStack(path:)`. See TODO.md.
    func navigationDestination<D: Hashable, C: View>(
        for data: D.Type,
        @ViewBuilder destination: @escaping (D) -> C
    ) -> some View {
        NavigationDestinationRegistrar(
            key: ObjectIdentifier(data),
            build: { anyValue in
                guard let typed = anyValue.base as? D else { return nil }
                return AnyView(destination(typed))
            },
            content: self)
    }
}
