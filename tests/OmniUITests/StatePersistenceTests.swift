#if os(Linux)
import XCTest
import Glibc
@testable import OmniUI


private let gtk_label_get_text_sp: @convention(c) (NativeView) -> UnsafePointer<CChar>? =
    fn(libgtk, "gtk_label_get_text")

@MainActor
private final class Model: ObservableObject {
    @Published var value = 0
    static var allocations = 0
    init() { Model.allocations += 1 }
}

@MainActor
private struct Child: View {
    @State var childCount = 0
    var body: some View { Text("child=\(childCount)") }
}

@MainActor
private struct Parent: View {
    @State var parentCount = 0
    var body: some View {
        VStack {
            Text("parent=\(parentCount)")
            Child()
        }
    }
}

@MainActor
private struct ModelHolder: View {
    @StateObject var model = Model()
    var body: some View { Text("value=\(model.value)") }
}

// ModelHolder must sit under a re-rendering parent: the root node's view is never
// replaced, so a root-level holder would never exercise adoption at all.
@MainActor
private struct ModelParent: View {
    @State var parentTick = 0
    var body: some View {
        VStack {
            Text("p=\(parentTick)")
            ModelHolder()
        }
    }
}

private func labelText(_ view: NativeView?) -> String? {
    guard let view, let cStr = gtk_label_get_text_sp(view) else { return nil }
    return String(cString: cStr)
}

final class StatePersistenceTests: XCTestCase {

    override func setUp() {
        super.setUp()
        gtk_init(nil, nil)
    }

    func testChildStateSurvivesAParentRerender() {
        MainActor.assumeIsolated {
            let parent = Parent()
            let node = Node(parent)
            Engine.render(node)

            // node.kids: [Text(parent=), Child]
            let childNode = node.kids[1]
            XCTAssertEqual(labelText(childNode.native), "child=0")

            // Advance the child's own state.
            guard let child = childNode.view as? Child else {
                return XCTFail("expected a Child view, got \(childNode.view.type)")
            }
            child.childCount = 7
            XCTAssertEqual(labelText(childNode.native), "child=7")

            // Now re-render the parent, which rebuilds Child() from scratch.
            parent.parentCount = 1
            XCTAssertEqual(labelText(node.kids[0].native), "parent=1")
            XCTAssertEqual(labelText(node.kids[1].native), "child=7",
                           "the parent's re-render reset the child's @State")
        }
    }

    func testStateObjectIsNotReallocatedOnRerender() {
        MainActor.assumeIsolated {
            Model.allocations = 0

            let parent = ModelParent()
            let node = Node(parent)
            Engine.render(node)
            XCTAssertEqual(Model.allocations, 1)

            guard let holder = node.kids[1].view as? ModelHolder else {
                return XCTFail("expected a ModelHolder, got \(node.kids[1].view.type)")
            }
            holder.model.value = 42
            XCTAssertEqual(labelText(node.kids[1].native), "value=42")

            // Rebuilds ModelHolder() from scratch.
            parent.parentTick = 1

            XCTAssertEqual(labelText(node.kids[1].native), "value=42",
                           "the view model was replaced on re-render")
            XCTAssertEqual(Model.allocations, 1,
                           "a second Model was allocated instead of adopting the first")
        }
    }
}
#endif
