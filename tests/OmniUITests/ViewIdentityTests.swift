import XCTest
@testable import OmniUI

final class ViewIdentityTests: XCTestCase {

    // Core.swift; `var id: AnyHashable { AnyHashable(type) }`
    func testBareViewIdentityIsStillTheTypeName() {
        MainActor.assumeIsolated {
            XCTAssertEqual(Text("Alpha").id, AnyHashable("Text"))
            XCTAssertEqual(Text("Alpha").id, Text("Beta").id)
        }
    }

    func testForEachGivesEachRowItsOwnIdentity() {
        MainActor.assumeIsolated {
            let rows = ForEach(0..<5) { Text("Row \($0)") }.unpacked

            XCTAssertEqual(rows.count, 5)
            XCTAssertEqual(Set(rows.map(\.id)).count, 5,
                           "each row must be distinguishable from its siblings")
        }
    }

    // The wrapper must not disguise what the caller wrote, because the
    // reconciler compares type as well as id.
    func testIdentifiedRowsReportTheWrappedViewsType() {
        MainActor.assumeIsolated {
            let rows = ForEach(0..<3) { Text("Row \($0)") }.unpacked
            XCTAssertEqual(rows.map(\.type), ["Text", "Text", "Text"])
        }
    }

    // Omni.unpackViews flattens structural views; IdentifiedView has to survive
    // it or the identity never reaches the engine.
    func testUnpackingPreservesRowIdentity() {
        MainActor.assumeIsolated {
            let flattened = Omni.unpackViews(ForEach(0..<4) { Text("Row \($0)") })

            XCTAssertEqual(flattened.count, 4)
            XCTAssertEqual(Set(flattened.map(\.id)).count, 4,
                           "unpackViews discarded the IdentifiedView wrappers")
        }
    }

    // With an explicit id, identity tracks the item. Reversing the data must
    // therefore be visible to the reconciler, which compares pairwise.
    func testKeyedReorderIsVisibleToTheReconciler() {
        MainActor.assumeIsolated {
            struct Row { let key: String }
            let forward = ForEach([Row(key: "a"), Row(key: "b"), Row(key: "c")], id: \.key) {
                Text($0.key)
            }.unpacked
            let reversed = ForEach([Row(key: "c"), Row(key: "b"), Row(key: "a")], id: \.key) {
                Text($0.key)
            }.unpacked

            XCTAssertEqual(forward.map(\.id), [AnyHashable("a"), AnyHashable("b"), AnyHashable("c")])
            let reconcilerSeesAChange = zip(forward, reversed).contains {
                $0.type != $1.type || $0.id != $1.id
            }
            XCTAssertTrue(reconcilerSeesAChange,
                          "a keyed reversal must not look identical to the reconciler")
        }
    }

    func testUnkeyedReorderLooksUnchanged() {
        MainActor.assumeIsolated {
            let forward = ForEach(["a", "b", "c"]) { Text($0) }.unpacked
            let reversed = ForEach(["c", "b", "a"]) { Text($0) }.unpacked

            XCTAssertEqual(forward.map(\.id), [AnyHashable(0), AnyHashable(1), AnyHashable(2)])
            let reconcilerSeesAChange = zip(forward, reversed).contains {
                $0.type != $1.type || $0.id != $1.id
            }
            XCTAssertFalse(reconcilerSeesAChange)
        }
    }
}
