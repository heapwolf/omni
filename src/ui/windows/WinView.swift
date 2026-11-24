// src/ui/windows/WinView.swift
//
// Windows' native view. Win32 has no layout and no compositing between child
// windows, so omni's views are drawn by omni: each is a WinView, a node in a
// tree that a window (WinSurface) lays out and paints in one Direct2D pass.
// Only what Windows does better itself is a Win32 control: text inputs,
// pickers, web views. Those are WinViews too, holding the control's HWND,
// which the surface positions after each layout.
//
// Layout is GTK's model, which is what the Linux backend writes against, so
// the components read the same on both: a view has a natural size (height
// for a given width, for text that wraps), a size request, and an expand flag
// per axis that it carries up to its parent unless it set it itself. Boxes
// share their surplus among the children that expand, and place the others
// by alignment. A stack that can't fit its children shrinks the ones that can
// shrink (text truncates), as SwiftUI does.
//
// NativeView on Windows is an opaque pointer to a WinView. The view is kept
// alive by `WinView.live` until it is destroyed (Node.unmount).

#if os(Windows)
import Foundation
import WinSDK

public struct WinSize: Equatable, Sendable {
    public var width: Double
    public var height: Double
    public static let zero = WinSize(width: 0, height: 0)
}

public struct WinRect: Equatable, Sendable {
    public var x: Double, y: Double, width: Double, height: Double
    public static let zero = WinRect(x: 0, y: 0, width: 0, height: 0)
    var maxX: Double { x + width }
    var maxY: Double { y + height }
    func contains(_ px: Double, _ py: Double) -> Bool { px >= x && px < maxX && py >= y && py < maxY }
    func intersection(_ other: WinRect) -> WinRect {
        let x0 = max(x, other.x), y0 = max(y, other.y)
        let x1 = min(maxX, other.maxX), y1 = min(maxY, other.maxY)
        return WinRect(x: x0, y: y0, width: max(0, x1 - x0), height: max(0, y1 - y0))
    }
}

/// Where a parent puts a child on one axis: GTK's GtkAlign.
public enum WinAlign {
    case fill, start, center, end
}

@MainActor
public final class WinView {
    public enum Layout {
        /// One child or none, inset by padding: a modifier, a frame, a gesture.
        case bin
        /// Children along an axis, with spacing.
        case box(StackAxis)
        /// Children over one another.
        case overlay
        /// Content that scrolls along an axis.
        case scroll(StackAxis)
        /// Draws itself, or holds a control.
        case leaf
    }

    /// Every view not yet destroyed, which is what keeps it alive.
    static var live: [UnsafeMutableRawPointer: WinView] = [:]

    public var layout: Layout
    /// For debugging and for the probe: what made it.
    public var kind: String

    public private(set) var children: [WinView] = []
    public private(set) weak var parent: WinView?
    /// Set on a surface's root only.
    weak var rootOf: WinSurface?

    // MARK: Layout properties

