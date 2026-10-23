// src/cli/platform/android/AndroidBuild.swift
import Foundation

struct Shell {
    /// Runs a command through the shell and returns its stdout.
    @discardableResult
    static func run(_ command: String) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", command]

        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        return String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    @discardableResult
    static func checked(_ command: String, step: String) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", command]

        let errorPath = NSTemporaryDirectory() + "omni-stderr-\(UUID().uuidString)"
        _ = FileManager.default.createFile(atPath: errorPath, contents: nil)
        defer { try? FileManager.default.removeItem(atPath: errorPath) }

        let outPipe = Pipe()
        process.standardOutput = outPipe
        if let errorHandle = FileHandle(forWritingAtPath: errorPath) {
            process.standardError = errorHandle
        }

        try process.run()
        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        let out = (String(data: outData, encoding: .utf8) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard process.terminationStatus == 0 else {
            let err = ((try? String(contentsOfFile: errorPath, encoding: .utf8)) ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw ShellError.failed(step, [err, out].filter { !$0.isEmpty }
                .joined(separator: "\n"))
        }
        return out
    }

    /// Runs an executable directly. Arguments are passed as a vector, so no shell
    /// reinterprets metacharacters.
    @discardableResult
    static func exec(_ launchPath: String,
                     _ arguments: [String],
                     environment: [String: String]? = nil,
                     quiet: Bool = true) throws -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments
        if let environment {
            process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, new in new }
        }

        let pipe = Pipe()
        if quiet {
            process.standardOutput = pipe
            process.standardError = pipe
        }
        try process.run()

        var output = ""
        if quiet {
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            output = String(data: data, encoding: .utf8) ?? ""
        }
        process.waitUntilExit()

        return (process.terminationStatus, output.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}

enum ShellError: LocalizedError {
    case failed(String, String)

    var errorDescription: String? {
        switch self {
        case .failed(let step, let detail): return "\(step) failed:\n\(detail)"
        }
    }
}

enum AndroidError: LocalizedError {
    case missing(String)
    case failed(String, String)

    var errorDescription: String? {
        switch self {
        case .missing(let what): return what
        case .failed(let step, let detail): return "\(step) failed:\n\(detail)"
        }
    }
}

// MARK: - Toolchain

struct AndroidToolchain {
    let root: String
    let buildToolsVersion = "36.0.0"
    let platformAPI = "34"

    private let fm = FileManager.default
    private let env = ProcessInfo.processInfo.environment

    init() {
        let home = fm.homeDirectoryForCurrentUser.path
        root = env["OMNI_TOOLCHAIN"] ?? "\(home)/.omni/toolchain"
    }

    /// The only two host tags the NDK ships.
    var ndkHostTag: String {
        #if os(macOS)
            return "darwin-x86_64"
        #else
            return "linux-x86_64"
        #endif
    }

    /// platform-tools and the NDK use "darwin"...
    private var osSlug: String {
        #if os(macOS)
            return "darwin"
        #else
            return "linux"
        #endif
    }

    /// build-tools archives use "macosx"; the wrong slug 404s.
    private var buildToolsSlug: String {
        #if os(macOS)
            return "macosx"
        #else
            return "linux"
        #endif
    }

    /// Some Android binaries are x86_64-only. OMNI_X86_SHIM names a launcher
    /// (e.g. qemu-x86_64) for hosts that cannot run them natively.
    private var x86Shim: [String] {
        guard let shim = env["OMNI_X86_SHIM"], !shim.isEmpty else { return [] }
        return shim.split(separator: " ").map(String.init)
    }

    func runHostTool(_ tool: String, _ arguments: [String]) throws -> (status: Int32, output: String) {
        let shim = x86Shim
        if shim.isEmpty {
            return try Shell.exec(tool, arguments)
        }
        return try Shell.exec(shim[0], Array(shim.dropFirst()) + [tool] + arguments)
    }

    // MARK: Downloads

    /// Total size after redirects, or nil if the server does not say.
    private func contentLength(of url: String) -> Int64? {
        guard let head = try? Shell.exec("/usr/bin/curl", ["-sIL", url]) else { return nil }
        // Split on isNewline: Swift treats CRLF as one Character.
        let lengths = head.output
            .split(whereSeparator: \.isNewline)
            .filter { $0.lowercased().hasPrefix("content-length:") }
            // HTTP header lines end with CRLF; the \r breaks Int64 conversion.
            .compactMap { Int64($0.split(separator: ":").last?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? "") }
        return lengths.last
    }

    private func renderProgress(label: String,
                                expected: Int64?,
                                while running: () -> Bool,
                                bytesSoFar: () -> Int64) {
        // STDOUT_FILENO: Swift 6 will not read the mutable C `stdout` global.
        guard isatty(STDOUT_FILENO) == 1 else {
            Console.info("fetching \(label)")
            while running() { usleep(200_000) }
            return
        }

        let width = 28
        func draw(_ done: Int64) {
            let mb = Double(done) / 1_048_576
            var line: String
            if let expected, expected > 0 {
                let fraction = min(1.0, Double(done) / Double(expected))
                let filled = Int((Double(width) * fraction).rounded())
                let bar = String(repeating: "█", count: filled)
                    + String(repeating: "░", count: width - filled)
                line = String(format: "  %@ %3.0f%%  %.0f/%.0f MB  %@",
                              bar, fraction * 100, mb,
                              Double(expected) / 1_048_576, label)
            } else {
                // Unknown total: animate rather than sit empty.
                let filled = min(width, Int(mb / 8))
                let bar = String(repeating: "█", count: filled)
                    + String(repeating: "░", count: width - filled)
                line = String(format: "  %@  %.0f MB  %@", bar, mb, label)
            }
            FileHandle.standardOutput.write(Data(("\r" + line + "\u{1B}[K").utf8))
        }

        Console.info("\(label)")
        while running() {
            draw(bytesSoFar())
            usleep(200_000)
        }
        draw(bytesSoFar())
        FileHandle.standardOutput.write(Data("\n".utf8))
    }

