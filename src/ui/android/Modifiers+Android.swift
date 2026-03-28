// src/lib/android/Modifiers+Android.swift
#if os(Android)
import Foundation
import CAndroid

@MainActor
enum AndroidModifierState {
    private static var storage: [UnsafeMutableRawPointer: AnyObject] = [:]

    static func set(_ value: AnyObject, for view: NativeView) {
        storage[view] = value
    }

    static func get<T: AnyObject>(_ type: T.Type, for view: NativeView) -> T? {
        storage[view] as? T
    }

    /// Returns the existing state for `view`, creating and storing it if absent.
    static func ensure<T: AnyObject>(for view: NativeView, create: () -> T) -> T {
        if let existing = storage[view] as? T { return existing }
        let created = create()
        storage[view] = created
        return created
    }

    static func clear(_ view: NativeView) {
        storage.removeValue(forKey: view)
    }
}

extension OmniAndroid {
    /// A plain FrameLayout, the container modifier views wrap their content in.
    @MainActor
    static func makeContainer() -> NativeView {
        createView(getEnv(), "android/widget/FrameLayout")
    }

    @MainActor
    static func addChild(_ child: NativeView, to parent: NativeView) {
        let env = getEnv()
        omni_jni_add_view(env, parent, child)

        omni_jni_resolve_child_size(env, child,
                                    AndroidExpansion.wants(child, horizontal: true) ? 1 : 0,
                                    AndroidExpansion.wants(child, horizontal: false) ? 1 : 0)
        AndroidExpansion.carry(from: child, to: parent)
    }
}
#endif