    public var spacing: Double = 0 { didSet { if spacing != oldValue { setNeedsLayout() } } }
    public var padding = EdgeInsets() { didSet { if padding != oldValue { setNeedsLayout() } } }
    /// Its own claim on surplus space, per axis.
    public var hexpand = false { didSet { if hexpand != oldValue { setNeedsLayout() } } }
    public var vexpand = false { didSet { if vexpand != oldValue { setNeedsLayout() } } }
    /// Set: the claim is its own, and its children's doesn't carry past it.
    public var hexpandSet = false { didSet { if hexpandSet != oldValue { setNeedsLayout() } } }
    public var vexpandSet = false { didSet { if vexpandSet != oldValue { setNeedsLayout() } } }
    /// How the parent places it on each axis.
    public var halign: WinAlign = .fill { didSet { if halign != oldValue { setNeedsLayout() } } }
    public var valign: WinAlign = .fill { didSet { if valign != oldValue { setNeedsLayout() } } }
    /// Fixed sizes, and bounds.
    public var fixedWidth: Double? { didSet { if fixedWidth != oldValue { setNeedsLayout() } } }
    public var fixedHeight: Double? { didSet { if fixedHeight != oldValue { setNeedsLayout() } } }
    public var minWidth: Double? { didSet { if minWidth != oldValue { setNeedsLayout() } } }
    public var minHeight: Double? { didSet { if minHeight != oldValue { setNeedsLayout() } } }
    public var maxWidth: Double? { didSet { if maxWidth != oldValue { setNeedsLayout() } } }
    public var maxHeight: Double? { didSet { if maxHeight != oldValue { setNeedsLayout() } } }
    /// Where a bin or overlay puts children that don't fill it.
    public var contentAlignment: Alignment = .center { didSet { if contentAlignment != oldValue { setNeedsLayout() } } }
    /// A leaf's natural size for a proposed width (nil: unconstrained).
    public var measure: ((Double?) -> WinSize)? { didSet { setNeedsLayout() } }
    /// How small a leaf can get along its width, for a stack short of room.
    /// nil: as small as zero for flexible views, else its natural width.
    public var minimumWidth: (() -> Double)?
    /// A Spacer: it gives way first, and is laid out by its stack's axis.
    public var isSpacer = false
    public var spacerLength: Double = 0
    public var isHidden = false { didSet { if isHidden != oldValue { setNeedsLayout() } } }
    /// An overlay's or a background's: fitted to its parent, which its base
    /// alone sizes, as SwiftUI's are. It neither asks for space nor claims
    /// any, and takes a click only where it handles one itself.
    public var isDecoration = false { didSet { if isDecoration != oldValue { setNeedsLayout() } } }
    /// Fills what its parent gives it across, though it asks only for its
    /// own width: a macOS pop-up button's way, which a Picker has.
    public var fillsWidthOffered = false

    // MARK: Paint properties

    public var background: Color? { didSet { if background != oldValue { setNeedsDisplay() } } }
    public var gradient: (stops: [(Double, Color)], start: UnitPoint, end: UnitPoint)? { didSet { setNeedsDisplay() } }
    public var cornerRadius: Double = 0 { didSet { if cornerRadius != oldValue { setNeedsDisplay() } } }
    /// Clips its content to its bounds (rounded by cornerRadius).
    public var clipsToBounds = false { didSet { if clipsToBounds != oldValue { setNeedsDisplay() } } }
    public var borderColor: Color? { didSet { if borderColor != oldValue { setNeedsDisplay() } } }
    public var borderWidth: Double = 0 { didSet { if borderWidth != oldValue { setNeedsDisplay() } } }
    public var opacity: Double = 1 { didSet { if opacity != oldValue { setNeedsDisplay() } } }
    public var shadow: (color: Color, radius: Double, x: Double, y: Double)? { didSet { setNeedsDisplay() } }
    public var offsetX: Double = 0 { didSet { if offsetX != oldValue { setNeedsDisplay() } } }
    public var offsetY: Double = 0 { didSet { if offsetY != oldValue { setNeedsDisplay() } } }
    public var scale: Double = 1 { didSet { if scale != oldValue { setNeedsDisplay() } } }
    public var zIndex: Double = 0 { didSet { if zIndex != oldValue { setNeedsDisplay() } } }
    /// Inherited by the text inside, unless the text has its own.
    public var foreground: Color? { didSet { if foreground != oldValue { setNeedsDisplay() } } }
    public var tint: Color? { didSet { if tint != oldValue { setNeedsDisplay() } } }
    /// Inherited: a disabled view's subtree takes no input and draws dimmed.
    public var disabled: Bool? { didSet { if disabled != oldValue { disabledChanged() } } }
    public var hitTesting = true
    /// Drawn after the background and before the children, in the view's own coordinates.
    public var draw: ((WinCanvas, WinRect) -> Void)? { didSet { setNeedsDisplay() } }

    // MARK: Input

