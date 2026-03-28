// src/lib/components/android/Font+Android.swift
#if os(Android)
import Foundation
import CAndroid

public extension Font {
    @discardableResult
    @MainActor static func register(_ path: String, as family: String) -> Bool {
        family.withCString { familyName in
            path.withCString { filePath in
                omni_jni_register_font(OmniAndroid.env, familyName, filePath) != 0
            }
        }
    }
}
#endif
