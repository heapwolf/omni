import XCTest
@testable import OmniUI

@MainActor
private struct Wrapper: View {
    var body: some View { Text("x").transition(.push(from: .trailing)) }
}

// .transition and friends. The animation itself needs UIKit and is checked on
// the simulator; these hold what the engine reads.
final class TransitionTests: XCTestCase {

    func testPushComesInFromItsEdgeAndLeavesByTheOpposite() {
        let push = AnyTransition.push(from: .trailing)
        guard case .move(.trailing) = push.insertion, case .move(.leading) = push.removal else {
            return XCTFail("push(from: .trailing) should arrive from trailing and leave by leading")
        }
    }

    func testASymmetricTransitionIsTheSameBothWays() {
        guard case .opacity = AnyTransition.opacity.insertion, case .opacity = AnyTransition.opacity.removal else {
            return XCTFail("opacity is symmetric")
        }
    }

    // A body that is the carrier itself is unpacked into its view's node; the
    // transition must still be found there.
    func testATransitionReturnedFromBodyIsFound() {
        MainActor.assumeIsolated {
            let node = Node(Wrapper())
            Engine.render(node)
            guard case .move(.trailing)? = AnyTransition.on(node)?.insertion else {
                return XCTFail("the transition on Wrapper's body was not found")
            }
        }
    }

    func testTheSearchStopsAtTheFirstNativeView() {
        MainActor.assumeIsolated {
            let node = Node(VStack { Text("x").transition(.opacity) })
            Engine.render(node)
            XCTAssertNil(AnyTransition.on(node), "a transition inside a stack is not the stack's")
        }
    }
}
