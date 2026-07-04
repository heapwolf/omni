
import Foundation

public final class AbortSignal: @unchecked Sendable {
    private let lock = NSLock()
    private var _aborted = false
    private var callbacks: [@Sendable () -> Void] = []

    public init() {}

    public var aborted: Bool {
        lock.lock(); defer { lock.unlock() }
        return _aborted
    }

    /// Fires immediately if already aborted, which is what makes a check-then-
    /// register sequence safe against a race.
    public func onAbort(_ callback: @escaping @Sendable () -> Void) {
        lock.lock()
        if _aborted {
            lock.unlock()
            callback()
            return
        }
        callbacks.append(callback)
        lock.unlock()
    }

    fileprivate func abort() {
        lock.lock()
        guard !_aborted else { lock.unlock(); return }
        _aborted = true
        let pending = callbacks
        callbacks = []
        lock.unlock()
        for callback in pending { callback() }
    }

    /// A signal already aborted, for tests and for cancelling before starting.
    public static func aborted() -> AbortSignal {
        let signal = AbortSignal()
        signal.abort()
        return signal
    }

    public static func timeout(_ seconds: TimeInterval) -> AbortSignal {
        let signal = AbortSignal()
        Task {
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            signal.abort()
        }
        return signal
    }
}

public final class AbortController: @unchecked Sendable {
    public let signal = AbortSignal()
    public init() {}
    public func abort() { signal.abort() }
}
