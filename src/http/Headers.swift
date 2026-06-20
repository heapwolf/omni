
import Foundation

public struct Headers: Sendable, Equatable, ExpressibleByDictionaryLiteral {
    /// Lowercased name to values, in insertion order within a name.
    private var storage: [String: [String]] = [:]

    public init() {}

    public init(_ pairs: [String: String]) {
        for (name, value) in pairs { append(name, value) }
    }

    public init(dictionaryLiteral elements: (String, String)...) {
        for (name, value) in elements { append(name, value) }
    }

    private static func validate(_ name: String, _ value: String) throws {
        guard !name.isEmpty, name.allSatisfy({ $0.isASCII && !$0.isWhitespace && !"()<>@,;:\\\"/[]?={}".contains($0) }) else {
            throw FetchError.invalidArgument("Invalid header name: \(name.debugDescription)")
        }
        // Unicode scalars, not Characters: "\r\n" is one grapheme cluster.
        guard !value.unicodeScalars.contains(where: { $0 == "\0" || $0 == "\r" || $0 == "\n" }) else {
            throw FetchError.invalidArgument("Header value for \(name) contains a forbidden character")
        }
    }

    private static func normalize(_ name: String) -> String { name.lowercased() }

    /// Values are trimmed, as the spec requires, before being stored.
    public mutating func append(_ name: String, _ value: String) {
        guard (try? Self.validate(name, value)) != nil else { return }
        storage[Self.normalize(name), default: []].append(value.trimmingCharacters(in: .whitespaces))
    }

    /// Throwing variant, for when a caller wants a malformed header to be loud.
    public mutating func appendOrThrow(_ name: String, _ value: String) throws {
        try Self.validate(name, value)
        storage[Self.normalize(name), default: []].append(value.trimmingCharacters(in: .whitespaces))
    }

    public mutating func set(_ name: String, _ value: String) {
        guard (try? Self.validate(name, value)) != nil else { return }
        storage[Self.normalize(name)] = [value.trimmingCharacters(in: .whitespaces)]
    }

    public mutating func delete(_ name: String) {
        storage.removeValue(forKey: Self.normalize(name))
    }

    /// Comma-joined, per spec; not the first value.
    public func get(_ name: String) -> String? {
        guard let values = storage[Self.normalize(name)], !values.isEmpty else { return nil }
        return values.joined(separator: ", ")
    }

    public func getSetCookie() -> [String] { storage["set-cookie"] ?? [] }

    public func has(_ name: String) -> Bool { storage[Self.normalize(name)] != nil }

    public subscript(name: String) -> String? {
        get { get(name) }
        set { newValue.map { set(name, $0) } ?? delete(name) }
    }

    /// Sorted by name, as the spec's header list iteration requires.
    public var entries: [(name: String, value: String)] {
        storage.keys.sorted().compactMap { name in get(name).map { (name, $0) } }
    }

    public var names: [String] { storage.keys.sorted() }
    public var isEmpty: Bool { storage.isEmpty }

    /// One value per name, for transports that cannot express repeats.
    public var flattened: [String: String] {
        Dictionary(uniqueKeysWithValues: entries.map { ($0.name, $0.value) })
    }
}
