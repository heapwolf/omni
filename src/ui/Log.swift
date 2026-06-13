
import Foundation

#if os(Android)
import CAndroid
#endif

// `Omni` already exists in Core.swift, so this extends it rather than
// redeclaring it.
public extension Omni {
    static func log(_ message: String, tag: String = "Omni") {
        #if os(Android)
        omni_jni_log(tag, message)
        #else
        FileHandle.standardError.write(Data("[\(tag)] \(message)\n".utf8))
        #endif
    }
}
