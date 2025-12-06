// src/lib/components/ZStack.swift
#if os(macOS) || os(iOS)
import Foundation
import QuartzCore

#if os(macOS)
import AppKit

// Create a flipped view for macOS so Y=0 is the top!
public class OmniZStackView: NSView {
    nonisolated public override var isFlipped: Bool { true }
}
#elseif os(iOS)
import UIKit
#endif

extension ZStack {
    @MainActor public func makeNative() -> NativeView {
        #if os(macOS)
            let v = OmniZStackView()
            v.wantsLayer = true
            v.translatesAutoresizingMaskIntoConstraints = false
        #elseif os(iOS)
            let v = UIView()
            v.translatesAutoresizingMaskIntoConstraints = false
        #endif

        // Low hugging, or an enclosing stack's fill constraint loses and this collapses.
        v.setContentHuggingPriority(.init(rawValue: 1), for: .horizontal)
        v.setContentHuggingPriority(.init(rawValue: 1), for: .vertical)
        return v
    }

    @MainActor public func updateNative(_ view: NativeView) {
        // Alignment is applied per child, in insertChild.
    }

    @MainActor public func insertChild(_ child: NativeView, into parent: NativeView) {
        #if os(macOS)
        if isNavigationContainer, let direction = Transaction.navigationTransition {
            parent.wantsLayer = true
            let transition = CATransition()
            transition.type = .push
            transition.subtype = direction == .push ? .fromRight : .fromLeft
            transition.duration = 0.35
            transition.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            parent.layer?.add(transition, forKey: kCATransition)
            Transaction.navigationTransition = nil
        }
        #endif

        parent.addSubview(child)
        NSLayoutConstraint.activate(alignmentConstraints(for: child, in: parent))
    }

    /// SwiftUI places each ZStack child at its own size and aligns it; it does
    /// not stretch it. Containment keeps the stack at least as large as every
    /// child, one equality per axis does the placing, and a child that asked to
    /// fill (hugging 1, the claim a Spacer and .frame(maxWidth:) both make)
    /// still stretches.
    @MainActor private func alignmentConstraints(
        for child: NativeView, in parent: NativeView
    ) -> [NSLayoutConstraint] {
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

        // 900 matches what VStack/HStack give a filling child, so the three
        // containers agree on what a fill claim outranks.
        if child.contentHuggingPriority(for: .horizontal).rawValue <= 1 {
            let fill = child.widthAnchor.constraint(equalTo: parent.widthAnchor)
            fill.priority = .init(rawValue: 900)
            constraints.append(fill)
        }
        if child.contentHuggingPriority(for: .vertical).rawValue <= 1 {
            let fill = child.heightAnchor.constraint(equalTo: parent.heightAnchor)
            fill.priority = .init(rawValue: 900)
            constraints.append(fill)
        }

        return constraints
    }
}
#endif
