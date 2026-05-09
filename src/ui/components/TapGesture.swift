// src/lib/components/TapGesture.swift
import Foundation

public struct TapGestureView: NativeComponent {
    public var content: any View
    public var action: () -> Void

    public var children: [any View] { Omni.unpackViews(content) }

    public init(content: any View, action: @escaping () -> Void) {
        self.content = content
        self.action = action
    }
}

public extension View {
    /// Runs `action` when this view is tapped.
    func onTapGesture(perform action: @escaping () -> Void) -> some View {
        TapGestureView(content: self, action: action)
    }
}
