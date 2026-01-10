// src/cli/platform/SwiftPackage.swift
import Foundation

public enum SwiftPackage {
    /// Nearest enclosing directory with a Package.swift. --app-path is usually an
    /// example subdirectory rather than the package root.
    public static func root(from path: String) -> String {
        var directory = URL(fileURLWithPath: path).standardizedFileURL
        for _ in 0..<12 {
            if FileManager.default.fileExists(
                atPath: directory.appendingPathComponent("Package.swift").path) {
                return directory.path
            }
            let parent = directory.deletingLastPathComponent()
            if parent.path == directory.path { break }
            directory = parent
        }
        return path
    }

    /// The product to build. --output defaults to "App", so an unmatched name is
    /// reported against the products that exist.
    public static func resolveProduct(named target: String, in path: String) throws -> String {
        let packageRoot = root(from: path)
        let dump = try Shell.exec("/usr/bin/env",
            ["swift", "package", "dump-package", "--package-path", packageRoot])
        guard dump.status == 0,
              let data = dump.output.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let products = json["products"] as? [[String: Any]] else {
            throw ShellError.failed("reading the package manifest at \(packageRoot)", dump.output)
        }

        var executables: [String] = []
        var everything: [String] = []
        for entry in products {
            guard let name = entry["name"] as? String else { continue }
            everything.append(name)
            if let type = entry["type"] as? [String: Any], type["executable"] != nil {
                executables.append(name)
            }
        }

        if everything.contains(target) { return target }

        throw ShellError.failed("choosing a product to build", """
            No product named '\(target)' in \(packageRoot)/Package.swift.
            Executable products: \(executables.isEmpty ? "none" : executables.joined(separator: ", "))
            Name one with --output, for example: omni run -o \(executables.first ?? "<product>")
            """)
    }
}
