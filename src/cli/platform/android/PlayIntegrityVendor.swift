// Play Integrity, built in only when omni.json asks for it: the vendored jar
// (vendor/play-integrity, made by its vendor.py), checked against its lock
// before use, the bridge that calls it, and the manifest entries it needs.

import Foundation
#if canImport(CryptoKit)
import CryptoKit
#endif

struct PlayIntegrityVendor {
    let jar: String
    let bridge: String
    let manifestEntries: String

    /// Nil when the app's omni.json has no playIntegrity.
    init?(framework: String, app: String) throws {
        guard let config = OmniManifest.load(from: app).playIntegrity else { return nil }
        let project = config.cloudProjectNumber
        guard !project.isEmpty, project.allSatisfy(\.isASCII), project.allSatisfy(\.isNumber) else {
            throw AndroidError.missing("omni.json: playIntegrity.cloudProjectNumber must be the project's number, digits only")
        }
        let vendor = "\(framework)/vendor/play-integrity"
        jar = "\(vendor)/play-integrity.jar"
        bridge = "\(framework)/src/keychain/android/play-integrity/OmniAttest.java"
        let lock = (try? String(contentsOfFile: "\(vendor)/artifacts.lock", encoding: .utf8)) ?? ""
        guard let pinned = lock.split(separator: "\n").first(where: { $0.hasPrefix("output ") })?.split(separator: " ").last,
              let bytes = FileManager.default.contents(atPath: jar) else {
            throw AndroidError.missing("vendor/play-integrity: no play-integrity.jar or lock; run vendor.py")
        }
        let actual = try Self.sha256(bytes, path: jar)
        guard actual == pinned else {
            throw AndroidError.failed("play integrity", "play-integrity.jar is \(actual), but artifacts.lock has \(pinned)")
        }
        let fragment = (try? String(contentsOfFile: "\(vendor)/manifest-fragment.xml", encoding: .utf8)) ?? ""
        let lines = fragment.split(separator: "\n").map { "\n        " + $0 }.joined()
        manifestEntries = lines + "\n        <meta-data android:name=\"omni.play_integrity.cloud_project\" android:value=\"project:\(project)\" />"
    }

    static func sha256(_ data: Data, path: String) throws -> String {
        #if canImport(CryptoKit)
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        #else
        let line = try Shell.checked("sha256sum \"\(path)\"", step: "hashing play-integrity.jar")
        return String(line.split(separator: " ").first ?? "")
        #endif
    }
}
