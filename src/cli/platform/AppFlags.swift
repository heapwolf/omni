// omni.json's `flags` section: named profiles of values baked into the app,
// read at runtime through OmniUI's `Flags`.
//
//   { "flags": { "dev": { "apiBase": "https://staging…" }, "mock": { "api": "mock" } } }
//
//   omni run --flags dev,mock --flag verbose=true
//
// Profiles merge left to right, then --flag overrides. A profile that is not in
// omni.json is an error: a typo must not silently build against the real API.

import ArgumentParser
import Foundation

/// The options every building command takes.
struct FlagOptions: ParsableArguments {
    @Option(name: .customLong("flags"),
            help: "Profiles from omni.json's `flags` section, merged left to right (dev,mock).")
    var profiles: [String] = []

    @Option(name: .customLong("flag"),
            help: "One value, applied after the profiles (key=value). Repeatable.")
    var overrides: [String] = []

    func resolve(appPath: String) throws -> AppFlags {
        try AppFlags.resolve(
            appPath: appPath,
            profiles: profiles.flatMap { $0.split(separator: ",") }
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty },
            overrides: overrides)
    }
}

struct FlagsError: Error, CustomStringConvertible {
    let description: String
}

struct AppFlags {
    /// The file the runtime reads. Must match OmniUI's Flags.fileName.
    static let fileName = "OmniFlags.json"

    let profiles: [String]
    /// JSON scalars only: String, Bool or a number.
    let values: [String: Any]

    /// Computed: [String: Any] is not Sendable, so it cannot be a stored static.
    static var none: AppFlags { AppFlags(profiles: [], values: [:]) }

    var isEmpty: Bool { values.isEmpty }

    static func resolve(appPath: String, profiles: [String], overrides: [String]) throws -> AppFlags {
        var values: [String: Any] = [:]

        if !profiles.isEmpty {
            let available = try loadProfiles(appPath: appPath)
            for name in profiles {
                guard let profile = available[name] else {
                    let names = available.keys.sorted()
                    throw FlagsError(description: """
                        No flags.\(name) in \(appPath)/omni.json \
                        (have: \(names.isEmpty ? "none" : names.joined(separator: ", "))).
                        """)
                }
                for (key, value) in profile {
                    // null unsets what an earlier profile set.
                    if value is NSNull { values.removeValue(forKey: key) } else { values[key] = value }
                }
            }
        }

        // Always strings: `--flag pin=0012` must not become the number 12. The
        // runtime's accessors read "true" and "3" where a Bool or number is asked for.
        for override in overrides {
            let parts = override.split(separator: "=", maxSplits: 1).map(String.init)
            guard parts.count == 2, !parts[0].isEmpty else {
                throw FlagsError(description: "--flag \(override): expected key=value.")
            }
            values[parts[0]] = parts[1]
        }

        return AppFlags(profiles: profiles, values: values)
    }

    /// Read on its own rather than through OmniManifest, whose decode falls
    /// back to defaults on any error. A bad flags section has to be reported.
    private static func loadProfiles(appPath: String) throws -> [String: [String: Any]] {
        let file = "\(appPath)/omni.json"
        guard let data = FileManager.default.contents(atPath: file) else {
            throw FlagsError(description: "--flags needs \(file), which does not exist.")
        }
        let root: Any
        do {
            root = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw FlagsError(description: "\(file) is not valid JSON: \(error.localizedDescription)")
        }
        guard let object = root as? [String: Any], let flags = object["flags"] else {
            throw FlagsError(description: "\(file) has no `flags` section.")
        }
        guard let sections = flags as? [String: Any] else {
            throw FlagsError(description: "\(file): `flags` must be an object of profiles.")
        }

        var profiles: [String: [String: Any]] = [:]
        for (name, section) in sections {
            guard let profile = section as? [String: Any] else {
                throw FlagsError(description: "\(file): flags.\(name) must be an object.")
            }
            for (key, value) in profile where !(value is String || value is NSNumber || value is NSNull) {
                throw FlagsError(description: """
                    \(file): flags.\(name).\(key) must be a string, number, boolean or null, \
                    not \(value is [Any] ? "an array" : "an object").
                    """)
            }
            profiles[name] = profile
        }
        return profiles
    }

    /// Sorted keys, so the same flags produce the same bytes.
    func json() throws -> Data {
        try JSONSerialization.data(withJSONObject: values, options: [.sortedKeys])
    }

    /// Writes the file into `directory`, or removes one a previous build left:
    /// bundles are reused between builds, and a stale file would keep mocking.
    func write(into directory: String) throws {
        let file = "\(directory)/\(Self.fileName)"
        if isEmpty {
            try? FileManager.default.removeItem(atPath: file)
            return
        }
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        try json().write(to: URL(fileURLWithPath: file))
    }

    /// Every build says what it baked in, so nothing ships unnoticed.
    func announce() {
        guard !isEmpty else { return }
        let source = profiles.isEmpty ? "--flag" : profiles.joined(separator: ", ")
        let pairs = values.keys.sorted().map { "\($0)=\(Self.display(values[$0]!))" }
        Console.warning("flags: \(source) → \(pairs.joined(separator: ", "))")
    }

    private static func display(_ value: Any) -> String {
        // "c" is how both Foundations tag a JSON boolean; CFGetTypeID is Darwin-only.
        if let number = value as? NSNumber, String(cString: number.objCType) == "c" {
            return number.boolValue ? "true" : "false"
        }
        return "\(value)"
    }
}
