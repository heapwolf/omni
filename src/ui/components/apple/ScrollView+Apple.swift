#if os(macOS) || os(iOS)
import Foundation

#if os(macOS)
import AppKit

public class OmniScrollView: NSScrollView {
    var onScroll: ((Double) -> Void)?
    var axis: ScrollAxis = .vertical {
        didSet { if axis != oldValue, let doc = documentView { pin(doc) } }
    }
    var geometryObservers: [ScrollGeometryObserver] = []
    private var geometryValues: [Any?] = []

    /// onScrollGeometryChange: after a scroll, and after a layout that may
    /// have grown the content.
    func reportGeometry() {
        guard !geometryObservers.isEmpty else { return }
        let geometry = ScrollGeometry(contentOffset: contentView.bounds.origin,
                                      contentSize: documentView?.frame.size ?? .zero,
                                      containerSize: contentView.bounds.size)
        if geometryValues.count != geometryObservers.count {
            geometryValues = Array(repeating: nil, count: geometryObservers.count)
        }
        for (index, observer) in geometryObservers.enumerated() {
            geometryValues[index] = observer.evaluate(geometry, geometryValues[index])
        }
    }
    // deinit is always nonisolated and Any is not Sendable, but nothing else
    // holds a reference by then.
    nonisolated(unsafe) private var observer: Any?

    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        self.hasVerticalScroller = true
        self.hasHorizontalScroller = true
        self.autohidesScrollers = true
        // Clear, as SwiftUI's is: AppKit's paints white over whatever the
        // scroll view sits on, so a page's background never showed.
        self.drawsBackground = false
        self.contentView.postsBoundsChangedNotifications = true

        self.observer = NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification, object: self.contentView, queue: .main) { [weak self] _ in
            // The closure is typed @Sendable: NotificationCenter cannot tell from the
            // signature that queue: .main makes every call main-actor isolated.
            MainActor.assumeIsolated {
                guard let self else { return }
                let val = self.axis == .horizontal ? self.contentView.bounds.origin.x : self.contentView.bounds.origin.y
                self.onScroll?(Double(val))
                self.reportGeometry()
            }
        }
    }
    required init?(coder: NSCoder) { fatalError() }
    deinit {
        if let obs = observer { NotificationCenter.default.removeObserver(obs) }
        if let frameObserver { NotificationCenter.default.removeObserver(frameObserver) }
    }

    /// The content, pinned to the clip view by constraints (`pin(_:)`): the
    /// window's layout engine sizes it with everything else, a little at a
    /// time. It was measured with `fittingSize` on every layout, a solve of
    /// the whole page on a temporary engine: a 300-row page took ~900 ms a
    /// step of a live resize.
    private weak var pinned: NSView?
    private var pins: [NSLayoutConstraint] = []

    func pin(_ doc: NSView) {
        NSLayoutConstraint.deactivate(pins)
        doc.translatesAutoresizingMaskIntoConstraints = false
        let clip = contentView
        // As small as the content allows along the scrolling axis, as
        // fittingSize measured it (its compression is this priority too).
        let natural = axis == .vertical ? doc.heightAnchor.constraint(equalToConstant: 0)
                                        : doc.widthAnchor.constraint(equalToConstant: 0)
        natural.priority = .fittingSizeCompression
        pins = [doc.topAnchor.constraint(equalTo: clip.topAnchor),
                doc.leadingAnchor.constraint(equalTo: clip.leadingAnchor), natural]
        if axis == .vertical {
            // As wide as the view, as on iOS, so text wraps rather than
            // widening the page. (It took its widest line's width, and a long
            // address made a phone-width window scroll sideways.)
            pins.append(doc.widthAnchor.constraint(equalTo: clip.widthAnchor))
        } else {
            // At least as tall as the view.
            pins.append(doc.heightAnchor.constraint(greaterThanOrEqualTo: clip.heightAnchor))
        }
        NSLayoutConstraint.activate(pins)
        pinned = doc
        // Its frame is set after this view's layout, when the clip view's
        // runs: the geometry is reported then, with the size it now has.
        if let frameObserver { NotificationCenter.default.removeObserver(frameObserver) }
        doc.postsFrameChangedNotifications = true
        frameObserver = NotificationCenter.default.addObserver(forName: NSView.frameDidChangeNotification, object: doc,
                                                               queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.reportGeometry() }
        }
    }
    nonisolated(unsafe) private var frameObserver: Any?

    public override func layout() {
        if let doc = documentView, doc !== pinned { pin(doc) }
        super.layout()
        if let page = pendingPage { show(page: page) }
        reportGeometry()
    }

    /// Paged: the page shown, and one asked for before there was a width to
    /// scroll it by. No paging of AppKit's own, so no drag settles on one:
    /// the page a binding names is shown, as iOS starts on it. A pager that
    /// opened on its second page showed its first.
    var shownPage: Int?
    var pendingPage: Int?
    /// .scrollDisabled(): a wheel or trackpad goes on to what holds it.
    var isScrollDisabled = false

    public override func scrollWheel(with event: NSEvent) {
        if isScrollDisabled { nextResponder?.scrollWheel(with: event) } else { super.scrollWheel(with: event) }
    }

    func show(page: Int) {
        let length = axis == .horizontal ? contentView.bounds.width : contentView.bounds.height
        guard length > 0 else { pendingPage = page; return }
        pendingPage = nil
        guard shownPage != page else { return }
        shownPage = page
        let offset = CGFloat(page) * length
        contentView.scroll(to: axis == .horizontal ? NSPoint(x: offset, y: 0) : NSPoint(x: 0, y: offset))
        reflectScrolledClipView(contentView)
    }
}
#elseif os(iOS)
import UIKit

