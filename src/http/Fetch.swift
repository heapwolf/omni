
import Foundation

public let defaultTransport: any Transport = HTTPClientTransport()

@discardableResult
public func fetch(_ request: Request, using transport: (any Transport)? = nil) async throws -> Response {
    FetchActivity.begin()
    defer { FetchActivity.end() }
    return try await (transport ?? defaultTransport).send(request)
}

/// How many fetches are under way, whatever their transport. For a test
/// driver waiting until the app is idle. Streams are not counted: one stays
/// open for as long as the app is.
public enum FetchActivity {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var count = 0

    public static var inFlight: Int {
        lock.lock(); defer { lock.unlock() }
        return count
    }

    static func begin() {
        lock.lock(); count += 1; lock.unlock()
    }

    static func end() {
        lock.lock(); count -= 1; lock.unlock()
    }
}

@discardableResult
public func fetch(_ url: URL, _ options: RequestInit = RequestInit(),
                  using transport: (any Transport)? = nil) async throws -> Response {
    try await fetch(Request(url: url, options: options), using: transport)
}

@discardableResult
public func fetch(_ url: String, _ options: RequestInit = RequestInit(),
                  using transport: (any Transport)? = nil) async throws -> Response {
    try await fetch(try Request(url, options: options), using: transport)
}
