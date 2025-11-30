// src/lib/components/Stack.swift
import Foundation

public enum StackAxis: Equatable, Sendable {
    case horizontal, vertical
}

public struct Stack: NativeComponent {
    public var axis: StackAxis
    /// Stack erases its axis, so it carries both components and projects
    /// whichever one is the cross axis once `axis` is known.
    public var alignment: Alignment
    public var spacing: Double?
    public var content: any View

    public var children: [any View] { Omni.unpackViews(content) }

    public init(axis: StackAxis,
                alignment: Alignment = .center,
                spacing: Double? = nil,
                @ViewBuilder _ content: @escaping () -> any View) {
        self.axis = axis
        self.alignment = alignment
        self.spacing = spacing
        self.content = content()
    }

    var asVStack: VStack {
        let captured = content
        return VStack(alignment: alignment.horizontal, spacing: spacing) { captured }
    }

    var asHStack: HStack {
        let captured = content
        return HStack(alignment: alignment.vertical, spacing: spacing) { captured }
    }

    @MainActor public func makeNative() -> NativeView {
        axis == .vertical ? asVStack.makeNative() : asHStack.makeNative()
    }

    @MainActor public func updateNative(_ view: NativeView) {
        applyAxis(view)
        if axis == .vertical { asVStack.updateNative(view) } else { asHStack.updateNative(view) }
    }

    @MainActor public func insertChild(_ child: NativeView, into parent: NativeView) {
        if axis == .vertical {
            asVStack.insertChild(child, into: parent)
        } else {
            asHStack.insertChild(child, into: parent)
        }
        recordChild(child, of: parent)
    }
}
