// src/lib/components/apple/TapGesture+Apple.swift
#if os(macOS) || os(iOS)
import Foundation

#if os(macOS)
    import AppKit

    public class OmniTapView: NSView {
        public var onTap: (() -> Void)?
        @objc public func handleClick(_ gesture: NSClickGestureRecognizer) { onTap?() }
    }
#elseif os(iOS)
    import UIKit

    public class OmniTapView: UIView, UIGestureRecognizerDelegate {
        public var onTap: (() -> Void)?
        @objc public func handleClick(_ gesture: UITapGestureRecognizer) { onTap?() }

        /// An inner control wins, as in SwiftUI: a Button, a text field, a
        /// switch inside a tappable row keeps its own taps.
        public func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                                      shouldReceive touch: UITouch) -> Bool {
            var view = touch.view
            while let current = view, current !== self {
                if current is UIControl || current is UITextView { return false }
                view = current.superview
            }
            return true
        }
    }
#endif

public extension TapGestureView {
    @MainActor
    func makeNative() -> NativeView {
        let view = OmniTapView()
        view.translatesAutoresizingMaskIntoConstraints = false

        #if os(macOS)
            let recognizer = NSClickGestureRecognizer(target: view, action: #selector(OmniTapView.handleClick(_:)))
        #elseif os(iOS)
            let recognizer = UITapGestureRecognizer(target: view, action: #selector(OmniTapView.handleClick(_:)))
            recognizer.delegate = view
        #endif
        view.addGestureRecognizer(recognizer)
        return view
    }

    @MainActor
    func updateNative(_ view: NativeView) {
        // Swap the closure the existing recognizer already reads, rather than
        // adding another one per render.
        (view as? OmniTapView)?.onTap = action
    }

    @MainActor
    func insertChild(_ child: NativeView, into parent: NativeView) {
        parent.addSubview(child)
        adoptSizing(of: child, into: parent)
        NSLayoutConstraint.activate([
            child.topAnchor.constraint(equalTo: parent.topAnchor),
            child.bottomAnchor.constraint(equalTo: parent.bottomAnchor),
            child.leadingAnchor.constraint(equalTo: parent.leadingAnchor),
            child.trailingAnchor.constraint(equalTo: parent.trailingAnchor)
        ])
    }
}
#endif
