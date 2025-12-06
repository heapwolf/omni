// src/lib/components/apple/GeometryReader+Apple.swift
import Foundation

#if os(macOS) || os(iOS)

#if os(macOS)
import AppKit

public class OmniGeometryView: NSView {
    var onResize: ((GeometryProxy) -> Void)?
    var lastSize: CGSize = CGSize(width: -1, height: -1)

    public override func layout() {
        super.layout()
        if bounds.size != lastSize {
            lastSize = bounds.size
            let newSize = GeometryProxy(width: Double(bounds.width), height: Double(bounds.height))

            // Call synchronously so the Engine renders in the same frame as the window resize
            self.onResize?(newSize)
        }
    }
}
#elseif os(iOS)
import UIKit

public class OmniGeometryView: UIView {
    var onResize: ((GeometryProxy) -> Void)?
    var lastSize: CGSize = CGSize(width: -1, height: -1)

    public override func layoutSubviews() {
        super.layoutSubviews()
        if bounds.size != lastSize {
            lastSize = bounds.size
            let newSize = GeometryProxy(width: Double(bounds.width), height: Double(bounds.height))

            // Call synchronously to avoid layout desync
            self.onResize?(newSize)
        }
    }
}
#endif

extension GeometryReaderPrimitive {
    @MainActor public func makeNative() -> NativeView {
        let v = OmniGeometryView()
        v.translatesAutoresizingMaskIntoConstraints = false

        v.setContentHuggingPriority(.init(rawValue: 1), for: .horizontal)
        v.setContentHuggingPriority(.init(rawValue: 1), for: .vertical)
        return v
    }

    @MainActor public func updateNative(_ view: NativeView) {
        if let v = view as? OmniGeometryView {
            v.onResize = onResize
        }
    }

    @MainActor public func insertChild(_ child: NativeView, into parent: NativeView) {
        parent.addSubview(child)
        // Tell Auto Layout to stretch the child to fill the GeometryReader
        NSLayoutConstraint.activate([
            child.topAnchor.constraint(equalTo: parent.topAnchor),
            child.bottomAnchor.constraint(equalTo: parent.bottomAnchor),
            child.leadingAnchor.constraint(equalTo: parent.leadingAnchor),
            child.trailingAnchor.constraint(equalTo: parent.trailingAnchor)
        ])
    }
}
#endif
