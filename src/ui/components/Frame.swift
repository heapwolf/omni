// src/lib/components/Frame.swift
import Foundation

public struct Frame: NativeComponent {
    public var content: any View

    public var width: Double?
    public var height: Double?
    public var alignment: Alignment
    public var cursor: String?
    public var onDrag: ((Double, Double) -> Void)?
    /// The drag let go: its velocity, in points per second (iOS and macOS).
    public var onDragEnded: ((Double, Double) -> Void)?
    /// Only horizontal drags: a vertical one goes to the scroll view around
    /// it, as a carousel inside a scrolling screen needs (iOS).
    public var dragsHorizontally: Bool
    public var onTap: (() -> Void)?
    public var onTapLocation: ((Double, Double) -> Void)?
    public var onScroll: ((Double, Double) -> Void)?
    public var children: [any View] { Omni.unpackViews(content) }

    public var body: any View { self }

    public init(
        width: Double? = nil,
        height: Double? = nil,
        alignment: Alignment = .center,
        cursor: String? = nil,
        onDrag: ((Double, Double) -> Void)? = nil,
        onDragEnded: ((Double, Double) -> Void)? = nil,
        dragsHorizontally: Bool = false,
        onTap: (() -> Void)? = nil,
        onTapLocation: ((Double, Double) -> Void)? = nil,
        onScroll: ((Double, Double) -> Void)? = nil,
        @ViewBuilder _ content: @escaping () -> any View
    ) {
        self.width = width
        self.height = height
        self.alignment = alignment
        self.cursor = cursor
        self.onDrag = onDrag
        self.onDragEnded = onDragEnded
        self.dragsHorizontally = dragsHorizontally
        self.onTap = onTap
        self.onTapLocation = onTapLocation
        self.onScroll = onScroll
        self.content = content()
    }
}
