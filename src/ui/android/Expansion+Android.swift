// src/lib/android/Expansion+Android.swift
#if os(Android)
import Foundation
import CAndroid

@MainActor
enum AndroidExpansion {
    private static var horizontal: Set<UnsafeMutableRawPointer> = []
    private static var vertical: Set<UnsafeMutableRawPointer> = []
    private static var pinnedWidth: Set<UnsafeMutableRawPointer> = []
    private static var pinnedHeight: Set<UnsafeMutableRawPointer> = []
    private static var spacers: Set<UnsafeMutableRawPointer> = []

    /// Claimed by the view itself (a Spacer, a ScrollView), not carried up from inside.
    private static var ownHorizontal: Set<UnsafeMutableRawPointer> = []
    private static var ownVertical: Set<UnsafeMutableRawPointer> = []

    /// `view` wants the surplus along these axes.
    static func claim(_ view: NativeView, horizontal wantsWidth: Bool, vertical wantsHeight: Bool) {
        if wantsWidth { horizontal.insert(view); ownHorizontal.insert(view) } else { horizontal.remove(view); ownHorizontal.remove(view) }
        if wantsHeight { vertical.insert(view); ownVertical.insert(view) } else { vertical.remove(view); ownVertical.remove(view) }
    }

    /// After omni_jni_set_stack_child: a child that wants the surplus only because
    /// something inside it does (a stack holding a Spacer) keeps its content's size
    /// and takes its share on top, as SwiftUI sizes it. From zero, it got an equal
    /// share whatever its content: a column of amounts was cut short. Spacers,
    /// scroll views and the like, which claim it themselves, still take only the
    /// surplus.
    static func settle(_ child: NativeView, vertical isVertical: Bool) {
        // Across a row only. Down a column, a stack holding Spacers (a screen's top
        // half above its keypad) measures as all the height there is, not its
        // content, and sized from that the screen ran past the window.
        guard !isVertical else { return }
        let wantsAlong = (isVertical ? vertical : horizontal).contains(child)
        let ownsIt = (isVertical ? ownVertical : ownHorizontal).contains(child) || fillers.contains(child)
        guard wantsAlong, !ownsIt else { return }
        omni_jni_size_to_content(OmniAndroid.env, child, isVertical ? 1 : 0)
    }

    static func wants(_ view: NativeView, horizontal axis: Bool) -> Bool {
        (axis ? horizontal : vertical).contains(view) || fillers.contains(view)
    }

    private static var fillers: Set<UnsafeMutableRawPointer> = []

    /// `view` takes its container's whole size but asks for no room in it, so
    /// nothing is carried up: an overlay's stroke is the size of what it
    /// decorates, as in SwiftUI.
    static func fill(_ view: NativeView) {
        fillers.insert(view)
    }

    /// `view` answers for its own size along an axis, so a claim from inside stops
    /// there. Each axis is separate.
    static func pin(_ view: NativeView, width: Bool, height: Bool) {
        if width { pinnedWidth.insert(view) } else { pinnedWidth.remove(view) }
        if height { pinnedHeight.insert(view) } else { pinnedHeight.remove(view) }
    }

    /// Passes a child's claim up to its container.
    ///
    /// A container already attached was sized in its own parent without the
    /// claim: a screen swapped in after the first render, into a NavigationStack
    /// that held EmptyView. So a new claim re-sizes each attached ancestor, up
    /// to the first one it leaves unchanged.
    static func carry(from child: NativeView, to parent: NativeView) {
        parents[child] = parent
        var view = parent
        var changed = absorb(from: child, into: parent)
        while changed, let above = parents[view] {
            resize(view, in: above)
            changed = absorb(from: view, into: above)
            view = above
        }
    }

    private static var parents: [UnsafeMutableRawPointer: UnsafeMutableRawPointer] = [:]

    /// True if `parent` gained a claim.
    private static func absorb(from child: NativeView, into parent: NativeView) -> Bool {
        var gained = false
        // Through a wrapper (a frame, a background), a child's own claim stays the
        // wrapper's own: a key's .frame(maxWidth: .infinity) inside its .frame(height:)
        // shares its row equally, as SwiftUI does. Only through a stack is it carried,
        // the stack sized to its content first (settle).
        let isWrapper = omni_jni_linear_orientation(OmniAndroid.env, parent) < 0
        if horizontal.contains(child) && !pinnedWidth.contains(parent) {
            gained = horizontal.insert(parent).inserted || gained
            if isWrapper && ownHorizontal.contains(child) { ownHorizontal.insert(parent) }
        }
        if vertical.contains(child) && !pinnedHeight.contains(parent) {
            gained = vertical.insert(parent).inserted || gained
            if isWrapper && ownVertical.contains(child) { ownVertical.insert(parent) }
        }
        return gained
    }

    /// What insertChild would have set, had the claim been there then.
    private static func resize(_ view: NativeView, in parent: NativeView) {
        let env = OmniAndroid.env
        let wantsWidth = horizontal.contains(view)
        let wantsHeight = vertical.contains(view)
        switch omni_jni_linear_orientation(env, parent) {
        case 1:
            omni_jni_set_stack_child(env, view, 1, wantsWidth ? 1 : 0, wantsHeight ? 1 : 0)
            settle(view, vertical: true)
        case 0:
            omni_jni_set_stack_child(env, view, 0, wantsHeight ? 1 : 0, wantsWidth ? 1 : 0)
            settle(view, vertical: false)
        default:
            omni_jni_resolve_child_size(env, view, wantsWidth ? 1 : 0, wantsHeight ? 1 : 0)
        }
    }

    /// Records that `view` is a Spacer.
    static func markSpacer(_ view: NativeView) {
        spacers.insert(view)
    }

    static func narrowSpacer(_ view: NativeView, toVertical isVertical: Bool) {
        guard spacers.contains(view) else { return }
        claim(view, horizontal: !isVertical, vertical: isVertical)
        omni_jni_set_spacer_extent(OmniAndroid.env, view, isVertical ? 1 : 0)
    }

    static func clear(_ view: NativeView) {
        parents.removeValue(forKey: view)
        fillers.remove(view)
        horizontal.remove(view)
        vertical.remove(view)
        ownHorizontal.remove(view)
        ownVertical.remove(view)
        pinnedWidth.remove(view)
        pinnedHeight.remove(view)
        spacers.remove(view)
    }
}
#endif
