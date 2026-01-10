// src/probe/apple/ProbeHost+Apple.swift
#if os(macOS) || os(iOS)
import Foundation
@_spi(Probe) import OmniUI

#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

/// A screen, or a whole app, in a window of its own in the test's process,
/// and a probe that looks there. Tier 1: journeys with no device.
@MainActor public final class ProbeHost {
    public let probe: Probe
    private let tree: HostedTree
    #if os(macOS)
    public let window: NSWindow
    #else
    public let window: UIWindow
    #endif

    /// `view` in a phone-sized window, as the app's root: what the engine
    /// renders again, and what sheets and alerts present from.
    public init(_ view: some View, width: Double = 390, height: Double = 844) {
        Font.registerBundled()
        // This window draws no frames, so an animation would never finish.
        Transaction.animationsDisabled = true
        let frame = CGRect(x: 0, y: 0, width: width, height: height)
        #if os(macOS)
        window = NSWindow(contentRect: frame, styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        #else
        // In the test host's scene: UIKit presents sheets only from a window that has one.
        if let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first {
            window = UIWindow(windowScene: scene)
            window.frame = frame
        } else {
            window = UIWindow(frame: frame)
        }
        window.rootViewController = UIViewController()
        #endif
        let container: NativeView
        #if os(macOS)
        container = window.contentView!
        #else
        container = window.rootViewController!.view
        #endif
        // Whatever the root shows, now and after: a root can be nothing until
        // its session loads, as a window's is.
        tree = HostedTree(view, asRoot: true) { [weak container] native in
            guard let container else { return }
            container.subviews.forEach { $0.removeFromSuperview() }
            guard let root = native else { return }
            container.addSubview(root)
            root.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                root.topAnchor.constraint(equalTo: container.topAnchor),
                root.bottomAnchor.constraint(equalTo: container.bottomAnchor),
                root.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                root.trailingAnchor.constraint(equalTo: container.trailingAnchor)
            ])
        }
        #if os(macOS)
        window.orderFront(nil)
        window.contentView?.layoutSubtreeIfNeeded()
        let window = self.window
        // Its sheets and alerts first: they are attached to it, and in front.
        probe = Probe(roots: {
            (window.sheets.reversed().compactMap(\.contentView)) + [window.contentView].compactMap { $0 }
        })
        #else
        window.makeKeyAndVisible()
        window.layoutIfNeeded()
        let window = self.window
        probe = Probe(roots: { [window] })
        #endif
    }

    /// An app, as App.main would show it.
    public convenience init<A: App>(app: A, width: Double = 390, height: Double = 844) {
        self.init(AnyView(app), width: width, height: height)
    }

    /// Takes the window down and stops the tree's tasks.
    public func close() {
        tree.tearDown()
        Transaction.animationsDisabled = false
        #if os(macOS)
        window.sheets.forEach { window.endSheet($0) }
        window.close()
        #else
        window.isHidden = true
        #endif
    }
}
#endif
