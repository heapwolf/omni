// src/lib/components/apple/Frame+Apple.swift
import Foundation

#if os(macOS) || os(iOS)

#if os(macOS)
    import AppKit
    import CoreGraphics
#elseif os(iOS)
    import UIKit
    import CoreGraphics
#endif

#if os(macOS)
    public class OmniFrameView: NSView, NSGestureRecognizerDelegate {
        nonisolated public override var isFlipped: Bool { true }

        // Declare explicit sizing properties
        public var explicitWidth: Double? { didSet { invalidateIntrinsicContentSize() } }
        public var explicitHeight: Double? { didSet { invalidateIntrinsicContentSize() } }

        // Straight into Auto Layout.
        public override var intrinsicContentSize: NSSize {
            return NSSize(
                width: explicitWidth ?? NSView.noIntrinsicMetric,
                height: explicitHeight ?? NSView.noIntrinsicMetric
            )
        }

        public var cursorStyle: String? {
            didSet { self.window?.invalidateCursorRects(for: self) }
        }
        public var onDrag: ((Double, Double) -> Void)?
        public var onDragEnded: ((Double, Double) -> Void)?
        public var dragsHorizontally = false
        public var onTap: (() -> Void)?
        public var onTapLocation: ((Double, Double) -> Void)?
        public var onScroll: ((Double, Double) -> Void)?

        public func gestureRecognizerShouldBegin(_ gestureRecognizer: NSGestureRecognizer) -> Bool {
            if gestureRecognizer is NSClickGestureRecognizer { return onTap != nil || onTapLocation != nil }
            if gestureRecognizer is NSPanGestureRecognizer { return onDrag != nil || onDragEnded != nil }
            return true
        }

        public func gestureRecognizer(_ gestureRecognizer: NSGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: NSGestureRecognizer) -> Bool {
            return true
        }

        public override func resetCursorRects() {
            if cursorStyle == "resizeLeftRight" {
                self.addCursorRect(self.bounds, cursor: .resizeLeftRight)
            } else if cursorStyle == "pointingHand" {
                self.addCursorRect(self.bounds, cursor: .pointingHand)
            } else {
                super.resetCursorRects()
            }
        }

        @objc public func handlePan(_ gesture: NSPanGestureRecognizer) {
            let translation = gesture.translation(in: self)
            switch gesture.state {
            case .changed:
                onDrag?(Double(translation.x), Double(translation.y))
                gesture.setTranslation(.zero, in: self)
            case .ended, .cancelled:
                let velocity = gesture.velocity(in: self)
                onDragEnded?(Double(velocity.x), Double(velocity.y))
            default: break
            }
        }

        @objc public func handleClick(_ gesture: NSClickGestureRecognizer) {
            if gesture.state == .ended {
                let loc = gesture.location(in: self)
                onTapLocation?(Double(loc.x), Double(loc.y))
                onTap?()
            }
        }

        public override func scrollWheel(with event: NSEvent) {
            onScroll?(Double(event.scrollingDeltaX), Double(event.scrollingDeltaY))
            super.scrollWheel(with: event)
        }
    }
#elseif os(iOS)
    public class OmniFrameView: UIView, UIGestureRecognizerDelegate {
        public var explicitWidth: Double? { didSet { invalidateIntrinsicContentSize() } }
        public var explicitHeight: Double? { didSet { invalidateIntrinsicContentSize() } }

        public override var intrinsicContentSize: CGSize {
            return CGSize(
                width: explicitWidth ?? UIView.noIntrinsicMetric,
                height: explicitHeight ?? UIView.noIntrinsicMetric
            )
        }

        public var onDrag: ((Double, Double) -> Void)?
        public var onDragEnded: ((Double, Double) -> Void)?
        public var dragsHorizontally = false
        public var onTap: (() -> Void)?
        public var onTapLocation: ((Double, Double) -> Void)?
        public var onScroll: ((Double, Double) -> Void)?

        public override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            if gestureRecognizer is UITapGestureRecognizer { return onTap != nil || onTapLocation != nil }
            if let pan = gestureRecognizer as? UIPanGestureRecognizer {
                guard onDrag != nil || onDragEnded != nil else { return false }
                guard dragsHorizontally else { return true }
                let velocity = pan.velocity(in: self)
                return abs(velocity.x) > abs(velocity.y)
            }
            return true
        }

        public func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            // A horizontal drag has the touch to itself: the screen must not
            // scroll up and down under a card being swiped.
            if dragsHorizontally, gestureRecognizer is UIPanGestureRecognizer,
               otherGestureRecognizer.view is UIScrollView { return false }
            return true
        }

        @objc public func handlePan(_ gesture: UIPanGestureRecognizer) {
            let translation = gesture.translation(in: self)
            switch gesture.state {
            case .changed:
                onDrag?(Double(translation.x), Double(translation.y))
                gesture.setTranslation(.zero, in: self)
            case .ended, .cancelled:
                let velocity = gesture.velocity(in: self)
                onDragEnded?(Double(velocity.x), Double(velocity.y))
            default: break
            }
        }

        @objc public func handleTap(_ gesture: UITapGestureRecognizer) {
            if gesture.state == .ended {
                let loc = gesture.location(in: self)
                onTapLocation?(Double(loc.x), Double(loc.y))
                onTap?()
            }
        }
    }
#endif

