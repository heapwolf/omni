// src/cli/platform/apple/AppleBuild.swift
import Foundation

public enum Platform: String {
    case macos
    case ios
    case iosSimulator = "ios-simulator"
    case linux
    case android
    case windows
}

public struct AppleBuilder {
    public let target: String
    public let path: String
    public let platform: Platform
    /// omni.json's resolved `flags`; see AppFlags.swift.
    let flags: AppFlags

    init(target: String, path: String, platform: Platform, flags: AppFlags = .none) {
        self.target = target
        self.path = path
        self.platform = platform
        self.flags = flags
    }

    /// Nearest enclosing directory with a Package.swift. --app-path is usually an
    /// example subdirectory rather than the package root.
    private func packageRoot() -> String {
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

    // internal: AppleInstaller.swift extends this type. The manifest lives in
    // AppManifest.swift, which Android also reads.
    func bundleIdentifier(for product: String) -> String {
        OmniManifest.load(from: path).bundleIdentifier ?? "com.omniswift.\(product.lowercased())"
    }

    /// The product to build. --output defaults to "App", so an unmatched name is
    /// reported against the products that exist rather than guessed at.
    func resolveProduct() throws -> String {
        let root = packageRoot()
        let dump = try Shell.exec("/usr/bin/env",
            ["swift", "package", "dump-package", "--package-path", root])
        guard dump.status == 0,
              let data = dump.output.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let products = json["products"] as? [[String: Any]] else {
            throw ShellError.failed("reading the package manifest at \(root)", dump.output)
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

        let targets = json["targets"] as? [[String: Any]] ?? []
        for entry in targets {
            guard let name = entry["name"] as? String, entry["type"] as? String == "executable",
                  !everything.contains(name) else { continue }
            everything.append(name)
            executables.append(name)
        }

        if everything.contains(target) { return target }

        throw ShellError.failed("choosing a product to build", """
            No product named '\(target)' in \(root)/Package.swift.
            Executable products: \(executables.isEmpty ? "none" : executables.joined(separator: ", "))
            Name one with --output, for example: omni run -o \(executables.first ?? "<product>")
            """)
    }

    public func build() throws {
        flags.announce()
        switch platform {
        case .ios:
            try buildIOSRequiringProfile()
        case .iosSimulator:
            try buildIOSSimulator()
        case .macos:
            try buildMacOS()
        default:
            throw NSError(domain: "AppleBuilder", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unsupported platform for AppleBuilder: \(platform.rawValue)"])
        }
    }

    // MARK: - iOS Device Routing

    /// --platform ios always means a real device — it never silently falls
    /// back to the Simulator depending on what happens to be lying around in
    /// --app-path. That ambiguity is exactly what --platform ios-simulator
    /// exists to remove: each platform value now does exactly one thing.
    private func buildIOSRequiringProfile() throws {
        let product = try resolveProduct()
        let expected = ProvisioningProfile.location(appPath: path,
                                                    bundleIdentifier: bundleIdentifier(for: product))
        let profile: String
        if FileManager.default.fileExists(atPath: expected) {
            profile = expected
        } else if let legacy = ProvisioningProfile.legacy(in: path) {
            Console.warning("""
                \(legacy) is inside the project. Move it to \(expected), or point omni.json's \
                provisioningProfile at wherever you keep it.
                """)
            profile = legacy
        } else {
            throw ShellError.failed("building for iOS Device", """
                No provisioning profile at \(expected).
                Run `omni provision`, which writes it there, or set omni.json's provisioningProfile \
                (or OMNI_PROVISIONING_PROFILE) to where yours is.
                Or use --platform ios-simulator to build for the Simulator instead.
                """)
        }
        Console.info("Provisioning profile: \(profile). Building for iOS Device...")
        try buildIOSDevice(provisioningProfile: profile)
    }

    // MARK: - macOS Build

    private func buildMacOS() throws {
        let product = try resolveProduct()
        Console.info("Compiling \(product) for macOS...")
        let buildCmd = "swift build -c release --product \"\(product)\" --package-path \"\(packageRoot())\""
        try Shell.checked(buildCmd, step: "swift build")

        Console.info("Packaging into an .app bundle...")
        let bundleDir = "\(path)/.build/macos/\(product).app/Contents/MacOS"
        try Shell.checked("mkdir -p \"\(bundleDir)\"", step: "creating the bundle directory")

        // The app's own icon, or the placeholder.
        let icon = AppIcon.resolve(in: path, name: product)
        Console.info(icon.isPlaceholder
              ? "No icon.png — using the placeholder"
              : "Generating AppIcon.icns...")
        let resourcesDir = "\(path)/.build/macos/\(product).app/Contents/Resources"
        try Shell.checked("mkdir -p \"\(resourcesDir)\"", step: "creating the Resources directory")
        try AppIcon.writeMacIcns(source: icon, into: resourcesDir)
        let iconFragment = "    <key>CFBundleIconFile</key>\n    <string>AppIcon</string>"

        let plistUrl = URL(fileURLWithPath: "\(path)/.build/macos/\(product).app/Contents/Info.plist")
        try generateInfoPlist(target: product, platform: .macOS, iconFragment: iconFragment).write(to: plistUrl, atomically: true, encoding: .utf8)

        // Dynamically locate output binary path
        let binDir = try Shell.checked("\(buildCmd) --show-bin-path",
                                       step: "locating the build directory")
        let binaryPath = "\(binDir)/\(product)"

        try Shell.checked("cp \"\(binaryPath)\" \"\(bundleDir)/\(product)\"",
                          step: "copying the executable into the bundle")
        try Shell.checked("chmod +x \"\(bundleDir)/\(product)\"", step: "marking the executable")

        try flags.write(into: resourcesDir)
        let fonts = AppFonts.find(in: path)
        fonts.announce()
        try fonts.copy(into: resourcesDir)

        // swift build ad-hoc signs the loose binary, and that signature is bound to
        // it as a standalone executable.
        let appBundle = "\(path)/.build/macos/\(product).app"
        try Shell.checked("codesign --force --deep --sign - \"\(appBundle)\"",
                          step: "ad-hoc signing the app bundle")

        Console.success("macOS build succeeded! App bundle located at:")
        print("   \(appBundle)")
    }

    // MARK: - iOS Device Build

    private func buildIOSDevice(provisioningProfile: String) throws {
        let product = try resolveProduct()
        let iosDir = "\(path)/.omni/ios-device"
        let appBundle = "\(iosDir)/\(product).app"
        try Shell.checked("mkdir -p \"\(appBundle)\"", step: "creating the bundle directory")

        Console.info("Locating real iOS SDK...")
        let sdkPath = try Shell.checked("xcrun --sdk iphoneos --show-sdk-path",
                                        step: "locating the iOS SDK")

        let targetTriple = "arm64-apple-ios\(Self.iOSDeploymentTarget)"
        Console.info("Executing swift build for \(targetTriple)...")

        let buildArgs = """
        -c release \
        --product "\(product)" \
        --package-path "\(packageRoot())" \
        --triple \(targetTriple) \
        --sdk "\(sdkPath)"
        """

        try Shell.checked("swift build \(buildArgs)", step: "swift build")

        let binDir = try Shell.checked("swift build \(buildArgs) --show-bin-path",
                                       step: "locating the build directory")
        let binaryPath = "\(binDir)/\(product)"

        Console.info("Constructing real iOS .app bundle...")
        try Shell.checked("cp \"\(binaryPath)\" \"\(appBundle)/\(product)\"",
                          step: "copying the executable into the bundle")

        let icon = AppIcon.resolve(in: path, name: product)
        Console.info(icon.isPlaceholder
              ? "No icon.png — using the placeholder"
              : "Generating app icon...")
        try AppIcon.writeIOSIcons(source: icon, into: appBundle, platform: "iphoneos",
                                   deploymentTarget: Self.iOSDeploymentTarget)
        let iconFragment = AppIcon.iosInfoPlistFragment

        let plistUrl = URL(fileURLWithPath: "\(appBundle)/Info.plist")
        try generateInfoPlist(target: product, platform: .iOSDevice, iconFragment: iconFragment).write(to: plistUrl, atomically: true, encoding: .utf8)

        try flags.write(into: appBundle)
        let fonts = AppFonts.find(in: path)
        fonts.announce()
        try fonts.copy(into: appBundle)

        Console.info("Embedding provisioning profile...")
        try Shell.checked("cp \"\(provisioningProfile)\" \"\(appBundle)/embedded.mobileprovision\"",
                          step: "embedding the provisioning profile")

        Console.info("Extracting device entitlements...")
        try Shell.checked("security cms -D -i \"\(appBundle)/embedded.mobileprovision\" > \"\(iosDir)/profile.plist\"",
                          step: "decoding the provisioning profile")
        try Shell.checked("/usr/libexec/PlistBuddy -x -c 'Print :Entitlements' \"\(iosDir)/profile.plist\" > \"\(iosDir)/Entitlements.plist\"",
                          step: "extracting entitlements")

        Console.info("Code signing for iOS Device...")
        let identity = try signingIdentity(profilePlist: "\(iosDir)/profile.plist", scratch: iosDir)
        try Shell.checked("codesign --force --entitlements \"\(iosDir)/Entitlements.plist\" --sign \(identity) \"\(appBundle)\"",
                          step: "code signing")

        Console.success("Real iOS Build Complete! App bundle located at:")
        print("   \(appBundle)")
    }

    /// The SHA-1 of the profile's own certificate. Signing by name picks the
    /// first "Apple Development" in the keychain, which need not be this one.
    private func signingIdentity(profilePlist: String, scratch: String) throws -> String {
        guard let data = FileManager.default.contents(atPath: profilePlist),
              let plist = try PropertyListSerialization.propertyList(
                from: data, options: [], format: nil) as? [String: Any],
              let certificate = (plist["DeveloperCertificates"] as? [Data])?.first else {
            throw NSError(domain: "AppleBuilder", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "The provisioning profile has no certificate."])
        }

        let derPath = "\(scratch)/signing-certificate.der"
        try certificate.write(to: URL(fileURLWithPath: derPath))
        let line = try Shell.checked("shasum -a 1 \"\(derPath)\"", step: "fingerprinting the certificate")
        return String(line.prefix(40))
    }

    // MARK: - iOS Simulator Build

    private func buildIOSSimulator() throws {
        let product = try resolveProduct()
        let iosDir = "\(path)/.omni/ios-simulator"
        let appBundle = "\(iosDir)/\(product).app"
        try Shell.checked("mkdir -p \"\(appBundle)\"", step: "creating the bundle directory")

        Console.info("Locating iOS Simulator SDK...")
        let sdkPath = try Shell.checked("xcrun --sdk iphonesimulator --show-sdk-path",
                                        step: "locating the iOS Simulator SDK")

        let targetTriple = "arm64-apple-ios\(Self.iOSDeploymentTarget)-simulator"
        Console.info("Executing swift build for \(targetTriple)...")

        let buildArgs = """
        -c debug \
        --product "\(product)" \
        --package-path "\(packageRoot())" \
        --triple \(targetTriple) \
        --sdk "\(sdkPath)"
        """

        try Shell.checked("swift build \(buildArgs)", step: "swift build")

        let binDir = try Shell.checked("swift build \(buildArgs) --show-bin-path",
                                       step: "locating the build directory")
        let binaryPath = "\(binDir)/\(product)"

        Console.info("Constructing Simulator .app bundle...")
        try Shell.checked("cp \"\(binaryPath)\" \"\(appBundle)/\(product)\"",
                          step: "copying the executable into the bundle")

        let icon = AppIcon.resolve(in: path, name: product)
        Console.info(icon.isPlaceholder
              ? "No icon.png — using the placeholder"
              : "Generating app icon...")
        try AppIcon.writeIOSIcons(source: icon, into: appBundle, platform: "iphonesimulator",
                                   deploymentTarget: Self.iOSDeploymentTarget)
        let iconFragment = AppIcon.iosInfoPlistFragment

        let plistUrl = URL(fileURLWithPath: "\(appBundle)/Info.plist")
        try generateInfoPlist(target: product, platform: .iOSSimulator, iconFragment: iconFragment).write(to: plistUrl, atomically: true, encoding: .utf8)

        try flags.write(into: appBundle)
        let fonts = AppFonts.find(in: path)
        fonts.announce()
        try fonts.copy(into: appBundle)

        Console.info("Ad-hoc signing the Simulator bundle...")
        try Shell.checked("codesign --force --sign - --timestamp=none \"\(appBundle)\"",
                          step: "ad-hoc signing")

        Console.success("Simulator Build Complete! App bundle located at:")
        print("   \(appBundle)")
    }

    // MARK: - Deployment / Execution Helpers

    public func run() throws {
        switch platform {
        case .macos:
            let appPath = "\(path)/.build/macos/\(try resolveProduct()).app"
            Console.info("Launching macOS app...")
            try Shell.run("open \"\(appPath)\"")

        case .ios:
            let product = try resolveProduct()
            let deviceBundle = "\(path)/.omni/ios-device/\(product).app"
            guard FileManager.default.fileExists(atPath: deviceBundle) else {
                Console.failure("No iOS Device build found. Run `omni build --platform ios` first.")
                return
            }
            let bundleID = bundleIdentifier(for: product)
            try runOnDevice(appBundle: deviceBundle, bundleID: bundleID)

        case .iosSimulator:
            let product = try resolveProduct()
            let simulatorBundle = "\(path)/.omni/ios-simulator/\(product).app"
            guard FileManager.default.fileExists(atPath: simulatorBundle) else {
                Console.failure("No iOS Simulator build found. Run `omni build --platform ios-simulator` first.")
                return
            }
            let bundleID = bundleIdentifier(for: product)

            var udid = try Shell.run(
                "xcrun simctl list devices booted | grep -oE '[0-9A-F-]{36}' | head -1")

            if udid.isEmpty {
                udid = try Shell.run(
                    "xcrun simctl list devices available | grep -E '^ *iPhone' "
                    + "| grep -oE '[0-9A-F-]{36}' | head -1")
                guard !udid.isEmpty else {
                    Console.failure("No iOS simulator installed. Add one in Xcode › Settings › Platforms.")
                    return
                }
                Console.info("Booting simulator \(udid)...")
                _ = try? Shell.run("xcrun simctl boot \(udid)")
            }

            _ = try Shell.run("open -a Simulator")
            _ = try? Shell.run("xcrun simctl bootstatus \(udid) -b")

            Console.info("Installing \(product).app...")
            _ = try Shell.run("xcrun simctl install \(udid) \"\(simulatorBundle)\"")
            _ = try Shell.run("xcrun simctl launch \(udid) \(bundleID)")
            Console.success("iOS App launched in Simulator!")

        default:
            break
        }
    }

    private func runOnDevice(appBundle: String, bundleID: String) throws {
        Console.info("Locating connected iOS device...")

        let listPath = NSTemporaryDirectory() + "omni-devicectl-list-\(UUID().uuidString).json"
        defer { try? FileManager.default.removeItem(atPath: listPath) }
        _ = try Shell.checked("xcrun devicectl list devices --json-output \"\(listPath)\"",
                              step: "listing connected devices")

        guard let data = FileManager.default.contents(atPath: listPath),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = json["result"] as? [String: Any],
              let devices = result["devices"] as? [[String: Any]],
              !devices.isEmpty else {
            Console.failure("No connected iOS device found. Plug one in over USB (or make sure it's paired over Wi-Fi), unlock it, and trust this Mac if prompted.")
            return
        }

        // Prefer a device that's actually reachable right now over one
        // merely remembered from a previous pairing.
        let connected = devices.first {
            (($0["connectionProperties"] as? [String: Any])?["tunnelState"] as? String) == "connected"
        }
        guard let device = connected ?? devices.first,
              let udid = device["identifier"] as? String else {
            Console.failure("Found a device record but couldn't read its identifier.")
            return
        }
        let deviceName = (device["deviceProperties"] as? [String: Any])?["name"] as? String ?? udid

        Console.info("Installing on \(deviceName)...")
        try Shell.checked("xcrun devicectl device install app --device \(udid) \"\(appBundle)\"",
                          step: "installing the app on the device")

        Console.info("Launching \(bundleID) on \(deviceName)...")
        try Shell.checked("xcrun devicectl device process launch --device \(udid) \(bundleID)",
                          step: "launching the app on the device")

        Console.success("App launched on \(deviceName)!")
    }

    // MARK: - Utilities

    enum BundlePlatform {
        case macOS, iOSDevice, iOSSimulator

        var supportedPlatform: String {
            switch self {
            case .macOS: return "MacOSX"
            case .iOSDevice: return "iPhoneOS"
            case .iOSSimulator: return "iPhoneSimulator"
            }
        }

        var isIOS: Bool { self != .macOS }
    }

    static let iOSDeploymentTarget = "17.0"
    static let macOSDeploymentTarget = "13.0"

    private func urlSchemeFragment(for product: String) -> String {
        let schemes = OmniManifest.load(from: path).validatedSchemes
        guard !schemes.isEmpty else { return "" }

        var lines = [
            "    <key>CFBundleURLTypes</key>",
            "    <array>",
            "        <dict>",
            "            <key>CFBundleURLName</key>",
            "            <string>\(bundleIdentifier(for: product))</string>",
            "            <key>CFBundleURLSchemes</key>",
            "            <array>"
        ]
        lines += schemes.map { "                <string>\($0)</string>" }
        lines += ["            </array>", "        </dict>", "    </array>"]
        return lines.joined(separator: "\n")
    }

    private func generateInfoPlist(target: String, platform: BundlePlatform,
                                   iconFragment: String = "") -> String {
        let platformKeys: String
        if platform.isIOS {
            platformKeys = """
                <key>LSRequiresIPhoneOS</key>
                <true/>
                <key>MinimumOSVersion</key>
                <string>\(Self.iOSDeploymentTarget)</string>
                <key>UIDeviceFamily</key>
                <array>
                    <integer>1</integer>
                    <integer>2</integer>
                </array>
                <key>UILaunchScreen</key>
                <dict/>
                <key>UIApplicationSceneManifest</key>
                <dict>
                    <key>UIApplicationSupportsMultipleScenes</key>
                    <false/>
                    <key>UISceneConfigurations</key>
                    <dict>
                        <key>UIWindowSceneSessionRoleApplication</key>
                        <array>
                            <dict>
                                <key>UISceneConfigurationName</key>
                                <string>Default</string>
                                <key>UISceneDelegateClassName</key>
                                <string>OmniSceneDelegate</string>
                            </dict>
                        </array>
                    </dict>
                </dict>
                <key>UISupportedInterfaceOrientations</key>
                <array>
                    <string>UIInterfaceOrientationPortrait</string>
                    <string>UIInterfaceOrientationLandscapeLeft</string>
                    <string>UIInterfaceOrientationLandscapeRight</string>
                </array>
            """
        } else {
            platformKeys = """
                <key>LSMinimumSystemVersion</key>
                <string>\(Self.macOSDeploymentTarget)</string>
            """
        }

        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>CFBundleExecutable</key>
            <string>\(target)</string>
            <key>CFBundleIdentifier</key>
            <string>\(bundleIdentifier(for: target))</string>
            <key>CFBundleName</key>
            <string>\(target)</string>
            <key>CFBundleDisplayName</key>
            <string>\(target)</string>
            <key>CFBundleInfoDictionaryVersion</key>
            <string>6.0</string>
            <key>CFBundlePackageType</key>
            <string>APPL</string>
            <key>CFBundleShortVersionString</key>
            <string>1.0</string>
            <key>CFBundleVersion</key>
            <string>1</string>
            <key>CFBundleSupportedPlatforms</key>
            <array>
                <string>\(platform.supportedPlatform)</string>
            </array>
        \(platformKeys)
        \(urlSchemeFragment(for: target))
            <!-- Declared unconditionally, the same way Android's manifest
                 always declares android.permission.CAMERA: the CLI has no
                 per-app config to know whether OmniCamera is actually
                 linked, and an unused usage-description key costs nothing at
                 runtime — it only matters the moment a camera/photo-library
                 API is actually called, and calling one WITHOUT this key
                 present is an instant, unrecoverable crash (SIGABRT), not a
                 denied-permission error a caller can react to. -->
            <key>NSCameraUsageDescription</key>
            <string>\(target) uses the camera to take a photo you choose to capture.</string>
            <key>NSPhotoLibraryUsageDescription</key>
            <string>\(target) uses your photo library to choose a photo you select.</string>
        \(iconFragment)
        </dict>
        </plist>
        """
    }
}
