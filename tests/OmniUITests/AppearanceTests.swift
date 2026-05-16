#if os(macOS) || os(iOS)
import XCTest
@testable import OmniUI

final class AppearanceTests: XCTestCase {
    override func tearDown() {
        MainActor.assumeIsolated { Appearance.prefer(nil) }
        super.tearDown()
    }

    func testAnAdaptiveColourResolvesToTheSchemeOnScreen() {
        MainActor.assumeIsolated {
            let color = Color(light: .white, dark: .black)

            Appearance.prefer(.light)
            XCTAssertEqual(Appearance.current, .light)
            XCTAssertEqual(color.rgbaComponents.r, 1)

            Appearance.prefer(.dark)
            XCTAssertEqual(Appearance.current, .dark)
            XCTAssertEqual(color.rgbaComponents.r, 0)
            XCTAssertEqual(EnvironmentValues().colorScheme, .dark)
        }
    }

    func testOpacityKeepsAnAdaptiveColourAdaptive() {
        MainActor.assumeIsolated {
            let faded = Color(light: .white, dark: .black).opacity(0.5)

            Appearance.prefer(.light)
            XCTAssertEqual(faded.rgbaComponents.r, 1)
            XCTAssertEqual(faded.rgbaComponents.a, 0.5)

            Appearance.prefer(.dark)
            XCTAssertEqual(faded.rgbaComponents.r, 0)
        }
    }
}
#endif
