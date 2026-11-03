// src/cli/platform/Setup.swift
import Foundation
import ArgumentParser

/// What a target platform needs on this machine, checked in order before
/// anything compiles, so a first build on a new Mac either sets itself up or
/// says, in one list, exactly what's left, instead of failing on one missing
/// tool at a time.
///
/// Three kinds of fix:
///   - omni downloads it into ~/.omni without asking (the NDK, a JDK, ...),
///     as builds always have;
///   - omni installs it after asking, because it needs an administrator
///     password, an Apple ID, or many gigabytes (Homebrew, Xcode, ...);
///   - the person has to do it, and gets the exact command.
enum Setup {
    enum State {
        /// Present. The detail is a path or version.
        case ok(String)
        /// Missing, and the build downloads it into ~/.omni on its own.
        case downloads(String)
        /// Missing, and `fix` installs it.
        case missing(String, Fix)
        /// Missing, and only the person can fix it.
        case manual(String, [String])

        var isSatisfied: Bool {
            switch self {
            case .ok, .downloads: return true
            case .missing, .manual: return false
            }
        }
    }

    struct Fix {
        /// "Install Homebrew", as the question asks it.
        let summary: String
        /// The command, shown to anyone who'd rather run it themselves.
        let commands: [String]
        /// Asked before running: a password, an Apple ID, or a big download.
        /// Fixes that don't ask run as part of the build, as downloads do.
        let asks: Bool
        let apply: () throws -> Void
    }

    struct Requirement {
        let name: String
        let check: () -> State
    }

    enum Mode {
        /// `omni doctor`: report only.
        case report
        /// `omni doctor --fix`: report and fix.
        case fixAll
        /// Before `omni build`/`run`: quiet unless something's missing.
        case preflight
    }

    // MARK: - Running the checks

    /// Throws `SetupError.incomplete` if a requirement is still unmet.
    static func ensure(_ platform: Platform, mode: Mode) throws {
        if mode == .preflight, ProcessInfo.processInfo.environment["OMNI_SKIP_SETUP"] == "1" { return }
        let requirements = self.requirements(for: platform)
        if mode != .preflight {
            if requirements.isEmpty {
                Console.info("no setup checks for \(platform.rawValue) on this machine")
                return
            }
            #if os(macOS)
                print("\(platform.rawValue) on this Mac:")
            #else
                print("\(platform.rawValue) on this machine:")
            #endif
        }

        let interactive = isatty(STDIN_FILENO) == 1 && isatty(STDOUT_FILENO) == 1
        var unmet: [(name: String, detail: String, commands: [String])] = []

        for requirement in requirements {
            var state = requirement.check()

            if case .missing(let detail, let fix) = state, mode != .report {
                let go: Bool
                if !fix.asks {
                    go = true
                } else if interactive {
                    report(requirement.name, state)
                    go = confirm("\(fix.summary)?")
                } else {
                    go = false
                }
                if go {
                    Console.info("\(fix.summary.lowercased())…")
                    do {
                        try fix.apply()
                        state = requirement.check()
                    } catch {
                        let reason = (error as? LocalizedError)?.errorDescription ?? "\(error)"
                        state = .manual("\(detail): \(reason)", fix.commands)
                    }
                }
            }

            if mode != .preflight || !state.isSatisfied { report(requirement.name, state) }

            switch state {
            case .ok, .downloads: break
            case .missing(let detail, let fix): unmet.append((requirement.name, detail, fix.commands))
            case .manual(let detail, let commands): unmet.append((requirement.name, detail, commands))
            }
            // Fixing goes in order (no Xcode, no license to accept), so the
            // first unmet one ends it. A report lists everything.
            if !unmet.isEmpty, mode != .report { break }
        }

        guard let first = unmet.first else {
            if mode != .preflight { Console.success("ready to build for \(platform.rawValue)") }
            return
        }
        if mode == .report {
            print("")
            print("\(unmet.count) missing. `omni doctor -p \(platform.rawValue) --fix` installs what it can and says what's left.")
            throw ExitCode.failure
        }
        throw SetupError.incomplete(platform: platform, name: first.name, commands: first.commands)
    }

