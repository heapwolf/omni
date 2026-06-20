
import Foundation

public enum FetchError: Error, Sendable, Equatable {
    /// The spec's "network error": DNS, connection refused, TLS failure, a
    /// reply that was not HTTP.
    case network(String)
    case timedOut
    /// The signal was aborted. The spec surfaces this as an AbortError.
    case aborted
    /// Malformed input; a bad URL, an illegal header. A programming error.
    case invalidArgument(String)
    /// `redirect: .error` and the server redirected.
    case redirectNotAllowed(to: String)
    /// The body was already read. Bodies are consumed once.
    case bodyAlreadyConsumed

    public var isRetryable: Bool {
        switch self {
        case .network, .timedOut: return true
        case .aborted, .invalidArgument, .redirectNotAllowed, .bodyAlreadyConsumed: return false
        }
    }
}
