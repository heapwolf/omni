#if os(macOS)
import XCTest
@testable import OmniUI

final class AppDirectoriesTests: XCTestCase {
    override func tearDown() {
        AppDirectories.override = nil
        super.tearDown()
    }

    /// The app's own folder in Application Support, never the shared root.
    /// Read, not created: a test must not write into the developer's Library.
    func testSupportIsTheAppsOwnFolder() {
        let support = AppDirectories.platformSupport
        let shared = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        XCTAssertEqual(support.deletingLastPathComponent().standardizedFileURL, shared.standardizedFileURL)
        XCTAssertEqual(support.lastPathComponent, AppDirectories.appIdentifier)
    }

    func testATestCanPointItElsewhere() {
        let elsewhere = FileManager.default.temporaryDirectory.appendingPathComponent("omni-\(UUID().uuidString)")
        AppDirectories.override = elsewhere
        XCTAssertEqual(AppDirectories.support, elsewhere)
        XCTAssertTrue(FileManager.default.fileExists(atPath: elsewhere.path), "not created on first use")
        try? FileManager.default.removeItem(at: elsewhere)
    }
}
#endif