    private static func report(_ name: String, _ state: State) {
        switch state {
        case .ok(let detail): Console.success("\(name): \(detail)")
        case .downloads(let detail): Console.info("\(name): \(detail)")
        case .missing(let detail, _), .manual(let detail, _): Console.failure("\(name): \(detail)")
        }
    }

    /// Defaults to Yes: someone running a build wants it to work. A closed
    /// stdin (no answer at all) declines.
    private static func confirm(_ question: String) -> Bool {
        print("  \(question) [Y/n]: ", terminator: "")
        fflush(nil)
        guard let answer = readLine()?.trimmingCharacters(in: .whitespaces).lowercased() else { return false }
        return answer.isEmpty || answer == "y" || answer == "yes"
    }

    // MARK: - What each platform needs

    static func requirements(for platform: Platform) -> [Requirement] {
        #if os(macOS)
            let mac = MacSetup()
            switch platform {
            case .macos:
                return [mac.homebrew, mac.developerTools]
            case .ios, .iosSimulator:
                return [mac.homebrew, mac.developerTools, mac.xcode, mac.xcodeSelected,
                        mac.xcodeLicense, mac.xcodeFirstLaunch]
                    + (platform == .iosSimulator ? [mac.iOSSimulator] : [])
            case .android:
                return [mac.homebrew, mac.developerTools] + AndroidSetup().requirements
            case .linux, .windows:
                return []
            }
        #else
            return platform == .android ? AndroidSetup().requirements : []
        #endif
    }
}

enum SetupError: LocalizedError {
    case incomplete(platform: Platform, name: String, commands: [String])

    var errorDescription: String? {
        switch self {
        case .incomplete(let platform, let name, let commands):
            var text = "\(name) is needed to build for \(platform.rawValue)."
            if !commands.isEmpty {
                text += "\n\n" + commands.map { "  " + $0 }.joined(separator: "\n")
            }
            text += "\n\nThen run `omni doctor -p \(platform.rawValue)` to check the rest, "
                + "or `omni doctor -p \(platform.rawValue) --fix` to let omni do it."
            return text
        }
    }
}

// MARK: - macOS

#if os(macOS)
struct MacSetup {
    private let fm = FileManager.default

    /// Runs with this terminal attached: installers that prompt (sudo,
    /// Homebrew, xcodes' Apple ID) need it.
    private func interactive(_ tool: String, _ arguments: [String]) throws {
        let result = try Shell.exec(tool, arguments, quiet: false)
        guard result.status == 0 else {
            throw AndroidError.failed(([tool] + arguments).joined(separator: " "),
                                      "exited with status \(result.status)")
        }
    }

    private func succeeds(_ tool: String, _ arguments: [String]) -> Bool {
        guard fm.isExecutableFile(atPath: tool) else { return false }
        return (try? Shell.exec(tool, arguments).status) == 0
    }

    private var isAdmin: Bool {
        ((try? Shell.exec("/usr/bin/id", ["-Gn"]).output) ?? "")
            .split(separator: " ").contains("admin")
    }

    // MARK: Homebrew

    var brewPath: String? {
        ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"].first(where: fm.isExecutableFile)
            ?? (try? Shell.run("command -v brew")).flatMap { $0.isEmpty ? nil : $0 }
    }

    var homebrew: Setup.Requirement {
        Setup.Requirement(name: "Homebrew") {
            if let brew = brewPath { return .ok(brew) }
            let script = #"/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)""#
            guard isAdmin else {
                return .manual("not installed, and installing it needs an administrator account",
                               ["# ask an administrator of this Mac to run:", script])
            }
            return .missing("not installed", Setup.Fix(
                summary: "Install Homebrew (asks for your Mac password)",
                commands: [script], asks: true,
                apply: installHomebrew))
        }
    }

