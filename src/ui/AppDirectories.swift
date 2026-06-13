// src/ui/AppDirectories.swift
// Where an app keeps its own files. Foundation's Application Support is the
// app's own only in a sandbox. On a Mac outside one it is the user's whole
// folder, which every app shares, and on Android it is not the app's storage
// at all. This is the app's own directory everywhere.
import Foundation
#if os(Android)
import CAndroid
#endif

public enum AppDirectories {
    /// Persistent files that are the app's, not the user's documents:
    /// settings, queues, stores. Created on first use.
    ///   iOS      Application Support, in the app's sandbox
    ///   macOS    Application Support/<bundle identifier>
    ///   Android  the app's files directory
    ///   Linux    $XDG_DATA_HOME/<app>, else ~/.local/share/<app>
    ///   Windows  %APPDATA%\<app>
    public static var support: URL {
        let directory = override ?? platformSupport
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    /// In place of `support`, for tests: a directory of their own, so a test
    /// run never writes where the installed app keeps its files.
    nonisolated(unsafe) public static var override: URL?

    /// The bundle identifier on Apple, the executable's name elsewhere.
    static var appIdentifier: String {
        Bundle.main.bundleIdentifier ?? ProcessInfo.processInfo.processName
    }

    static var platformSupport: URL {
        let fm = FileManager.default
        #if os(iOS)
        return fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        #elseif os(macOS)
        return fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(appIdentifier, isDirectory: true)
        #elseif os(Android)
        let env = OmniAndroid.env
        if let path = omni_jni_files_dir(env, omni_jni_activity()) {
            defer { free(path) }
            return URL(fileURLWithPath: String(cString: path), isDirectory: true)
        }
        return fm.temporaryDirectory.appendingPathComponent(appIdentifier, isDirectory: true)
        #elseif os(Windows)
        let base = ProcessInfo.processInfo.environment["APPDATA"].map { URL(fileURLWithPath: $0) }
            ?? fm.homeDirectoryForCurrentUser.appendingPathComponent("AppData/Roaming")
        return base.appendingPathComponent(appIdentifier, isDirectory: true)
        #else
        let base = ProcessInfo.processInfo.environment["XDG_DATA_HOME"].map { URL(fileURLWithPath: $0) }
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".local/share")
        return base.appendingPathComponent(appIdentifier, isDirectory: true)
        #endif
    }
}