    private func download(_ url: String, to destination: String, label: String) throws {
        if fm.fileExists(atPath: destination) { return }
        try fm.createDirectory(atPath: (destination as NSString).deletingLastPathComponent,
                               withIntermediateDirectories: true)

        // Moved into place only on success: a partial file at `destination` would be
        // mistaken for a complete download next run.
        let partial = destination + ".part"
        try? fm.removeItem(atPath: partial)

        // --retry without --retry-all-errors: a 404 just repeats.
        let curl = Process()
        curl.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
        curl.arguments = ["-fsSL", "--retry", "3", "--retry-delay", "2", "-o", partial, url]

        let errors = Pipe()
        curl.standardError = errors
        curl.standardOutput = Pipe()
        try curl.run()

        renderProgress(label: label, expected: contentLength(of: url), while: { curl.isRunning },
                       bytesSoFar: { (try? fm.attributesOfItem(atPath: partial)[.size] as? Int64) ?? 0 })

        curl.waitUntilExit()
        guard curl.terminationStatus == 0 else {
            let detail = String(data: errors.fileHandleForReading.readDataToEndOfFile(),
                                encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            try? fm.removeItem(atPath: partial)
            throw AndroidError.failed("downloading \(label)", detail.isEmpty
                ? "curl exited with status \(curl.terminationStatus)" : detail)
        }

        try fm.moveItem(atPath: partial, toPath: destination)
    }

    private func unzip(_ archive: String, into directory: String) throws {
        try fm.createDirectory(atPath: directory, withIntermediateDirectories: true)
        _ = try Shell.exec("/usr/bin/unzip", ["-q", "-o", archive, "-d", directory])
    }

    /// adb, downloaded if the host has none.
    func adb() throws -> String {
        let cached = "\(root)/platform-tools/adb"
        if fm.isExecutableFile(atPath: cached) { return cached }

        if let onPath = try? Shell.run("command -v adb"), !onPath.isEmpty,
           fm.isExecutableFile(atPath: onPath) {
            return onPath
        }

        let archive = "\(root)/platform-tools.zip"
        try download("https://dl.google.com/android/repository/platform-tools-latest-\(osSlug).zip",
                     to: archive, label: "platform-tools")
        try unzip(archive, into: root)
        _ = try? Shell.exec("/bin/chmod", ["+x", cached])

        guard fm.isExecutableFile(atPath: cached) else {
            throw AndroidError.missing("adb could not be installed at \(cached)")
        }
        return cached
    }

    /// build-tools, which carry aapt2, zipalign, d8 and apksigner.
    func buildTools() throws -> String {
        let dir = "\(root)/build-tools/\(buildToolsVersion)"
        if fm.fileExists(atPath: "\(dir)/aapt2") { return dir }

        let archive = "\(root)/build-tools.zip"
        try download("https://dl.google.com/android/repository/build-tools_r36_\(buildToolsSlug).zip",
                     to: archive, label: "build-tools \(buildToolsVersion)")
        try unzip(archive, into: "\(root)/build-tools-staging")

        // The directory name differs per release.
        let staging = "\(root)/build-tools-staging"
        guard let inner = (try? fm.contentsOfDirectory(atPath: staging))?.first else {
            throw AndroidError.missing("build-tools archive was empty")
        }
        try? fm.removeItem(atPath: dir)
        try fm.createDirectory(atPath: "\(root)/build-tools", withIntermediateDirectories: true)
        try fm.moveItem(atPath: "\(staging)/\(inner)", toPath: dir)
        try? fm.removeItem(atPath: staging)
        return dir
    }

    /// android.jar for the compile-time API surface.
    func platformJar() throws -> String {
        let jar = "\(root)/platforms/android-\(platformAPI)/android.jar"
        if fm.fileExists(atPath: jar) { return jar }

        let archive = "\(root)/platform.zip"
        try download("https://dl.google.com/android/repository/platform-34-ext7_r03.zip",
                     to: archive, label: "android-\(platformAPI) platform")
        try unzip(archive, into: "\(root)/platform-staging")

        let staging = "\(root)/platform-staging"
        guard let inner = (try? fm.contentsOfDirectory(atPath: staging))?.first else {
            throw AndroidError.missing("platform archive was empty")
        }
        try fm.createDirectory(atPath: "\(root)/platforms", withIntermediateDirectories: true)
        try? fm.removeItem(atPath: "\(root)/platforms/android-\(platformAPI)")
        try fm.moveItem(atPath: "\(staging)/\(inner)",
                        toPath: "\(root)/platforms/android-\(platformAPI)")
        try? fm.removeItem(atPath: staging)
        return jar
    }

    /// Adoptium's arch slug; their API needs no account.
    private var adoptiumArch: String {
        #if arch(arm64)
            return "aarch64"
        #else
            return "x64"
        #endif
    }

    private var adoptiumOS: String {
        #if os(macOS)
            return "mac"
        #else
            return "linux"
        #endif
    }

    /// The NDK, downloaded if ANDROID_NDK_HOME is unset. The Swift Android SDK
    /// links against its sysroot, so r27 is the floor.
    func ndk() throws -> String {
        if let fromEnv = env["ANDROID_NDK_HOME"], fm.fileExists(atPath: fromEnv) { return fromEnv }

        let version = "r28b"
        let installed = "\(root)/android-ndk-\(version)"
        if fm.fileExists(atPath: "\(installed)/source.properties") {
            stripPythonInstallers(installed)
            return installed
        }

        let archive = "\(root)/ndk-\(version).zip"
        try download("https://dl.google.com/android/repository/android-ndk-\(version)-\(osSlug).zip",
                     to: archive, label: "Android NDK \(version) (~700MB)")
        try unzip(archive, into: root)

        guard fm.fileExists(atPath: "\(installed)/source.properties") else {
            throw AndroidError.missing("""
                Could not install the Android NDK automatically.
                Download it and point ANDROID_NDK_HOME at it:

                  curl -fsSLO https://dl.google.com/android/repository/android-ndk-\(version)-\(osSlug).zip
                  unzip -q android-ndk-\(version)-\(osSlug).zip -d ~/.omni/toolchain
                  export ANDROID_NDK_HOME=~/.omni/toolchain/android-ndk-\(version)
                """)
        }
        stripPythonInstallers(installed)
        return installed
    }

    /// The NDK's Python without pip and setuptools (NDKPython says why).
    private func stripPythonInstallers(_ ndk: String) {
        let gone = NDKPython.stripInstallers(ndk: ndk, hostTag: ndkHostTag)
        if !gone.isEmpty {
            Console.info("removed the NDK Python's package installers (pip, setuptools): nothing builds with them, and their CA store is out of date")
        }
    }

    /// JAVA_HOME, a JDK on PATH, or a Temurin build from Adoptium.
    func jdkHome() throws -> String {
        if let home = env["JAVA_HOME"], fm.isExecutableFile(atPath: "\(home)/bin/javac") {
            return home
        }
        if let javac = try? Shell.run("command -v javac"), !javac.isEmpty {
            // <home>/bin/javac -> <home>
            return ((javac as NSString).deletingLastPathComponent as NSString).deletingLastPathComponent
        }

        // Cached from a previous run?
        if let entries = try? fm.contentsOfDirectory(atPath: root) {
            for entry in entries where entry.hasPrefix("jdk-") {
                for candidate in ["\(root)/\(entry)/Contents/Home", "\(root)/\(entry)"] {
                    if fm.isExecutableFile(atPath: "\(candidate)/bin/javac") { return candidate }
                }
            }
        }

        let url = "https://api.adoptium.net/v3/binary/latest/21/ga/"
            + "\(adoptiumOS)/\(adoptiumArch)/jdk/hotspot/normal/eclipse"
        let archive = "\(root)/temurin21.tar.gz"
        try download(url, to: archive, label: "Temurin JDK 21")

        let extract = try Shell.exec("/usr/bin/tar", ["xzf", archive, "-C", root])
        guard extract.status == 0 else {
            throw AndroidError.failed("extracting the JDK", extract.output)
        }

        if let entries = try? fm.contentsOfDirectory(atPath: root) {
            for entry in entries where entry.hasPrefix("jdk-") {
                // macOS bundles are jdk-21.x/Contents/Home; Linux is flat.
                for candidate in ["\(root)/\(entry)/Contents/Home", "\(root)/\(entry)"] {
                    if fm.isExecutableFile(atPath: "\(candidate)/bin/javac") { return candidate }
                }
            }
        }

        throw AndroidError.missing("""
            Could not install a JDK automatically. Install one (17 or newer) and
            set JAVA_HOME, for example:

              macOS:  brew install --cask temurin@21
              Debian: sudo apt install openjdk-21-jdk-headless
              manual: \(url)
            """)
    }

    func java(_ tool: String) throws -> String {
        let home = try jdkHome()
        let path = "\(home)/bin/\(tool)"
        guard fm.isExecutableFile(atPath: path) else {
            throw AndroidError.missing("\(tool) not found in \(home)/bin")
        }
        return path
    }

    /// A swift.org `swift`, even if PATH resolves to Xcode's: Xcode's compiler
    /// cannot read the Android SDK's modules.
    func swiftExecutable() throws -> String {
        func isSwiftOrg(_ candidate: String) -> Bool {
            guard fm.isExecutableFile(atPath: candidate),
                  let result = try? Shell.exec(candidate, ["--version"]),
                  result.status == 0 else { return false }
            return !result.output.contains("swiftlang-")
        }

        if let override = env["OMNI_SWIFT"] {
            guard isSwiftOrg(override) else {
                throw AndroidError.missing("OMNI_SWIFT=\(override) is not a swift.org toolchain.")
            }
            return override
        }

        if let onPath = try? Shell.run("command -v swift"), isSwiftOrg(onPath) {
            return onPath
        }

        var candidates = ["\(NSHomeDirectory())/.swiftly/bin/swift"]
        for toolchains in ["\(NSHomeDirectory())/Library/Developer/Toolchains",
                           "/Library/Developer/Toolchains"] {
            let entries = (try? fm.contentsOfDirectory(atPath: toolchains)) ?? []
            candidates += entries
                .filter { $0.hasSuffix(".xctoolchain") }
                .sorted()
                .reversed()
                .map { "\(toolchains)/\($0)/usr/bin/swift" }
        }

        if let found = candidates.first(where: isSwiftOrg) {
            Console.info("using swift.org toolchain at \(found)")
            return found
        }

        let active = (try? Shell.run("swift --version")) ?? "(none on PATH)"
        throw AndroidError.missing("""
            Cross-compiling for Android needs a swift.org toolchain. The active
            one is Xcode's, and no swift.org toolchain was found:

              \(active.split(whereSeparator: \.isNewline).first.map(String.init) ?? active)

            Even at the same version number these are different compiler builds,
            and the Android SDK's modules come from swift.org, so Xcode's
            compiler refuses them.

            Install one:

              curl -L https://swiftlang.github.io/swiftly/swiftly-install.sh | bash
              swiftly install 6.3.3

            Looked in:
            \(candidates.map { "  " + $0 }.joined(separator: "\n"))

            Set OMNI_SWIFT to a swift binary directly if it lives elsewhere.
            Xcode stays untouched for your macOS and iOS builds.
            """)
    }

    /// The version of the toolchain that will actually be used.
    func toolchainVersion() throws -> String {
        let swift = try swiftExecutable()
        let output = (try? Shell.exec(swift, ["--version"]).output) ?? ""
        guard !output.isEmpty else {
            throw AndroidError.missing("""
                No Swift toolchain on PATH. Install one, then re-run:

                  curl -L https://swiftlang.github.io/swiftly/swiftly-install.sh | bash
                  swiftly install latest
                """)
        }
        // Anchor on "Swift version": swift prints a driver version first
        // (swift-driver version: 1.148.6 Apple Swift version 6.3.3).
        guard let range = output.range(of: #"Swift version [0-9]+(\.[0-9]+)*"#,
                                       options: .regularExpression) else {
            throw AndroidError.missing("""
                Could not read a Swift version from:
                \(output)
                """)
        }
        let version = output[range]
            .replacingOccurrences(of: "Swift version ", with: "")

        return version
    }

    /// Every directory SwiftPM may keep installed SDKs in. Both can exist at once
    /// with bundles split between them.
    private func swiftSDKsDirectories() -> [String] {
        let candidates = [
            "\(NSHomeDirectory())/Library/org.swift.swiftpm/swift-sdks",
            "\(NSHomeDirectory())/.swiftpm/swift-sdks"
        ]
        return candidates.filter { fm.fileExists(atPath: $0) }
    }

    /// The installed artifactbundle for a Swift version, if present.
    func androidBundle(version: String) -> String? {
        for directory in swiftSDKsDirectories() {
            guard let entries = try? fm.contentsOfDirectory(atPath: directory) else { continue }
            if let match = entries.first(where: {
                $0.contains("swift-\(version)-RELEASE") && $0.lowercased().contains("android")
            }) {
                return "\(directory)/\(match)"
            }
        }
        return nil
    }

    /// Bundle directory names actually present, for diagnostics.
    func installedAndroidBundles() -> [String] {
        let directories = swiftSDKsDirectories()
        guard !directories.isEmpty else { return ["(no Swift SDK directory found)"] }

        var found: [String] = []
        for directory in directories {
            guard let entries = try? fm.contentsOfDirectory(atPath: directory) else { continue }
            found += entries
                .filter { $0.lowercased().contains("android") }
                .map { "\(directory)/\($0)" }
        }
        return found.isEmpty ? ["(none)"] : found
    }

    func scopedSDKDirectory(version: String) throws -> String? {
        guard let bundle = androidBundle(version: version) else { return nil }

        let scope = "\(root)/sdk-scope-\(version)"
        try? fm.removeItem(atPath: scope)
        try fm.createDirectory(atPath: scope, withIntermediateDirectories: true)
        try fm.createSymbolicLink(atPath: "\(scope)/\((bundle as NSString).lastPathComponent)",
                                  withDestinationPath: bundle)
        return scope
    }

    /// Where the Swift runtime .so files for an ABI live inside the bundle.
    func swiftRuntimeDirectory(version: String, arch: String) -> String? {
        guard let bundle = androidBundle(version: version) else { return nil }
        let path = "\(bundle)/swift-android/swift-resources/usr/lib/swift-\(arch)/android"
        return fm.fileExists(atPath: path) ? path : nil
    }

    /// Checksum from swift.org, so any release can be installed.
    private func publishedChecksum(for version: String) -> String? {
        guard let releases = try? Shell.exec("/usr/bin/curl",
                ["-fsSL", "https://www.swift.org/api/v1/install/releases.json"]),
              releases.status == 0,
              let data = releases.output.data(using: .utf8),
              let list = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else { return nil }

        for release in list where release["name"] as? String == version {
            for platform in (release["platforms"] as? [[String: Any]]) ?? [] {
                if platform["platform"] as? String == "android-sdk" {
                    return platform["checksum"] as? String
                }
            }
        }
        return nil
    }

    /// SDK and compiler versions must match exactly.
    @discardableResult
    func ensureSwiftAndroidSDK() throws -> String {
        let version = try toolchainVersion()

        if androidBundle(version: version) != nil {
            try ensureNDKSysroot(version: version)
            return version
        }

        // SwiftPM may otherwise resolve the triple to one of these.
        let installed = (try? Shell.exec(try swiftExecutable(), ["sdk", "list"]).output) ?? ""
        let stale = installed
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.lowercased().contains("android") }

        guard let checksum = publishedChecksum(for: version) else {
            throw AndroidError.missing("""
                No Swift SDK for Android matching your toolchain (Swift \(version)),
                and swift.org lists no bundle for that version.

                \(stale.isEmpty ? "" : "Installed but mismatched: \(stale.joined(separator: ", "))\n")
                The SDK version must equal the compiler version. Either install a
                toolchain that has a published Android SDK, or install the bundle
                manually from https://www.swift.org/install/:

                  swift sdk install <artifactbundle-url> --checksum <sha256>
                """)
        }

        if !stale.isEmpty {
            Console.warning("installed Android SDKs do not match Swift \(version): \(stale.joined(separator: ", "))")
            print("   after this completes, remove the stale one so the right bundle is chosen:")
            for entry in stale { print("     swift sdk remove \(entry)") }
        }

        let url = "https://download.swift.org/swift-\(version)-release/android-sdk/"
            + "swift-\(version)-RELEASE/swift-\(version)-RELEASE_android.artifactbundle.tar.gz"

        // Streamed, not captured: roughly a gigabyte, and SwiftPM prints its own
        // percentages. Swallowing them looks like a hang.
        Console.info("installing the Swift SDK for Android \(version) (~1GB, one time)")
        let install = try Shell.exec(try swiftExecutable(),
            ["sdk", "install", url, "--checksum", checksum], quiet: false)
        guard install.status == 0 else {
            throw AndroidError.failed("swift sdk install", install.output + """


                Install it manually with:
                  swift sdk install \(url) --checksum \(checksum)
                """)
        }

        try ensureNDKSysroot(version: version)
        return version
    }