    /// Homebrew's own installer, then PATH set up in ~/.zprofile, the step
    /// its installer leaves to "Next steps" and people miss.
    private func installHomebrew() throws {
        let script = NSTemporaryDirectory() + "homebrew-install-\(UUID().uuidString).sh"
        defer { try? fm.removeItem(atPath: script) }
        let fetch = try Shell.exec("/usr/bin/curl",
            ["-fsSL", "-o", script, "https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh"])
        guard fetch.status == 0 else { throw AndroidError.failed("downloading Homebrew's installer", fetch.output) }
        try interactive("/bin/bash", [script])

        guard let brew = brewPath else { throw AndroidError.missing("Homebrew's installer finished, but brew isn't there") }
        let profile = "\(NSHomeDirectory())/.zprofile"
        let line = #"eval "$(\#(brew) shellenv)""#
        let existing = (try? String(contentsOfFile: profile, encoding: .utf8)) ?? ""
        if !existing.contains("brew shellenv") {
            try (existing + (existing.isEmpty || existing.hasSuffix("\n") ? "" : "\n") + line + "\n")
                .write(toFile: profile, atomically: true, encoding: .utf8)
            Console.info("added Homebrew to ~/.zprofile; new terminal windows will find `brew`")
        }
    }

    // MARK: Command Line Tools

    /// `xcode-select -p`: Xcode's or the Command Line Tools' developer dir.
    var developerDirectory: String? {
        guard let result = try? Shell.exec("/usr/bin/xcode-select", ["-p"]),
              result.status == 0, fm.fileExists(atPath: result.output) else { return nil }
        return result.output
    }

    var developerTools: Setup.Requirement {
        Setup.Requirement(name: "Apple developer tools") {
            if let dir = developerDirectory, succeeds("/usr/bin/xcrun", ["--find", "clang"]) {
                return .ok(dir)
            }
            return .missing("not installed (the compiler, linker and git come with them)", Setup.Fix(
                summary: "Install Apple's Command Line Tools (a window opens; about 1GB)",
                commands: ["xcode-select --install"], asks: true,
                apply: installCommandLineTools))
        }
    }

    /// Apple only offers these through a dialog; open it and wait for it.
    private func installCommandLineTools() throws {
        _ = try? Shell.exec("/usr/bin/xcode-select", ["--install"])
        Console.info("finish the installer window that just opened; omni continues when it's done")
        let deadline = Date().addingTimeInterval(60 * 60)
        while Date() < deadline {
            if developerDirectory != nil, succeeds("/usr/bin/xcrun", ["--find", "clang"]) { return }
            Thread.sleep(forTimeInterval: 5)
        }
        throw AndroidError.missing("the Command Line Tools didn't finish installing within an hour")
    }

    // MARK: Xcode

    /// The Xcode to use: the selected one, else the newest in /Applications.
    var xcodeApp: String? {
        if let dir = developerDirectory, dir.hasSuffix(".app/Contents/Developer") {
            return String(dir.dropLast("/Contents/Developer".count))
        }
        let apps = ((try? fm.contentsOfDirectory(atPath: "/Applications")) ?? [])
            .filter { $0.hasPrefix("Xcode") && $0.hasSuffix(".app") }
            .sorted { $0.compare($1, options: .numeric) == .orderedDescending }
            .map { "/Applications/\($0)" }
            .filter { fm.fileExists(atPath: "\($0)/Contents/Developer/usr/bin/xcodebuild") }
        return apps.first
    }

    private var xcodebuild: String? {
        xcodeApp.map { "\($0)/Contents/Developer/usr/bin/xcodebuild" }
    }

    /// Gigabytes free on the startup disk.
    private var freeGB: Int? {
        let values = try? URL(fileURLWithPath: NSHomeDirectory())
            .resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage.map { Int($0 / 1_000_000_000) }
    }