    public var onTap: (() -> Void)?
    public var onTapLocation: ((Double, Double) -> Void)?
    /// A press: true as the button goes down, false as it comes up or leaves.
    public var onPress: ((Bool) -> Void)?
    public var onDrag: ((Double, Double) -> Void)?
    public var onDragEnded: ((Double, Double) -> Void)?
    public var onScrollWheel: ((Double, Double) -> Void)?
    public var onHover: ((Bool) -> Void)?
    public var onSecondaryClick: ((Double, Double) -> Void)?
    /// A cursor name, as Frame's: "pointer", "text", "resizeLeftRight", "resizeUpDown".
    public var cursor: String?
    /// Takes keyboard focus when clicked, and the keys while it has it.
    public var onKey: ((UInt32, Bool) -> Bool)?
    public var onFocusChange: ((Bool) -> Void)?

    // MARK: Controls

    /// A Win32 control this view is, made once the view is in a window.
    public var control: WinControl? {
        didSet { oldValue?.destroy(); control?.view = self; setNeedsLayout() }
    }

    // MARK: Scrolling

    public var scrollOffset: (x: Double, y: Double) = (0, 0) { didSet { setNeedsLayout() } }
    public var onScrollOffsetChange: ((Double, Double) -> Void)?
    /// The content's size, from the last layout.
    public private(set) var contentSize = WinSize.zero
    public var showsIndicators = true
    /// .scrollDisabled: the wheel goes on to whatever scrolls around it.
    public var isScrollEnabled = true

    // MARK: Component state

    /// What a modifier keeps between renders (has it appeared, its task, the
    /// value it last saw). Let go with the view, which is when a task is
    /// cancelled and onDisappear runs.
    public var state: AnyObject?

    public func state<T: AnyObject>(_ make: () -> T) -> T {
        if let existing = state as? T { return existing }
        let made = make()
        state = made
        return made
    }

    // MARK: Results of layout

    /// In the parent's coordinates (its content's, for a scroll view).
    public internal(set) var frame = WinRect.zero

    /// Natural sizes, by proposed width, since the last change below.
    private var naturalCache: [Int: WinSize] = [:]

    public init(_ kind: String, layout: Layout = .bin) {
        self.kind = kind
        self.layout = layout
    }

    // MARK: Identity

    public var pointer: UnsafeMutableRawPointer { Unmanaged.passUnretained(self).toOpaque() }

    /// A new view, kept until `destroy`.
    public static func make(_ kind: String, layout: Layout = .bin) -> NativeView {
        let view = WinView(kind, layout: layout)
        live[view.pointer] = view
        return view.pointer
    }

    public static func from(_ native: NativeView) -> WinView {
        if let view = live[native] { return view }
        return Unmanaged<WinView>.fromOpaque(native).takeUnretainedValue()
    }

    public static func existing(_ native: NativeView?) -> WinView? {
        guard let native else { return nil }
        return live[native]
    }

    /// Takes it out of its parent and its window, and lets it go, with its subtree.
    public static func destroy(_ native: NativeView) {
        guard let view = live[native] else { return }
        #if DEBUG
        note("destroy \(view.label)")
        #endif
        view.removeFromParent()
        view.tearDown()
    }

    private func tearDown() {
        for child in children { child.tearDown() }
        children.removeAll()
        control?.destroy()
        control = nil
        state = nil
        draw = nil
        measure = nil
        WinSurface.forget(self)
        WinView.live[pointer] = nil
    }

    // MARK: The tree

    #if DEBUG
    /// The last changes to the tree, for WinSurface.dumpTree.
    static var journal: [String] = []
    static func note(_ event: String) {
        journal.append(event)
        if journal.count > 5000 { journal.removeFirst(journal.count - 5000) }
    }
    var label: String { "\(kind)@\(String(UInt(bitPattern: pointer), radix: 16).suffix(5))" }
    #endif

    public func add(_ child: WinView) {
        #if DEBUG
        WinView.note("add \(child.label) to \(label)")
        #endif
        if child.parent === self, let i = children.firstIndex(where: { $0 === child }) {
            children.remove(at: i)
        } else {
            child.removeFromParent()
        }
        children.append(child)
        child.parent = self
        child.attached()
        setNeedsLayout()
    }