    /// The SDK ships without a sysroot; skipping the link script yields 'jni.h' not found.
    private func ensureNDKSysroot(version: String) throws {
        guard let bundle = androidBundle(version: version) else { return }

        let sdkDir = "\(bundle)/swift-android"
        if fm.fileExists(atPath: "\(sdkDir)/ndk-sysroot/usr/include/jni.h") { return }

        let script = "\(sdkDir)/scripts/setup-android-sdk.sh"
        guard fm.fileExists(atPath: script) else { return }

        Console.info("linking the SDK sysroot to the NDK")
        let ndkPath = try ndk()
        let result = try Shell.exec("/bin/bash", [script],
                                    environment: ["ANDROID_NDK_HOME": ndkPath])
        guard result.status == 0 else {
            throw AndroidError.failed("linking the NDK sysroot", result.output + """


                Run it manually:
                  ANDROID_NDK_HOME=\(ndkPath) \(script)
                """)
        }
    }

    /// A debug keystore, generated once. Unsigned APKs cannot be installed.
    func debugKeystore() throws -> String {
        let keystore = "\(root)/debug.keystore"
        if fm.fileExists(atPath: keystore) { return keystore }

        Console.info("generating debug keystore")
        let keytool = try java("keytool")
        let result = try Shell.exec(keytool, [
            "-genkeypair", "-keystore", keystore,
            "-storepass", "android", "-keypass", "android",
            "-alias", "omnidebug", "-keyalg", "RSA", "-keysize", "2048",
            "-validity", "10000", "-dname", "CN=Omni Debug"
        ])
        guard result.status == 0 else {
            throw AndroidError.failed("generating keystore", result.output)
        }
        return keystore
    }
}

// MARK: - Builder

public struct AndroidBuilder {
    public let target: String
    public let path: String
    /// omni.json's resolved `flags`, embedded in the generated entry.
    let flags: AppFlags

