// Values baked in at build time from omni.json's `flags` section:
//
//   omni run --flags dev,mock          # profiles, merged left to right
//   omni run --flag apiBase=http://…   # one value, applied last
//
// Read-only, and fixed for the life of the process. Launch arguments of the
// form `--omni-flag key=value` override the baked-in values, for flipping one
// without a rebuild (`xcrun simctl launch <udid> <bundle> --omni-flag api=live`).
//
// Where the build puts them:
//   iOS      OmniFlags.json in the .app
//   macOS    OmniFlags.json in Contents/Resources
//   Linux,   OmniFlags.json beside the executable
//   Windows
//   Android  compiled into the generated JNI entry, which calls install(base64:)

import Foundation

public enum FlagValue: Sendable, Equatable {
    case string(String)
    case bool(Bool)
    case number(Double)

    var text: String {
        switch self {
        case .string(let value): return value
        case .bool(let value): return value ? "true" : "false"
        case .number(let value):
            return value.rounded() == value && abs(value) < 1e15 ? String(Int64(value)) : String(value)
        }
    }

    var boolean: Bool? {
        switch self {
        case .bool(let value): return value
        case .string("true"): return true
        case .string("false"): return false
        default: return nil
        }
    }

    var numeric: Double? {
        switch self {
        case .number(let value): return value
        case .string(let value): return Double(value)
        case .bool: return nil
        }
    }

    var integer: Int? {
        guard let value = numeric, value.rounded() == value,
              abs(value) <= Double(Int32.max) else { return nil }
        return Int(value)
    }
}

public enum Flags {
    /// Must match the CLI's AppFlags.fileName.
    public static let fileName = "OmniFlags.json"

    /// Every flag, after launch overrides.
    public static var all: [String: FlagValue] { values }

    public static subscript(key: String) -> FlagValue? { values[key] }

    /// Any value as text: `true`, `3`, or the string itself.
    public static func string(_ key: String) -> String? { values[key]?.text }

    /// A boolean, or the string "true"/"false" (what `--flag` produces).
    public static func bool(_ key: String) -> Bool? { values[key]?.boolean }

    /// A number, or a string that parses as one.
    public static func number(_ key: String) -> Double? { values[key]?.numeric }

    public static func int(_ key: String) -> Int? { values[key]?.integer }

    // MARK: Loading

    /// Set by the generated Android entry before anything reads a flag.
    /// Not for app code.
    nonisolated(unsafe) private static var installed: Data?

    public static func install(base64: String) {
        installed = Data(base64Encoded: base64)
    }

    /// Lazily, once: a static let is initialised thread-safely, so a transport
    /// may read flags off the main actor.
    private static let values: [String: FlagValue] = {
        var values = baked().map(parse) ?? [:]
        for (key, value) in launchOverrides(ProcessInfo.processInfo.arguments) {
            values[key] = .string(value)
        }
        return values
    }()

    private static func baked() -> Data? {
        #if os(Android)
        return installed
        #elseif os(macOS) || os(iOS)
        guard let url = Bundle.main.url(forResource: "OmniFlags", withExtension: "json") else { return nil }
        return try? Data(contentsOf: url)
        #else
        guard let executable = Bundle.main.executableURL else { return nil }
        return try? Data(contentsOf: executable.deletingLastPathComponent().appendingPathComponent(fileName))
        #endif
    }

    static func parse(_ data: Data) -> [String: FlagValue] {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            Omni.log("\(fileName) is not a JSON object; no flags are set")
            return [:]
        }
        var values: [String: FlagValue] = [:]
        for (key, raw) in object {
            if let number = raw as? NSNumber, String(cString: number.objCType) == "c" {
                values[key] = .bool(number.boolValue)
            } else if let number = raw as? NSNumber {
                values[key] = .number(number.doubleValue)
            } else if let string = raw as? String {
                values[key] = .string(string)
            }
        }
        return values
    }

    /// `--omni-flag key=value` or `--omni-flag=key=value`, repeatable.
    static func launchOverrides(_ arguments: [String]) -> [(String, String)] {
        var pairs: [(String, String)] = []
        var index = arguments.startIndex
        while index < arguments.endIndex {
            let argument = arguments[index]
            var pair: String?
            if argument == "--omni-flag", index + 1 < arguments.endIndex {
                pair = arguments[index + 1]
                index += 1
            } else if argument.hasPrefix("--omni-flag=") {
                pair = String(argument.dropFirst("--omni-flag=".count))
            }
            if let pair {
                let parts = pair.split(separator: "=", maxSplits: 1).map(String.init)
                if parts.count == 2, !parts[0].isEmpty { pairs.append((parts[0], parts[1])) }
                else { Omni.log("--omni-flag \(pair): expected key=value; ignored") }
            }
            index += 1
        }
        return pairs
    }
}
