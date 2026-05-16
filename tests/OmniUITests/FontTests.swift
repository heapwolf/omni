#if os(macOS)
import XCTest
import AppKit
import CoreText
@testable import OmniUI

// A registered family picks the face for each weight: the nearest of its static
// files, or a variable file's weight axis set exactly. The fixtures are Inter
// (OFL, Fixtures/Inter-LICENSE.txt) cut down to five glyphs.
final class FontTests: XCTestCase {

    private static let fixtures = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().appendingPathComponent("Fixtures")

    private static let weightAxis = 0x77676874 // 'wght'

    override class func setUp() {
        super.setUp()
        MainActor.assumeIsolated {
            for file in ["OmniTest-Regular.ttf", "OmniTest-Bold.ttf"] {
                XCTAssertTrue(Font.register(fixtures.appendingPathComponent(file).path, as: "TestStatic"))
            }
            XCTAssertTrue(Font.register(fixtures.appendingPathComponent("OmniTestVariable.ttf").path,
                                        as: "TestVariable"))
        }
    }

    @MainActor private static func postScriptName(_ font: Font) -> String? {
        font.registeredFace(size: 17).map { CTFontCopyPostScriptName($0) as String }
    }

    @MainActor private static func weightAxisValue(_ font: Font) -> Double? {
        guard let face = font.registeredFace(size: 17),
              let variation = CTFontCopyVariation(face) as? [NSNumber: NSNumber] else { return nil }
        return variation[NSNumber(value: Self.weightAxis)]?.doubleValue
    }

    func testAStaticFamilyPicksTheFaceForEachWeight() {
        MainActor.assumeIsolated {
            XCTAssertEqual(Self.postScriptName(.custom("TestStatic", size: 17)), "Inter-Regular")
            XCTAssertEqual(Self.postScriptName(.custom("TestStatic", size: 17, weight: .bold)), "Inter-Bold")
        }
    }

    func testAStaticFamilyFallsToTheNearestFace() {
        MainActor.assumeIsolated {
            // Semibold is nearer bold than regular, and light nearer regular.
            XCTAssertEqual(Self.postScriptName(.custom("TestStatic", size: 17, weight: .semibold)), "Inter-Bold")
            XCTAssertEqual(Self.postScriptName(.custom("TestStatic", size: 17, weight: .light)), "Inter-Regular")
        }
    }

    func testAVariableFamilySetsTheWeightAxisExactly() {
        MainActor.assumeIsolated {
            // Exact, not the nearest named instance: light is 300, not ExtraLight's 200.
            XCTAssertEqual(Self.weightAxisValue(.custom("TestVariable", size: 17, weight: .light)), 300)
            XCTAssertEqual(Self.weightAxisValue(.custom("TestVariable", size: 17, weight: .semibold)), 600)
            XCTAssertEqual(Self.weightAxisValue(.custom("TestVariable", size: 17, weight: .black)), 900)
        }
    }

    func testAnUnregisteredFamilyHasNoFace() {
        MainActor.assumeIsolated {
            XCTAssertNil(Font.custom("NeverRegistered", size: 17).registeredFace(size: 17))
            XCTAssertNil(Font.body.registeredFace(size: 17))
        }
    }

    func testTextIsSetInTheRegisteredFace() {
        MainActor.assumeIsolated {
            let node = Node(Text("iiii").font(.custom("TestVariable", size: 20, weight: .semibold)))
            Engine.render(node)
            guard let field = node.native as? NSTextField, let font = field.font else {
                return XCTFail("Text did not render as an NSTextField")
            }
            XCTAssertEqual(font.pointSize, 20)
            let variation = CTFontCopyVariation(font as CTFont) as? [NSNumber: NSNumber]
            XCTAssertEqual(variation?[NSNumber(value: Self.weightAxis)]?.doubleValue, 600)
        }
    }
}
#endif