    public func insert(_ child: WinView, at index: Int) {
        add(child)
        if let i = children.firstIndex(where: { $0 === child }) {
            children.remove(at: i)
            children.insert(child, at: min(index, children.count))
        }
    }

    public func removeFromParent() {
        guard let parent else { return }
        #if DEBUG
        WinView.note("remove \(label) from \(parent.label)")
        #endif
        parent.children.removeAll { $0 === self }
        parent.setNeedsLayout()
        self.parent = nil
        detached()
    }

    /// The window it's in.
    public var surface: WinSurface? {
        var view: WinView? = self
        while let v = view {
            if let s = v.rootOf { return s }
            view = v.parent
        }
        return nil
    }

    /// Controls inside take their window; text inside its colours.
    func attached() {
        forEachInSubtree { view in
            view.control?.attachIfNeeded()
        }
    }

    func detached() {
        forEachInSubtree { $0.control?.hide() }
    }

    func forEachInSubtree(_ body: (WinView) -> Void) {
        body(self)
        for child in children { child.forEachInSubtree(body) }
    }

    // MARK: Invalidation

    public func setNeedsLayout() {
        var view: WinView? = self
        while let v = view {
            v.naturalCache.removeAll(keepingCapacity: true)
            if let s = v.rootOf { s.setNeedsLayout(); return }
            view = v.parent
        }
    }

    public func setNeedsDisplay() {
        surface?.setNeedsDisplay()
    }

    private func disabledChanged() {
        forEachInSubtree { $0.control?.applyEnabled() }
        setNeedsDisplay()
    }

    // MARK: Inherited

    public var isDisabled: Bool {
        var view: WinView? = self
        while let v = view {
            if let d = v.disabled { return d }
            view = v.parent
        }
        return false
    }

    public var inheritedForeground: Color? {
        var view: WinView? = self
        while let v = view {
            if let f = v.foreground { return f }
            view = v.parent
        }
        return nil
    }

    public var inheritedTint: Color? {
        var view: WinView? = self
        while let v = view {
            if let t = v.tint { return t }
            view = v.parent
        }
        return nil
    }

    // MARK: Expand

    /// GTK's computed expand: its own, or any child's unless it set its own.
    public var expandsH: Bool {
        if isHidden { return false }
        if hexpandSet { return hexpand }
        if hexpand { return true }
        return sizingChildren.contains { $0.expandsH }
    }

    public var expandsV: Bool {
        if isHidden { return false }
        if vexpandSet { return vexpand }
        if vexpand { return true }
        return sizingChildren.contains { $0.expandsV }
    }

    func expands(_ axis: StackAxis) -> Bool { axis == .horizontal ? expandsH : expandsV }

    var visibleChildren: [WinView] { children.filter { !$0.isHidden } }
    /// The children that size it: not its overlays and backgrounds.
    var sizingChildren: [WinView] { children.filter { !$0.isHidden && !$0.isDecoration } }

    // MARK: Measuring

    /// The size it would like, given at most `width` across (nil: any).
    public func natural(width proposed: Double?) -> WinSize {
        if isHidden { return .zero }
        // A fixed width is what it's offered, whatever the parent offers.
        let offered = fixedWidth ?? proposed.map { p in maxWidth.map { min($0, p) } ?? p }
        let key = offered.map { Int(($0 * 4).rounded()) } ?? -1
        if let cached = naturalCache[key] { return cached }
        var size = intrinsic(width: offered)
        if let fixedWidth { size.width = fixedWidth }
        if let fixedHeight { size.height = fixedHeight }
        if let minWidth, fixedWidth == nil { size.width = max(size.width, minWidth) }
        if let minHeight, fixedHeight == nil { size.height = max(size.height, minHeight) }
        if let maxWidth, maxWidth.isFinite, fixedWidth == nil { size.width = min(size.width, maxWidth) }
        if let maxHeight, maxHeight.isFinite, fixedHeight == nil { size.height = min(size.height, maxHeight) }
        naturalCache[key] = size
        return size
    }

