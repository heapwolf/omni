// src/cli/omni.swift
import Foundation
import ArgumentParser

@main
struct Omni: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "omni",
        abstract: "A CLI to compile and run cross-platform declarative UI framework.",
        subcommands: [Build.self, Run.self, Package.self, Provision.self]
    )

    // ParsableCommand's own synthesized main() catches everything with
    // exit(withError:), which prints a plain, unstyled "Error: ..." — every
    // other failure in this tool goes through Console.failure's red 🅧, and a
    // thrown error should not be the one exception.
    //
    // This is a whitelist, not a blacklist: parseAsRoot()/run() throwing on
    // --help or a bad argument surfaces ArgumentParser's own internal
    // CommandError, not ValidationError/CleanExit directly (tried that
    // first — it broke --help and usage text, since CommandError matched
    // neither catch and fell into the generic handler as a raw struct dump).
    // So only our own known error types get the Console.failure treatment;
    // everything else — including ArgumentParser's own control-flow errors,
    // today's or a future version's — still goes through exit(withError:)
    // exactly as the synthesized main() would have.
    static func main() {
        do {
            var command = try parseAsRoot()
            try command.run()
        } catch let error as ProvisionError {
            Console.failure(error.description)
            Foundation.exit(1)
        } catch let error as ShellError {
            Console.failure(error.errorDescription ?? "\(error)")
            Foundation.exit(1)
        } catch let error as AndroidError {
            Console.failure(error.errorDescription ?? "\(error)")
            Foundation.exit(1)
        } catch let error as FlagsError {
            Console.failure(error.description)
            Foundation.exit(1)
        } catch let error as WebView2Error {
            Console.failure(error.description)
            Foundation.exit(1)
        } catch {
            exit(withError: error)
        }
    }
}

struct Build: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Compiles the swift files.")

    @Option(name: .shortAndLong, help: "The output executable name.")
    var output: String = "App"

    @Option(name: [.customShort("a"), .customLong("app-path")], help: "The path containing app files.")
    var appPath: String = FileManager.default.currentDirectoryPath

    @Option(name: [.customShort("l"), .customLong("lib-path")], help: "The path containing framework lib files.")
    var libPath: String = "src/lib"

    @Option(name: [.customShort("p"), .customLong("platform")], help: "Target platform (macos, ios, ios-simulator, linux, android).")
    var platform: String = "macos"

    @OptionGroup var flagOptions: FlagOptions

    func run() throws {
        guard let targetPlatform = Platform(rawValue: platform.lowercased()) else {
            Console.failure("Invalid platform '\(platform)'. Options: macos, ios, ios-simulator, linux, android.")
            throw ExitCode.failure
        }
        let flags = try flagOptions.resolve(appPath: appPath)

        switch targetPlatform {
            case .android:
                let builder = AndroidBuilder(target: output, path: appPath, flags: flags)
                try builder.build()

            case .macos, .ios, .iosSimulator:
                let builder = AppleBuilder(target: output, path: appPath, platform: targetPlatform, flags: flags)
                try builder.build()

            case .linux:
                let builder = LinuxBuilder(target: output, path: appPath, libPath: libPath, flags: flags)
                try builder.build()

            case .windows:
                let builder = WindowsBuilder(target: output, path: appPath, libPath: libPath, flags: flags)
                try builder.build()
        }
    }
}

