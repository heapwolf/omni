// src/lib/components/GeometryReader.swift
import Foundation

#if os(macOS) || os(iOS)
import CoreGraphics
#endif

#if os(macOS) || os(iOS)
/// CGSize on Apple, so `geometry.size` is the very type SwiftUI hands back.
public typealias Size = CGSize
#else
public struct Size: Equatable, Sendable {
    public var width: Double
    public var height: Double
    public init(width: Double = 0, height: Double = 0) {
        self.width = width
        self.height = height
    }
}
#endif

public struct GeometryProxy: Equatable {
    public var width: Double
    public var height: Double

    /// SwiftUI reads `geometry.size.width`; this is that.
    public var size: Size { Size(width: width, height: height) }

    // No frame(in:) or safeAreaInsets: a GeometryProxy here only ever learns its
    // own dimensions, so either would have to invent an origin. An API that
    // compiles and returns a wrong number is worse than one that is absent.

    public init(width: Double = 0, height: Double = 0) {
        self.width = width
        self.height = height
    }
}

/// The measuring container itself. `GeometryReader` wraps it to provide
/// SwiftUI's shape, where the content is a function of the measured size.
public struct GeometryReaderPrimitive: NativeComponent {
    public var onResize: (GeometryProxy) -> Void

    // Store the raw block
    public var content: any View

    // Unpack it dynamically for the engine
    public var children: [any View] { Omni.unpackViews(content) }

    /// Initializes with a closure that fires when the view bounds change
    public init(onResize: @escaping (GeometryProxy) -> Void, @ViewBuilder _ content: () -> any View) {
        self.onResize = onResize
        self.content = content()
    }

    /// Convenience initializer to directly bind the dimensions to a @State variable
    public init(size: Binding<GeometryProxy>, @ViewBuilder _ content: () -> any View) {
        self.init(onResize: { size.wrappedValue = $0 }, content)
    }
}

@MainActor public struct GeometryReader: View {
    @State private var proxy = GeometryProxy()
    private let build: (GeometryProxy) -> any View
    /// Fired only from the native layout callback in `body`, below — never
    /// from `build`, which the engine can invoke while constructing this
    /// view's own body. Calling it from there mutates state mid-render, and
    /// the resulting re-render is dropped rather than looping, silently
    /// leaving whatever was mid-render (a tab's whole screen, at worst) unbuilt.
    private let onResize: ((GeometryProxy) -> Void)?

    /// SwiftUI's shape: the content is built from the measured size, and is
    /// rebuilt whenever that size changes.
    public init(@ViewBuilder _ content: @escaping (GeometryProxy) -> any View) {
        self.build = content
        self.onResize = nil
    }

    /// Measure-only: fires on resize and builds content that ignores the size.
    public init(onResize: @escaping (GeometryProxy) -> Void, @ViewBuilder _ content: @escaping () -> any View) {
        self.build = { _ in content() }
        self.onResize = onResize
    }

    /// Writes the measured size straight into a binding.
    public init(size: Binding<GeometryProxy>, @ViewBuilder _ content: @escaping () -> any View) {
        self.init(onResize: { size.wrappedValue = $0 }, content)
    }

    public var body: some View {
        let current = proxy
        let onResize = self.onResize
        return GeometryReaderPrimitive(onResize: { measured in
            // Measure-only, the content ignores the size: telling the caller
            // is all. (Storing it re-rendered the content on every step of a
            // live resize: Responsive's whole page, each frame.)
            if let onResize { return onResize(measured) }
            // Re-render only on a real change, or this loops.
            if measured.width != current.width || measured.height != current.height {
                proxy = measured
            }
        }) { build(current) }
    }
}
