#if os(macOS) || os(iOS)
import XCTest
@testable import OmniUI

// A screen inside a sheet that swaps its step replaces the sheet's root
// native, and the sheet moves the two. The transitions are the changed
// node's: read down from the sheet's root, an outer screen's won (OneDosh's
// Profile, still "forward" from opening a PIN step), and going back from the
// step played forward.

@MainActor
private struct Steps: View {
    @State var isSecond = false
    @State var forward = true
    var body: some View {
        content.transition(.push(from: forward ? .trailing : .leading))
    }

    private var content: some View {
        if isSecond { return AnyView(Text("second")) }
        return AnyView(VStack { Text("first") })
    }
}

@MainActor
private struct Screen: View {
    var body: some View {
        // Forward, always: the outer screen's own step never changes here.
        Steps().transition(.push(from: .trailing))
    }
}

final class SheetTransitionTests: XCTestCase {
    func testASheetMovesAnInnerStepWithTheStepsOwnTransition() {
        MainActor.assumeIsolated {
            let root = Node(Screen())
            root.isDetachedRoot = true
            var seen: (removal: AnyTransition?, insertion: AnyTransition?)?
            root.onRootNativeChange = { _, removal, insertion in seen = (removal, insertion) }
            Engine.render(root)
            guard let steps = root.kids.first?.view as? Steps else {
                return XCTFail("expected Steps, got \(String(describing: root.kids.first?.view))")
            }

            // Back: the direction first, in a render of its own, then the step.
            steps.forward = false
            withAnimation(.easeInOut(duration: 0.3)) { steps.isSecond = true }

            guard let seen else { return XCTFail("the sheet was not told of its new native") }
            guard case .move(.leading)? = seen.insertion?.insertion else {
                return XCTFail("the new step should come in from the leading edge, going back")
            }
            guard case .move(.trailing)? = seen.removal?.removal else {
                return XCTFail("the old step should leave to the trailing edge, going back")
            }
            // What the sheet used to read: the outer screen's, forward.
            guard case .move(.trailing)? = AnyTransition.on(root)?.insertion else {
                return XCTFail("expected the outer screen's transition first down from the root")
            }
        }
    }
}
#endif