struct Package: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Builds a distributable installer (.pkg/.deb/.rpm/.msi) for the app. "
            + "iOS/Android aren't covered — a device install and a .apk are already the installer."
    )

    @Option(name: .shortAndLong, help: "The output executable name.")
    var output: String = "App"

    @Option(name: [.customShort("a"), .customLong("app-path")], help: "The path containing app files.")
    var appPath: String = FileManager.default.currentDirectoryPath

    @Option(name: [.customShort("l"), .customLong("lib-path")], help: "The path containing framework lib files.")
    var libPath: String = "src/lib"

    @Option(name: [.customShort("p"), .customLong("platform")], help: "Target platform (macos, linux, windows).")
    var platform: String = "macos"

    @OptionGroup var flagOptions: FlagOptions

    @Option(name: .long, help: "Installer architecture — linux: amd64/arm64 (default amd64/x86_64); windows: x64/arm64 (default x64).")
    var arch: String = ""

    @Option(name: .long, help: "Installer version string.")
    var version: String = "1.0"

    @Option(name: .long, help: "Linux package format: deb, rpm, or both.")
    var format: String = "deb"

    func run() throws {
        guard let targetPlatform = Platform(rawValue: platform.lowercased()) else {
            Console.failure("Invalid platform '\(platform)'. Options: macos, linux, windows.")
            throw ExitCode.failure
        }
        let flags = try flagOptions.resolve(appPath: appPath)

        switch targetPlatform {
        case .macos:
            let builder = AppleBuilder(target: output, path: appPath, platform: .macos, flags: flags)
            try builder.build()
            _ = try builder.buildPkg()

        case .linux:
            let builder = LinuxBuilder(target: output, path: appPath, libPath: libPath, flags: flags)
            try builder.build()
            if format == "deb" || format == "both" {
                _ = try builder.buildDeb(architecture: arch.isEmpty ? "amd64" : arch, version: version)
            }
            if format == "rpm" || format == "both" {
                _ = try builder.buildRpm(architecture: arch.isEmpty ? "x86_64" : arch, version: version)
            }

        case .windows:
            let builder = WindowsBuilder(target: output, path: appPath, libPath: libPath, flags: flags)
            try builder.build()
            _ = try builder.buildMsi(architecture: arch.isEmpty ? "x64" : arch, version: version)

        case .ios, .iosSimulator, .android:
            Console.info("\(platform) doesn't need a separate installer — iOS installs via devicectl/the App Store, "
                + "and Android's .apk from `omni build` is already the installer.")
        }
    }
}

struct Run: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Compiles and runs the program.")

    @Option(name: .shortAndLong, help: "The output executable name.")
    var output: String = "App"

    @Option(name: [.customShort("a"), .customLong("app-path")], help: "The path containing app files.")
    var appPath: String = FileManager.default.currentDirectoryPath

    @Option(name: [.customShort("l"), .customLong("lib-path")], help: "The path containing framework lib files.")
    var libPath: String = "src/lib"

    @Option(name: [.customShort("p"), .customLong("platform")], help: "Target platform (macos, ios, ios-simulator, linux, android).")
    var platform: String = "macos"

    @OptionGroup var flagOptions: FlagOptions

    func run() throws {
        guard let targetPlatform = Platform(rawValue: platform.lowercased()) else {
            Console.failure("Invalid platform '\(platform)'. Options: macos, ios, ios-simulator, linux, android.")
            throw ExitCode.failure
        }
        let flags = try flagOptions.resolve(appPath: appPath)

        switch targetPlatform {
            case .android:
                // Builds for the ABI the attached device reports, installs,
                // launches, and reports the launch outcome with its log.
                let deployer = AndroidDeployer(target: output, path: appPath, flags: flags)
                try deployer.run()

            case .macos, .ios, .iosSimulator:
                let builder = AppleBuilder(target: output, path: appPath, platform: targetPlatform, flags: flags)
                try builder.build()
                try builder.run()

            case .linux:
                let builder = LinuxBuilder(target: output, path: appPath, libPath: libPath, flags: flags)
                try builder.build()
                try builder.run()

            case .windows:
                let builder = WindowsBuilder(target: output, path: appPath, libPath: libPath, flags: flags)
                try builder.build()
                try builder.run()
        }
    }
}

struct Provision: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Ensures a development certificate, App ID, device and profile, then writes "
            + "the profile to ~/.omni/provisioning (or omni.json's provisioningProfile). For developer machines; QA installs come "
            + "from TestFlight."
    )

    @Option(name: .shortAndLong, help: "The app name.")
    var output: String = "App"

    @Option(name: [.customShort("a"), .customLong("app-path")], help: "The path containing app files.")
    var appPath: String = FileManager.default.currentDirectoryPath

    @Flag(name: .long, help: "Sign in to App Store Connect, once per machine.")
    var login = false

    @Flag(name: .long, help: "List this team's registered devices as Apple's API reports them, then exit.")
    var listDevices = false

    func run() throws {
        let provisioner = Provisioner(path: appPath)
        if login {
            try provisioner.login()
            return
        }
        if listDevices {
            try provisioner.listDevices()
            return
        }
        try provisioner.run(product: output)
    }
}
