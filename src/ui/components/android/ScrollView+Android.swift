#if os(Android)
import Foundation
import CAndroid

@MainActor private var scrollStateRegistry: [UnsafeMutableRawPointer: AndroidScrollState] = [:]

@MainActor private final class AndroidScrollState {
    let handler = EventHandlerFloat2 { _, _ in }
    let pageHandler = EventHandlerInt { _ in }
    let sizeHandler = EventHandlerFloat2 { _, _ in }
    let contentHandler = EventHandlerFloat2 { _, _ in }
    var lastReported: Double = 0

    /// onScrollGeometryChange: told after a scroll, and after a layout.
    var geometryObservers: [ScrollGeometryObserver] = []
    private var geometryValues: [Any?] = []
    var offset = CGPoint.zero
    var size = CGSize.zero
    var contentSize = CGSize.zero

    func reportGeometry() {
        guard !geometryObservers.isEmpty else { return }
        let geometry = ScrollGeometry(contentOffset: offset, contentSize: contentSize, containerSize: size)
        if geometryValues.count != geometryObservers.count {
            geometryValues = Array(repeating: nil, count: geometryObservers.count)
        }
        for (index, observer) in geometryObservers.enumerated() {
            geometryValues[index] = observer.evaluate(geometry, geometryValues[index])
        }
    }
}

extension ScrollView {
    @MainActor public func makeNative() -> NativeView {
        let env = OmniAndroid.env

        // omni's subclasses: paging, holding still, and their sizes.
        let className = axis == .horizontal ? "com/omni/OmniEventBridge$OmniHorizontalScrollView"
                                            : "com/omni/OmniEventBridge$OmniVerticalScrollView"
        let view = OmniAndroid.createView(env, className)

        // Remove scrollbars for cleaner UI (matching SwiftUI default behavior).
        // These setters take a boolean, so they need the (Z)V bridge.
        omni_jni_call_void_method_bool(
            env, view,
            axis == .horizontal ? "setHorizontalScrollBarEnabled" : "setVerticalScrollBarEnabled",
            0)

        // A scroll view takes the space it is offered rather than the space its
        // content happens to need, or everything after it is pushed off screen.
        AndroidExpansion.claim(view, horizontal: true, vertical: true)
        return view
    }

    @MainActor public func unmountNative(_ view: NativeView) {
        scrollStateRegistry.removeValue(forKey: view)
    }

    @MainActor public func updateNative(_ view: NativeView) {
        let env = OmniAndroid.env
        let currentOffset = offset
        let horizontal = axis == .horizontal

        let state: AndroidScrollState
        if let existing = scrollStateRegistry[view] {
            state = existing
        } else {
            state = AndroidScrollState()
            scrollStateRegistry[view] = state
            let ptr = UnsafeMutableRawPointer(Unmanaged.passUnretained(state.handler).toOpaque())
            omni_jni_attach_on_scroll_change(env, view, ptr)
            state.sizeHandler.action = { w, h in
                state.size = CGSize(width: Double(w), height: Double(h))
                state.reportGeometry()
            }
            state.contentHandler.action = { w, h in
                state.contentSize = CGSize(width: Double(w), height: Double(h))
                state.reportGeometry()
            }
            omni_jni_attach_scroll_sizes(env, view,
                UnsafeMutableRawPointer(Unmanaged.passUnretained(state.sizeHandler).toOpaque()),
                UnsafeMutableRawPointer(Unmanaged.passUnretained(state.contentHandler).toOpaque()))
        }

        // Applied to this ScrollView, so found on its own node's environment.
        state.geometryObservers = Tracker.current?.environment.scrollGeometryObservers ?? []

        state.handler.action = { x, y in
            state.offset = CGPoint(x: Double(x), y: Double(y))
            let value = Double(horizontal ? x : y)
            state.lastReported = value
            currentOffset?.wrappedValue = value
            state.reportGeometry()
        }

        // Paged, or held still: settled in Java as the finger lifts.
        let pageBinding = page
        state.pageHandler.action = { pageBinding?.wrappedValue = $0 }
        omni_jni_set_scroll_behavior(env, view, isPaging ? 1 : 0, isScrollDisabled ? 1 : 0,
                                     UnsafeMutableRawPointer(Unmanaged.passUnretained(state.pageHandler).toOpaque()))
        if isPaging, let shown = page?.wrappedValue { omni_jni_show_page(env, view, Int32(shown)) }
        if let scrubber {
            scrubber.onMove = { pages in omni_jni_scrub_pages(OmniAndroid.env, view, Float(pages)) }
            scrubber.onRelease = { velocity in omni_jni_release_scrub(OmniAndroid.env, view, Float(velocity)) }
            scrubber.onGo = { page in omni_jni_go_to_page(OmniAndroid.env, view, Int32(page)) }
        }

        if let target = currentOffset?.wrappedValue, abs(target - state.lastReported) > 1 {
            state.lastReported = target
            if horizontal {
                omni_jni_scroll_to(env, view, Int32(target), 0)
            } else {
                omni_jni_scroll_to(env, view, 0, Int32(target))
            }
        }
    }

}
#endif