    private func intrinsic(width offered: Double?) -> WinSize {
        let ph = padding.leading + padding.trailing, pv = padding.top + padding.bottom
        let inner = offered.map { max(0, $0 - ph) }
        var size: WinSize
        switch layout {
        case .leaf:
            size = measure?(inner) ?? .zero
            if isSpacer { size = WinSize(width: spacerLength, height: spacerLength) }
        case .bin, .overlay:
            var w = 0.0, h = 0.0
            for child in sizingChildren {
                let s = child.natural(width: inner)
                w = max(w, s.width)
                h = max(h, s.height)
            }
            size = WinSize(width: w, height: h)
        case .box(let axis):
            size = measureBox(axis, width: inner)
        case .scroll(let axis):
            // Flexible along its axis, as SwiftUI's: it asks for nothing there
            // and takes what it's given (it expands).
            var w = 0.0, h = 0.0
            for child in sizingChildren {
                let s = child.natural(width: axis == .vertical ? inner : nil)
                w = max(w, s.width)
                h = max(h, s.height)
            }
            size = axis == .vertical ? WinSize(width: w, height: 0) : WinSize(width: 0, height: h)
        }
        if let control, let controlSize = control.naturalSize(width: inner) {
            size = WinSize(width: max(size.width, controlSize.width), height: max(size.height, controlSize.height))
        }
        return WinSize(width: size.width + ph, height: size.height + pv)
    }

    private func measureBox(_ axis: StackAxis, width: Double?) -> WinSize {
        let kids = sizingChildren
        guard !kids.isEmpty else { return .zero }
        let gaps = spacing * Double(kids.count - 1)
        if axis == .vertical {
            var w = 0.0, h = gaps
            for kid in kids {
                let s = kid.isSpacer ? WinSize(width: 0, height: kid.spacerLength) : kid.natural(width: width)
                w = max(w, s.width)
                h += s.height
            }
            return WinSize(width: w, height: h)
        }
        // Across: each child's width as the row would give it, then each
        // one's height at that width.
        let widths = distribute(kids, along: .horizontal, available: width, naturals: kids.map { kid in
            kid.isSpacer ? kid.spacerLength : kid.natural(width: nil).width
        })
        var h = 0.0
        for (kid, w) in zip(kids, widths) where !kid.isSpacer {
            h = max(h, kid.natural(width: w).height)
        }
        let total = width.map { _ in widths.reduce(0, +) + gaps } ?? (widths.reduce(0, +) + gaps)
        return WinSize(width: total, height: h)
    }

    /// The least a child can be along an axis, when its stack is short.
    func minimum(along axis: StackAxis, natural: Double) -> Double {
        if isHidden { return 0 }
        if axis == .horizontal {
            if let fixedWidth { return fixedWidth }
            if let minWidth { return minWidth }
        } else {
            if let fixedHeight { return fixedHeight }
            if let minHeight { return minHeight }
        }
        if isSpacer { return spacerLength }
        switch layout {
        case .leaf:
            if axis == .horizontal, let minimumWidth { return min(natural, minimumWidth()) }
            return natural
        case .scroll:
            return 0
        case .bin, .overlay:
            let p = axis == .horizontal ? padding.leading + padding.trailing : padding.top + padding.bottom
            let kids = sizingChildren
            if kids.isEmpty { return natural }
            // Each child's own least, from its own natural size: not this view's.
            return kids.map { $0.minimum(along: axis, natural: $0.naturalLength(along: axis)) }.max()! + p
        case .box(let boxAxis):
            let kids = sizingChildren
            if kids.isEmpty { return natural }
            if boxAxis == axis {
                let naturals = kids.map { axis == .horizontal ? $0.natural(width: nil).width : $0.natural(width: nil).height }
                return zip(kids, naturals).map { $0.minimum(along: axis, natural: $1) }.reduce(0, +)
                    + spacing * Double(kids.count - 1)
            }
            return kids.map { $0.minimum(along: axis, natural: $0.naturalLength(along: axis)) }.max()!
        }
    }

    /// Its natural size along an axis, unconstrained.
    func naturalLength(along axis: StackAxis) -> Double {
        let size = natural(width: nil)
        return axis == .horizontal ? size.width : size.height
    }