    var xcode: Setup.Requirement {
        Setup.Requirement(name: "Xcode") {
            if let app = xcodeApp {
                let version = (try? Shell.exec("/usr/bin/defaults",
                    ["read", "\(app)/Contents/Info", "CFBundleShortVersionString"]).output) ?? ""
                return .ok(version.isEmpty ? app : "\(version) at \(app)")
            }
            // Apple's license doesn't allow passing Xcode around; xcodes gets
            // it from Apple with the person's own Apple ID.
            let appStore = "open 'macappstore://apps.apple.com/app/id497799835'"
            let space = freeGB.map { $0 < 40 ? " Only \($0)GB is free; Xcode needs about 40GB." : "" } ?? ""
            guard let brew = brewPath else {
                return .manual("not installed. iOS builds need it.\(space)", [appStore])
            }
            return .missing("not installed. iOS builds need it.\(space)", Setup.Fix(
                summary: "Download Xcode from Apple (asks for your Apple ID; about 10GB)",
                commands: ["brew install xcodes", "xcodes install --latest --experimental-unxip",
                           "# or from the App Store:", appStore],
                asks: true,
                apply: {
                    try interactive(brew, ["install", "xcodes"])
                    let xcodes = ((brew as NSString).deletingLastPathComponent as NSString)
                        .appendingPathComponent("xcodes")
                    try interactive(xcodes, ["install", "--latest", "--experimental-unxip"])
                }))
        }
    }

    var xcodeSelected: Setup.Requirement {
        Setup.Requirement(name: "Active developer tools") {
            guard let app = xcodeApp else { return .manual("Xcode isn't installed", []) }
            let developer = "\(app)/Contents/Developer"
            if developerDirectory == developer { return .ok(app) }
            // The Command Line Tools have no iOS SDK, simulators or devicectl.
            let current = developerDirectory ?? "nothing"
            return .missing("set to \(current), not Xcode", Setup.Fix(
                summary: "Use \((app as NSString).lastPathComponent) (asks for your Mac password)",
                commands: ["sudo xcode-select --switch \"\(developer)\""], asks: true,
                apply: { try interactive("/usr/bin/sudo", ["/usr/bin/xcode-select", "--switch", developer]) }))
        }
    }

    var xcodeLicense: Setup.Requirement {
        Setup.Requirement(name: "Xcode license") {
            guard let xcodebuild else { return .manual("Xcode isn't installed", []) }
            if succeeds(xcodebuild, ["-license", "check"]) { return .ok("accepted") }
            return .missing("not accepted yet; Xcode's tools refuse to run until it is", Setup.Fix(
                summary: "Accept the Xcode license (asks for your Mac password; read it with `xcodebuild -license`)",
                commands: ["sudo xcodebuild -license accept"], asks: true,
                apply: { try interactive("/usr/bin/sudo", [xcodebuild, "-license", "accept"]) }))
        }
    }

    var xcodeFirstLaunch: Setup.Requirement {
        Setup.Requirement(name: "Xcode components") {
            guard let xcodebuild else { return .manual("Xcode isn't installed", []) }
            if succeeds(xcodebuild, ["-checkFirstLaunchStatus"]) { return .ok("installed") }
            return .missing("not installed; Xcode installs them on first launch", Setup.Fix(
                summary: "Install Xcode's components (asks for your Mac password)",
                commands: ["sudo xcodebuild -runFirstLaunch"], asks: true,
                apply: { try interactive("/usr/bin/sudo", [xcodebuild, "-runFirstLaunch"]) }))
        }
    }

    var iOSSimulator: Setup.Requirement {
        Setup.Requirement(name: "iOS Simulator") {
            guard let xcodebuild else { return .manual("Xcode isn't installed", []) }
            let runtimes = (try? Shell.exec("/usr/bin/xcrun", ["simctl", "list", "runtimes", "available"]).output) ?? ""
            if let line = runtimes.split(separator: "\n").first(where: { $0.hasPrefix("iOS ") }) {
                return .ok(String(line.split(separator: "(").first ?? line).trimmingCharacters(in: .whitespaces))
            }
            return .missing("no iOS simulator runtime installed", Setup.Fix(
                summary: "Download the iOS Simulator (about 8GB)",
                commands: ["xcodebuild -downloadPlatform iOS"], asks: true,
                apply: { try interactive(xcodebuild, ["-downloadPlatform", "iOS"]) }))
        }
    }
}
#endif

// MARK: - Android

struct AndroidSetup {
    private let tools = AndroidToolchain()
    private let fm = FileManager.default

