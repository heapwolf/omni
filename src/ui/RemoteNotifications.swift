// iOS hands an app its push device token only through its UIApplicationDelegate, which is
// OmniUI's (Core.swift's Del). The delegate passes it here; OmniPush (src/push) waits on it.

#if os(iOS)
import Foundation

public enum RemoteNotifications {
    /// The registration's outcome: the device token, or why there's none.
    public typealias Outcome = Result<Data, any Error>

    nonisolated(unsafe) private static var waiting: ((Outcome) -> Void)?
    private static let lock = NSLock()

    /// Called once with the next outcome. A newer wait replaces an older one.
    public static func next(_ handler: @escaping (Outcome) -> Void) {
        lock.withLock { waiting = handler }
    }

    /// From the app delegate.
    public static func finished(_ outcome: Outcome) {
        let handler = lock.withLock { () -> ((Outcome) -> Void)? in
            defer { waiting = nil }
            return waiting
        }
        handler?(outcome)
    }
}
#endif
