// src/cli/Console.swift
import Foundation

/// Every status line the CLI prints goes through here, so there is exactly
/// one place deciding what a message looks like — a color and a symbol —
/// instead of each call site picking its own emoji.
enum Console {
    private static let isColorEnabled = isatty(fileno(stdout)) != 0

    private static let reset = "\u{001B}[0m"
    private static let red = "\u{001B}[31m"
    private static let yellow = "\u{001B}[33m"
    private static let green = "\u{001B}[32m"
    private static let gray = "\u{001B}[90m"

    private static func line(_ color: String, _ symbol: String, _ message: String) -> String {
        guard isColorEnabled else { return "\(symbol) \(message)" }
        return "\(color)\(symbol)\(reset) \(message)"
    }

    /// A step completed. Green ✓.
    static func success(_ message: String) {
        print(line(green, "✓", message))
    }

    /// A step failed outright. Red 🅧.
    static func failure(_ message: String) {
        print(line(red, "🅧", message))
    }

    /// Something is off but not fatal — the build keeps going. Yellow ●.
    static func warning(_ message: String) {
        print(line(yellow, "●", message))
    }

    /// Routine progress: "doing X now". Gray ●.
    static func info(_ message: String) {
        print(line(gray, "●", message))
    }
}
