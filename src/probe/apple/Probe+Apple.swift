// src/probe/apple/Probe+Apple.swift
#if os(macOS) || os(iOS)
import Foundation
@_spi(Probe) import OmniUI

#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

extension Probe {
    // MARK: Where to look

    /// The app's windows, front first: a sheet or an alert before what it covers.
    static func windowRoots() -> [NativeView] {
        #if os(macOS)
        return NSApplication.shared.orderedWindows.filter(\.isVisible).compactMap(\.contentView)
        #else
        let windows = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows).filter { !$0.isHidden }
        return windows.sorted { $0.windowLevel > $1.windowLevel }
        #endif
    }

    static func layOut(_ root: NativeView) {
        #if os(macOS)
        root.layoutSubtreeIfNeeded()
        #else
        root.layoutIfNeeded()
        #endif
    }

    // MARK: What is there

    static func collect(from root: NativeView) -> [Located] {
        var found: [Located] = []
        func walk(_ view: NativeView, depth: Int) {
            let role = self.role(of: view)
            let identifier = self.identifier(of: view)
            if role != .other || identifier != nil {
                found.append(Located(element: element(for: view, role: role, identifier: identifier, depth: depth),
                                     view: view))
            }
            // A field's own insides (its editor, its clear button) are not the app's.
            if role == .field || role == .secureField { return }
            for subview in view.subviews { walk(subview, depth: role == .other && identifier == nil ? depth : depth + 1) }
        }
        walk(root, depth: 0)
        return found
    }

    static func element(for view: NativeView, role: ProbeElement.Role, identifier: String?, depth: Int) -> ProbeElement {
        ProbeElement(identifier: identifier,
                     path: Interactions.path(of: view),
                     role: role,
                     text: text(of: view, role: role),
                     label: accessibilityLabel(of: view),
                     value: value(of: view),
                     frame: frame(of: view),
                     // The control it stands for: an identifier is often on what wraps it.
                     isEnabled: isEnabled(actionable(for: view) ?? view),
                     isVisible: isVisible(view),
                     depth: depth)
    }

    static func role(of view: NativeView) -> ProbeElement.Role {
        #if os(macOS)
        switch view {
        case is NSSecureTextField: return .secureField
        case let field as NSTextField: return field.isEditable ? .field : .text
        case is NSSwitch: return .toggle
        case is NSButton, is OmniPressView: return .button
        case is OmniTapView: return .control
        case is NSControl: return .control
        case is NSImageView: return .image
        default: return .other
        }
        #else
        switch view {
        case let field as UITextField: return field.isSecureTextEntry ? .secureField : .field
        case is UISwitch: return .toggle
        case is UIButton, is OmniPressView: return .button
        case is UIControl, is OmniTapView: return .control
        case is UILabel: return .text
        case is UIImageView: return .image
        case is UITextView: return .field
        default: return .other
        }
        #endif
    }

    static func identifier(of view: NativeView) -> String? {
        #if os(macOS)
        let id = view.accessibilityIdentifier()
        #else
        let id = view.accessibilityIdentifier ?? ""
        #endif
        return id.isEmpty ? nil : id
    }

    static func accessibilityLabel(of view: NativeView) -> String? {
        #if os(macOS)
        let label = view.accessibilityLabel()
        #else
        let label = view.accessibilityLabel
        #endif
        return label?.isEmpty == false ? label : nil
    }

    static func text(of view: NativeView, role: ProbeElement.Role) -> String? {
        #if os(macOS)
        switch view {
        case is NSSecureTextField: return nil
        case let field as NSTextField: return field.stringValue
        case let button as NSButton: return button.title.isEmpty ? nil : button.title
        default: break
        }
        #else
        switch view {
        case let field as UITextField: return field.isSecureTextEntry ? nil : field.text
        case let label as UILabel: return label.text
        case let button as UIButton: return button.title(for: .normal) ?? button.titleLabel?.text
        case let textView as UITextView: return textView.text
        default: break
        }
        #endif
        // A control's text is the text inside it, so a button made of a label
        // can be found by what it says.
        guard role == .button || role == .control else { return nil }
        let inner = labels(in: view)
        return inner.isEmpty ? nil : inner.joined(separator: " ")
    }

    private static func labels(in view: NativeView) -> [String] {
        view.subviews.flatMap { subview -> [String] in
            #if os(macOS)
            if let field = subview as? NSTextField, !field.isEditable, !field.stringValue.isEmpty { return [field.stringValue] }
            #else
            if let label = subview as? UILabel, let text = label.text, !text.isEmpty { return [text] }
            #endif
            return labels(in: subview)
        }
    }

    static func value(of view: NativeView) -> String? {
        #if os(macOS)
        if let toggle = view as? NSSwitch { return toggle.state == .on ? "on" : "off" }
        #else
        if let toggle = view as? UISwitch { return toggle.isOn ? "on" : "off" }
        #endif
        return nil
    }

    #if os(macOS)
    /// `point`, in `view`'s coordinates, in its window's, where it is drawn.
    /// NSView's convert leaves out the layer transforms .offset and
    /// .scaleEffect draw with; UIKit's convert includes them.
    static func toWindow(_ point: NSPoint, from view: NSView) -> NSPoint {
        var p = point
        var current = view
        while let parent = current.superview {
            p = current.convert(p, to: parent)
            if let modified = current as? OmniModifierView { p = modified.shown(p) }
            current = parent
        }
        return p
    }

    static func toWindow(_ rect: NSRect, from view: NSView) -> NSRect {
        let a = toWindow(NSPoint(x: rect.minX, y: rect.minY), from: view)
        let b = toWindow(NSPoint(x: rect.maxX, y: rect.maxY), from: view)
        return NSRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(b.x - a.x), height: abs(b.y - a.y))
    }
    #endif

    /// In its window, origin top left.
    static func frame(of view: NativeView) -> ProbeRect {
        #if os(macOS)
        let rect = toWindow(view.bounds, from: view)
        #else
        let rect = view.convert(view.bounds, to: nil)
        #endif
        #if os(macOS)
        let height = view.window?.contentView?.bounds.height ?? rect.maxY
        return ProbeRect(x: rect.minX, y: height - rect.maxY, width: rect.width, height: rect.height)
        #else
        return ProbeRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height)
        #endif
    }

    static func isEnabled(_ view: NativeView) -> Bool {
        var current: NativeView? = view
        while let candidate = current {
            #if os(macOS)
            if let control = candidate as? NSControl, !control.isEnabled { return false }
            if let press = candidate as? OmniPressView, !press.isEnabled { return false }
            #else
            if let control = candidate as? UIControl, !control.isEnabled { return false }
            if !candidate.isUserInteractionEnabled, candidate === view || candidate is UIControl { return false }
            #endif
            current = candidate.superview
        }
        return true
    }

    static func isVisible(_ view: NativeView) -> Bool {
        guard view.window != nil, view.bounds.width > 0, view.bounds.height > 0 else { return false }
        var current: NativeView? = view
        while let candidate = current {
            #if os(macOS)
            if candidate.isHidden || candidate.alphaValue < 0.01 { return false }
            #else
            if candidate.isHidden || candidate.alpha < 0.01 { return false }
            #endif
            current = candidate.superview
        }
        return isOnScreen(view)
    }

    /// Its centre inside its window and inside every view that clips it.
    static func isOnScreen(_ view: NativeView) -> Bool {
        guard let window = view.window else { return false }
        #if os(macOS)
        let centre = toWindow(CGPoint(x: view.bounds.midX, y: view.bounds.midY), from: view)
        #else
        let centre = view.convert(CGPoint(x: view.bounds.midX, y: view.bounds.midY), to: nil)
        #endif
        #if os(macOS)
        guard let content = window.contentView, content.bounds.contains(content.convert(centre, from: nil)) else { return false }
        #else
        guard window.bounds.contains(centre) else { return false }
        #endif
        var current = view.superview
        while let clip = current {
            #if os(macOS)
            let clips = clip is NSClipView || clip.layer?.masksToBounds == true
            #else
            let clips = clip.clipsToBounds
            #endif
            if clips, !clip.bounds.contains(clip.convert(centre, from: nil)) { return false }
            current = clip.superview
        }
        return true
    }

    // MARK: What to act on

    /// What a tap on `view` operates: the view, the control around it, or the
    /// one control inside it.
    /// The view itself, else the one control inside it (an identifier on a
    /// button's wrapper), else the nearest control above it.
    static func actionable(for view: NativeView) -> NativeView? {
        if isActionable(view) { return view }
        let inside = descendants(of: view).filter(isActionable)
        if inside.count == 1 { return inside[0] }
        var current = view.superview
        while let candidate = current {
            if isActionable(candidate) { return candidate }
            current = candidate.superview
        }
        return nil
    }

    static func field(for view: NativeView) -> NativeView? {
        if isField(view) { return view }
        var current = view.superview
        while let candidate = current {
            if isField(candidate) { return candidate }
            current = candidate.superview
        }
        let inside = descendants(of: view).filter(isField)
        return inside.count == 1 ? inside[0] : nil
    }

    private static func isActionable(_ view: NativeView) -> Bool {
        #if os(macOS)
        if let field = view as? NSTextField { return field.isEditable }
        return view is OmniPressView || view is OmniTapView || view is NSControl
        #else
        return view is UIControl || view is OmniTapView || view is UITextView
        #endif
    }

    private static func isField(_ view: NativeView) -> Bool {
        #if os(macOS)
        return (view as? NSTextField)?.isEditable == true
        #else
        return view is UITextField || view is UITextView
        #endif
    }

    private static func descendants(of view: NativeView) -> [NativeView] {
        view.subviews.flatMap { [$0] + descendants(of: $0) }
    }

    static func scrollIntoView(_ view: NativeView) {
        #if os(macOS)
        view.scrollToVisible(view.bounds)
        #else
        var current = view.superview
        while let candidate = current {
            if let scroll = candidate as? UIScrollView {
                scroll.scrollRectToVisible(view.convert(view.bounds, to: scroll), animated: false)
                scroll.layoutIfNeeded()
            }
            current = candidate.superview
        }
        #endif
    }

    /// What a tap at the view's centre would reach instead of it, if anything.
    static func obstacle(over view: NativeView) -> String? {
        guard let window = view.window else { return "nothing: it is not in a window" }
        #if os(macOS)
        if let sheet = window.attachedSheet { return "a sheet (\(sheet.title))" }
        guard let content = window.contentView else { return nil }
        let point = content.superview?.convert(toWindow(NSPoint(x: view.bounds.midX, y: view.bounds.midY), from: view),
                                               from: nil) ?? .zero
        guard let hit = content.hitTest(point) else { return "nothing" }
        #else
        let point = view.convert(CGPoint(x: view.bounds.midX, y: view.bounds.midY), to: window)
        guard let hit = window.hitTest(point, with: nil) else { return "nothing" }
        #endif
        if hit === view || hit.isDescendant(of: view) { return nil }
        let reached = collect(from: hit).first?.element.description.trimmingCharacters(in: .whitespaces)
        return Interactions.path(of: hit) ?? reached ?? String(describing: Swift.type(of: hit))
    }

    static func isAnimating(_ root: NativeView) -> Bool {
        #if os(macOS)
        if root.layer?.animationKeys()?.isEmpty == false { return true }
        #else
        if root.layer.animationKeys()?.isEmpty == false { return true }
        #endif
        return root.subviews.contains(where: isAnimating)
    }

    // MARK: Acting

    /// What a person's touch or typing would do: the same actions and
    /// notifications, so the app's own handlers run.
    static func perform(_ action: Action, on view: NativeView) {
        switch action {
        case .tap:
            #if os(macOS)
            if let press = view as? OmniPressView {
                press.onPressChange?(true)
                press.onPressChange?(false)
                press.onAction?()
            } else if let tap = view as? OmniTapView {
                tap.onTap?()
            } else if let field = view as? NSTextField, field.isEditable {
                field.window?.makeFirstResponder(field)
            } else if let control = view as? NSControl {
                control.performClick(nil)
            }
            #else
            // Before UIControl: a styled button's press fires from its touches, not control actions.
            if let press = view as? OmniPressView {
                press.onPressChange?(true)
                press.onPressChange?(false)
                press.onAction?()
            } else if let tap = view as? OmniTapView {
                tap.onTap?()
            } else if let field = view as? UITextField {
                field.becomeFirstResponder()
            } else if let toggle = view as? UISwitch {
                toggle.setOn(!toggle.isOn, animated: false)
                toggle.sendActions(for: .valueChanged)
            } else if let control = view as? UIControl {
                control.sendActions(for: .touchDown)
                control.sendActions(for: .touchUpInside)
            }
            #endif
        case .type(let text, let replacing):
            #if os(macOS)
            guard let field = view as? NSTextField else { return }
            field.window?.makeFirstResponder(field)
            field.stringValue = replacing ? text : field.stringValue + text
            NotificationCenter.default.post(name: NSControl.textDidChangeNotification, object: field)
            #else
            if let field = view as? UITextField {
                field.becomeFirstResponder()
                field.text = replacing ? text : (field.text ?? "") + text
                field.sendActions(for: .editingChanged)
            } else if let textView = view as? UITextView {
                textView.becomeFirstResponder()
                textView.text = replacing ? text : textView.text + text
                textView.delegate?.textViewDidChange?(textView)
            }
            #endif
        }
    }
}
#endif