    /// Sizes along an axis for children with these natural sizes: the surplus
    /// to those that expand (spacers first in line only if nothing else
    /// expands), the shortfall taken from those that can shrink.
    func distribute(_ kids: [WinView], along axis: StackAxis, available: Double?, naturals: [Double]) -> [Double] {
        var sizes = naturals
        guard let available else { return sizes }
        let gaps = spacing * Double(max(0, kids.count - 1))
        let room = max(0, available - gaps)
        let total = sizes.reduce(0, +)
        if total < room {
            let expanders = kids.indices.filter { kids[$0].expands(axis) }
            if !expanders.isEmpty {
                let share = (room - total) / Double(expanders.count)
                for i in expanders { sizes[i] += share }
            }
            return sizes
        }
        if total > room {
            // Shrink what can shrink, in proportion to how much it can.
            let minimums = kids.indices.map { kids[$0].minimum(along: axis, natural: naturals[$0]) }
            let slack = kids.indices.map { max(0, naturals[$0] - minimums[$0]) }
            let totalSlack = slack.reduce(0, +)
            let deficit = total - room
            if totalSlack > 0 {
                let ratio = min(1, deficit / totalSlack)
                for i in kids.indices { sizes[i] = naturals[i] - slack[i] * ratio }
            }
        }
        return sizes
    }

    // MARK: Arranging

    /// Told its size after a layout that changed it: GeometryReader's.
    public var onSizeChange: ((WinSize) -> Void)?
    private var reportedSize: WinSize?

    /// Lays it out in `rect`, in its parent's coordinates.
    public func layout(in rect: WinRect) {
        frame = rect
        if let onSizeChange {
            let size = WinSize(width: rect.width, height: rect.height)
            if reportedSize != size {
                reportedSize = size
                // After this layout: the callback sets state, which renders.
                DispatchQueue.main.async { MainActor.assumeIsolated { onSizeChange(size) } }
            }
        }
        let inner = WinRect(x: padding.leading, y: padding.top,
                            width: max(0, rect.width - padding.leading - padding.trailing),
                            height: max(0, rect.height - padding.top - padding.bottom))
        let kids = visibleChildren
        // Decorations (overlays, backgrounds) are fitted to the view after
        // its own children are laid out; a box or a scroll view leaves them out.
        let content = kids.filter { !$0.isDecoration }
        switch layout {
        case .leaf:
            break
        case .bin, .overlay:
            for kid in content { kid.layout(in: place(kid, in: inner, alignment: contentAlignment)) }
        case .box(let axis):
            layoutBox(axis, kids: content, in: inner)
        case .scroll(let axis):
            layoutScroll(axis, kids: content, in: inner)
        }
        for kid in kids where kid.isDecoration {
            kid.layout(in: place(kid, in: inner, alignment: contentAlignment))
        }
        for child in children where child.isHidden { child.frame = .zero }
    }

    /// A child's rect in `area`: filling an axis it expands along or is told
    /// to fill, else its natural size placed by its alignment.
    func place(_ kid: WinView, in area: WinRect, alignment: Alignment) -> WinRect {
        let fillsH = kid.halign == .fill || kid.expandsH || kid.fillsWidthOffered
        let fillsV = kid.valign == .fill || kid.expandsV
        let natural = kid.natural(width: area.width)
        var w = fillsH ? area.width : min(natural.width, area.width)
        if let fw = kid.fixedWidth { w = fw }
        let h0 = fillsH || kid.fixedWidth != nil ? kid.natural(width: w).height : natural.height
        var h = fillsV ? area.height : h0
        if let fh = kid.fixedHeight { h = fh }
        let hAlign: WinAlign = kid.halign == .fill ? alignment.horizontal.winAlign : kid.halign
        let vAlign: WinAlign = kid.valign == .fill ? alignment.vertical.winAlign : kid.valign
        return WinRect(x: area.x + offset(hAlign, free: area.width - w),
                       y: area.y + offset(vAlign, free: area.height - h),
                       width: w, height: h)
    }

