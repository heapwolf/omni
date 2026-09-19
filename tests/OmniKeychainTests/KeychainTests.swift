import XCTest
import Foundation
@testable import OmniKeychain

#if os(Linux)
final class FileKeychainStoreTests: XCTestCase {
    private var store: FileKeychainStore!
    private var directory: URL!

    override func setUp() {
        super.setUp()
        directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("omni-keychain-\(UUID().uuidString)")
        store = FileKeychainStore(directory: directory)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        super.tearDown()
    }

    func testRoundTrip() throws {
        try store.set(Data("token".utf8), for: "auth", accessibility: .whenUnlocked)
        XCTAssertEqual(try store.get("auth"), Data("token".utf8))
    }

    func testAbsentKeyIsNilNotAnError() throws {
        XCTAssertNil(try store.get("never-written"))
    }

    func testSetReplaces() throws {
        try store.setString("first", for: "k")
        try store.setString("second", for: "k")
        XCTAssertEqual(try store.getString("k"), "second")
    }

    func testDeleteRemoves() throws {
        try store.setString("v", for: "k")
        try store.delete("k")
        XCTAssertNil(try store.get("k"))
    }

    /// The distinction the protocol promises: get returns nil for absent,
    /// delete throws. A caller can tell a no-op from a success.
    func testDeleteOfAbsentKeyThrowsNotFound() throws {
        XCTAssertThrowsError(try store.delete("never-written")) { error in
            XCTAssertEqual(error as? KeychainError, .notFound)
        }
    }

    func testEmptyValueIsStoredAndIsNotAbsence() throws {
        try store.set(Data(), for: "empty", accessibility: .whenUnlocked)
        XCTAssertEqual(try store.get("empty"), Data())
    }

    func testStringConvenienceRoundTripsUTF8() throws {
        try store.setString("héllo — 世界", for: "unicode")
        XCTAssertEqual(try store.getString("unicode"), "héllo — 世界")
    }

    /// Keys become filenames, so a traversal attempt must not escape.
    func testKeyWithPathSeparatorsCannotEscapeTheDirectory() throws {
        try store.setString("v", for: "../../escaped")
        let contents = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        XCTAssertEqual(contents.count, 1)
        XCTAssertFalse(contents[0].contains("."))
        XCTAssertEqual(try store.getString("../../escaped"), "v")
    }

    func testFileIsOwnerReadableOnly() throws {
        try store.setString("secret", for: "k")
        let file = try FileManager.default.contentsOfDirectory(atPath: directory.path)[0]
        let attributes = try FileManager.default.attributesOfItem(
            atPath: directory.appendingPathComponent(file).path)
        XCTAssertEqual(attributes[.posixPermissions] as? NSNumber, 0o600)
    }

    func testDistinctKeysDoNotCollide() throws {
        for i in 0..<50 { try store.setString("value-\(i)", for: "key-\(i)") }
        for i in 0..<50 { XCTAssertEqual(try store.getString("key-\(i)"), "value-\(i)") }
    }
}
#endif
