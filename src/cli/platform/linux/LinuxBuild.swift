// src/cli/platform/linux/LinuxBuild.swift
import Foundation

public struct LinuxBuilder {
    public let target: String
    public let path: String
    public let libPath: String
    /// omni.json's resolved `flags`, written beside the binary.
    let flags: AppFlags

    init(target: String, path: String, libPath: String = "src/lib", flags: AppFlags = .none) {
        self.target = target
        self.path = path
        self.libPath = libPath
        self.flags = flags
    }

    public func build() throws {
        let product = try SwiftPackage.resolveProduct(named: target, in: path)
        let packageRoot = SwiftPackage.root(from: path)
        flags.announce()
        Console.info("Compiling \(product) for Linux...")

        let buildDir = "\(path)/.omni/linux"
        try Shell.checked("mkdir -p \"\(buildDir)\"", step: "creating the build directory")
        let outputPath = "\(buildDir)/\(product)"

        let icon = AppIcon.resolve(in: path, name: product)
        Console.info(icon.isPlaceholder
              ? "No icon.png — using the placeholder"
              : "Generating app icon...")
        try AppIcon.write(icon, size: 256, to: "\(buildDir)/icon.png")

        let buildCmd = "swift build -c release --product \(product) --package-path \"\(packageRoot)\""
        try Shell.checked(buildCmd, step: "swift build")

        // Copied next to the icon rather than run from SwiftPM's own bin
        // directory: the installer stages from .omni/linux, and so does run().
        let binDir = try Shell.checked("\(buildCmd) --show-bin-path",
                                       step: "locating the build directory")
        try Shell.checked("cp \"\(binDir)/\(product)\" \"\(outputPath)\"",
                          step: "copying the executable")
        try Shell.checked("chmod +x \"\(outputPath)\"", step: "marking the executable")
        try flags.write(into: buildDir)

        Console.success("Linux build succeeded! Binary located at:")
        print("   \(outputPath)")
    }

    public func run() throws {
        let product = try SwiftPackage.resolveProduct(named: target, in: path)
        let binaryPath = "\(path)/.omni/linux/\(product)"
        let fm = FileManager.default

        if !fm.fileExists(atPath: binaryPath) {
            Console.warning("Linux binary not found at \(binaryPath). Running build step first...")
            try build()
        }

        Console.info("Launching \(product) on Linux...\n")
        _ = try Shell.exec("/bin/sh", ["-c", binaryPath], quiet: false)
    }
}