    var requirements: [Setup.Requirement] {
        #if os(macOS)
            return [swift, swiftAndroidSDK, ndk, jdk, androidTools]
        #else
            return [swift, swiftAndroidSDK, ndk, jdk, androidTools, imageMagick]
        #endif
    }

    var swift: Setup.Requirement {
        Setup.Requirement(name: "Swift (swift.org)") {
            if let swift = tools.installedSwiftOrg() {
                let version = (try? tools.toolchainVersion()) ?? ""
                return .ok(version.isEmpty ? swift : "\(version) at \(swift)")
            }
            if let override = ProcessInfo.processInfo.environment["OMNI_SWIFT"] {
                return .manual("OMNI_SWIFT=\(override) isn't a swift.org toolchain",
                               ["unset OMNI_SWIFT"])
            }
            #if os(macOS)
                // Xcode's Swift can't cross-compile for Android: the Android
                // SDK is built by swift.org's compiler and only it reads it.
                return .missing("not installed. Xcode's Swift can't build for Android.", Setup.Fix(
                    summary: "Install Swift from swift.org (for your user only, no password; about 1GB)",
                    commands: ["omni doctor -p android --fix"], asks: false,
                    apply: {
                        guard let version = tools.latestSwiftWithAndroidSDK() else {
                            throw AndroidError.missing("couldn't reach swift.org to find a release")
                        }
                        try tools.installSwiftOrg(version: version)
                    }))
            #else
                return .manual("not installed", ["# see https://www.swift.org/install/"])
            #endif
        }
    }

    var swiftAndroidSDK: Setup.Requirement {
        Setup.Requirement(name: "Swift SDK for Android") {
            guard let version = try? tools.toolchainVersion() else {
                return .manual("needs Swift first", [])
            }
            if let bundle = tools.androidBundle(version: version) {
                return .ok((bundle as NSString).lastPathComponent)
            }
            return .downloads("downloaded on the first build (Swift \(version), about 1GB)")
        }
    }

    var ndk: Setup.Requirement {
        Setup.Requirement(name: "Android NDK") {
            let minimum = AndroidToolchain.minimumNDKMajor
            guard let ndk = tools.installedNDK() else {
                return .downloads("NDK \(AndroidToolchain.ndkVersion) downloaded on the first build (about 700MB)")
            }
            if ndk.fromEnv, let major = ndk.major, major < minimum {
                return .manual("ANDROID_NDK_HOME is r\(major); apps built with it crash at launch. "
                               + "r\(minimum) or newer is needed.",
                               ["unset ANDROID_NDK_HOME   # omni downloads r\(minimum)"])
            }
            return .ok(ndk.major.map { "r\($0) at \(ndk.path)" } ?? ndk.path)
        }
    }

    var jdk: Setup.Requirement {
        Setup.Requirement(name: "Java (JDK)") {
            if let home = tools.installedJDK() { return .ok(home) }
            return .downloads("JDK 21 downloaded on the first build (about 200MB)")
        }
    }

    #if !os(macOS)
    /// Icons.swift resizes the app icon with sips on a Mac and ImageMagick elsewhere (`magick`, or `convert`
    /// on ImageMagick 6): without it a first build on Linux fails at the icon, after the whole toolchain came down.
    var imageMagick: Setup.Requirement {
        Setup.Requirement(name: "ImageMagick") {
            for tool in ["magick", "convert"] {
                if let path = try? Shell.run("command -v \(tool)"), !path.isEmpty { return .ok(path) }
            }
            return .manual("not installed; the app icon is resized with it",
                           ["sudo apt-get install -y imagemagick   # Debian, Ubuntu",
                            "sudo dnf install -y ImageMagick       # Fedora"])
        }
    }
    #endif

    var androidTools: Setup.Requirement {
        Setup.Requirement(name: "Android build tools") {
            let root = tools.root
            let have = fm.fileExists(atPath: "\(root)/build-tools/\(tools.buildToolsVersion)/aapt2")
                && fm.fileExists(atPath: "\(root)/platforms/android-\(tools.platformAPI)/android.jar")
            return have ? .ok(root) : .downloads("adb, build-tools and android.jar downloaded on the first build")
        }
    }
}
