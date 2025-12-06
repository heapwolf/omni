#if os(macOS) || os(iOS)
import Foundation

#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

// A local target to catch objective-c gesture events without polluting the global namespace
class OmniSwipeTarget: NSObject {
    var onSwipeLeft: () -> Void
    var onSwipeRight: () -> Void

    init(onLeft: @escaping () -> Void, onRight: @escaping () -> Void) {
        self.onSwipeLeft = onLeft
        self.onSwipeRight = onRight
    }

    #if os(macOS)
    @MainActor @objc func handlePan(_ sender: NSPanGestureRecognizer) {
        if sender.state == .ended {
            let trans = sender.translation(in: sender.view)
            if trans.x < -20 { onSwipeLeft() }
            else if trans.x > 20 { onSwipeRight() }
        }
    }
    #elseif os(iOS)
    @MainActor @objc func handleSwipe(_ sender: UISwipeGestureRecognizer) {
        if sender.direction == .left { onSwipeLeft() }
        else if sender.direction == .right { onSwipeRight() }
    }
    #endif
}

extension NativeSwipeModifierView {
    @MainActor public func makeNative() -> NativeView {
        #if os(macOS)
            let v = NSView()
            v.translatesAutoresizingMaskIntoConstraints = false

            let target = OmniSwipeTarget(onLeft: onSwipeLeft, onRight: onSwipeRight)
            let pan = NSPanGestureRecognizer(target: target, action: #selector(OmniSwipeTarget.handlePan(_:)))
            v.addGestureRecognizer(pan)

            // Retain the target
            objc_setAssociatedObject(v, UnsafeRawPointer(bitPattern: 1)!, target, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            return v

        #elseif os(iOS)
            let v = UIView()
            v.translatesAutoresizingMaskIntoConstraints = false

            let target = OmniSwipeTarget(onLeft: onSwipeLeft, onRight: onSwipeRight)
            let swipeLeft = UISwipeGestureRecognizer(target: target, action: #selector(OmniSwipeTarget.handleSwipe(_:)))
            swipeLeft.direction = .left

            let swipeRight = UISwipeGestureRecognizer(target: target, action: #selector(OmniSwipeTarget.handleSwipe(_:)))
            swipeRight.direction = .right

            v.addGestureRecognizer(swipeLeft)
            v.addGestureRecognizer(swipeRight)

            objc_setAssociatedObject(v, UnsafeRawPointer(bitPattern: 1)!, target, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            return v
        #endif
    }

    /// The closures of this render: the ones made with the view knew only the
    /// first page, so a swipe always went from page one (to two, or back).
    @MainActor public func updateNative(_ view: NativeView) {
        guard let target = objc_getAssociatedObject(view, UnsafeRawPointer(bitPattern: 1)!) as? OmniSwipeTarget else { return }
        target.onSwipeLeft = onSwipeLeft
        target.onSwipeRight = onSwipeRight
    }

    @MainActor public func insertChild(_ child: NativeView, into parent: NativeView) {
        #if os(macOS) || os(iOS)
            parent.addSubview(child)
            // Sized as its content asks, as the safe-area wrapper is: a plain
            // view's default hugging, with nothing inside to size it by, made
            // the layout around a full-screen child ambiguous, and a screen
            // swiped between laid itself out at random.
            adoptSizing(of: child, into: parent)
            NSLayoutConstraint.activate([
                child.topAnchor.constraint(equalTo: parent.topAnchor),
                child.bottomAnchor.constraint(equalTo: parent.bottomAnchor),
                child.leadingAnchor.constraint(equalTo: parent.leadingAnchor),
                child.trailingAnchor.constraint(equalTo: parent.trailingAnchor)
            ])
        #endif
    }
}
#endif
