import Foundation

public enum ScrollAxis {
    case vertical
    case horizontal
}

/// SwiftUI's axis type. ScrollView takes an Axis.Set; a set naming both axes
/// resolves to vertical here, which is the axis these backends can scroll.
public enum Axis: Sendable {
    case horizontal, vertical

    public struct Set: OptionSet, Sendable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }

        public static let horizontal = Set(rawValue: 1 << 0)
        public static let vertical = Set(rawValue: 1 << 1)

        var scrollAxis: ScrollAxis { self == .horizontal ? .horizontal : .vertical }
    }
}

/// SwiftUI's scrollTargetBehavior: where a scroll comes to rest.
public enum ScrollTargetBehavior: Sendable, Equatable {
    /// A page, the scroll view's own width (or height), at a time.
    case paging
}

/// Omni's: moves a paged scroll view from outside it (a drag along a tab
/// bar, say) straight on the native view, a frame at a time, rendering
/// nothing; letting go settles on a page, as a drag on the pages would.
/// Hold one in a view's state and give it to `.pageScrubber(_:)`. iOS; on
/// other platforms it does nothing.
@MainActor public final class PageScrubber {
    var onMove: ((Double) -> Void)?
    var onRelease: ((Double) -> Void)?
    var onGo: ((Int) -> Void)?

    public init() {}

    /// Moves the pages by `pages`: 0.5 is half the scroll view's width.
    public func move(by pages: Double) { onMove?(pages) }

    /// Lets go, at `velocity` pages a second: it settles on the nearest page,
    /// carried a little toward where it was going, and tells `.page`.
    public func release(velocity: Double = 0) { onRelease?(velocity) }

    /// Slides to `page` now, on the native view, and tells `.page` once it's
    /// there: a tap on a tab bar starts the move at once, rather than after
    /// the render that a changed page sets off.
    public func go(to page: Int) { onGo?(page) }
}

public struct ScrollView: NativeComponent {
    public var axis: ScrollAxis
    public var offset: Binding<Double>?
    /// Paged: rests a whole page at a time (iOS; elsewhere it scrolls freely).
    public var isPaging = false
    /// The page it rests on, told once it has settled, never mid-drag; set,
    /// it scrolls there. Paged scroll views only.
    public var page: Binding<Int>?
    public var scrubber: PageScrubber?
    /// Not moved by a drag or a wheel; set from code, it still scrolls (Apple).
    public var isScrollDisabled = false

    public var content: any View
    public var children: [any View] { Omni.unpackViews(content) }
    public var body: any View { self }

    public init(axis: ScrollAxis = .vertical, offset: Binding<Double>? = nil, @ViewBuilder _ content: @escaping () -> any View) {
        self.axis = axis
        self.offset = offset
        self.content = content()
    }

    /// SwiftUI's: `.scrollTargetBehavior(.paging)`.
    public func scrollTargetBehavior(_ behavior: ScrollTargetBehavior) -> ScrollView {
        var copy = self; copy.isPaging = behavior == .paging; return copy
    }

    /// Omni's: the page a paged scroll view rests on, two ways. The app hears
    /// of a page once a drag has settled on it, so a drag costs it nothing;
    /// a page set here is scrolled to, as the system animates it.
    public func page(_ binding: Binding<Int>) -> ScrollView {
        var copy = self; copy.page = binding; return copy
    }

    /// SwiftUI's `.scrollDisabled(_:)`: no drag moves it, and one goes on to
    /// what holds it. A pager held on a page while a flow covers its bar,
    /// rather than shortened to that page: a shorter pager slid to the new
    /// index, under the flow sliding in.
    public func scrollDisabled(_ disabled: Bool) -> ScrollView {
        var copy = self; copy.isScrollDisabled = disabled; return copy
    }

    /// Omni's: `scrubber` moves the pages from elsewhere; see PageScrubber.
    public func pageScrubber(_ scrubber: PageScrubber) -> ScrollView {
        var copy = self; copy.scrubber = scrubber; return copy
    }

    /// SwiftUI's spelling: `ScrollView(.horizontal) { ... }`. showsIndicators is
    /// accepted and ignored — no backend here exposes the toggle.
    public init(_ axes: Axis.Set = .vertical, showsIndicators: Bool = true,
                offset: Binding<Double>? = nil,
                @ViewBuilder _ content: @escaping () -> any View) {
        self.init(axis: axes.scrollAxis, offset: offset, content)
    }
}
