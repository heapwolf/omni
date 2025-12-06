#if os(macOS)
import AppKit

/// A sheet on macOS, drawn the way iOS draws one: inside the window, over a
/// dimmed backdrop, sliding up from the bottom. A click on the backdrop or
/// Esc closes it, unless the sheet disables interactive dismissal.
@MainActor final class SheetOverlay: NSView {
    static let duration = 0.3
    static let cornerRadius: CGFloat = 16

    private let backdrop = NSView()
    private let panel = NSView()
    private var content: NSView?
    private var panelHeight: CGFloat = 0
    private var isShown = false
    /// Asks the sheet's owner to close it.
    var onDismiss: () -> Void = {}
    /// Read when the backdrop is clicked or Esc is pressed.
    var isDismissable: () -> Bool = { true }

    override var isFlipped: Bool { true }

    init(content: NSView, height: CGFloat) {
        super.init(frame: .zero)
        autoresizingMask = [.width, .height]
        wantsLayer = true
        backdrop.wantsLayer = true
        backdrop.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.4).cgColor
        backdrop.alphaValue = 0
        addSubview(backdrop)
        panel.wantsLayer = true
        panel.layer?.cornerRadius = Self.cornerRadius
        panel.layer?.maskedCorners = [.layerMinXMaxYCorner, .layerMaxXMaxYCorner]
        panel.layer?.masksToBounds = true
        addSubview(panel)
        panelHeight = height
        setContent(content)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Shows `view` in the panel, in place of what was there.
    func setContent(_ view: NSView) {
        guard view !== content else { return }
        content?.removeFromSuperview()
        content = view
        view.translatesAutoresizingMaskIntoConstraints = false
        panel.addSubview(view)
        NSLayoutConstraint.activate([
            view.topAnchor.constraint(equalTo: panel.topAnchor),
            view.bottomAnchor.constraint(equalTo: panel.bottomAnchor),
            view.leadingAnchor.constraint(equalTo: panel.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: panel.trailingAnchor)
        ])
    }

    private func panelFrame(shown: Bool) -> NSRect {
        let height = min(panelHeight, bounds.height)
        return NSRect(x: 0, y: shown ? bounds.height - height : bounds.height, width: bounds.width, height: height)
    }

    override func layout() {
        super.layout()
        backdrop.frame = bounds
        panel.frame = panelFrame(shown: isShown)
    }

    /// Adds the overlay over `host` and slides the panel up.
    func present(over host: NSView) {
        frame = host.bounds
        host.addSubview(self)
        layoutSubtreeIfNeeded()
        panel.frame = panelFrame(shown: false)
        isShown = true
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.duration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            backdrop.animator().alphaValue = 1
            panel.animator().frame = panelFrame(shown: true)
        }
        window?.makeFirstResponder(self)
    }

    /// Slides the panel down and removes the overlay.
    func dismiss() {
        isShown = false
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = Self.duration
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            backdrop.animator().alphaValue = 0
            panel.animator().frame = panelFrame(shown: false)
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated { self?.removeFromSuperview() }
        })
    }

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if !panel.frame.contains(point), isDismissable() { onDismiss() }
    }

    /// Esc, from the overlay or any view in the panel.
    override func cancelOperation(_ sender: Any?) {
        if isDismissable() { onDismiss() }
    }

    /// Clicks on the backdrop stop here; the window under the sheet gets none.
    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        guard bounds.contains(local) else { return nil }
        return super.hitTest(point) ?? self
    }
}
#endif