    private func offset(_ align: WinAlign, free: Double) -> Double {
        switch align {
        case .fill, .start: return 0
        case .center: return (free / 2).rounded()
        case .end: return free
        }
    }

    private func layoutBox(_ axis: StackAxis, kids: [WinView], in area: WinRect) {
        guard !kids.isEmpty else { return }
        if axis == .horizontal {
            let naturals = kids.map { $0.isSpacer ? $0.spacerLength : $0.natural(width: nil).width }
            let widths = distribute(kids, along: .horizontal, available: area.width, naturals: naturals)
            let used = widths.reduce(0, +) + spacing * Double(kids.count - 1)
            var x = area.x + (used < area.width ? ((area.width - used) / 2).rounded() : 0)
            for (kid, w) in zip(kids, widths) {
                let fills = kid.valign == .fill || kid.expandsV || kid.isSpacer
                var h = fills ? area.height : min(kid.natural(width: w).height, area.height)
                if let fh = kid.fixedHeight { h = fh }
                let y = area.y + offset(kid.valign == .fill ? .center : kid.valign, free: area.height - h)
                kid.layout(in: WinRect(x: x, y: y, width: w, height: h))
                x += w + spacing
            }
        } else {
            var widths: [Double] = []
            var naturals: [Double] = []
            for kid in kids {
                let fills = kid.halign == .fill || kid.expandsH || kid.isSpacer || kid.fillsWidthOffered
                var w = fills ? area.width : min(kid.natural(width: area.width).width, area.width)
                if let fw = kid.fixedWidth { w = fw }
                widths.append(w)
                naturals.append(kid.isSpacer ? kid.spacerLength : kid.natural(width: w).height)
            }
            let heights = distribute(kids, along: .vertical, available: area.height, naturals: naturals)
            let used = heights.reduce(0, +) + spacing * Double(kids.count - 1)
            var y = area.y + (used < area.height ? ((area.height - used) / 2).rounded() : 0)
            for (i, kid) in kids.enumerated() {
                let w = widths[i]
                let x = area.x + offset(kid.halign == .fill ? .center : kid.halign, free: area.width - w)
                kid.layout(in: WinRect(x: x, y: y, width: w, height: heights[i]))
                y += heights[i] + spacing
            }
        }
    }

    private func layoutScroll(_ axis: StackAxis, kids: [WinView], in area: WinRect) {
        var content = WinSize.zero
        for kid in kids {
            let size: WinSize
            if axis == .vertical {
                let h = kid.natural(width: area.width).height
                size = WinSize(width: area.width, height: max(h, kid.expandsV ? area.height : h))
            } else {
                let w = kid.natural(width: nil).width
                size = WinSize(width: max(w, kid.expandsH ? area.width : w), height: area.height)
            }
            kid.layout(in: WinRect(x: area.x, y: area.y, width: size.width, height: size.height))
            content.width = max(content.width, size.width)
            content.height = max(content.height, size.height)
        }
        contentSize = content
        // Kept in range as the content or the viewport changes size.
        let maxX = max(0, content.width - area.width), maxY = max(0, content.height - area.height)
        let clamped = (x: min(max(0, scrollOffset.x), maxX), y: min(max(0, scrollOffset.y), maxY))
        if clamped.x != scrollOffset.x || clamped.y != scrollOffset.y {
            scrollOffsetSilently(clamped)
        }
    }

    /// Moves the content without asking for another layout: it's laid out already.
    func scrollOffsetSilently(_ offset: (x: Double, y: Double)) {
        let cache = naturalCache
        scrollOffset = offset
        naturalCache = cache
    }

    public var maxScroll: (x: Double, y: Double) {
        let viewport = WinSize(width: frame.width - padding.leading - padding.trailing,
                               height: frame.height - padding.top - padding.bottom)
        return (max(0, contentSize.width - viewport.width), max(0, contentSize.height - viewport.height))
    }

