import Foundation

/// NDK's Python (`toolchains/llvm/prebuilt/<host>/python3`) contains
/// package installers: pip, setuptools, and ensurepip's wheels of both. r28b's
/// pip is 23.1.2 vendors certifi still trusts the emSign roots pulled
/// in October 2026 after their intermediates' keys were compromised
/// (GHSA-6q48-6c7w-9gw2). Python is built without `ssl`, pip 
/// can't reach anything over HTTPS and the stale roots were never usable; but
/// nothing a build runs uses the installers either (the NDK's helper scripts
/// included) omni removes them from the NDK it installs: new
/// installs, and ones made before this. An NDK of your own (ANDROID_NDK_HOME)
/// isn't changed.
enum NDKPython {
    /// removed; relative to `lib/python3.x`: the installers, what
    /// setuptools hooks into every interpreter start (`distutils-precedence.pth`
    /// imports `_distutils_hack`), and ensurepip's wheels put them back.
    static let removed = [
        "site-packages/pip", "site-packages/setuptools", "site-packages/pkg_resources",
        "site-packages/_distutils_hack", "site-packages/distutils-precedence.pth"
    ]
    static let removedPrefixes = ["site-packages/pip-", "site-packages/setuptools-"]   // their .dist-info

    /// Removes them from the NDK at `ndk` for host `hostTag`; returns what it
    /// removed, relative to the NDK, a second run dopesnt return anything.
    @discardableResult
    static func stripInstallers(ndk: String, hostTag: String, fm: FileManager = .default) -> [String] {
        let python = "toolchains/llvm/prebuilt/\(hostTag)/python3/lib"
        guard let versions = try? fm.contentsOfDirectory(atPath: "\(ndk)/\(python)") else { return [] }
        var gone: [String] = []
        for version in versions.sorted() where version.hasPrefix("python3") {
            let lib = "\(python)/\(version)"
            var targets = removed.map { "\(lib)/\($0)" }
            let packages = (try? fm.contentsOfDirectory(atPath: "\(ndk)/\(lib)/site-packages")) ?? []
            for prefix in removedPrefixes {
                let name = String(prefix.dropFirst("site-packages/".count))
                targets += packages.filter { $0.hasPrefix(name) && $0.hasSuffix(".dist-info") }.map { "\(lib)/site-packages/\($0)" }
            }
            let wheels = (try? fm.contentsOfDirectory(atPath: "\(ndk)/\(lib)/ensurepip/_bundled")) ?? []
            targets += wheels.filter { $0.hasSuffix(".whl") }.map { "\(lib)/ensurepip/_bundled/\($0)" }
            for target in targets.sorted() where fm.fileExists(atPath: "\(ndk)/\(target)") {
                if (try? fm.removeItem(atPath: "\(ndk)/\(target)")) != nil { gone.append(target) }
            }
        }
        return gone
    }
}
