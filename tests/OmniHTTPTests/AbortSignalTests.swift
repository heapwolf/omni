import XCTest
@testable import OmniHTTP

/// https://dom.spec.whatwg.org/#interface-abortsignal
final class AbortSignalTests: XCTestCase {

    func testAFreshSignalIsNotAborted() {
        XCTAssertFalse(AbortSignal().aborted)
        XCTAssertFalse(AbortController().signal.aborted)
    }

    func testAbortFlipsTheFlagAndFiresOnce() {
        let controller = AbortController()
        let fired = Counter()
        controller.signal.onAbort { fired.increment() }

        controller.abort()
        XCTAssertTrue(controller.signal.aborted)
        XCTAssertEqual(fired.value, 1)

        controller.abort()
        XCTAssertEqual(fired.value, 1, "aborting twice must not fire twice")
    }

    func testRegisteringAfterTheAbortStillRuns() {
        let controller = AbortController()
        controller.abort()

        let fired = Counter()
        controller.signal.onAbort { fired.increment() }
        XCTAssertEqual(fired.value, 1, "a check-then-register sequence must not be able to miss")
    }

    func testEveryRegisteredCallbackRuns() {
        let controller = AbortController()
        let fired = Counter()
        for _ in 0..<5 { controller.signal.onAbort { fired.increment() } }
        controller.abort()
        XCTAssertEqual(fired.value, 5)
    }

    func testPreAbortedFactory() {
        XCTAssertTrue(AbortSignal.aborted().aborted)
    }

    func testTimeoutSignalAbortsOnItsOwn() async throws {
        let signal = AbortSignal.timeout(0.05)
        XCTAssertFalse(signal.aborted)
        try await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertTrue(signal.aborted)
    }

    func testConcurrentAbortsFireTheCallbackExactlyOnce() async {
        let controller = AbortController()
        let fired = Counter()
        controller.signal.onAbort { fired.increment() }

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<20 { group.addTask { controller.abort() } }
        }
        XCTAssertEqual(fired.value, 1, "twenty racing aborts must still fire one callback")
    }
}

/// A counter safe to touch from the callbacks, which may run on any thread.
final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    func increment() { lock.lock(); count += 1; lock.unlock() }
    var value: Int { lock.lock(); defer { lock.unlock() }; return count }
}
