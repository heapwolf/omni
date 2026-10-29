// src/lib/Modifiers.swift

import Foundation

#if os(macOS) || os(iOS)
    import ObjectiveC
#elseif os(Android)
    import CAndroid
#endif

#if os(iOS)
    import UIKit
#endif


#if os(macOS)
    import AppKit
    public class OmniModifierView: NSView {
        nonisolated public override var isFlipped: Bool { true }

        public var customOpacity: Double?
        public var customScale: Double?
        public var customOffsetX: Double?
        public var customOffsetY: Double?
        public var customZIndex: Double?
        public var customBackgroundColor: Color?
        public var customForegroundColor: Color?
        public var customBorderColor: Color?
        public var customBorderWidth: Double?
        /// .disabled(): clicks pass through to what is behind, as UIKit's
        /// isUserInteractionEnabled does. AppKit only greys its controls, and
        /// an empty full-screen cover, disabled, still took every click.
        public var isClickThrough = false

        public override var wantsUpdateLayer: Bool { true }

        public override func layout() {
            super.layout()
            self.needsDisplay = true
        }

        public override func updateLayer() {
            super.updateLayer()

            if let bg = customBackgroundColor {
                self.layer?.backgroundColor = bg.nsColor.cgColor
            }

            if let opacity = customOpacity {
                self.alphaValue = opacity
            }

            if let fg = customForegroundColor {
                applyForegroundColor(fg, to: self)
            }

            guard let layer = self.layer else { return }

            if let width = customBorderWidth {
                layer.borderWidth = CGFloat(width)
                layer.borderColor = (customBorderColor ?? .clear).nsColor.cgColor
            }

            if let z = customZIndex {
                layer.zPosition = CGFloat(z)
            }

            var transform = CATransform3DIdentity

            if let ox = customOffsetX, let oy = customOffsetY {
                transform = CATransform3DTranslate(transform, ox, oy, 0)
            }

            if let scale = customScale {
                let b = self.bounds
                if b.width > 0 && b.height > 0 {
                    let dx = (b.width / 2.0) * (1.0 - scale)
                    let dy = (b.height / 2.0) * (1.0 - scale)
                    transform = CATransform3DTranslate(transform, dx, dy, 0)
                }
                transform = CATransform3DScale(transform, scale, scale, 1)
            }

            layer.transform = transform
        }

        /// `point`, in the superview's coordinates, where the transform above
        /// draws it: scaled about the frame's centre, then offset.
        public func shown(_ point: NSPoint) -> NSPoint {
            var p = point
            if let scale = customScale {
                p.x = frame.midX + (p.x - frame.midX) * scale
                p.y = frame.midY + (p.y - frame.midY) * scale
            }
            let down: CGFloat = superview?.isFlipped ?? true ? 1 : -1
            p.x += customOffsetX ?? 0
            p.y += (customOffsetY ?? 0) * down
            return p
        }

        /// The layer's transform moves what is drawn, not where AppKit looks
        /// for a click. Undone here, a click reaches the view where it shows:
        /// a carousel's cards, each offset across one full-width row, took
        /// each other's clicks. UIKit hit-tests through a transform itself.
        public override func hitTest(_ point: NSPoint) -> NSView? {
            if isClickThrough { return nil }
            guard customOffsetX != nil || customScale != nil else { return super.hitTest(point) }
            var p = point
            let down: CGFloat = superview?.isFlipped ?? true ? 1 : -1
            p.x -= customOffsetX ?? 0
            p.y -= (customOffsetY ?? 0) * down
            if let scale = customScale, scale > 0 {
                p.x = frame.midX + (p.x - frame.midX) / scale
                p.y = frame.midY + (p.y - frame.midY) / scale
            }
            return super.hitTest(p)
        }

        private func applyForegroundColor(_ color: Color, to view: NSView) {
            if let label = view as? NSTextField {
                label.textColor = color.nsColor
            }
            if let imageView = view as? NSImageView {
                imageView.contentTintColor = color.nsColor
            }
            if let button = view as? NSButton {
                button.contentTintColor = color.nsColor
            }
            for subview in view.subviews {
                applyForegroundColor(color, to: subview)
            }
        }
    }

    class OmniShadowView: NSView {
        init() {
            super.init(frame: .zero)
            self.wantsLayer = true // Required for NSShadow to render properly on NSView
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        // Optional, but standard for custom AppKit views mapped from SwiftUI
        nonisolated override var isFlipped: Bool { true }
    }
#endif

public struct ModifierView: NativeComponent {
    public var content: any View

    public var opacity: Double?
    public var scale: Double?
    public var offsetX: Double?
    public var offsetY: Double?
    public var zIndex: Double?
    public var backgroundColor: Color?
    public var foregroundColor: Color?
    public var width: Double?
    public var height: Double?
    /// Only .infinity is meaningful: it takes the surplus along that axis. A
    /// finite value is an upper bound on Apple and ignored elsewhere.
    public var maxWidth: Double?
    public var maxHeight: Double?
    /// At least this big; the content can make it bigger.
    public var minWidth: Double?
    public var minHeight: Double?
    public var borderColor: Color?
    public var borderWidth: Double?
    public var padding: EdgeInsets?
    /// nil means inherit — only an explicit .disabled() writes it.
    public var disabled: Bool?
    /// nil means fill, which is what every modifier but .frame wants: a
    /// .padding() or .background() must not reposition what it wraps.
    public var alignment: Alignment?

    public var children: [any View] { [content] }

    public init(
        content: any View,
        opacity: Double? = nil,
        scale: Double? = nil,
        offsetX: Double? = nil,
        offsetY: Double? = nil,
        zIndex: Double? = nil,
        backgroundColor: Color? = nil,
        foregroundColor: Color? = nil,
        width: Double? = nil,
        height: Double? = nil,
        maxWidth: Double? = nil,
        maxHeight: Double? = nil,
        minWidth: Double? = nil,
        minHeight: Double? = nil,
        borderColor: Color? = nil,
        borderWidth: Double? = nil,
        padding: EdgeInsets? = nil,
        alignment: Alignment? = nil,
        disabled: Bool? = nil
    ) {
        self.content = content
        self.opacity = opacity
        self.scale = scale
        self.offsetX = offsetX
        self.offsetY = offsetY
        self.zIndex = zIndex
        self.backgroundColor = backgroundColor
        self.foregroundColor = foregroundColor
        self.width = width
        self.height = height
        self.maxWidth = maxWidth
        self.maxHeight = maxHeight
        self.minWidth = minWidth
        self.minHeight = minHeight
        self.borderColor = borderColor
        self.borderWidth = borderWidth
        self.padding = padding
        self.alignment = alignment
        self.disabled = disabled
    }

    #if os(Linux)
    var cssDeclarations: [String] {
        var css: [String] = []
        if let backgroundColor { css.append("background-color: \(backgroundColor.css);") }
        if let foregroundColor { css.append("color: \(foregroundColor.css);") }
        if let opacity { css.append("opacity: \(opacity);") }
        if let borderWidth {
            css.append("border: \(borderWidth)px solid \((borderColor ?? .clear).css);")
        }
        return css
    }
    #endif

    /// 1 is the priority a Spacer carries, and the stacks already read it as a
    /// claim on the surplus.
    var fillsWidth: Bool { maxWidth?.isInfinite == true }
    var fillsHeight: Bool { maxHeight?.isInfinite == true }

    @MainActor public func makeNative() -> NativeView {
        #if os(Linux)
            return gtk_box_new(0, 0)
        #elseif os(macOS)
            let v = OmniModifierView()
            v.wantsLayer = true
            v.translatesAutoresizingMaskIntoConstraints = false
            return v
        #elseif os(iOS)
            let v = UIView()
            v.translatesAutoresizingMaskIntoConstraints = false
            return v
        #elseif os(Android)
            return OmniAndroid.makeContainer()
        #else
        #error("no implementation for this platform")
        #endif
    }

    @MainActor public func updateNative(_ view: NativeView) {
        #if os(macOS)
            if let v = view as? OmniModifierView {
                v.customOpacity = opacity
                v.customScale = scale
                v.customOffsetX = offsetX
                v.customOffsetY = offsetY
                v.customZIndex = zIndex
                v.customBackgroundColor = backgroundColor
                v.customForegroundColor = foregroundColor
                v.customBorderColor = borderColor
                v.customBorderWidth = borderWidth
                if let disabled {
                    Self.applyEnabled(!disabled, to: v)
                    v.isClickThrough = disabled
                }
                v.needsDisplay = true

                if Transaction.currentAnimation != nil {
                    v.updateLayer()
                }
            }
        #elseif os(iOS)
            if let opacity = opacity { view.alpha = opacity }
            if let bg = backgroundColor { view.backgroundColor = bg.uiColor }
            if let fg = foregroundColor { applyForegroundColor(fg, to: view) }
            if let disabled { Self.applyEnabled(!disabled, to: view) }
            if let zIndex = zIndex { view.layer.zPosition = CGFloat(zIndex) }
            if let borderWidth {
                view.layer.borderWidth = CGFloat(borderWidth)
                view.layer.borderColor = (borderColor ?? .clear).uiColor.cgColor
            }
            var transform = CGAffineTransform.identity
            if let offsetX = offsetX, let offsetY = offsetY { transform = transform.translatedBy(x: offsetX, y: offsetY) }
            if let scale = scale { transform = transform.scaledBy(x: scale, y: scale) }
            view.transform = transform
        #endif

        #if os(Linux)
            // GTK Layout & Padding implementation
            // GTK's size request is a minimum: a fixed size, else .frame(min...:).
            let w = (width ?? minWidth).map { Int32($0) } ?? -1
            let h = (height ?? minHeight).map { Int32($0) } ?? -1
            gtk_widget_set_size_request(view, w, h)

            // A fixed dimension is a promise not to grow along it; the explicit flag also
            // stops the content's expand propagating past here.
            gtk_widget_set_hexpand(view, fillsWidth ? 1 : 0)
            gtk_widget_set_vexpand(view, fillsHeight ? 1 : 0)
            gtk_widget_set_hexpand_set(view, (width == nil && !fillsWidth) ? 0 : 1)
            gtk_widget_set_vexpand_set(view, (height == nil && !fillsHeight) ? 0 : 1)

            applyCSS(cssDeclarations, to: view)

            if let disabled { gtk_widget_set_sensitive(view, disabled ? 0 : 1) }

            if let p = padding {
                let gtk_widget_set_margin_top: @convention(c) (NativeView, Int32) -> Void = fn(libgtk, "gtk_widget_set_margin_top")
                let gtk_widget_set_margin_bottom: @convention(c) (NativeView, Int32) -> Void = fn(libgtk, "gtk_widget_set_margin_bottom")
                let gtk_widget_set_margin_start: @convention(c) (NativeView, Int32) -> Void = fn(libgtk, "gtk_widget_set_margin_start")
                let gtk_widget_set_margin_end: @convention(c) (NativeView, Int32) -> Void = fn(libgtk, "gtk_widget_set_margin_end")

                gtk_widget_set_margin_top(view, Int32(p.top))
                gtk_widget_set_margin_bottom(view, Int32(p.bottom))
                gtk_widget_set_margin_start(view, Int32(p.leading))
                gtk_widget_set_margin_end(view, Int32(p.trailing))
            }
        #elseif os(macOS) || os(iOS)
            let oldConstraints = view.constraints.filter {
                $0.identifier == "Mod-Width" || $0.identifier == "Mod-Height"
            }
            NSLayoutConstraint.deactivate(oldConstraints)

            if let w = width {
                let widthAnchor = view.widthAnchor.constraint(equalToConstant: CGFloat(w))
                widthAnchor.identifier = "Mod-Width"
                widthAnchor.isActive = true
            }
            if let h = height {
                let heightAnchor = view.heightAnchor.constraint(equalToConstant: CGFloat(h))
                heightAnchor.identifier = "Mod-Height"
                heightAnchor.isActive = true
            }
            if let maxWidth, maxWidth.isFinite {
                let c = view.widthAnchor.constraint(lessThanOrEqualToConstant: CGFloat(maxWidth))
                c.identifier = "Mod-Width"
                c.isActive = true
            }
            if let maxHeight, maxHeight.isFinite {
                let c = view.heightAnchor.constraint(lessThanOrEqualToConstant: CGFloat(maxHeight))
                c.identifier = "Mod-Height"
                c.isActive = true
            }
            if let minWidth {
                let c = view.widthAnchor.constraint(greaterThanOrEqualToConstant: CGFloat(minWidth))
                c.identifier = "Mod-Width"
                c.isActive = true
            }
            if let minHeight {
                let c = view.heightAnchor.constraint(greaterThanOrEqualToConstant: CGFloat(minHeight))
                c.identifier = "Mod-Height"
                c.isActive = true
            }
            let claim = NativeLayoutPriority(rawValue: 1)
            if fillsWidth { view.setContentHuggingPriority(claim, for: .horizontal) }
            if fillsHeight { view.setContentHuggingPriority(claim, for: .vertical) }

            // The child's place is insertChild's, made once: a kept child, its
            // padding or frame changed since, stayed where it was. A screen
            // padded below the status bar only once it covered the tab bar
            // drew its header under it. Placed again, as it would be anew.
            if view.subviews.count == 1, let child = view.subviews.first,
               let placed = objc_getAssociatedObject(view, &placementKey) as? String, placed != placement {
                child.removeFromSuperview()
                insertChild(child, into: view)
            }
        #elseif os(Android)
            let env = OmniAndroid.getEnv()

            if let opacity { omni_jni_set_alpha(env, view, Float(opacity)) }
            // Put back once unset, as an animation's or transition's last frame leaves it.
            if offsetX != nil || offsetY != nil || scale != nil {
                omni_jni_set_transform(env, view, Float(offsetX ?? 0), Float(offsetY ?? 0), Float(scale ?? 1))
                Self.transformed.insert(view)
            } else if Self.transformed.remove(view) != nil {
                omni_jni_set_transform(env, view, 0, 0, 1)
            }
            // A re-render: the children exist. On the first, insertChild tints them.
            if let foregroundColor { tintSymbols(foregroundColor, in: view) }
            if let borderWidth {
                // A stroke needs a drawable, so the fill goes into the same one.
                let fill = (backgroundColor ?? .clear).rgbaComponents
                let stroke = (borderColor ?? .clear).rgbaComponents
                omni_jni_set_box(env, view,
                    backgroundColor == nil ? 0 : 1,
                    Int32(fill.a * 255), Int32(fill.r * 255), Int32(fill.g * 255), Int32(fill.b * 255),
                    Int32(borderWidth),
                    Int32(stroke.a * 255), Int32(stroke.r * 255), Int32(stroke.g * 255), Int32(stroke.b * 255))
            } else if let backgroundColor {
                let c = backgroundColor.rgbaComponents
                omni_jni_set_background_color(env, view,
                    Int32(c.a * 255), Int32(c.r * 255), Int32(c.g * 255), Int32(c.b * 255))
            }
            if let p = padding {
                omni_jni_set_padding(env, view,
                    Int32(p.leading), Int32(p.top), Int32(p.trailing), Int32(p.bottom))
            }
            if let disabled {
                omni_jni_call_void_method_bool(env, view, "setEnabled", disabled ? 0 : 1)
            }

            // An unset axis is left as the parent generated it: forcing WRAP_CONTENT
            // collapses a wrapper whose content has no intrinsic size.
            omni_jni_set_layout_params(
                env, view,
                width.map { Int32($0) } ?? Int32(fillsWidth ? MATCH_PARENT : OMNI_LAYOUT_KEEP),
                height.map { Int32($0) } ?? Int32(fillsHeight ? MATCH_PARENT : OMNI_LAYOUT_KEEP))

            if minWidth != nil || minHeight != nil {
                omni_jni_set_minimum_size(env, view, Float(minWidth ?? 0), Float(minHeight ?? 0))
            }

            // A fixed dimension is a promise not to grow along it.
            AndroidExpansion.pin(view, width: width != nil, height: height != nil)

            // Additive: a claim carried up from a child must survive.
            if fillsWidth || fillsHeight {
                AndroidExpansion.claim(
                    view,
                    horizontal: fillsWidth || AndroidExpansion.wants(view, horizontal: true),
                    vertical: fillsHeight || AndroidExpansion.wants(view, horizontal: false))
            }
        #else
        #error("no implementation for this platform")
        #endif
    }

    #if os(Android)
        /// Views moved or scaled by a ModifierView, to put back when it stops.
        @MainActor static var transformed: Set<NativeView> = []

        /// Text takes its color itself; a symbol image takes it from here.
        @MainActor private func tintSymbols(_ color: Color, in view: NativeView) {
            let c = color.rgbaComponents
            omni_jni_tint_symbols(OmniAndroid.getEnv(), view,
                Int32(c.a * 255), Int32(c.r * 255), Int32(c.g * 255), Int32(c.b * 255))
        }
    #endif

    #if os(macOS)
        /// .disabled() covers a subtree, and only the controls inside it can
        /// actually take a disabled state.
        @MainActor static func applyEnabled(_ enabled: Bool, to view: NSView) {
            if let control = view as? NSControl { control.isEnabled = enabled }
            // A styled Button's press is a view, not an NSControl.
            if let press = view as? OmniPressView { press.isEnabled = enabled }
            for subview in view.subviews { applyEnabled(enabled, to: subview) }
        }
    #elseif os(iOS)
        @MainActor static func applyEnabled(_ enabled: Bool, to view: UIView) {
            if let control = view as? UIControl { control.isEnabled = enabled }
            view.isUserInteractionEnabled = enabled
            for subview in view.subviews { applyEnabled(enabled, to: subview) }
        }
    #endif

    #if os(iOS)
        private func applyForegroundColor(_ color: Color, to view: UIView) {
            if let label = view as? UILabel { label.textColor = color.uiColor }
            if let imageView = view as? UIImageView { imageView.tintColor = color.uiColor }
            // A ProgressView's spinner, as SwiftUI tints it.
            if let spinner = view as? UIActivityIndicatorView { spinner.color = color.uiColor }
            // A TextEditor's text.
            if let textView = view as? UITextView { textView.textColor = color.uiColor }
            if let button = view as? UIButton {
                button.tintColor = color.uiColor
                button.setTitleColor(color.uiColor, for: .normal)
                button.setTitleColor(color.uiColor, for: .highlighted)
            }
            for subview in view.subviews { applyForegroundColor(color, to: subview) }
        }
    #endif

    @MainActor public func insertChild(_ child: NativeView, into parent: NativeView) {
        #if os(Linux)
            packFill(child, into: parent)
            if let alignment {
                gtk_widget_set_halign(child, width == nil && minWidth == nil ? GtkAlign.fill : alignment.horizontal.gtkAlign)
                gtk_widget_set_valign(child, height == nil && minHeight == nil ? GtkAlign.fill : alignment.vertical.gtkAlign)
            }
        #elseif os(macOS) || os(iOS)
            parent.addSubview(child)
            #if os(iOS)
            // updateNative ran before this child existed, so a first render
            // left it untinted. macOS re-applies in layout instead.
            if let foregroundColor { applyForegroundColor(foregroundColor, to: child) }
            #endif
            // Likewise .disabled: the child's subtree is whole by now, and a
            // first render left every control in it enabled.
            if let disabled { Self.applyEnabled(!disabled, to: child) }
            objc_setAssociatedObject(parent, &placementKey, placement, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)

            // Native Apple Padding mapping
            let pt = padding?.top ?? 0
            let pb = padding?.bottom ?? 0
            let pl = padding?.leading ?? 0
            let pr = padding?.trailing ?? 0

            if let alignment {
                var constraints: [NSLayoutConstraint] = [
                    child.topAnchor.constraint(greaterThanOrEqualTo: parent.topAnchor, constant: CGFloat(pt)),
                    child.leadingAnchor.constraint(greaterThanOrEqualTo: parent.leadingAnchor, constant: CGFloat(pl)),
                    parent.bottomAnchor.constraint(greaterThanOrEqualTo: child.bottomAnchor, constant: CGFloat(pb)),
                    parent.trailingAnchor.constraint(greaterThanOrEqualTo: child.trailingAnchor, constant: CGFloat(pr))
                ]
                // On a fixed axis, a child of a fixed size larger still overflows,
                // as in SwiftUI, for a .clipped() to trim: one short of required.
                // Required, it squashed the child instead (a tab bar drawn 28
                // taller to clip off its bottom corners kept all four). Text and
                // anything flexible still fit inside: their sizes are not required.
                if width != nil { constraints[1].priority = .init(rawValue: 999); constraints[3].priority = .init(rawValue: 999) }
                if height != nil { constraints[0].priority = .init(rawValue: 999); constraints[2].priority = .init(rawValue: 999) }

                switch alignment.horizontal {
                case .leading:
                    constraints.append(child.leadingAnchor.constraint(equalTo: parent.leadingAnchor, constant: CGFloat(pl)))
                case .center:
                    constraints.append(child.centerXAnchor.constraint(equalTo: parent.centerXAnchor))
                case .trailing:
                    constraints.append(child.trailingAnchor.constraint(equalTo: parent.trailingAnchor, constant: CGFloat(-pr)))
                }

                switch alignment.vertical {
                case .top:
                    constraints.append(child.topAnchor.constraint(equalTo: parent.topAnchor, constant: CGFloat(pt)))
                case .center:
                    constraints.append(child.centerYAnchor.constraint(equalTo: parent.centerYAnchor))
                case .bottom:
                    constraints.append(child.bottomAnchor.constraint(equalTo: parent.bottomAnchor, constant: CGFloat(-pb)))
                }

                // Only the pinned axis is the frame's to place; the other stays
                // the child's to fill. And even on a pinned axis, a child that
                // claims fill (hugging<=1 — a ZStack/HStack/VStack whose own
                // content wants the room) still stretches to it, or
                // `ZStack{ Circle().fill(_:) }.frame(width:40,height:40)`
                // centers the circle at its unfilled natural size instead of
                // the 40x40 box.
                // On a flexible axis (maxWidth/maxHeight .infinity) the fill is
                // the child's to take, not the frame's to be sized by: above
                // content hugging (250), so a child that can stretch does, and
                // below everything that sizes the frame from outside: a
                // sidebar's width (260), the window's (490, contentHost). At 900
                // a fixed-size child dragged the frame down to it; at 700 a
                // capped one (.frame(maxWidth: 680) inside) still did, and the
                // page, the sidebar and once the window shrank to fit it.
                // A minimum places the child on its axis too, at its own size and
                // aligned, as SwiftUI does: a pill's label centred in its 54pt.
                // Text is the exception: SwiftUI places it in a flexible frame at
                // its own size, aligned, and never stretches it. Stretched, a
                // label draws at its leading edge, so a segmented control's
                // halves read left-aligned. Below its hugging (250), it keeps
                // its width and the alignment above places it.
                let isText = Self.isText(child)
                if (width == nil && minWidth == nil) || child.contentHuggingPriority(for: .horizontal).rawValue <= 1 {
                    let fill = child.widthAnchor.constraint(equalTo: parent.widthAnchor, constant: CGFloat(-(pl + pr)))
                    fill.priority = .init(rawValue: fillsWidth ? (isText ? 249 : 255) : 900)
                    constraints.append(fill)
                }
                if (height == nil && minHeight == nil) || child.contentHuggingPriority(for: .vertical).rawValue <= 1 {
                    let fill = child.heightAnchor.constraint(equalTo: parent.heightAnchor, constant: CGFloat(-(pt + pb)))
                    fill.priority = .init(rawValue: fillsHeight ? (isText ? 249 : 255) : 900)
                    constraints.append(fill)
                }
                // A minimum with nothing above it is the child's size, raised to
                // the minimum, not a claim on a stack's surplus: hug the child,
                // short of required, so the minimum wins and a Spacer still does.
                if minWidth != nil, width == nil, !fillsWidth {
                    let hug = parent.widthAnchor.constraint(equalTo: child.widthAnchor, constant: CGFloat(pl + pr))
                    hug.priority = .defaultHigh
                    constraints.append(hug)
                }
                if minHeight != nil, height == nil, !fillsHeight {
                    let hug = parent.heightAnchor.constraint(equalTo: child.heightAnchor, constant: CGFloat(pt + pb))
                    hug.priority = .defaultHigh
                    constraints.append(hug)
                }

                NSLayoutConstraint.activate(constraints)
            } else {
                NSLayoutConstraint.activate([
                    child.topAnchor.constraint(equalTo: parent.topAnchor, constant: CGFloat(pt)),
                    child.bottomAnchor.constraint(equalTo: parent.bottomAnchor, constant: CGFloat(-pb)),
                    child.leadingAnchor.constraint(equalTo: parent.leadingAnchor, constant: CGFloat(pl)),
                    child.trailingAnchor.constraint(equalTo: parent.trailingAnchor, constant: CGFloat(-pr))
                ])
            }

            if width == nil {
                let childH = child.contentHuggingPriority(for: .horizontal)
                if childH.rawValue < parent.contentHuggingPriority(for: .horizontal).rawValue {
                    parent.setContentHuggingPriority(childH, for: .horizontal)
                }
            }
            if height == nil {
                let childV = child.contentHuggingPriority(for: .vertical)
                if childV.rawValue < parent.contentHuggingPriority(for: .vertical).rawValue {
                    parent.setContentHuggingPriority(childV, for: .vertical)
                }
            }
        #elseif os(Android)
            // Padding is set on the container in updateNative, which already
            // insets the child on Android.
            OmniAndroid.addChild(child, to: parent)
            // A frame centers what doesn't fill it, as in SwiftUI. Apple gets
            // this from the child stretching; a wrapped Android child sits
            // top-left without a gravity.
            if let resolved = alignment ?? (fillsWidth || fillsHeight ? .center : nil) {
                omni_jni_set_child_gravity(OmniAndroid.getEnv(), child, resolved.androidGravity)
            }
            if let foregroundColor { tintSymbols(foregroundColor, in: child) }
        #else
        #error("no implementation for this platform")
        #endif
    }
}

#if os(macOS) || os(iOS)
@MainActor private var placementKey: UInt8 = 0

extension ModifierView {
    /// What insertChild placed the child by: its constraints read these, and
    /// only whether a size is set, the size itself being updateNative's.
    var placement: String {
        let p = padding ?? EdgeInsets()
        return "\(p.top),\(p.leading),\(p.bottom),\(p.trailing)|\(String(describing: alignment))|"
            + "\(width != nil)\(height != nil)\(minWidth != nil)\(minHeight != nil)\(fillsWidth)\(fillsHeight)"
    }

    /// A label, or one inside wrappers that each hold only it and so take its
    /// size: a .foregroundColor or .padding around a Text. A stack ends it.
    @MainActor static func isText(_ view: NativeView) -> Bool {
        var current: NativeView? = view
        while let candidate = current {
            #if os(iOS)
            if candidate is UILabel { return true }
            if candidate is UIStackView { return false }
            #else
            if let field = candidate as? NSTextField { return !field.isEditable }
            if candidate is NSStackView { return false }
            #endif
            guard candidate.subviews.count == 1 else { return false }
            current = candidate.subviews[0]
        }
        return false
    }
}
#endif

public struct EdgeInsets: Equatable {
    public var top: Double
    public var leading: Double
    public var bottom: Double
    public var trailing: Double

    public init(top: Double = 0, leading: Double = 0, bottom: Double = 0, trailing: Double = 0) {
        self.top = top; self.leading = leading; self.bottom = bottom; self.trailing = trailing
    }
}

// MARK: - Modifier Protocols

@MainActor
public protocol ViewModifier {
    associatedtype Body: View
    // Allows the modifier to bypass proxy unwrapping and directly mount its content
    typealias Content = any View

    @ViewBuilder func body(content: Content) -> Body
}

public struct ModifiedContent<Content: View, Modifier: ViewModifier>: View {
    public var content: Content
    public var modifier: Modifier

    public init(content: Content, modifier: Modifier) {
        self.content = content
        self.modifier = modifier
    }

    public var type: String { "ModifiedContent<\(content.type), \(String(describing: Modifier.self))>" }

    public var body: some View {
        modifier.body(content: content)
    }
}

public extension View {
    func modifier<M: ViewModifier>(_ modifier: M) -> ModifiedContent<Self, M> {
        ModifiedContent(content: self, modifier: modifier)
    }
}

// MARK: - Built-in Modifiers

public struct FrameModifier: ViewModifier {
    public var width: Double?
    public var height: Double?
    public var maxWidth: Double?
    public var maxHeight: Double?
    public var minWidth: Double? = nil
    public var minHeight: Double? = nil
    public var alignment: Alignment
    public func body(content: Content) -> some View {
        // Alignment only means something once an axis is pinned or flexible.
        // A .frame(maxWidth: .infinity) is a box the child is placed in, as in
        // SwiftUI: a child that can stretch still fills it (the 900 fill in
        // insertChild), and one with a fixed size is centred. Pinned edge to
        // edge instead, a fixed-size child held the whole frame to its width:
        // a keypad's delete key, a 26pt icon, came out a 26pt column.
        let pins = width != nil || height != nil || maxWidth != nil || maxHeight != nil
            || minWidth != nil || minHeight != nil
        return ModifierView(content: content, width: width, height: height,
                            maxWidth: maxWidth, maxHeight: maxHeight,
                            minWidth: minWidth, minHeight: minHeight,
                            alignment: pins ? alignment : nil)
    }
}

public struct BorderModifier: ViewModifier {
    public var color: Color
    public var width: Double
    public func body(content: Content) -> some View {
        ModifierView(content: content, borderColor: color, borderWidth: width)
    }
}

public struct BackgroundModifier: ViewModifier {
    public var color: Color
    public func body(content: Content) -> some View { ModifierView(content: content, backgroundColor: color) }
}

public struct DisabledModifier: ViewModifier {
    public var disabled: Bool
    public func body(content: Content) -> some View { ModifierView(content: content, disabled: disabled) }
}

public struct OpacityModifier: ViewModifier {
    public var opacity: Double
    public func body(content: Content) -> some View { ModifierView(content: content, opacity: opacity) }
}

public struct OffsetModifier: ViewModifier {
    public var x: Double
    public var y: Double
    public func body(content: Content) -> some View { ModifierView(content: content, offsetX: x, offsetY: y) }
}

public struct ScaleEffectModifier: ViewModifier {
    public var scale: Double
    public func body(content: Content) -> some View { ModifierView(content: content, scale: scale) }
}

public struct ZIndexModifier: ViewModifier {
    public var zIndex: Double
    public func body(content: Content) -> some View { ModifierView(content: content, zIndex: zIndex) }
}

public struct ForegroundColorModifier: ViewModifier {
    public var color: Color
    public func body(content: Content) -> some View { ModifierView(content: content, foregroundColor: color) }
}

// MARK: - View Extensions

public extension View {
    /// A fixed size, or SwiftUI's flexible frame: at least `min...`, at most
    /// `max...` (`.infinity` takes the surplus), in SwiftUI's argument order.
    func frame(width: Double? = nil, height: Double? = nil,
               minWidth: Double? = nil, maxWidth: Double? = nil,
               minHeight: Double? = nil, maxHeight: Double? = nil,
               alignment: Alignment = .center)
    -> ModifiedContent<Self, FrameModifier> {
        self.modifier(FrameModifier(width: width, height: height,
                                    maxWidth: maxWidth, maxHeight: maxHeight,
                                    minWidth: minWidth, minHeight: minHeight,
                                    alignment: alignment))
    }

    func border(_ color: Color, width: Double = 1) -> ModifiedContent<Self, BorderModifier> {
        self.modifier(BorderModifier(color: color, width: width))
    }

    func background(_ color: Color) -> ModifiedContent<Self, BackgroundModifier> {
        self.modifier(BackgroundModifier(color: color))
    }

    func disabled(_ isDisabled: Bool = true) -> ModifiedContent<Self, DisabledModifier> {
        self.modifier(DisabledModifier(disabled: isDisabled))
    }

    func opacity(_ value: Double) -> ModifiedContent<Self, OpacityModifier> {
        self.modifier(OpacityModifier(opacity: value))
    }

    func offset(x: Double = 0, y: Double = 0) -> ModifiedContent<Self, OffsetModifier> {
        self.modifier(OffsetModifier(x: x, y: y))
    }

    func scaleEffect(_ value: Double) -> ModifiedContent<Self, ScaleEffectModifier> {
        self.modifier(ScaleEffectModifier(scale: value))
    }

    func zIndex(_ value: Double) -> ModifiedContent<Self, ZIndexModifier> {
        self.modifier(ZIndexModifier(zIndex: value))
    }

    func foregroundColor(_ color: Color) -> ModifiedContent<Self, ForegroundColorModifier> {
        self.modifier(ForegroundColorModifier(color: color))
    }
}

// MARK: - Lifecycle & State Tracking

public class AppearanceState {
    public var hasAppeared = false
    public var onDisappear: (() -> Void)?

    deinit {
        onDisappear?()
    }
}

public class ChangeState<V: Equatable> {
    public var isInitialized = false
    public var lastValue: V?
}

#if os(macOS) || os(iOS)
    nonisolated(unsafe) private var appearanceKey: UInt8 = 0
    nonisolated(unsafe) private var changeKey: UInt8 = 0
#endif

// MARK: - Deferral

/// Runs `action` on the next turn of the platform's own loop. gtk_main() never
/// drains libdispatch's main queue; every other backend pumps it.
@MainActor func deferToMainLoop(_ action: @escaping () -> Void) {
    // The hop is main-to-main, so the closure never leaves the actor.
    final class Deferred: @unchecked Sendable {
        let action: () -> Void
        init(_ action: @escaping () -> Void) { self.action = action }
    }
    let deferred = Deferred(action)

    #if os(Linux)
    let box = Unmanaged.passRetained(deferred).toOpaque()
    g_idle_add({ pointer in
        guard let pointer else { return 0 }
        let deferred = Unmanaged<Deferred>.fromOpaque(pointer).takeRetainedValue()
        MainActor.assumeIsolated { deferred.action() }
        return 0 // G_SOURCE_REMOVE — a one-shot
    }, box)
    #else
    DispatchQueue.main.async { MainActor.assumeIsolated { deferred.action() } }
    #endif
}

// MARK: Native Components for Lifecycle

public struct AppearanceModifierView: NativeComponent {
    public var content: any View
    public var onAppear: (() -> Void)?
    public var onDisappear: (() -> Void)?

    public var children: [any View] { [content] }

    public init(content: any View, onAppear: (() -> Void)? = nil, onDisappear: (() -> Void)? = nil) {
        self.content = content
        self.onAppear = onAppear
        self.onDisappear = onDisappear
    }

    @MainActor public func makeNative() -> NativeView {
        #if os(Linux)
            let v = gtk_box_new(0, 0)
            let state = AppearanceState()
            let ptr = Unmanaged.passRetained(state).toOpaque()
            g_object_set_data_full(v, "appearance_state", ptr) { pPtr in
                if let p = pPtr { Unmanaged<AppearanceState>.fromOpaque(p).release() }
            }
            return v
        #elseif os(macOS)
            let v = OmniModifierView()
            v.wantsLayer = true
            v.translatesAutoresizingMaskIntoConstraints = false
            objc_setAssociatedObject(v, &appearanceKey, AppearanceState(), .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            return v
        #elseif os(iOS)
            let v = UIView()
            v.translatesAutoresizingMaskIntoConstraints = false
            objc_setAssociatedObject(v, &appearanceKey, AppearanceState(), .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            return v
        #elseif os(Android)
            let v = OmniAndroid.makeContainer()
            AndroidModifierState.set(AppearanceState(), for: v)
            return v
        #else
        #error("no implementation for this platform")
        #endif
    }

    @MainActor public func updateNative(_ view: NativeView) {
        #if os(Linux)
            let ptr = g_object_get_data(view, "appearance_state")
            let state = Unmanaged<AppearanceState>.fromOpaque(ptr!).takeUnretainedValue()
        #elseif os(macOS) || os(iOS)
            guard let state = objc_getAssociatedObject(view, &appearanceKey) as? AppearanceState else { return }
        #elseif os(Android)
            let state = AndroidModifierState.ensure(for: view) { AppearanceState() }
        #else
        #error("no implementation for this platform")
        #endif

        state.onDisappear = onDisappear

        if !state.hasAppeared {
            state.hasAppeared = true
            if let action = onAppear {
                deferToMainLoop(action)
            }
        }
    }

    @MainActor public func insertChild(_ child: NativeView, into parent: NativeView) {
        #if os(Linux)
            packFill(child, into: parent)
        #elseif os(macOS) || os(iOS)
            parent.addSubview(child)
            adoptSizing(of: child, into: parent)
            NSLayoutConstraint.activate([
                child.topAnchor.constraint(equalTo: parent.topAnchor),
                child.bottomAnchor.constraint(equalTo: parent.bottomAnchor),
                child.leadingAnchor.constraint(equalTo: parent.leadingAnchor),
                child.trailingAnchor.constraint(equalTo: parent.trailingAnchor)
            ])
        #elseif os(Android)
            OmniAndroid.addChild(child, to: parent)
        #else
        #error("no implementation for this platform")
        #endif
    }
}

public struct ChangeModifierView<V: Equatable>: NativeComponent {
    public var content: any View
    public var value: V
    /// The value before the change, and after it.
    public var change: (V, V) -> Void

    public var children: [any View] { [content] }

    public init(content: any View, value: V, action: @escaping (V) -> Void) {
        self.init(content: content, value: value, change: { _, new in action(new) })
    }

    public init(content: any View, value: V, change: @escaping (V, V) -> Void) {
        self.content = content
        self.value = value
        self.change = change
    }

    public func makeNative() -> NativeView {
        #if os(Linux)
            let v = gtk_box_new(0, 0)
            let state = ChangeState<V>()
            let ptr = Unmanaged.passRetained(state).toOpaque()
            g_object_set_data_full(v, "change_state", ptr) { pPtr in
                if let p = pPtr { Unmanaged<AnyObject>.fromOpaque(p).release() }
            }
            return v
        #elseif os(macOS)
            let v = OmniModifierView()
            v.wantsLayer = true
            v.translatesAutoresizingMaskIntoConstraints = false
            objc_setAssociatedObject(v, &changeKey, ChangeState<V>(), .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            return v
        #elseif os(iOS)
            let v = UIView()
            v.translatesAutoresizingMaskIntoConstraints = false
            objc_setAssociatedObject(v, &changeKey, ChangeState<V>(), .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            return v
        #elseif os(Android)
            let v = OmniAndroid.makeContainer()
            AndroidModifierState.set(ChangeState<V>(), for: v)
            return v
        #else
        #error("no implementation for this platform")
        #endif
    }

    public func updateNative(_ view: NativeView) {
        #if os(Linux)
            let ptr = g_object_get_data(view, "change_state")
            let state = Unmanaged<ChangeState<V>>.fromOpaque(ptr!).takeUnretainedValue()
        #elseif os(macOS) || os(iOS)
            guard let state = objc_getAssociatedObject(view, &changeKey) as? ChangeState<V> else { return }
        #elseif os(Android)
            let state = AndroidModifierState.ensure(for: view) { ChangeState<V>() }
        #else
        #error("no implementation for this platform")
        #endif

        if state.isInitialized, let last = state.lastValue, last != value {
            let newValue = value
            let perform = change
            deferToMainLoop { perform(last, newValue) }
        }

        state.lastValue = value
        state.isInitialized = true
    }

    @MainActor public func insertChild(_ child: NativeView, into parent: NativeView) {
        #if os(Linux)
            packFill(child, into: parent)
        #elseif os(macOS) || os(iOS)
            parent.addSubview(child)

            adoptSizing(of: child, into: parent)

            NSLayoutConstraint.activate([
                child.topAnchor.constraint(equalTo: parent.topAnchor),
                child.bottomAnchor.constraint(equalTo: parent.bottomAnchor),
                child.leadingAnchor.constraint(equalTo: parent.leadingAnchor),
                child.trailingAnchor.constraint(equalTo: parent.trailingAnchor)
            ])
        #elseif os(Android)
            OmniAndroid.addChild(child, to: parent)
        #else
        #error("no implementation for this platform")
        #endif
    }
}

#if os(macOS) || os(iOS)
/// A pass-through wrapper (onAppear, onChange, task, a tap target) has no size
/// of its own. It must hug and resist like what it wraps: at the default 250 it
/// stops a Spacer-filled screen stretching, and lets a Text in a row grab the
/// row's spare width.
@MainActor func adoptSizing(of child: NativeView, into wrapper: NativeView) {
    wrapper.setContentHuggingPriority(child.contentHuggingPriority(for: .horizontal), for: .horizontal)
    wrapper.setContentHuggingPriority(child.contentHuggingPriority(for: .vertical), for: .vertical)
    wrapper.setContentCompressionResistancePriority(
        child.contentCompressionResistancePriority(for: .horizontal), for: .horizontal)
    wrapper.setContentCompressionResistancePriority(
        child.contentCompressionResistancePriority(for: .vertical), for: .vertical)
}
#endif

// MARK: - Lifecycle View Modifiers

public struct LifecycleModifier: ViewModifier {
    public var onAppear: (() -> Void)?
    public var onDisappear: (() -> Void)?

    public func body(content: Content) -> some View {
        AppearanceModifierView(content: content, onAppear: onAppear, onDisappear: onDisappear)
    }
}

public struct OnChangeModifier<V: Equatable>: ViewModifier {
    public var value: V
    /// The value before the change, and after it.
    public var change: (V, V) -> Void

    public init(value: V, action: @escaping (V) -> Void) {
        self.value = value
        self.change = { _, new in action(new) }
    }

    public init(value: V, change: @escaping (V, V) -> Void) {
        self.value = value
        self.change = change
    }

    public func body(content: Content) -> some View {
        ChangeModifierView(content: content, value: value, change: change)
    }
}

public extension View {
    func onAppear(perform action: @escaping () -> Void) -> ModifiedContent<Self, LifecycleModifier> {
        self.modifier(LifecycleModifier(onAppear: action, onDisappear: nil))
    }

    func onDisappear(perform action: @escaping () -> Void) -> ModifiedContent<Self, LifecycleModifier> {
        self.modifier(LifecycleModifier(onAppear: nil, onDisappear: action))
    }

    func onChange<V: Equatable>(of value: V, perform action: @escaping (V) -> Void) -> ModifiedContent<Self, OnChangeModifier<V>> {
        self.modifier(OnChangeModifier(value: value, action: action))
    }

    /// The current SwiftUI spelling: `onChange(of: x) { old, new in }`.
    /// `initial:` is accepted and ignored — the modifier fires on change only.
    func onChange<V: Equatable>(
        of value: V, initial: Bool = false,
        _ action: @escaping (V, V) -> Void
    ) -> ModifiedContent<Self, OnChangeModifier<V>> {
        self.modifier(OnChangeModifier(value: value, change: action))
    }

    /// `onChange(of: x) { ... }` with no parameters.
    func onChange<V: Equatable>(
        of value: V, initial: Bool = false,
        _ action: @escaping () -> Void
    ) -> ModifiedContent<Self, OnChangeModifier<V>> {
        self.modifier(OnChangeModifier(value: value, action: { _ in action() }))
    }
}

// MARK: - Asynchronous Task Lifecycle

public class TaskState {
    public var task: Task<Void, Never>?
    public var hasStarted = false

    deinit {
        // Automatically cancels the task when the native view is deallocated
        task?.cancel()
    }
}

#if os(macOS) || os(iOS)
// Only the address is used as an objc_associated_object key, never the
// value. `&key` needs a mutable lvalue, so `let` isn't an option here.
nonisolated(unsafe) private var taskKey: UInt8 = 0
#endif

public struct TaskModifierView: NativeComponent {
    public var content: any View
    public var priority: TaskPriority
    public var action: @isolated(any) @Sendable () async -> Void

    public var children: [any View] { [content] }

    public init(content: any View, priority: TaskPriority, action: @escaping @isolated(any) @Sendable () async -> Void) {
        self.content = content
        self.priority = priority
        self.action = action
    }

    public func makeNative() -> NativeView {
        #if os(Linux)
            let v = gtk_box_new(0, 0)
            let state = TaskState()
            let ptr = Unmanaged.passRetained(state).toOpaque()
            g_object_set_data_full(v, "task_state", ptr) { pPtr in
                if let p = pPtr { Unmanaged<TaskState>.fromOpaque(p).release() }
            }
            return v
        #elseif os(macOS)
            let v = OmniModifierView()
            v.wantsLayer = true
            v.translatesAutoresizingMaskIntoConstraints = false
            objc_setAssociatedObject(v, &taskKey, TaskState(), .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            return v
        #elseif os(iOS)
            let v = UIView()
            v.translatesAutoresizingMaskIntoConstraints = false
            objc_setAssociatedObject(v, &taskKey, TaskState(), .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            return v
        #elseif os(Android)
            let v = OmniAndroid.makeContainer()
            AndroidModifierState.set(TaskState(), for: v)
            return v
        #else
        #error("no implementation for this platform")
        #endif
    }

    public func updateNative(_ view: NativeView) {
        #if os(Linux)
            let ptr = g_object_get_data(view, "task_state")
            let state = Unmanaged<TaskState>.fromOpaque(ptr!).takeUnretainedValue()
        #elseif os(macOS) || os(iOS)
            guard let state = objc_getAssociatedObject(view, &taskKey) as? TaskState else { return }
        #elseif os(Android)
            let state = AndroidModifierState.ensure(for: view) { TaskState() }
        #else
        #error("no implementation for this platform")
        #endif

        // Ensure the task is only fired once when the view appears
        if !state.hasStarted {
            state.hasStarted = true

            // Creates the task inheriting the current MainActor context
            state.task = Task(priority: priority) {
                await action()
            }
        }
    }

    public func insertChild(_ child: NativeView, into parent: NativeView) {
        #if os(Linux)
            packFill(child, into: parent)
        #elseif os(macOS) || os(iOS)
            parent.addSubview(child)
            adoptSizing(of: child, into: parent)
            NSLayoutConstraint.activate([
                child.topAnchor.constraint(equalTo: parent.topAnchor),
                child.bottomAnchor.constraint(equalTo: parent.bottomAnchor),
                child.leadingAnchor.constraint(equalTo: parent.leadingAnchor),
                child.trailingAnchor.constraint(equalTo: parent.trailingAnchor)
            ])
        #elseif os(Android)
            OmniAndroid.addChild(child, to: parent)
        #else
        #error("no implementation for this platform")
        #endif
    }
}

public struct TaskModifier: ViewModifier {
    public var priority: TaskPriority
    public var action: @isolated(any) @Sendable () async -> Void

    public func body(content: Content) -> some View {
        TaskModifierView(content: content, priority: priority, action: action)
    }
}

public extension View {
    /// Adds an asynchronous task to perform when this view appears.
    /// The task is automatically cancelled when the view disappears.
    func task(
        priority: TaskPriority = .userInitiated,
        // As SwiftUI and Task.init: a closure written in a view runs on its
        // actor, so it may read and write the view's @State.
        @_inheritActorContext _ action: @escaping @isolated(any) @Sendable () async -> Void
    ) -> ModifiedContent<Self, TaskModifier> {
        self.modifier(TaskModifier(priority: priority, action: action))
    }
}

/// MARK: - Padding

public struct PaddingModifier: ViewModifier {
    public var insets: EdgeInsets
    public func body(content: Content) -> some View {
        ModifierView(content: content, padding: insets)
    }
}

public enum Edge: Sendable {
    case top, leading, bottom, trailing

    public struct Set: OptionSet, Sendable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }

        public static let top = Set(rawValue: 1 << 0)
        public static let leading = Set(rawValue: 1 << 1)
        public static let bottom = Set(rawValue: 1 << 2)
        public static let trailing = Set(rawValue: 1 << 3)
        public static let horizontal: Set = [.leading, .trailing]
        public static let vertical: Set = [.top, .bottom]
        public static let all: Set = [.top, .leading, .bottom, .trailing]
    }
}

public extension View {
    /// SwiftUI resolves an unspecified length from the platform; 16 is what
    /// these backends have always used.
    static var systemPadding: Double { 16.0 }

    func padding(_ length: Double? = nil) -> ModifiedContent<Self, PaddingModifier> {
        padding(.all, length)
    }

    /// SwiftUI's `padding(_ insets: EdgeInsets)`.
    func padding(_ insets: EdgeInsets) -> ModifiedContent<Self, PaddingModifier> {
        self.modifier(PaddingModifier(insets: insets))
    }

    func padding(_ edges: Edge.Set, _ length: Double? = nil) -> ModifiedContent<Self, PaddingModifier> {
        let length = length ?? Self.systemPadding
        return self.modifier(PaddingModifier(insets: EdgeInsets(
            top: edges.contains(.top) ? length : 0,
            leading: edges.contains(.leading) ? length : 0,
            bottom: edges.contains(.bottom) ? length : 0,
            trailing: edges.contains(.trailing) ? length : 0)))
    }

    func padding(horizontal: Double, vertical: Double) -> ModifiedContent<Self, PaddingModifier> {
        self.modifier(PaddingModifier(insets: EdgeInsets(top: vertical, leading: horizontal, bottom: vertical, trailing: horizontal)))
    }
}

// MARK: - OnAppear Lifecycle

public struct ShadowModifierView: NativeComponent {
    public var content: any View
    public var color: Color
    public var radius: Double
    public var x: Double
    public var y: Double
    public var children: [any View] { [content] }

    public init(content: any View, color: Color = ShadowModifier.defaultColor,
                radius: Double, x: Double = 0, y: Double = 0) {
        self.content = content
        self.color = color
        self.radius = radius
        self.x = x
        self.y = y
    }

    @MainActor public func makeNative() -> NativeView {
        #if os(Linux)
            return gtk_box_new(0, 0)
        #elseif os(macOS)
            let v = OmniShadowView()
            v.translatesAutoresizingMaskIntoConstraints = false
            v.shadow = NSShadow()
            return v
        #elseif os(iOS)
            let v = UIView()
            v.translatesAutoresizingMaskIntoConstraints = false
            v.layer.masksToBounds = false
            return v
        #elseif os(Android)
            // Android has no blur-radius shadow on a plain view; elevation is the
            // platform's equivalent and drives a material drop shadow.
            return OmniAndroid.makeContainer()
        #else
        #error("no implementation for this platform")
        #endif
    }

    /// Applied on every render, so a shadow that follows state (a field's
    /// focus, say) changes with it.
    @MainActor public func updateNative(_ view: NativeView) {
        #if os(macOS)
            view.shadow?.shadowBlurRadius = CGFloat(radius)
            view.shadow?.shadowColor = color.nsColor
            // AppKit's y runs up; SwiftUI's y runs down.
            view.shadow?.shadowOffset = NSSize(width: x, height: -y)
        #elseif os(iOS)
            // CALayer's radius is about half a CSS blur, which is how SwiftUI
            // treats it too. The colour carries the opacity.
            view.layer.shadowRadius = CGFloat(radius)
            view.layer.shadowColor = color.uiColor.cgColor
            view.layer.shadowOpacity = 1
            view.layer.shadowOffset = CGSize(width: x, height: y)
        #elseif os(Android)
            omni_jni_set_shadow(OmniAndroid.getEnv(), view, Float(radius))
        #endif
    }

    @MainActor public func insertChild(_ child: NativeView, into parent: NativeView) {
        #if os(Linux)
            packFill(child, into: parent)
        #elseif os(macOS) || os(iOS)
            parent.addSubview(child)
            adoptSizing(of: child, into: parent)
            NSLayoutConstraint.activate([
                child.topAnchor.constraint(equalTo: parent.topAnchor),
                child.bottomAnchor.constraint(equalTo: parent.bottomAnchor),
                child.leadingAnchor.constraint(equalTo: parent.leadingAnchor),
                child.trailingAnchor.constraint(equalTo: parent.trailingAnchor)
            ])
        #elseif os(Android)
            OmniAndroid.addChild(child, to: parent)
        #else
        #error("no implementation for this platform")
        #endif
    }
}

public struct ShadowModifier: ViewModifier {
    /// SwiftUI's default: black at a third.
    public static let defaultColor = Color.black.opacity(0.33)

    public var color: Color = ShadowModifier.defaultColor
    public var radius: Double
    public var x: Double = 0
    public var y: Double = 0
    public func body(content: Content) -> some View {
        ShadowModifierView(content: content, color: color, radius: radius, x: x, y: y)
    }
}

// MARK: - Extensions

public extension View {
    /// SwiftUI's: a shadow in `color`, blurred by `radius`, offset by x and y
    /// (y down). Only the radius drives Android's elevation for now.
    func shadow(color: Color = ShadowModifier.defaultColor, radius: Double,
                x: Double = 0, y: Double = 0) -> ModifiedContent<Self, ShadowModifier> {
        self.modifier(ShadowModifier(color: color, radius: radius, x: x, y: y))
    }

    /// Layers a view on top of this one.
    ///
    /// Same caveat as .background: this is a ZStack, so the result sizes to the
    /// larger of the two rather than to the content. `alignment` is honoured.
    func overlay<V: View>(_ overlayView: V, alignment: Alignment = .center) -> some View {
        #if os(macOS) || os(iOS)
        AnyView(OverlayView(base: self, overlay: overlayView, alignment: alignment))
        #else
        AnyView(ZStack(alignment: alignment) {
            self
            overlayView
        })
        #endif
    }

    /// SwiftUI's current spelling, with the overlay in a trailing closure.
    func overlay<V: View>(
        alignment: Alignment = .center,
        @ViewBuilder content: () -> V
    ) -> some View {
        return overlay(content(), alignment: alignment)
    }
}

// MARK: - Safe area

public extension View {
    /// SwiftUI's: the view reaches under the status bar and home indicator
    /// along each side where it touches the safe area, as a full-screen
    /// background should. Content otherwise stays inside it. iOS and Android
    /// have a safe area; elsewhere this changes nothing.
    func ignoresSafeArea() -> some View {
        #if os(iOS) || os(Android)
        AnyView(SafeAreaBleedView(content: self))
        #else
        AnyView(self)
        #endif
    }
}

#if os(iOS) || os(Android)
public struct SafeAreaBleedView: NativeComponent {
    public var content: any View
    public var children: [any View] { [content] }

    @MainActor public func makeNative() -> NativeView {
        #if os(iOS)
        let view = OmniBleedView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
        #else
        return OmniAndroid.createView(OmniAndroid.env, "com/omni/OmniEventBridge$BleedLayout")
        #endif
    }

    @MainActor public func updateNative(_ view: NativeView) {}

    @MainActor public func insertChild(_ child: NativeView, into parent: NativeView) {
        #if os(iOS)
        guard let bleed = parent as? OmniBleedView else { return }
        parent.addSubview(child)
        adoptSizing(of: child, into: parent)
        bleed.edges = [
            child.topAnchor.constraint(equalTo: parent.topAnchor),
            child.bottomAnchor.constraint(equalTo: parent.bottomAnchor),
            child.leadingAnchor.constraint(equalTo: parent.leadingAnchor),
            child.trailingAnchor.constraint(equalTo: parent.trailingAnchor)
        ]
        NSLayoutConstraint.activate(bleed.edges)
        #else
        OmniAndroid.addChild(child, to: parent)
        #endif
    }
}
#endif

#if os(iOS)
/// Stretches its one child past its own edges to the window's, along each side
/// where it sits against the safe area. Nothing clips it: UIKit draws outside a
/// view's bounds unless told not to.
public final class OmniBleedView: UIView {
    /// top, bottom, leading, trailing, as insertChild made them.
    var edges: [NSLayoutConstraint] = []

    public override func layoutSubviews() {
        super.layoutSubviews()
        guard let window, edges.count == 4 else { return }
        let frame = convert(bounds, to: window)
        let insets = window.safeAreaInsets
        let bottomGap = window.bounds.maxY - frame.maxY
        let trailingGap = window.bounds.maxX - frame.maxX
        let reach: [CGFloat] = [
            frame.minY <= insets.top + 0.5 ? -frame.minY : 0,
            bottomGap <= insets.bottom + 0.5 ? bottomGap : 0,
            frame.minX <= insets.left + 0.5 ? -frame.minX : 0,
            trailingGap <= insets.right + 0.5 ? trailingGap : 0
        ]
        var changed = false
        for (constraint, constant) in zip(edges, reach) where constraint.constant != constant {
            constraint.constant = constant
            changed = true
        }
        if changed { setNeedsLayout() }
    }
}
#endif

