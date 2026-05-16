import XCTest
@testable import OmniUI

// The runtime half of omni.json's `flags`. The CLI writes OmniFlags.json with
// JSONSerialization; these read what it writes.
final class FlagsTests: XCTestCase {

    func testParseKeepsEachScalarsType() {
        let json = Data(#"{"api":"mock","verbose":true,"retries":3,"ratio":0.5}"#.utf8)
        XCTAssertEqual(Flags.parse(json), [
            "api": .string("mock"),
            "verbose": .bool(true),
            "retries": .number(3),
            "ratio": .number(0.5)
        ])
    }

    // A JSON 1 must not read as true, nor true as 1.
    func testBooleansAndNumbersStayApart() {
        let parsed = Flags.parse(Data(#"{"one":1,"yes":true}"#.utf8))
        XCTAssertEqual(parsed["one"], .number(1))
        XCTAssertEqual(parsed["yes"], .bool(true))
    }

    func testAMalformedFileSetsNothing() {
        XCTAssertEqual(Flags.parse(Data("not json".utf8)), [:])
        XCTAssertEqual(Flags.parse(Data("[1,2]".utf8)), [:])
    }

    // --flag always produces strings, so the accessors read them as asked.
    func testStringsCoerceWhereABoolOrNumberIsAskedFor() {
        XCTAssertEqual(FlagValue.string("true").boolean, true)
        XCTAssertEqual(FlagValue.string("false").boolean, false)
        XCTAssertNil(FlagValue.string("yes").boolean)
        XCTAssertEqual(FlagValue.string("3").integer, 3)
        XCTAssertNil(FlagValue.string("3.5").integer)
    }

    func testTextOfEachKind() {
        XCTAssertEqual(FlagValue.number(3).text, "3")
        XCTAssertEqual(FlagValue.number(0.5).text, "0.5")
        XCTAssertEqual(FlagValue.bool(false).text, "false")
        XCTAssertEqual(FlagValue.string("0012").text, "0012")
    }

    func testLaunchOverridesInBothSpellings() {
        let pairs = Flags.launchOverrides([
            "/path/App", "--omni-flag", "api=live", "--other", "--omni-flag=apiBase=http://x/?a=b"
        ])
        XCTAssertEqual(pairs.map(\.0), ["api", "apiBase"])
        XCTAssertEqual(pairs.map(\.1), ["live", "http://x/?a=b"])
    }

    func testMalformedLaunchOverridesAreIgnored() {
        XCTAssertTrue(Flags.launchOverrides(["--omni-flag", "novalue", "--omni-flag"]).isEmpty)
    }
}
