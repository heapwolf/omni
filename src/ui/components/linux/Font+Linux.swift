// src/lib/components/linux/Font+Linux.swift
#if os(Linux)
import Foundation
import Glibc

private nonisolated(unsafe) let libfontconfig = dlopen("libfontconfig.so.1", RTLD_LAZY | RTLD_GLOBAL)

private nonisolated(unsafe) let FcConfigAppFontAddFile: @convention(c) (UnsafeMutableRawPointer?, UnsafePointer<CChar>) -> Int32 =
    fn(libfontconfig, "FcConfigAppFontAddFile")
private nonisolated(unsafe) let FcFreeTypeQuery: @convention(c) (UnsafePointer<CChar>, UInt32, UnsafeMutableRawPointer?, UnsafeMutablePointer<Int32>?) -> UnsafeMutableRawPointer? =
    fn(libfontconfig, "FcFreeTypeQuery")
private nonisolated(unsafe) let FcPatternGetString: @convention(c) (UnsafeMutableRawPointer, UnsafePointer<CChar>, Int32, UnsafeMutablePointer<UnsafePointer<CChar>?>) -> Int32 =
    fn(libfontconfig, "FcPatternGetString")
private nonisolated(unsafe) let FcPatternDestroy: @convention(c) (UnsafeMutableRawPointer) -> Void =
    fn(libfontconfig, "FcPatternDestroy")

public extension Font {
    @discardableResult
    @MainActor static func register(_ path: String, as family: String) -> Bool {
        guard FileManager.default.fileExists(atPath: path) else { return false }
        guard path.withCString({ FcConfigAppFontAddFile(nil, $0) }) != 0 else { return false }

        // The alias stands if the file will not say what it is called.
        var declared = family
        path.withCString { filePath in
            var count: Int32 = 0
            guard let pattern = FcFreeTypeQuery(filePath, 0, nil, &count) else { return }
            var name: UnsafePointer<CChar>? = nil
            if "family".withCString({ FcPatternGetString(pattern, $0, 0, &name) }) == 0,
               let name {
                declared = String(cString: name)
            }
            FcPatternDestroy(pattern)
        }

        registeredFamilies[family] = declared
        return true
    }
}
#endif
