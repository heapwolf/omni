
import Foundation

/// What to do with a navigation the page is about to make.
public enum NavigationPolicy: Sendable, Equatable {
    case allow
    /// Stop the navigation; the app handled the URL.
    case cancel
}

// MARK: - The page

/// The observable half of a web view: what the page is doing, and how to drive
/// it. The screen owns one (`@StateObject`) and the `WebView` renders it.
@MainActor
public final class WebPage: OmniObservableObject {

    // All private(set): navigation goes through load(_:). A settable url would
    // race the page's own redirects.

    @Published public private(set) var url: URL?
    @Published public private(set) var title: String = ""
    @Published public private(set) var isLoading: Bool = false
    @Published public private(set) var estimatedProgress: Double = 0
    @Published public private(set) var canGoBack: Bool = false
    @Published public private(set) var canGoForward: Bool = false

    /// The platform's own words, or nil. Also where a backend reports that this
    /// machine has no web engine.
    @Published public private(set) var lastError: String?

    // Plain closures: assigning one is configuration and must not provoke a render.

    /// Consulted before every navigation. Runs on the main actor; return quickly.
    public var decidePolicy: ((URL) -> NavigationPolicy)?

    /// Receives window.omni.postMessage(value). Structured data should be JSON.
    public var onMessage: ((String) -> Void)?

    public init() {}

    // MARK: Driving it

    public func load(_ url: URL) { enqueue(.load(url)) }
    public func loadHTML(_ html: String, baseURL: URL? = nil) { enqueue(.loadHTML(html, baseURL)) }
    public func goBack() { enqueue(.goBack) }
    public func goForward() { enqueue(.goForward) }
    public func reload() { enqueue(.reload) }
    public func stop() { enqueue(.stop) }
    public func evaluateJavaScript(_ source: String) { enqueue(.evaluate(source)) }

    // MARK: The command queue

    enum Command {
        case load(URL)
        case loadHTML(String, URL?)
        case goBack
        case goForward
        case reload
        case stop
        case evaluate(String)
    }

    private var queue: [Command] = []

    /// Not @Published: a write from updateNative re-enters Engine.render.
    @Published private var revision: Int = 0

    private func enqueue(_ command: Command) {
        queue.append(command)

        guard Tracker.current == nil else { return }
        revision &+= 1
    }

    /// Call before any early return in updateNative, or the node observes nothing.
    func observe() {
        _ = revision
    }

    /// Drained by the backend from updateNative. Observes as a side effect.
    func drainCommands() -> [Command] {
        observe()
        defer { queue.removeAll() }
        return queue
    }

    // Equality-guarded: @Published notifies on every set.

    func report(url value: URL?) { if url != value { url = value } }
    func report(title value: String) { if title != value { title = value } }
    func report(isLoading value: Bool) { if isLoading != value { isLoading = value } }
    func report(progress value: Double) { if estimatedProgress != value { estimatedProgress = value } }
    func report(canGoBack value: Bool) { if canGoBack != value { canGoBack = value } }
    func report(canGoForward value: Bool) { if canGoForward != value { canGoForward = value } }
    func report(error value: String?) { if lastError != value { lastError = value } }

    /// Absent a decidePolicy, everything is allowed.
    func policy(for url: URL) -> NavigationPolicy {
        decidePolicy?(url) ?? .allow
    }

    func deliver(message: String) { onMessage?(message) }
}

// MARK: - The view

public struct WebView: NativeComponent {
    /// nil for the WebView(url:) form.
    let page: WebPage?
    let staticURL: URL?

    /// The screen owns the page.
    public init(_ page: WebPage) {
        self.page = page
        self.staticURL = nil
    }

    /// For a page with nothing to observe: terms, a help article.
    public init(url: URL) {
        self.page = nil
        self.staticURL = url
    }
}

// MARK: - Shared backend bookkeeping

/// Per-native-view state. Each backend keys its own registry by native view,
/// the way Canvas and TextField do.
@MainActor
final class WebViewBacking {
    /// Last URL actually loaded, so the static form loads once.
    var lastRequested: URL?
    var isApplyingReport = false

    init() {}
}
