// src/cli/platform/windows/WindowsBuild.swift
import Foundation

public struct WindowsBuilder {
    public let target: String
    public let path: String
    public let libPath: String
    /// Names the WebView2 loader to link; the package ships x64, arm64 and x86.
    public let architecture: String
    /// omni.json's resolved `flags`, written beside the .exe.
    let flags: AppFlags

    init(target: String, path: String, libPath: String = "src/lib",
         architecture: String = "x64", flags: AppFlags = .none) {
        self.target = target
        self.path = path
        self.libPath = libPath
        self.architecture = architecture
        self.flags = flags
    }

    public func build() throws {
        flags.announce()
        Console.info("Compiling \(target) for Windows...")

        let fm = FileManager.default
        var sourceFiles: [String] = []

        // Swift and C files from the app directory and the framework.
        for searchPath in [path, libPath] {
            guard fm.fileExists(atPath: searchPath) else { continue }
            guard let enumerator = fm.enumerator(atPath: searchPath) else { continue }

            for case let file as String in enumerator {
                // Ignore SPM package definitions
                if file.contains("Package.swift") { continue }

                let fullPath = URL(fileURLWithPath: searchPath).appendingPathComponent(file).path

                if file.hasSuffix(".swift") {
                    sourceFiles.append(fullPath)
                } else if file.hasSuffix(".c") && searchPath == libPath {
                    // The CWindows bridge files.
                    sourceFiles.append(fullPath)
                }
            }
        }

        guard !sourceFiles.isEmpty else {
            Console.failure("No source files found for Windows build.")
            throw NSError(domain: "WindowsBuilder", code: 1, userInfo: nil)
        }

        let buildDir = "\(path)/.omni/windows"

        // FileManager rather than mkdir -p, for native Windows.
        try? fm.createDirectory(atPath: buildDir, withIntermediateDirectories: true)

        // Output must have a .exe extension on Windows
        let outputExe = "\(buildDir)/\(target).exe"
        let bridgingHeader = "\(libPath)/CWindows/CWinBridge.h"

        // Win32 GUI, COM and Direct2D.
        var extraFlags = [
            "-import-objc-header", bridgingHeader,
            "-Xlinker", "User32.lib",
            "-Xlinker", "Ole32.lib",
            "-Xlinker", "D2d1.lib",
            "-Xlinker", "Dwrite.lib"
        ]

        do {
            let webView2 = try WebView2SDK().ensure(architecture: architecture)
            extraFlags += [
                "-Xcc", "-I\(webView2.includeDirectory)",
                "-Xlinker", webView2.loaderLibrary
            ]
            if webView2.requiresLoaderDLL {
                // Only the import library: the DLL must ship beside the .exe.
                print("   linking WebView2Loader.dll.lib — WebView2Loader.dll must ship with the app")
            }
        } catch {
            Console.warning("\(error)")
            print("   Building without WebView2 — WebView will report that this machine has no engine.")
        }

        // The .ico is always generated; embedding it in the .exe needs a resource
        // compiler (rc.exe/llvm-rc), which is not guaranteed present.
        var resourceObjArgs: [String] = []
        do {
            let icon = AppIcon.resolve(in: path, name: target)
            Console.info(icon.isPlaceholder
                  ? "No icon.png — using the placeholder"
                  : "Generating app icon...")
            let icoPath = "\(buildDir)/\(target).ico"
            try AppIcon.writeWindowsIco(source: icon, output: icoPath)

            if let rc = try? Shell.run("which llvm-rc 2>/dev/null || which rc 2>/dev/null"), !rc.isEmpty {
                let rcScript = "\(buildDir)/\(target).rc"
                try "1 ICON \"\(icoPath)\"".write(toFile: rcScript, atomically: true, encoding: .utf8)
                let resObj = "\(buildDir)/\(target).res"
                let rcResult = try Shell.exec(rc, [rcScript, "/FO", resObj])
                if rcResult.status == 0 {
                    resourceObjArgs = [resObj]
                    print("   embedded as the .exe's own icon resource")
                } else {
                    Console.warning("\(rc) failed, leaving \(icoPath) unembedded: \(rcResult.output)")
                }
            } else {
                print("   no rc.exe/llvm-rc on PATH — \(icoPath) generated but not embedded in the .exe")
            }
        }

        Console.info("Executing swiftc for \(sourceFiles.count) source files...")

        let swiftcArgs = ["swiftc"] + sourceFiles + resourceObjArgs + ["-o", outputExe] + extraFlags
        let compileCmd = swiftcArgs.joined(separator: " ")

        try Shell.run(compileCmd)
        try flags.write(into: buildDir)

        Console.success("Windows build succeeded! Binary located at:")
        print("   \(outputExe)")
    }

    public func run() throws {
        let outputExe = "\(path)/.omni/windows/\(target).exe"
        let fm = FileManager.default

        if !fm.fileExists(atPath: outputExe) {
            Console.warning("Windows binary not found at \(outputExe). Running build step first...")
            try build()
        }

        Console.info("Launching \(target) on Windows...\n")
        _ = try Shell.exec("/bin/sh", ["-c", outputExe], quiet: false)
    }
}
