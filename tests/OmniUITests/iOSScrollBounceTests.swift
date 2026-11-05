#if os(iOS)
import XCTest
import UIKit
@testable import OmniUI

// SwiftUI's ScrollView bounces along its axis even when its content fits, so
// a short refreshable list can still be pulled down. UIKit's doesn't unless
// told to.

final class iOSScrollBounceTests: XCTestCase {

    @MainActor private func scrollView(_ axis: ScrollAxis, in view: some View) -> OmniScrollView? {
        let node = Node(view)
        Engine.render(node)
        func find(_ v: UIView) -> OmniScrollView? {
            if let sv = v as? OmniScrollView, sv.axis == axis { return sv }
            for sub in v.subviews { if let found = find(sub) { return found } }
            return nil
        }
        return node.native.flatMap(find)
    }

    @MainActor func testAVerticalScrollViewBouncesVerticallyEvenWhenItsContentFits() {
        guard let sv = scrollView(.vertical, in: ScrollView { Text("short") }) else {
            return XCTFail("no vertical scroll view rendered")
        }
        XCTAssertTrue(sv.alwaysBounceVertical)
        XCTAssertFalse(sv.alwaysBounceHorizontal)
    }

    @MainActor func testAHorizontalScrollViewBouncesHorizontallyOnly() {
        guard let sv = scrollView(.horizontal, in: ScrollView(.horizontal) { Text("short") }) else {
            return XCTFail("no horizontal scroll view rendered")
        }
        XCTAssertTrue(sv.alwaysBounceHorizontal)
        XCTAssertFalse(sv.alwaysBounceVertical)
    }
}
#endif