public class OmniScrollView: UIScrollView, UIScrollViewDelegate {
    var onScroll: ((Double) -> Void)?
    /// Paged: the page a scroll settled on, and the one last shown.
    var onPageSettled: ((Int) -> Void)?
    var shownPage: Int?
    /// A page asked for before there was a width to scroll it by.
    var pendingPage: Int?
    var axis: ScrollAxis = .vertical
    var geometryObservers: [ScrollGeometryObserver] = []
    private var geometryValues: [Any?] = []
    var refreshAction: RefreshAction? {
        didSet { updateRefreshControl() }
    }

    /// onScrollGeometryChange: after a scroll, and after a layout that may
    /// have grown the content.
    func reportGeometry() {
        guard !geometryObservers.isEmpty else { return }
        let geometry = ScrollGeometry(contentOffset: contentOffset, contentSize: contentSize,
                                      containerSize: bounds.size)
        if geometryValues.count != geometryObservers.count {
            geometryValues = Array(repeating: nil, count: geometryObservers.count)
        }
        for (index, observer) in geometryObservers.enumerated() {
            geometryValues[index] = observer.evaluate(geometry, geometryValues[index])
        }
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        updateSheetBleed()
        if let page = pendingPage, bounds.width > 0 {
            pendingPage = nil
            contentOffset = pageOffset(page)
            shownPage = page
        }
        reportGeometry()
    }

    // MARK: Under a sheet's foot

    /// How far past its bottom it draws: in a sheet, to the sheet's edge.
    private var sheetBleed: CGFloat = 0
    private let bleedMask = CAGradientLayer()
    /// How far the top fades, once scrolled: what passes under a sheet's
    /// header goes softly, not cut along a line.
    private static let topFade: CGFloat = 24