    /// Scrolls by a delta, kept in range; true if it moved.
    @discardableResult
    public func scroll(by dx: Double, _ dy: Double) -> Bool {
        let limit = maxScroll
        let next = (x: min(max(0, scrollOffset.x + dx), limit.x), y: min(max(0, scrollOffset.y + dy), limit.y))
        guard next.x != scrollOffset.x || next.y != scrollOffset.y else { return false }
        scrollOffset = next
        onScrollOffsetChange?(next.x, next.y)
        return true
    }

    // MARK: Geometry

    /// Its rect in the window's coordinates, after scrolling and offsets.
    public var windowFrame: WinRect {
        var x = frame.x + offsetX, y = frame.y + offsetY
        var view = parent
        while let v = view {
            x += v.frame.x + v.offsetX
            y += v.frame.y + v.offsetY
            if case .scroll = v.layout {
                x -= v.scrollOffset.x
                y -= v.scrollOffset.y
            }
            view = v.parent
        }
        return WinRect(x: x, y: y, width: frame.width, height: frame.height)
    }

    /// The part of the window it can be seen in: its ancestors' clips.
    public var visibleWindowRect: WinRect {
        var rect = windowFrame
        var view = parent
        while let v = view {
            var clips = v.clipsToBounds
            if case .scroll = v.layout { clips = true }
            if clips { rect = rect.intersection(v.windowFrame) }
            view = v.parent
        }
        return rect
    }

    /// The deepest view at a point in its own coordinates that takes input.
    func hitTest(_ x: Double, _ y: Double) -> WinView? {
        if isHidden || !hitTesting { return nil }
        let lx = x - frame.x - offsetX, ly = y - frame.y - offsetY
        let inside = lx >= 0 && ly >= 0 && lx < frame.width && ly < frame.height
        var clips = clipsToBounds
        if case .scroll = layout { clips = true }
        if clips && !inside { return nil }
        var cx = lx, cy = ly
        if case .scroll = layout { cx += scrollOffset.x; cy += scrollOffset.y }
        for child in paintOrder.reversed() {
            guard let hit = child.hitTest(cx, cy) else { continue }
            // A decoration takes the click only where something in it handles
            // one: a border drawn over a button is the button's.
            if child.isDecoration, !hit.handlesInput(within: child) { continue }
            return hit
        }
        return inside ? self : nil
    }

    /// Whether it, or a view between it and `root`, takes clicks or keys.
    func handlesInput(within root: WinView) -> Bool {
        var v: WinView? = self
        while let current = v {
            if current.onTap != nil || current.onPress != nil || current.onTapLocation != nil || current.onDrag != nil
                || current.onKey != nil || current.control != nil || current.onHover != nil { return true }
            if current === root { return false }
            v = current.parent
        }
        return false
    }

    /// Children by zIndex, then in order.
    var paintOrder: [WinView] {
        let kids = visibleChildren
        guard kids.contains(where: { $0.zIndex != 0 }) else { return kids }
        return kids.enumerated().sorted { a, b in
            a.element.zIndex == b.element.zIndex ? a.offset < b.offset : a.element.zIndex < b.element.zIndex
        }.map(\.element)
    }

    /// A point in the window, in this view's own coordinates.
    public func convertFromWindow(_ x: Double, _ y: Double) -> (Double, Double) {
        let f = windowFrame
        return (x - f.x, y - f.y)
    }
}

extension HorizontalAlignment {
    var winAlign: WinAlign {
        switch self {
        case .leading: return .start
        case .center: return .center
        case .trailing: return .end
        }
    }
}

extension VerticalAlignment {
    var winAlign: WinAlign {
        switch self {
        case .top: return .start
        case .center: return .center
        case .bottom, .lastTextBaseline: return .end
        }
    }
}

// MARK: - For the components

/// Shorthands the components use, as the Linux backend's GTK helpers.
@MainActor func winView(_ native: NativeView) -> WinView { WinView.from(native) }

/// A child that fills its parent: GTK's packFill.
@MainActor func winPackFill(_ child: NativeView, into parent: NativeView) {
    let c = WinView.from(child)
    c.halign = .fill
    c.valign = .fill
    WinView.from(parent).add(c)
}
#endif
