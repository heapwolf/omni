// src/ui/Clipboard.swift
// The system clipboard. SwiftUI has no API for it (apps reach for UIPasteboard
// or NSPasteboard directly); an omni app cannot, so this is omni's own.
import Foundation
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#elseif os(Android)
import CAndroid
#endif

public enum Clipboard {
    /// Replaces what is on the clipboard with `text`.
    @MainActor public static func copy(_ text: String) {
        #if os(iOS)
        UIPasteboard.general.string = text
        #elseif os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #elseif os(Android)
        omni_jni_copy_text(OmniAndroid.env, text)
        #else
        Omni.log("Clipboard is not supported on this platform yet")
        #endif
    }

    /// The clipboard's text, if it holds any. Reading it may show the system's
    /// paste prompt on iOS.
    @MainActor public static var string: String? {
        #if os(iOS)
        return UIPasteboard.general.string
        #elseif os(macOS)
        return NSPasteboard.general.string(forType: .string)
        #elseif os(Android)
        guard let text = omni_jni_pasted_text(OmniAndroid.env) else { return nil }
        defer { free(text) }
        return String(cString: text)
        #else
        return nil
        #endif
    }
}