    /// A vertical scroll view whose foot is a sheet's bottom safe area runs
    /// on under it, as a sheet's list does in UIKit and SwiftUI: its content
    /// drawn to the sheet's edge, and inset by as much so the last of it
    /// still scrolls clear. Left at the safe area, content was cut along a
    /// line above an empty band. Its top fades under the header as it scrolls.
    private func updateSheetBleed() {
        var next: CGFloat = 0
        if axis == .vertical, let host = sheetHost, let superview {
            let foot = superview.convert(frame, to: host).maxY
            let room = host.bounds.height - foot
            // At the safe area, give or take the screen's own bottom padding.
            if room > 0, room <= host.safeAreaInsets.bottom + 24 { next = room }
        }
        if next != sheetBleed {
            contentInset.bottom += next - sheetBleed
            verticalScrollIndicatorInsets.bottom += next - sheetBleed
            sheetBleed = next
        }
        if sheetBleed > 0 {
            clipsToBounds = false
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            let height = bounds.height + sheetBleed
            // Faded in as it scrolls: at rest the first row is whole.
            let fade = min(max(contentOffset.y, 0), Self.topFade) / max(height, 1)
            bleedMask.colors = [UIColor.black.withAlphaComponent(fade > 0 ? 0 : 1).cgColor,
                                UIColor.black.cgColor, UIColor.black.cgColor]
            bleedMask.locations = [0, NSNumber(value: Double(fade)), 1]
            // In the layer's own space, which moves with the scroll.
            bleedMask.frame = CGRect(x: bounds.minX, y: bounds.minY, width: bounds.width, height: height)
            CATransaction.commit()
            if layer.mask !== bleedMask { layer.mask = bleedMask }
        } else if layer.mask === bleedMask {
            layer.mask = nil
            clipsToBounds = true
        }
    }

    /// The view of the sheet this is in, if it's in one.
    private var sheetHost: UIView? {
        var responder: UIResponder? = next
        while let current = responder {
            if let controller = current as? UIViewController {
                return controller.presentingViewController != nil && controller.sheetPresentationController != nil
                    ? controller.view : nil
            }
            responder = current.next
        }
        return nil
    }

    func pageOffset(_ page: Int) -> CGPoint {
        axis == .horizontal ? CGPoint(x: CGFloat(page) * bounds.width, y: 0)
                            : CGPoint(x: 0, y: CGFloat(page) * bounds.height)
    }

    /// Shows `page`: at once the first time, then sliding into place. Moved
    /// a frame at a time: setContentOffset(_:animated:) was over in a tenth
    /// of a second, and an animation in UIView.animate was undone by the
    /// render that follows a page change. The clock starts at the first
    /// frame: that render holds the main thread for a moment, and the slide
    /// was most of the way there when it first drew.
    func show(page: Int) {
        guard shownPage != page else { return }
        guard bounds.width > 0 else { pendingPage = page; return }
        let isFirst = shownPage == nil
        shownPage = page
        if isFirst {
            contentOffset = pageOffset(page)
            return
        }
        startSlide(to: pageOffset(page))
    }

