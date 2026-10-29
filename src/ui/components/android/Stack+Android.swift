// src/lib/components/android/Stack+Android.swift
#if os(Android)
import Foundation
import CAndroid

@MainActor private var stackChildren: [UnsafeMutableRawPointer: [NativeView]] = [:]
@MainActor private var stackAxes: [UnsafeMutableRawPointer: StackAxis] = [:]

extension Stack {
    @MainActor func applyAxis(_ view: NativeView) {
        let vertical = axis == .vertical
        omni_jni_call_void_method_int(OmniAndroid.env, view, "setOrientation", vertical ? 1 : 0)

        guard stackAxes[view] != axis else { return }
        stackAxes[view] = axis

        for child in stackChildren[view] ?? [] {
            AndroidExpansion.narrowSpacer(child, toVertical: vertical)
            omni_jni_set_stack_child(
                OmniAndroid.env, child, vertical ? 1 : 0,
                AndroidExpansion.wants(child, horizontal: vertical) ? 1 : 0,
                AndroidExpansion.wants(child, horizontal: !vertical) ? 1 : 0)
            AndroidExpansion.settle(child, vertical: vertical)
        }
    }

    @MainActor func recordChild(_ child: NativeView, of parent: NativeView) {
        stackChildren[parent, default: []].append(child)
        stackAxes[parent] = axis
    }
}
#endif
