// omni.json; build-time app metadata: what the OS must be told before the
// app runs. Optional throughout; an app without one builds as before.

import Foundation

struct OmniManifest: Decodable {
    var bundleIdentifier: String?
    /// Custom URL schemes: ["example"] routes example://... to the app. Declared
    /// here because the Info.plist and AndroidManifest are both generated.
    var urlSchemes: [String]?
    /// Where the iOS provisioning profile lives; see ProvisioningProfile below.
    /// A path, not the profile: safe to commit.
    var provisioningProfile: String?
    /// Google Play Integrity, for OmniKeychain's attestation on Android:
    /// `{"cloudProjectNumber": "123456789012"}`. Without it no Play code is
    /// built in (vendor/play-integrity).
    var playIntegrity: PlayIntegrity?

    struct PlayIntegrity: Decodable {
        var cloudProjectNumber: String
    }

    static func load(from appPath: String) -> OmniManifest {
        guard let data = FileManager.default.contents(atPath: "\(appPath)/omni.json"),
              let manifest = try? JSONDecoder().decode(OmniManifest.self, from: data)
        else { return OmniManifest() }
        return manifest
    }

    var validatedSchemes: [String] {
        (urlSchemes ?? []).compactMap { raw in
            let scheme = raw.lowercased()
            let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789+-.")
            guard let first = scheme.first, first.isLetter,
                  scheme.unicodeScalars.allSatisfy({ allowed.contains($0) }) else {
                Console.warning("omni.json: '\(raw)' is not a usable URL scheme — a letter, then letters, digits, + - or . — skipping it")
                return nil
            }
            return scheme
        }
    }
}

/// The development provisioning profile, kept out of the project directory:
/// it names the team, the registered devices and the entitlements, and does
/// not belong in a repository or in front of a tool reading the sources.
///
/// Resolved in this order:
///   1. OMNI_PROVISIONING_PROFILE, for CI
///   2. omni.json's `provisioningProfile`; `~` expands, a relative path is
///      taken from omni.json's directory
///   3. ~/.omni/provisioning/<bundleIdentifier>.mobileprovision
///
/// `omni provision` writes to the same place a build reads from.
enum ProvisioningProfile {
    static func location(appPath: String, bundleIdentifier: String) -> String {
        if let fromEnvironment = ProcessInfo.processInfo.environment["OMNI_PROVISIONING_PROFILE"],
           !fromEnvironment.isEmpty {
            return expand(fromEnvironment, relativeTo: appPath)
        }
        if let fromManifest = OmniManifest.load(from: appPath).provisioningProfile, !fromManifest.isEmpty {
            return expand(fromManifest, relativeTo: appPath)
        }
        return "\(NSHomeDirectory())/.omni/provisioning/\(bundleIdentifier).mobileprovision"
    }

    static func expand(_ raw: String, relativeTo base: String) -> String {
        let path: String
        if raw == "~" { path = NSHomeDirectory() }
        else if raw.hasPrefix("~/") { path = NSHomeDirectory() + raw.dropFirst(1) }
        else if raw.hasPrefix("/") { path = raw }
        else { path = "\(base)/\(raw)" }
        return URL(fileURLWithPath: path).standardizedFileURL.path
    }

    /// Where profiles used to go: loose in the app directory. Still read, with
    /// a warning, so an existing setup keeps building.
    static func legacy(in appPath: String) -> String? {
        let contents = (try? FileManager.default.contentsOfDirectory(atPath: appPath)) ?? []
        return contents.first { $0.hasSuffix(".mobileprovision") }.map { "\(appPath)/\($0)" }
    }
}