    /// `commit`: the page to tell `.page` of once the slide has landed.
    private func startSlide(to target: CGPoint, commit: Int? = nil) {
        slide = Slide(from: contentOffset, to: target, commit: commit)
        if slideLink == nil {
            let link = CADisplayLink(target: self, selector: #selector(stepSlide))
            link.add(to: .main, forMode: .common)
            slideLink = link
        }
    }

    private struct Slide {
        let from: CGPoint
        let to: CGPoint
        var commit: Int?
        var start: CFTimeInterval?
    }

    private static let slideDuration: CFTimeInterval = 0.35
    private var slide: Slide?
    private var slideLink: CADisplayLink?

    @objc private func stepSlide() {
        guard let slide else { return stopSlide() }
        let now = CACurrentMediaTime()
        guard let start = slide.start else {
            self.slide?.start = now
            return
        }
        let t = min((now - start) / Self.slideDuration, 1)
        // Ease out: quick away, settling gently.
        let eased = 1 - pow(1 - t, 3)
        contentOffset = CGPoint(x: slide.from.x + (slide.to.x - slide.from.x) * eased,
                                y: slide.from.y + (slide.to.y - slide.from.y) * eased)
        if t >= 1 {
            stopSlide()
            if let page = slide.commit, page != shownPage {
                shownPage = page
                onPageSettled?(page)
            }
        }
    }

    private func stopSlide() {
        slide = nil
        slideLink?.invalidate()
        slideLink = nil
    }

    /// PageScrubber: the pages moved from outside, under a finger elsewhere.
    func scrub(by pages: Double) {
        stopSlide()
        let length = axis == .horizontal ? bounds.width : bounds.height
        guard length > 0 else { return }
        let content = axis == .horizontal ? contentSize.width : contentSize.height
        let farthest = max(content - length, 0)
        let current = axis == .horizontal ? contentOffset.x : contentOffset.y
        let next = min(max(current + CGFloat(pages) * length, 0), farthest)
        contentOffset = axis == .horizontal ? CGPoint(x: next, y: 0) : CGPoint(x: 0, y: next)
    }

    /// PageScrubber let go: the nearest page, a fifth of a second's travel
    /// on, slid to, and told as a drag's page is: once it's there. Told at
    /// once, the app's render for the new page held the slide's first frames,
    /// and it paused before it went.
    func releaseScrub(velocity: Double) {
        let length = axis == .horizontal ? bounds.width : bounds.height
        guard length > 0 else { return }
        let content = axis == .horizontal ? contentSize.width : contentSize.height
        let last = max(Int((content / length).rounded()) - 1, 0)
        let current = Double(axis == .horizontal ? contentOffset.x : contentOffset.y) / Double(length)
        let page = min(max(Int((current + velocity * 0.2).rounded()), 0), last)
        startSlide(to: pageOffset(page), commit: page)
    }

    /// PageScrubber.go: slid to at once, and told once it's there.
    func goNow(to page: Int) {
        guard bounds.width > 0 else { return }
        startSlide(to: pageOffset(page), commit: page)
    }

    /// A finger takes over from a slide.
    public func scrollViewWillBeginDragging(_ scrollView: UIScrollView) { stopSlide() }

    private func settled() {
        guard isPagingEnabled else { return }
        let length = axis == .horizontal ? bounds.width : bounds.height
        guard length > 0 else { return }
        let offset = axis == .horizontal ? contentOffset.x : contentOffset.y
        let page = Int((offset / length).rounded())
        guard page != shownPage else { return }
        shownPage = page
        onPageSettled?(page)
    }

    public func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) { settled() }

    public func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        if !decelerate { settled() }
    }

    /// refreshable: a UIRefreshControl while there is an action.
    private func updateRefreshControl() {
        if refreshAction == nil {
            refreshControl = nil
        } else if refreshControl == nil {
            let control = UIRefreshControl()
            control.addTarget(self, action: #selector(pulled), for: .valueChanged)
            refreshControl = control
        }
    }

    @objc private func pulled() {
        guard let refreshAction else { refreshControl?.endRefreshing(); return }
        Task { @MainActor [weak self] in
            await refreshAction()
            self?.refreshControl?.endRefreshing()
        }
    }

    public override init(frame: CGRect) {
        super.init(frame: frame)
        self.delegate = self

        // Disables the touch delay, which crashes on first tap on iOS 17-27.
        self.delaysContentTouches = false
    }
    required init?(coder: NSCoder) { fatalError() }

    public func scrollViewDidScroll(_ scrollView: UIScrollView) {
        let val = self.axis == .horizontal ? scrollView.contentOffset.x : scrollView.contentOffset.y
        onScroll?(Double(val))
        reportGeometry()
    }
}
#endif

extension ScrollView {
    @MainActor public func makeNative() -> NativeView {
        let sv = OmniScrollView()
        sv.axis = axis
        sv.translatesAutoresizingMaskIntoConstraints = false

        sv.setContentHuggingPriority(.init(rawValue: 1), for: .horizontal)
        sv.setContentHuggingPriority(.init(rawValue: 1), for: .vertical)

        #if os(iOS)
        // Matches plain SwiftUI's own default: dragging the scroll view
        // dismisses an active keyboard interactively, tracking the drag.
        sv.keyboardDismissMode = .interactive
        // No inset of UIKit's own: a scroll view laid under the status bar or
        // home indicator (.ignoresSafeArea) runs its content where it is put,
        // as on Android, rather than gaining the safe area again on top of
        // any room the content leaves itself. Inside the safe area, nothing
        // changes: there is no overlap to adjust for.
        sv.contentInsetAdjustmentBehavior = .never
        #endif

        return sv
    }