extension Frame {
    @MainActor public func makeNative() -> NativeView {
        let v = OmniFrameView()
        v.translatesAutoresizingMaskIntoConstraints = false

        #if os(macOS)
        v.cursorStyle = self.cursor
        v.wantsLayer = true
        #endif

        v.onDrag = self.onDrag
        v.onDragEnded = self.onDragEnded
        v.dragsHorizontally = self.dragsHorizontally
        v.onTap = self.onTap
        v.onTapLocation = self.onTapLocation
        v.onScroll = self.onScroll

        updateGestureRecognizers(on: v)

        // 251: stronger than flexible space, weaker than a window drag.
        v.setContentCompressionResistancePriority(.init(rawValue: 251), for: .horizontal)
        v.setContentCompressionResistancePriority(.init(rawValue: 251), for: .vertical)

        v.setContentHuggingPriority(.init(rawValue: 250), for: .horizontal)
        v.setContentHuggingPriority(.init(rawValue: 250), for: .vertical)

        v.explicitWidth = width
        v.explicitHeight = height

        return v
    }

    @MainActor public func updateNative(_ view: NativeView) {
        guard let v = view as? OmniFrameView else { return }

        #if os(macOS)
        v.cursorStyle = self.cursor
        #endif

        v.onDrag = self.onDrag
        v.onDragEnded = self.onDragEnded
        v.dragsHorizontally = self.dragsHorizontally
        v.onTap = self.onTap
        v.onTapLocation = self.onTapLocation
        v.onScroll = self.onScroll

        updateGestureRecognizers(on: v)

        v.explicitWidth = width
        v.explicitHeight = height
    }

    // Create a recognizer only once something asks for it, checked again on every
    // update so a Frame assigned a callback later still gains one.
    @MainActor private func updateGestureRecognizers(on v: OmniFrameView) {
        #if os(macOS)
        if self.onDrag != nil || self.onDragEnded != nil, !(v.gestureRecognizers.contains { $0 is NSPanGestureRecognizer }) {
            let pan = NSPanGestureRecognizer(target: v, action: #selector(OmniFrameView.handlePan(_:)))
            pan.delegate = v
            v.addGestureRecognizer(pan)
        }
        if self.onTap != nil || self.onTapLocation != nil,
           !(v.gestureRecognizers.contains { $0 is NSClickGestureRecognizer }) {
            let click = NSClickGestureRecognizer(target: v, action: #selector(OmniFrameView.handleClick(_:)))
            click.delegate = v
            v.addGestureRecognizer(click)
        }
        #elseif os(iOS)
        if self.onDrag != nil || self.onDragEnded != nil, !((v.gestureRecognizers ?? []).contains { $0 is UIPanGestureRecognizer }) {
            let pan = UIPanGestureRecognizer(target: v, action: #selector(OmniFrameView.handlePan(_:)))
            pan.delegate = v
            v.addGestureRecognizer(pan)
        }
        if self.onTap != nil || self.onTapLocation != nil,
           !((v.gestureRecognizers ?? []).contains { $0 is UITapGestureRecognizer }) {
            let tap = UITapGestureRecognizer(target: v, action: #selector(OmniFrameView.handleTap(_:)))
            tap.delegate = v
            v.addGestureRecognizer(tap)
        }
        #endif
    }

    @MainActor public func insertChild(_ child: NativeView, into parent: NativeView) {
        parent.addSubview(child)

        // Containment first: a frame answers for its own size, so the child is
        // held inside it rather than pushing it out.
        var constraints: [NSLayoutConstraint] = [
            child.topAnchor.constraint(greaterThanOrEqualTo: parent.topAnchor),
            child.leadingAnchor.constraint(greaterThanOrEqualTo: parent.leadingAnchor),
            parent.bottomAnchor.constraint(greaterThanOrEqualTo: child.bottomAnchor),
            parent.trailingAnchor.constraint(greaterThanOrEqualTo: child.trailingAnchor)
        ]

        switch alignment.horizontal {
        case .leading: constraints.append(child.leadingAnchor.constraint(equalTo: parent.leadingAnchor))
        case .center: constraints.append(child.centerXAnchor.constraint(equalTo: parent.centerXAnchor))
        case .trailing: constraints.append(child.trailingAnchor.constraint(equalTo: parent.trailingAnchor))
        }

        switch alignment.vertical {
        case .top: constraints.append(child.topAnchor.constraint(equalTo: parent.topAnchor))
        case .center: constraints.append(child.centerYAnchor.constraint(equalTo: parent.centerYAnchor))
        case .bottom: constraints.append(child.bottomAnchor.constraint(equalTo: parent.bottomAnchor))
        }

        // An axis the frame does not pin is still the child's to fill, or a
        // Frame(height:) wrapping a row would collapse that row's width. And
        // even on a pinned axis, a child that claims fill (a ZStack/HStack/
        // VStack whose own content wants the room — the same hugging<=1
        // claim ZStack honors for its own children) still stretches to it,
        // or `ZStack{ Circle().fill(_:) }.frame(width:40,height:40)` centers
        // the circle at its unfilled natural size instead of the 40x40 box.
        if width == nil || child.contentHuggingPriority(for: .horizontal).rawValue <= 1 {
            let fill = child.widthAnchor.constraint(equalTo: parent.widthAnchor)
            fill.priority = .init(rawValue: 900)
            constraints.append(fill)
        }
        if height == nil || child.contentHuggingPriority(for: .vertical).rawValue <= 1 {
            let fill = child.heightAnchor.constraint(equalTo: parent.heightAnchor)
            fill.priority = .init(rawValue: 900)
            constraints.append(fill)
        }

        NSLayoutConstraint.activate(constraints)
    }
}
#endif