    private let tools = AndroidToolchain()
    private let fm = FileManager.default

    init(target: String, path: String, flags: AppFlags = .none) {
        self.target = target
        self.path = path
        self.flags = flags
    }

    func packageName(for product: String) -> String {
        OmniManifest.load(from: path).bundleIdentifier
            ?? ProcessInfo.processInfo.environment["OMNI_PACKAGE"]
            ?? "com.omniswift.\(product.lowercased())"
    }

    /// The symbol the generated MainActivity's native method resolves to.
    func expectedJNISymbol(for product: String) -> String {
        "Java_" + packageName(for: product).replacingOccurrences(of: ".", with: "_")
            + "_MainActivity_startSwiftEngine"
    }

    func apkPath(product: String, abi: String) -> String {
        "\(packageRoot())/.omni/android/\(product)-\(abi).apk"
    }

    /// Nearest enclosing directory with a Package.swift. --app-path is often an
    /// example subdirectory rather than the package root.
    func packageRoot() -> String {
        var directory = URL(fileURLWithPath: path).standardizedFileURL
        for _ in 0..<12 {
            if fm.fileExists(atPath: directory.appendingPathComponent("Package.swift").path) {
                return directory.path
            }
            let parent = directory.deletingLastPathComponent()
            if parent.path == directory.path { break }
            directory = parent
        }
        return path
    }

    /// The Omni checkout the app builds against: an enclosing directory for the
    /// examples, else the package's own dependency on Omni, local or fetched.
    func frameworkRoot() -> String? {
        var directory = URL(fileURLWithPath: packageRoot()).standardizedFileURL
        for _ in 0..<12 {
            if isFramework(directory.path) { return directory.path }
            let parent = directory.deletingLastPathComponent()
            if parent.path == directory.path { break }
            directory = parent
        }

        // A path: dependency, e.g. an app next to omni rather than inside it.
        var candidates: [String] = []
        if let swift = try? tools.swiftExecutable(),
           let dump = try? Shell.exec(swift,
                ["package", "dump-package", "--package-path", packageRoot()]),
           dump.status == 0,
           let data = dump.output.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let dependencies = json["dependencies"] as? [[String: Any]] {
            for dependency in dependencies {
                for entry in dependency["fileSystem"] as? [[String: Any]] ?? [] {
                    if let path = entry["path"] as? String { candidates.append(path) }
                }
            }
        }
        // A url: dependency lives in SwiftPM's checkouts.
        let checkouts = "\(packageRoot())/.build/checkouts"
        candidates += ((try? fm.contentsOfDirectory(atPath: checkouts)) ?? [])
            .map { "\(checkouts)/\($0)" }
        return candidates.first(where: isFramework)
    }

    private func isFramework(_ directory: String) -> Bool {
        fm.fileExists(atPath: "\(directory)/src/ui/android/OmniEventBridge.java")
    }

