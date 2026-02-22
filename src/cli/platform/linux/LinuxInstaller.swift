// src/cli/platform/linux/LinuxInstaller.swift
import Foundation

extension LinuxBuilder {
    // pkgbuild silently corrupts output written to a path containing spaces.
    private var installerStageRoot: String { NSTemporaryDirectory() + "omni-linux-installer-stage" }

    /// The standard Linux desktop payload: binary under /opt, icon in the hicolor
    /// theme, and a .desktop entry.
    private func stagePayload(into root: String) throws {
        let fm = FileManager.default
        try? fm.removeItem(atPath: root)

        let opt = "\(root)/opt/\(target)"
        try fm.createDirectory(atPath: opt, withIntermediateDirectories: true)
        let binaryPath = "\(path)/.omni/linux/\(target)"
        guard fm.fileExists(atPath: binaryPath) else {
            throw ShellError.failed("packaging", "no built binary at \(binaryPath) — build for Linux first")
        }
        try fm.copyItem(atPath: binaryPath, toPath: "\(opt)/\(target)")
        try Shell.checked("chmod +x \"\(opt)/\(target)\"", step: "marking the executable")

        let iconSourcePath = "\(path)/.omni/linux/icon.png"
        if fm.fileExists(atPath: iconSourcePath) {
            let iconDir = "\(root)/usr/share/icons/hicolor/256x256/apps"
            try fm.createDirectory(atPath: iconDir, withIntermediateDirectories: true)
            try fm.copyItem(atPath: iconSourcePath, toPath: "\(iconDir)/\(target).png")
        }

        let appsDir = "\(root)/usr/share/applications"
        try fm.createDirectory(atPath: appsDir, withIntermediateDirectories: true)
        let desktopEntry = """
        [Desktop Entry]
        Type=Application
        Name=\(target)
        Exec=/opt/\(target)/\(target)
        Icon=\(target)
        Categories=Utility;
        Terminal=false
        """
        try desktopEntry.write(toFile: "\(appsDir)/\(target).desktop", atomically: true, encoding: .utf8)
    }

    public func buildDeb(architecture: String = "amd64", version: String = "1.0") throws -> String {
        let root = "\(installerStageRoot)-deb"
        try stagePayload(into: root)

        let debianDir = "\(root)/DEBIAN"
        try FileManager.default.createDirectory(atPath: debianDir, withIntermediateDirectories: true)

        let installedSize = (try? Shell.run("du -sk \"\(root)/opt\" 2>/dev/null | awk '{print $1}'")) ?? "0"
        let control = """
        Package: \(target.lowercased())
        Version: \(version)
        Architecture: \(architecture)
        Maintainer: omni-app
        Installed-Size: \(installedSize.isEmpty ? "0" : installedSize)
        Section: x11
        Priority: optional
        Description: \(target)
        """
        try control.write(toFile: "\(debianDir)/control", atomically: true, encoding: .utf8)

        let tempOutput = "\(installerStageRoot)-out/\(target.lowercased())_\(version)_\(architecture).deb"
        try FileManager.default.createDirectory(
            atPath: (tempOutput as NSString).deletingLastPathComponent,
            withIntermediateDirectories: true)

        Console.info("Building .deb installer...")
        try Shell.checked("dpkg-deb --build --root-owner-group \"\(root)\" \"\(tempOutput)\"", step: "dpkg-deb")

        let outputDir = "\(path)/.build/installers"
        try Shell.checked("mkdir -p \"\(outputDir)\"", step: "creating the installer output directory")
        let output = "\(outputDir)/\(target.lowercased())_\(version)_\(architecture).deb"
        try? FileManager.default.removeItem(atPath: output)
        try FileManager.default.copyItem(atPath: tempOutput, toPath: output)

        Console.success("Installer built: \(output)")
        print("   Install with: sudo dpkg -i \"\(output)\"")
        return output
    }

    public func buildRpm(architecture: String = "x86_64", version: String = "1.0") throws -> String {
        let root = "\(installerStageRoot)-rpm"
        try stagePayload(into: root)

        let topdir = "\(installerStageRoot)-rpm-topdir"
        try? FileManager.default.removeItem(atPath: topdir)
        for sub in ["BUILD", "RPMS", "SOURCES", "SPECS", "SRPMS"] {
            try FileManager.default.createDirectory(atPath: "\(topdir)/\(sub)", withIntermediateDirectories: true)
        }

        // %install copies straight from the already-staged payload rather
        // than re-deriving it, so the .deb and .rpm always agree on layout.
        let spec = """
        Name: \(target.lowercased())
        Version: \(version)
        Release: 1
        Summary: \(target)
        License: Proprietary
        BuildArch: \(architecture)

        %description
        \(target)

        %install
        mkdir -p %{buildroot}
        cp -a \(shellQuote(root))/. %{buildroot}/

        %files
        /opt/\(target)/\(target)
        /usr/share/applications/\(target).desktop
        %ifarch \(architecture)
        %endif

        %post
        exit 0

        %postun
        exit 0
        """
        try spec.write(toFile: "\(topdir)/SPECS/\(target.lowercased()).spec", atomically: true, encoding: .utf8)

        Console.info("Building .rpm installer...")
        let build = try Shell.exec("/usr/bin/env", [
            "rpmbuild", "--define", "_topdir \(topdir)",
            "--target", architecture,
            "-bb", "\(topdir)/SPECS/\(target.lowercased()).spec"
        ])
        guard build.status == 0 else { throw ShellError.failed("rpmbuild", build.output) }

        guard let rpmFile = (try? FileManager.default.contentsOfDirectory(atPath: "\(topdir)/RPMS"))?
            .compactMap({ dir -> String? in
                let sub = "\(topdir)/RPMS/\(dir)"
                return (try? FileManager.default.contentsOfDirectory(atPath: sub))?
                    .first(where: { $0.hasSuffix(".rpm") })
                    .map { "\(sub)/\($0)" }
            }).first else {
            throw ShellError.failed("rpmbuild", "no .rpm produced under \(topdir)/RPMS")
        }

        let outputDir = "\(path)/.build/installers"
        try Shell.checked("mkdir -p \"\(outputDir)\"", step: "creating the installer output directory")
        let output = "\(outputDir)/\(target.lowercased())-\(version)-1.\(architecture).rpm"
        try? FileManager.default.removeItem(atPath: output)
        try FileManager.default.copyItem(atPath: rpmFile, toPath: output)

        Console.success("Installer built: \(output)")
        print("   Install with: sudo rpm -i \"\(output)\"")
        return output
    }

    private func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
