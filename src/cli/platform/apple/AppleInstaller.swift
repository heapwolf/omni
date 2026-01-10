// src/cli/platform/apple/AppleInstaller.swift
import Foundation

extension AppleBuilder {
    public func buildPkg() throws -> String {
        let product = try resolveProduct()
        let appBundle = "\(path)/.build/macos/\(product).app"
        guard FileManager.default.fileExists(atPath: appBundle) else {
            throw ShellError.failed(
                "building .pkg",
                "no .app bundle at \(appBundle) — build for macOS first")
        }

        let outputDir = "\(path)/.build/installers"
        try Shell.checked("mkdir -p \"\(outputDir)\"", step: "creating the installer output directory")
        let outputPkg = "\(outputDir)/\(product).pkg"

        // pkgbuild silently corrupts output written to a path containing spaces.
        let tempPkg = NSTemporaryDirectory() + "omni-pkg-\(UUID().uuidString)/\(product).pkg"
        try FileManager.default.createDirectory(
            atPath: (tempPkg as NSString).deletingLastPathComponent,
            withIntermediateDirectories: true)

        Console.info("Building .pkg installer from \(appBundle)...")
        let pkgbuildCmd = "pkgbuild --component \"\(appBundle)\" --install-location /Applications"
            + " --identifier \"\(bundleIdentifier(for: product))\" --version 1.0 \"\(tempPkg)\""
        try Shell.checked(pkgbuildCmd, step: "pkgbuild")

        try? FileManager.default.removeItem(atPath: outputPkg)
        try FileManager.default.copyItem(atPath: tempPkg, toPath: outputPkg)
        try? FileManager.default.removeItem(atPath: (tempPkg as NSString).deletingLastPathComponent)

        Console.success("Installer built: \(outputPkg)")
        print("   Install with: sudo installer -pkg \"\(outputPkg)\" -target /")
        return outputPkg
    }
}