    /// The product to build. --output defaults to "App", so an unmatched name
    /// falls back to the sole dynamic library product.
    func resolveProduct() throws -> String {
        let root = packageRoot()
        guard fm.fileExists(atPath: "\(root)/Package.swift") else {
            throw AndroidError.missing(
                "No Package.swift found at \(path) or in any parent directory.")
        }

        let dump = try Shell.exec(try tools.swiftExecutable(),
            ["package", "dump-package", "--package-path", root])
        guard dump.status == 0,
              let data = dump.output.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let products = json["products"] as? [[String: Any]] else {
            throw AndroidError.failed("reading the package manifest", dump.output)
        }

        var dynamicLibraries: [String] = []
        var everything: [String] = []
        for entry in products {
            guard let name = entry["name"] as? String else { continue }
            everything.append(name)
            if let type = entry["type"] as? [String: Any],
               let library = type["library"] as? [String],
               library.contains("dynamic") {
                dynamicLibraries.append(name)
            }
        }

        if dynamicLibraries.contains(target) { return target }

        if dynamicLibraries.count == 1 {
            let only = dynamicLibraries[0]
            if target != "App" {
                Console.info("no dynamic library product named '\(target)'; using '\(only)'")
            }
            return only
        }

        if dynamicLibraries.isEmpty {
            throw AndroidError.missing("""
                This package has no dynamic library product, which Android needs
                because the JVM loads the app as a shared library.

                Add one to Package.swift:
                    .library(name: "MyApp", type: .dynamic, targets: ["MyApp"])

                Products found: \(everything.isEmpty ? "none" : everything.joined(separator: ", "))
                """)
        }

        throw AndroidError.missing("""
            This package has several dynamic library products, so pick one:

              omni build --platform android --output <name>

            Available: \(dynamicLibraries.joined(separator: ", "))
            """)
    }

    func triple(for abi: String) throws -> String {
        switch abi {
        case "arm64-v8a": return "aarch64-unknown-linux-android28"
        case "x86_64":    return "x86_64-unknown-linux-android28"
        case "armeabi-v7a": return "armv7-unknown-linux-android28"
        default: throw AndroidError.missing("unsupported ABI: \(abi)")
        }
    }

    func swiftArch(for abi: String) throws -> String {
        switch abi {
        case "arm64-v8a": return "aarch64"
        case "x86_64":    return "x86_64"
        case "armeabi-v7a": return "armv7"
        default: throw AndroidError.missing("unsupported ABI: \(abi)")
        }
    }

    func ndkLibDir(for abi: String) throws -> String {
        switch abi {
        case "arm64-v8a": return "aarch64-linux-android"
        case "x86_64":    return "x86_64-linux-android"
        case "armeabi-v7a": return "arm-linux-androideabi"
        default: throw AndroidError.missing("unsupported ABI: \(abi)")
        }
    }

    /// Contents only: copyItem replicates permissions, which 9p and SMB refuse.
    private func copyFile(_ source: String, to destination: String) throws {
        let data = try Data(contentsOf: URL(fileURLWithPath: source))
        try data.write(to: URL(fileURLWithPath: destination))
    }