    @MainActor public func updateNative(_ view: NativeView) {
        let currentOffset = offset
        // Applied to this ScrollView, so found on its own node's environment.
        let environment = Tracker.current?.environment ?? EnvironmentValues()
        if let sv = view as? OmniScrollView {
            sv.geometryObservers = environment.scrollGeometryObservers
            #if os(iOS)
            sv.refreshAction = environment.refresh
            #endif
        }

        #if os(macOS)
        if let sv = view as? OmniScrollView {
            // Re-rendered, so its content may have grown or shrunk: the
            // document is sized in layout(), which nothing else would call
            // again, and stale it squeezes everything to the old height.
            sv.needsLayout = true
            sv.onScroll = { val in
                currentOffset?.wrappedValue = val
            }
            if let page { sv.show(page: page.wrappedValue) }
            sv.isScrollDisabled = isScrollDisabled

            // TWO-WAY BINDING
            if let target = currentOffset?.wrappedValue {
                let current = sv.axis == .horizontal ? sv.contentView.bounds.origin.x : sv.contentView.bounds.origin.y
                if abs(Double(current) - target) > 0.5 {
                    let newPoint = sv.axis == .horizontal ? NSPoint(x: target, y: 0) : NSPoint(x: 0, y: target)
                    sv.contentView.scroll(to: newPoint)
                    sv.reflectScrolledClipView(sv.contentView)
                }
            }
        }
        #elseif os(iOS)
        if let sv = view as? OmniScrollView {
            if sv.isScrollEnabled == isScrollDisabled { sv.isScrollEnabled = !isScrollDisabled }
            if sv.isPagingEnabled != isPaging {
                sv.isPagingEnabled = isPaging
                sv.showsHorizontalScrollIndicator = !isPaging
            }
            if let page {
                sv.onPageSettled = { page.wrappedValue = $0 }
                sv.show(page: page.wrappedValue)
            }
            if let scrubber {
                scrubber.onMove = { [weak sv] pages in sv?.scrub(by: pages) }
                scrubber.onRelease = { [weak sv] velocity in sv?.releaseScrub(velocity: velocity) }
                scrubber.onGo = { [weak sv] page in sv?.goNow(to: page) }
            }
            sv.onScroll = { val in
                currentOffset?.wrappedValue = val
            }
            if let target = currentOffset?.wrappedValue {
                let current = sv.axis == .horizontal ? sv.contentOffset.x : sv.contentOffset.y
                if abs(Double(current) - target) > 0.5 {
                    let newPoint = sv.axis == .horizontal ? CGPoint(x: target, y: 0) : CGPoint(x: 0, y: target)
                    sv.setContentOffset(newPoint, animated: false)
                }
            }
        }
        #endif
    }

    @MainActor public func insertChild(_ child: NativeView, into parent: NativeView) {
        #if os(macOS)
        if let sv = parent as? NSScrollView {
            sv.documentView = child
            (sv as? OmniScrollView)?.pin(child)
            sv.needsLayout = true
        }
        #elseif os(iOS)
        parent.addSubview(child)
        if let sv = parent as? UIScrollView {
            NSLayoutConstraint.activate([
                child.topAnchor.constraint(equalTo: sv.contentLayoutGuide.topAnchor),
                child.bottomAnchor.constraint(equalTo: sv.contentLayoutGuide.bottomAnchor),
                child.leadingAnchor.constraint(equalTo: sv.contentLayoutGuide.leadingAnchor),
                child.trailingAnchor.constraint(equalTo: sv.contentLayoutGuide.trailingAnchor)
            ])

            NSLayoutConstraint.activate([
                axis == .horizontal
                    ? child.heightAnchor.constraint(equalTo: sv.frameLayoutGuide.heightAnchor)
                    : child.widthAnchor.constraint(equalTo: sv.frameLayoutGuide.widthAnchor)
            ])

        }
        #endif
    }
}
#endif
