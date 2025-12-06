// src/lib/components/apple/PressGesture+Apple.swift
#if os(macOS) || os(iOS)
import Foundation

#if os(macOS)
    import AppKit

    /// Tracks the mouse from down to up, as NSButton does.
    public class OmniPressView: NSView {
        public var onPressChange: ((Bool) -> Void)?
        public var onAction: (() -> Void)?
        /// Off under .disabled(true), as an NSControl would be: no press, no action.
        public var isEnabled = true {
            didSet { if !isEnabled { setInside(false) } }
        }
        private var isInside = false

        /// The press is this view's, not a label's inside it: only a control
        /// that takes its own clicks (a field, a switch) keeps them.
        public override func hitTest(_ point: NSPoint) -> NSView? {
            guard let hit = super.hitTest(point) else { return nil }
            if let field = hit as? NSTextField, !field.isEditable { return self }
            return hit is NSControl ? hit : self
        }

        public override func mouseDown(with event: NSEvent) {
            guard isEnabled else { return }
            setInside(true)
        }

        public override func mouseDragged(with event: NSEvent) {
            setInside(isWithinSlop(convert(event.locationInWindow, from: nil)))
        }

        public override func mouseUp(with event: NSEvent) {
            let released = isInside && isWithinSlop(convert(event.locationInWindow, from: nil))
            setInside(false)
            if released { onAction?() }
        }

        private func isWithinSlop(_ point: NSPoint) -> Bool {
            bounds.insetBy(dx: -pressSlop, dy: -pressSlop).contains(point)
        }

        private func setInside(_ inside: Bool) {
            guard inside != isInside else { return }
            isInside = inside
            onPressChange?(inside)
        }
    }
#elseif os(iOS)
    import UIKit

    /// A UIControl, so a press has UIButton's rules: a scroll that starts in
    /// time takes the touch, a tappable row around it leaves it alone (see
    /// OmniTapView), and dragging off and back on un-presses and re-presses.
    public class OmniPressView: UIControl {
        public var onPressChange: ((Bool) -> Void)?
        public var onAction: (() -> Void)?
        private var isInside = false

        public override init(frame: CGRect) {
            super.init(frame: frame)
            addTarget(self, action: #selector(pressed), for: [.touchDown, .touchDragEnter, .touchDragInside])
            addTarget(self, action: #selector(unpressed), for: [.touchDragExit, .touchDragOutside, .touchUpOutside,
                                                                .touchCancel, .touchUpInside])
            addTarget(self, action: #selector(released), for: .touchUpInside)
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

        /// The press is this view's, not a label's inside it: only a control
        /// of its own (a field, a switch) keeps its touches.
        public override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
            guard let hit = super.hitTest(point, with: event) else { return nil }
            var view: UIView? = hit
            while let current = view, current !== self {
                if current is UIControl || current is UITextView { return hit }
                view = current.superview
            }
            return self
        }

        @objc private func pressed() { setInside(true) }
        @objc private func unpressed() { setInside(false) }

        private func setInside(_ inside: Bool) {
            guard inside != isInside else { return }
            isInside = inside
            onPressChange?(inside)
        }

        @objc private func released() {
            onAction?()
        }

        // VoiceOver's double tap: the same as a release inside.
        public override func accessibilityActivate() -> Bool {
            onAction?()
            return true
        }
    }
#endif

public extension PressGestureView {
    @MainActor
    func makeNative() -> NativeView {
        let view = OmniPressView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }

    @MainActor
    func updateNative(_ view: NativeView) {
        // Swap the closures the view already calls, rather than re-binding.
        guard let view = view as? OmniPressView else { return }
        view.onPressChange = onPressChange
        view.onAction = action
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