    /// Locates the `App` conforming type so the JNI entry can name it.
    func findAppType(in root: String) throws -> (type: String, directory: String) {
        if let explicit = ProcessInfo.processInfo.environment["OMNI_APP_TYPE"],
           let anySource = enumerateSwiftSources(root).first {
            return (explicit, (anySource as NSString).deletingLastPathComponent)
        }

        for file in enumerateSwiftSources(root) {
            guard let text = try? String(contentsOfFile: file, encoding: .utf8) else { continue }
            guard let range = text.range(
                of: #"struct\s+([A-Za-z_][A-Za-z0-9_]*)\s*:\s*App\b"#,
                options: .regularExpression) else { continue }

            let declaration = String(text[range])
            let name = declaration
                .replacingOccurrences(of: #"struct\s+"#, with: "", options: .regularExpression)
                .replacingOccurrences(of: #"\s*:\s*App\b"#, with: "", options: .regularExpression)
            return (name, (file as NSString).deletingLastPathComponent)
        }

        throw AndroidError.missing("""
            No type conforming to App was found under \(root).

            An Omni app declares one, exactly as it does on iOS:

                struct MyApp: App {
                    var body: some View { ContentView() }
                }

            Set OMNI_APP_TYPE to name it explicitly if it lives elsewhere.
            """)
    }

    private func enumerateSwiftSources(_ root: String) -> [String] {
        guard let walker = fm.enumerator(atPath: root) else { return [] }
        return walker.compactMap { $0 as? String }
            .filter { $0.hasSuffix(".swift") && !$0.hasPrefix(".") }
            .filter { !$0.contains("/.build/") && !$0.contains(".omni/") }
            .filter { $0 != "Package.swift" }
            .map { "\(root)/\($0)" }
    }

    /// Writes the JNI entry point beside the app declaration for the build, then
    /// removes it. Keeps @_cdecl/JNIEnv/jobject out of application sources.
    func writeAndroidEntry(appType: String, directory: String, product: String) throws -> String {
        let path = "\(directory)/OmniAndroidEntry.generated.swift"
        // Compiled in, not an APK asset: Swift has no AssetManager of its own.
        // Base64, so no value needs escaping inside a Swift literal.
        let installFlags = flags.isEmpty ? ""
            : "Flags.install(base64: \"\(try flags.json().base64EncodedString())\")\n    "
        let source = """
        // Generated by `omni build --platform android`. Do not edit; this file
        // is written before the build and removed after it.
        #if os(Android)
        import OmniUI
        import CAndroid

        // @MainActor on the function: a closure boundary trips Swift 6's sending check.
        @_cdecl("\(expectedJNISymbol(for: product))")
        @MainActor
        public func omniAndroidMain(
            _ env: UnsafeMutablePointer<JNIEnv?>?,
            _ thiz: jobject?,
            _ activity: jobject?
        ) {
            \(installFlags)OmniAndroid.launch(\(appType)(), env: env, activity: activity)
        }
        #endif

        """
        try source.write(toFile: path, atomically: true, encoding: .utf8)
        return path
    }

    public func build() throws {
        try build(abi: ProcessInfo.processInfo.environment["OMNI_ABI"] ?? "arm64-v8a")
    }

    @discardableResult
    public func build(abi: String) throws -> String {
        flags.announce()
        let product = try resolveProduct()
        let root = packageRoot()
        // Staged off the project: zip and zipalign rewrite in place, which some
        // shares reject.
        let stage = ProcessInfo.processInfo.environment["OMNI_STAGE"]
            ?? "\(NSHomeDirectory())/.omni/build/stage-\(product)-\(abi)"
        try? fm.removeItem(atPath: stage)
        for sub in ["java", "classes", "dex", "lib/\(abi)"] {
            try fm.createDirectory(atPath: "\(stage)/\(sub)", withIntermediateDirectories: true)
        }

        let swiftVersion = try tools.ensureSwiftAndroidSDK()
        let ndk = try tools.ndk()
        let buildTools = try tools.buildTools()
        let androidJar = try tools.platformJar()
        let triple = try triple(for: abi)

        let app: (type: String, directory: String)
        if let inAppPath = try? findAppType(in: path) {
            app = inAppPath
        } else {
            app = try findAppType(in: root)
        }
        let entryPath = try writeAndroidEntry(appType: app.type,
                                              directory: app.directory,
                                              product: product)
        defer { try? fm.removeItem(atPath: entryPath) }

        let javaPackageDir = "\(stage)/java/"
            + packageName(for: product).replacingOccurrences(of: ".", with: "/")
        try fm.createDirectory(atPath: javaPackageDir, withIntermediateDirectories: true)
        try mainActivity(product: product).write(toFile: "\(javaPackageDir)/MainActivity.java",
                                 atomically: true, encoding: .utf8)

        // Java -> classes, before the Swift build: it needs nothing from it and
        // takes seconds, so a Java error in the bridge fails the build now, not
        // after minutes of Swift. The framework's own bridge classes come from
        // the library sources so the APK carries them too. Dexed in step 4.
        Console.info("compiling java")
        // MainActivity calls into com.omni, so a missing bridge is an error here,
        // not four confusing ones from javac.
        guard let framework = frameworkRoot() else {
            throw AndroidError.missing("""
                Couldn't find Omni's Java bridge (src/ui/android). Put the app inside
                the omni checkout or depend on Omni from its Package.swift.
                """)
        }
        let bridgeDir = "\(framework)/src/ui/android"
        let bridge = try fm.contentsOfDirectory(atPath: bridgeDir)
        var javaSources = ["\(javaPackageDir)/MainActivity.java"]
            + bridge.filter { $0.hasSuffix(".java") }.map { "\(bridgeDir)/\($0)" }
        var classpath = androidJar
        let play = try PlayIntegrityVendor(framework: framework, app: path)
        if let play {
            Console.info("play integrity: \(play.jar)")
            javaSources.append(play.bridge)
            classpath += ":" + play.jar
        }

        let javac = try Shell.exec(try tools.java("javac"),
            ["-nowarn", "-classpath", classpath, "-d", "\(stage)/classes"] + javaSources)
        guard javac.status == 0 else { throw AndroidError.failed("javac", javac.output) }

        Console.info("building \(product) for \(abi) · app \(app.type)")
        // SwiftPM's clone needs chmod, which 9p and SMB refuse.
        let scratch = ProcessInfo.processInfo.environment["OMNI_SCRATCH"]
            ?? "\(NSHomeDirectory())/.omni/build/\(product)-\(abi)"
        var buildArguments = [
            "build",
            "--product", product,
            "--package-path", root,
            "--swift-sdk", triple,
            "--scratch-path", scratch,
            // liblog for __android_log_print, libandroid for the platform APIs.
            "-Xlinker", "-llog",
            "-Xlinker", "-landroid"
        ]
        // Never build unscoped: SwiftPM may resolve the triple to another compiler's bundle.
        guard let scope = try tools.scopedSDKDirectory(version: swiftVersion) else {
            throw AndroidError.missing("""
                No Swift SDK for Android matching Swift \(swiftVersion) is installed,
                so the build cannot be pinned to the right one.

                Installed bundles:
                \(tools.installedAndroidBundles().map { "  " + $0 }.joined(separator: "\n"))

                Install the matching bundle:
                  swift sdk install \
                    https://download.swift.org/swift-\(swiftVersion)-release/android-sdk/swift-\(swiftVersion)-RELEASE/swift-\(swiftVersion)-RELEASE_android.artifactbundle.tar.gz \
                    --checksum <sha256 from https://www.swift.org/install/>
                """)
        }
        buildArguments += ["--swift-sdks-path", scope]
        print("   swift \(swiftVersion) · SDK scoped to \(scope)")

        // SwiftPM reuses its build plan unless it sees a directory change, and on
        // shared folders (9p, SMB, VirtioFS) a new file may not change one: the file
        // was left out of the build. Planning again costs seconds.
        try? fm.removeItem(atPath: "\(scratch)/\(triple)/debug/description.json")
        let swiftBuild = try Shell.exec(try tools.swiftExecutable(), buildArguments,
            environment: ["ANDROID_NDK_HOME": ndk], quiet: true)

        guard swiftBuild.status == 0 else {
            throw AndroidError.failed("swift build", swiftBuild.output)
        }

        let soName = "lib\(product).so"
        guard let builtSO = Self.builtLibrary(soName, in: scratch, triple: triple, fm: fm) else {
            throw AndroidError.missing("""
                \(soName) was not produced.
                Package.swift must declare the app as a dynamic library, e.g.
                    .library(name: "\(product)", type: .dynamic, targets: ["\(product)"])
                """)
        }
        // A mismatch surfaces at launch as UnsatisfiedLinkError.
        let soBytes = try Data(contentsOf: URL(fileURLWithPath: builtSO))
        guard let symbol = expectedJNISymbol(for: product).data(using: .utf8),
              soBytes.range(of: symbol) != nil else {
            throw AndroidError.missing("""
                \(soName) does not export \(expectedJNISymbol(for: product)).

                The JNI entry point's name must match the app's package. Declare it as:
                    @_cdecl("\(expectedJNISymbol(for: product))")
                    public func startSwiftEngine(
                        _ env: UnsafeMutablePointer<JNIEnv?>?,
                        _ thiz: jobject?,
                        _ activity: jobject?
                    ) { ... }

                Or set OMNI_PACKAGE to the package your entry point already targets.
                """)
        }

        try copyFile(builtSO, to: "\(stage)/lib/\(abi)/\(soName)")

        // 2. Swift runtime + libc++, which the APK must carry itself.
        guard let swiftRuntime = tools.swiftRuntimeDirectory(
                version: swiftVersion, arch: try swiftArch(for: abi)) else {
            throw AndroidError.missing("""
                Could not find the Swift runtime for \(abi) in the Android SDK
                for Swift \(swiftVersion). Without it the APK loads no Swift
                runtime and dies at startup.
                """)
        }
        if let runtimeLibs = try? fm.contentsOfDirectory(atPath: swiftRuntime) {
            for lib in runtimeLibs where lib.hasSuffix(".so") {
                try? copyFile("\(swiftRuntime)/\(lib)",
                              to: "\(stage)/lib/\(abi)/\(lib)")
            }
        }
        let libcpp = "\(ndk)/toolchains/llvm/prebuilt/\(tools.ndkHostTag)/sysroot/usr/lib/"
            + "\(try ndkLibDir(for: abi))/libc++_shared.so"
        try? copyFile(libcpp, to: "\(stage)/lib/\(abi)/libc++_shared.so")

        let icon = AppIcon.resolve(in: path, name: product)
        try manifest(product: product, hasIcon: true, play: play)
            .write(toFile: "\(stage)/AndroidManifest.xml", atomically: true, encoding: .utf8)

        // aapt2 needs res/ compiled before link can reference it; see step 5.
        let resDir = "\(stage)/res"
        Console.info(icon.isPlaceholder
              ? "No icon.png — using the placeholder"
              : "Generating app icon...")
        try AppIcon.writeAndroidMipmaps(source: icon, into: resDir)


        // 4. classes -> dex.
        let classFiles = (fm.enumerator(atPath: "\(stage)/classes")?
            .compactMap { $0 as? String }
            .filter { $0.hasSuffix(".class") }
            .map { "\(stage)/classes/\($0)" }) ?? []

        let d8 = try Shell.exec(try tools.java("java"),
            ["-cp", "\(buildTools)/lib/d8.jar", "com.android.tools.r8.D8",
             "--min-api", "28", "--lib", androidJar, "--output", "\(stage)/dex"] + classFiles + (play.map { [$0.jar] } ?? []))
        guard d8.status == 0 else { throw AndroidError.failed("d8", d8.output) }

        // aapt2 links the manifest and resources into base.apk.
        Console.info("packaging")
        var linkArgs = [
            "link", "-I", androidJar,
            "--manifest", "\(stage)/AndroidManifest.xml",
            "--min-sdk-version", "28", "--target-sdk-version", "34",
            "-o", "\(stage)/base.apk"
        ]
        // The app's Fonts/<Family>/, as assets/Fonts/; see AppFonts.swift.
        let fonts = AppFonts.find(in: path)
        fonts.announce()
        let assetsDir = "\(stage)/assets"
        try? fm.removeItem(atPath: assetsDir)
        if !fonts.isEmpty {
            try fonts.copy(into: assetsDir)
            // Stored, not deflated: a font is read in place, by offset.
            linkArgs += ["-A", assetsDir, "-0", "ttf", "-0", "otf"]
        }
        // Every build has an icon, so every build has a res/.
        do {
            let compiled = "\(stage)/compiled.zip"
            let compile = try tools.runHostTool("\(buildTools)/aapt2", [
                "compile", "--dir", resDir, "-o", compiled
            ])
            guard compile.status == 0 else { throw AndroidError.failed("aapt2 compile", compile.output) }
            linkArgs.append(compiled)
        }
        let aapt2 = try tools.runHostTool("\(buildTools)/aapt2", linkArgs)
        guard aapt2.status == 0 else { throw AndroidError.failed("aapt2 link", aapt2.output) }

        // 6. Add dex + native libs, align, sign.
        try? fm.removeItem(atPath: "\(stage)/unsigned.apk")
        try copyFile("\(stage)/base.apk", to: "\(stage)/unsigned.apk")
        try copyFile("\(stage)/dex/classes.dex", to: "\(stage)/classes.dex")

        _ = try Shell.exec("/bin/sh", ["-c",
            "cd \(shellQuote(stage)) && zip -q unsigned.apk classes.dex && zip -q -r unsigned.apk lib"])

        let aligned = "\(stage)/aligned.apk"
        try? fm.removeItem(atPath: aligned)
        let zipalign = try tools.runHostTool("\(buildTools)/zipalign",
            ["-f", "4", "\(stage)/unsigned.apk", aligned])
        guard zipalign.status == 0 else { throw AndroidError.failed("zipalign", zipalign.output) }

        let output = apkPath(product: product, abi: abi)
        // apksigner throws if the parent directory does not already exist.
        try fm.createDirectory(atPath: (output as NSString).deletingLastPathComponent,
                               withIntermediateDirectories: true)
        try? fm.removeItem(atPath: output)
        let signer = try Shell.exec(try tools.java("java"), [
            "-cp", "\(buildTools)/lib/apksigner.jar", "com.android.apksigner.ApkSignerTool",
            "sign", "--ks", try tools.debugKeystore(),
            "--ks-pass", "pass:android", "--key-pass", "pass:android",
            "--min-sdk-version", "28", "--out", output, aligned
        ])
        guard signer.status == 0 else { throw AndroidError.failed("apksigner", signer.output) }

        Console.success("\(output)")
        return output
    }

    private func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// One VIEW intent-filter per declared scheme. BROWSABLE is what lets a
    /// link in a browser or a message reach the app.
    private func deepLinkFilters() -> String {
        let schemes = OmniManifest.load(from: path).validatedSchemes
        guard !schemes.isEmpty else { return "" }
        return schemes.map { scheme in
            """

                        <intent-filter>
                            <action android:name="android.intent.action.VIEW" />
                            <category android:name="android.intent.category.DEFAULT" />
                            <category android:name="android.intent.category.BROWSABLE" />
                            <data android:scheme="\(scheme)" />
                        </intent-filter>
            """
        }.joined()
    }

    /// singleTask is what routes a second link to onNewIntent instead of a new Activity.
    private func launchMode() -> String {
        OmniManifest.load(from: path).validatedSchemes.isEmpty
            ? "" : " android:launchMode=\"singleTask\""
    }

    private func manifest(product: String, hasIcon: Bool, play: PlayIntegrityVendor? = nil) -> String {
        // Referencing an absent mipmap makes aapt2 link fail.
        let iconAttr = hasIcon ? "\n                         android:icon=\"@mipmap/ic_launcher\"" : ""
        return """
        <?xml version="1.0" encoding="utf-8"?>
        <manifest xmlns:android="http://schemas.android.com/apk/res/android"
                  package="\(packageName(for: product))">
            <uses-sdk android:minSdkVersion="28" android:targetSdkVersion="34" />

            <!-- Without this every request fails with an unhelpful error. -->
            <uses-permission android:name="android.permission.INTERNET" />

            <!-- Unconditional: the CLI cannot tell whether OmniCamera is
                 linked, and an unused permission costs nothing at runtime. -->
            <uses-permission android:name="android.permission.CAMERA" />

            <!-- Approval keys. -->
            <uses-permission android:name="android.permission.USE_BIOMETRIC" />

            <application android:label="\(product)"
                         android:theme="@android:style/Theme.DeviceDefault.Light.NoActionBar"
                         android:extractNativeLibs="true"
                         android:debuggable="true"
                         android:usesCleartextTraffic="true"\(iconAttr)>
                <!-- configChanges: rotating, resizing or a keyboard coming and going
                     keeps the activity. Recreating it would start the engine
                     again; omni lays the root out at the new size instead. -->
                <activity android:name="\(packageName(for: product)).MainActivity" android:exported="true"
                          android:configChanges="orientation|screenSize|screenLayout|smallestScreenSize|keyboard|keyboardHidden|navigation"\(launchMode())>
                    <intent-filter>
                        <action android:name="android.intent.action.MAIN" />
                        <category android:name="android.intent.category.LAUNCHER" />
                    </intent-filter>\(deepLinkFilters())
                </activity>

                <!-- OmniFileProvider: a file:// Uri handed to another app has
                     been blocked since API 24, and androidx.core.content
                     .FileProvider is a Gradle dependency this build cannot
                     resolve. -->
                <provider android:name="com.omni.OmniFileProvider"
                          android:authorities="\(packageName(for: product)).omnifileprovider"
                          android:exported="false"
                          android:grantUriPermissions="true" />\(play?.manifestEntries ?? "")
            </application>
        </manifest>
        """
    }

    private func mainActivity(product: String) -> String {
        """
        package \(packageName(for: product));

        import android.app.Activity;
        import android.content.Intent;
        import android.os.Bundle;

        public class MainActivity extends Activity {
            static {
                // Dependencies first: no RPATH finds their siblings.
                System.loadLibrary("c++_shared");
                System.loadLibrary("swiftCore");
                System.loadLibrary("\(product)");
            }

            public native void startSwiftEngine(Object activity);

            @Override
            protected void onCreate(Bundle savedInstanceState) {
                super.onCreate(savedInstanceState);
                // The app's fonts, before the first render lays text out.
                com.omni.OmniEventBridge.registerBundledFonts(this);
                startSwiftEngine(this);
                // The launch intent, for a cold start. DeepLink holds it until the app's
                // handler is installed.
                com.omni.OmniEventBridge.deliverIntent(getIntent());
            }

            // AppLifecycle: stopped is in the background, whatever stopped it.
            @Override
            protected void onStart() {
                super.onStart();
                com.omni.OmniEventBridge.dispatchLifecycle(true);
            }

            @Override
            protected void onStop() {
                super.onStop();
                com.omni.OmniEventBridge.dispatchLifecycle(false);
            }

            // Every touch passes here first, whatever view it lands on: what
            // an idle timer counts as activity. It only watches.
            @Override
            public boolean dispatchTouchEvent(android.view.MotionEvent event) {
                int action = event.getActionMasked();
                if (action == android.view.MotionEvent.ACTION_DOWN
                        || action == android.view.MotionEvent.ACTION_POINTER_DOWN) {
                    com.omni.OmniEventBridge.dispatchActivity();
                }
                return super.dispatchTouchEvent(event);
            }

            // A link arriving at a running app; reached because of singleTask.
            @Override
            protected void onNewIntent(Intent intent) {
                super.onNewIntent(intent);
                setIntent(intent);
                com.omni.OmniEventBridge.deliverIntent(intent);
            }

            // OmniCamera's permission and capture/pick results. Per-Activity overrides,
            // so they belong in generated code; see OmniEventBridge.java.
            @Override
            public void onRequestPermissionsResult(int requestCode, String[] permissions, int[] grantResults) {
                super.onRequestPermissionsResult(requestCode, permissions, grantResults);
                com.omni.OmniEventBridge.onRequestPermissionsResult(requestCode, grantResults);
            }

            @Override
            protected void onActivityResult(int requestCode, int resultCode, Intent data) {
                super.onActivityResult(requestCode, resultCode, data);
                com.omni.OmniEventBridge.onActivityResult(requestCode, resultCode, data);
            }
        }
        """
    }
}

// MARK: - Deployment

struct AndroidDevice {
    let serial: String
    let model: String
    let release: String
    let abi: String
}

public struct AndroidDeployer {
    let builder: AndroidBuilder
    private let tools = AndroidToolchain()

    init(target: String, path: String, flags: AppFlags = .none) {
        builder = AndroidBuilder(target: target, path: path, flags: flags)
    }

    func adbx(_ device: AndroidDevice?, _ arguments: [String]) throws -> (status: Int32, output: String) {
        let adb = try tools.adb()
        let prefix = device.map { ["-s", $0.serial] } ?? []
        return try tools.runHostTool(adb, prefix + arguments)
    }

    func attachedDevice() throws -> AndroidDevice {
        _ = try? adbx(nil, ["start-server"])
        let listing = try adbx(nil, ["devices"])

        var serials: [String] = []
        var unauthorized = false
        for line in listing.output.split(whereSeparator: \.isNewline).dropFirst() {
            let parts = line.split(separator: "\t").map(String.init)
            guard parts.count == 2 else { continue }
            if parts[1].hasPrefix("unauthorized") { unauthorized = true }
            if parts[1] == "device" { serials.append(parts[0]) }
        }

        if unauthorized {
            throw AndroidError.missing(
                "Device is unauthorized — accept the 'Allow USB debugging' prompt, then retry.")
        }
        guard let serial = serials.first else {
            throw AndroidError.missing(
                "No device detected. Connect over USB with debugging enabled, or `adb connect` a wireless one.")
        }
        if serials.count > 1 {
            Console.warning("\(serials.count) devices attached; using \(serial)")
        }

        func prop(_ name: String) -> String {
            ((try? adbx(AndroidDevice(serial: serial, model: "", release: "", abi: ""),
                        ["shell", "getprop", name]))?.output ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return AndroidDevice(serial: serial,
                             model: prop("ro.product.model"),
                             release: prop("ro.build.version.release"),
                             abi: prop("ro.product.cpu.abi"))
    }

    /// Builds for the ABI the attached device reports.
    public func run() throws {
        let device = try attachedDevice()
        Console.info("\(device.model) (Android \(device.release), \(device.abi)) [\(device.serial)]")

        let apk = try builder.build(abi: device.abi)

        Console.info("installing")
        let install = try adbx(device, ["install", "-r", "-g", apk])
        guard install.status == 0, !install.output.contains("FAILED") else {
            throw AndroidError.failed("adb install", install.output)
        }

        _ = try? adbx(device, ["logcat", "-c"])

        let product = try builder.resolveProduct()
        let activity = "\(builder.packageName(for: product))/.MainActivity"
        let launch = try adbx(device, ["shell", "am", "start", "-W", "-n", activity])
        print(launch.output)

        Thread.sleep(forTimeInterval: 3)

        let pid = try adbx(device, ["shell", "pidof", builder.packageName(for: product)])
        if pid.output.isEmpty {
            Console.failure("process is not running — it started and died")
        } else {
            Console.success("running (pid \(pid.output))")
        }

        // The crash buffer carries the exception or tombstone. Filtering the main
        // buffer by package is useless: the window manager names it on every line.
        let crash = try adbx(device, ["logcat", "-b", "crash", "-d", "-t", "200"])
        if !crash.output.isEmpty {
            print("\n--- crash ---")
            print(crash.output)
        }

        // Native aborts and linker failures use the main buffer.
        let layout = try adbx(device, ["logcat", "-d", "-s", "OmniLayout:I", "-t", "400"])
        let tree = layout.output.split(whereSeparator: \.isNewline)
            .filter { $0.contains("OmniLayout") }
        if !tree.isEmpty {
            print("\n--- layout ---")
            print(tree.joined(separator: "\n"))
        }

        let crashTags = ["AndroidRuntime", "DEBUG", "libc", "linker", "System.err", "art"]
        let log = try adbx(device, ["logcat", "-d", "-t", "400"])
        let interesting = log.output.split(whereSeparator: \.isNewline).filter { line in
            crashTags.contains { line.contains(" \($0)") }
                || line.lowercased().contains("unsatisfiedlink")
                || line.lowercased().contains("dlopen")
        }
        if !interesting.isEmpty {
            print("\n--- runtime/linker ---")
            print(interesting.suffix(40).joined(separator: "\n"))
        }

        if crash.output.isEmpty && interesting.isEmpty {
            print("""

                No crash detail captured. Get it directly with:
                  adb logcat -b crash -d
                  adb logcat -d | grep -E 'AndroidRuntime|DEBUG|libc|linker'
                """)
        }
    }
}

extension AndroidBuilder {
    /// `<triple>/debug/`, or `out/Products/<Config>-android-<arch>/` from Swift 6.4.
    static func builtLibrary(_ soName: String, in scratch: String, triple: String, fm: FileManager) -> String? {
        let legacy = "\(scratch)/\(triple)/debug/\(soName)"
        if fm.fileExists(atPath: legacy) { return legacy }
        let products = "\(scratch)/out/Products"
        let arch = triple.split(separator: "-").first.map(String.init) ?? ""
        let candidates = ((try? fm.contentsOfDirectory(atPath: products)) ?? [])
            .filter { $0.hasSuffix("-android-\(arch)") }
            .map { "\(products)/\($0)/\(soName)" }
            .filter { fm.fileExists(atPath: $0) }
        // Newest.
        return candidates.max { a, b in
            let date = { (path: String) in
                (try? fm.attributesOfItem(atPath: path)[.modificationDate] as? Date) ?? .distantPast
            }
            return date(a) < date(b)
        }
    }
}
