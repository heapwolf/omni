import XCTest
@testable import OmniHTTP

/// https://fetch.spec.whatwg.org/#headers-class
final class HeadersTests: XCTestCase {

    // MARK: case-insensitivity

    func testNamesAreCaseInsensitiveOnEveryOperation() {
        var h = Headers()
        h.set("Content-Type", "application/json")
        XCTAssertEqual(h.get("content-type"), "application/json")
        XCTAssertEqual(h.get("CONTENT-TYPE"), "application/json")
        XCTAssertEqual(h.get("CoNtEnT-tYpE"), "application/json")
        XCTAssertTrue(h.has("Content-TYPE"))
        h.delete("CONTENT-TYPE")
        XCTAssertFalse(h.has("content-type"))
    }

    func testNamesAreStoredLowercasedForIteration() {
        var h = Headers()
        h.set("X-Request-ID", "abc")
        XCTAssertEqual(h.names, ["x-request-id"])
    }

    // MARK: multi-value

    func testAppendKeepsBothValuesAndGetCommaJoins() {
        var h = Headers()
        h.append("accept", "text/html")
        h.append("Accept", "application/json")
        XCTAssertEqual(h.get("accept"), "text/html, application/json",
                       "get must comma-join every value, not return the first")
    }

    func testAppendPreservesOrderWithinAName() {
        var h = Headers()
        for value in ["a", "b", "c"] { h.append("x", value) }
        XCTAssertEqual(h.get("x"), "a, b, c")
    }

    func testSetReplacesEveryValue() {
        var h = Headers()
        h.append("accept", "a")
        h.append("accept", "b")
        h.set("accept", "c")
        XCTAssertEqual(h.get("accept"), "c")
    }

    func testSetCookieSurvivesAsSeparateValues() {
        var h = Headers()
        h.append("Set-Cookie", "a=1; Path=/")
        h.append("set-cookie", "b=2; Path=/")
        XCTAssertEqual(h.getSetCookie(), ["a=1; Path=/", "b=2; Path=/"],
                       "comma-joining cookies would corrupt them — Expires contains a comma")
        XCTAssertEqual(h.getSetCookie().count, 2)
    }

    func testGetSetCookieIsEmptyWhenThereAreNone() {
        XCTAssertEqual(Headers().getSetCookie(), [])
    }

    // MARK: normalisation

    func testValuesAreTrimmedOfSurroundingWhitespace() {
        var h = Headers()
        h.set("x", "   spaced   ")
        XCTAssertEqual(h.get("x"), "spaced")
        h.append("y", "\ttabbed\t")
        XCTAssertEqual(h.get("y"), "tabbed")
    }

    func testInternalWhitespaceIsKept() {
        var h = Headers()
        h.set("x", "two words")
        XCTAssertEqual(h.get("x"), "two words")
    }

    func testIterationIsSortedByName() {
        var h = Headers()
        h.set("zeta", "1"); h.set("alpha", "2"); h.set("mid", "3")
        XCTAssertEqual(h.names, ["alpha", "mid", "zeta"])
        XCTAssertEqual(h.entries.map(\.name), ["alpha", "mid", "zeta"])
    }

    // MARK: absence

    func testMissingLookupsAreNilNotEmpty() {
        let h = Headers()
        XCTAssertNil(h.get("nothing"))
        XCTAssertFalse(h.has("nothing"))
        XCTAssertTrue(h.isEmpty)
        XCTAssertEqual(h.entries.count, 0)
    }

    func testDeletingSomethingAbsentIsHarmless() {
        var h = Headers(["a": "1"])
        h.delete("b")
        XCTAssertEqual(h.get("a"), "1")
    }

    // MARK: injection; the security-relevant part

    func testCarriageReturnInAValueIsRefused() {
        var h = Headers()
        h.set("x-evil", "value\r\nX-Injected: yes")
        XCTAssertNil(h.get("x-evil"), "CRLF in a value is a header injection")
    }

    func testBareNewlineAndNulInAValueAreRefused() {
        var h = Headers()
        h.set("a", "one\ntwo")
        h.set("b", "one\u{0}two")
        XCTAssertNil(h.get("a"))
        XCTAssertNil(h.get("b"))
    }

    func testNamesMustBeTokens() {
        var h = Headers()
        for bad in ["bad name", "colon:name", "semi;colon", "paren()", "", "quote\"name"] {
            h.set(bad, "v")
            XCTAssertNil(h.get(bad), "\(bad.debugDescription) is not a valid token")
        }
    }

    func testThrowingVariantReportsRatherThanSwallowing() {
        var h = Headers()
        XCTAssertThrowsError(try h.appendOrThrow("x", "a\r\nb"))
        XCTAssertThrowsError(try h.appendOrThrow("bad name", "v"))
        XCTAssertNoThrow(try h.appendOrThrow("x-fine", "value"))
    }

    // MARK: construction

    func testDictionaryLiteralAndInitAgree() {
        let literal: Headers = ["accept": "application/json"]
        let constructed = Headers(["accept": "application/json"])
        XCTAssertEqual(literal, constructed)
        XCTAssertEqual(literal.get("Accept"), "application/json")
    }

    func testSubscriptReadsWritesAndDeletes() {
        var h = Headers()
        h["Accept"] = "application/json"
        XCTAssertEqual(h["accept"], "application/json")
        h["accept"] = nil
        XCTAssertFalse(h.has("accept"))
    }

    func testFlattenedGivesOneValuePerName() {
        var h = Headers()
        h.append("accept", "a")
        h.append("accept", "b")
        XCTAssertEqual(h.flattened, ["accept": "a, b"])
    }

    func testEquatableIgnoresCaseAndInsertionOrder() {
        var a = Headers(); a.set("A", "1"); a.set("B", "2")
        var b = Headers(); b.set("b", "2"); b.set("a", "1")
        XCTAssertEqual(a, b)
    }

    func testValueIsACopyNotAReference() {
        let original = Headers(["a": "1"])
        var copy = original
        copy.set("a", "2")
        XCTAssertEqual(original.get("a"), "1", "Headers is a value type")
    }
}
