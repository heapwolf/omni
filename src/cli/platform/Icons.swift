// src/cli/platform/Icons.swift
import Foundation

/// Per-platform icon sizes and containers, generated at build time from one
/// source image. Uses only sips and iconutil, plus a hand-rolled .ico packer.
enum AppIcon {
    /// Where each size comes from.
    enum Source {
        /// The app's own icon.png, resized per platform.
        case file(String)
        /// Drawn by IconArt, carrying the app's initial, when the app has no icon.
        case placeholder(Character?)

        var isPlaceholder: Bool { if case .placeholder = self { return true }; return false }
    }

    /// icon.png beside omni.json in the app's directory.
    static func find(in appPath: String) -> String? {
        let candidate = "\(appPath)/icon.png"
        return FileManager.default.fileExists(atPath: candidate) ? candidate : nil
    }

    /// The app's icon, or the placeholder. Never nil.
    static func resolve(in appPath: String, name: String) -> Source {
        if let icon = find(in: appPath) { return .file(icon) }
        // The initial, uppercased. An unwritable first character leaves it empty.
        return .placeholder(name.first.map { Character($0.uppercased()) })
    }

    /// Drawn at the requested size; sips is macOS-only, so there is no resample.
    static func write(_ source: Source, size: Int, to output: String) throws {
        switch source {
        case .file(let path):
            try resize(path, to: size, output: output)
        case .placeholder(let letter):
            try IconArt.placeholder(size: size, letter: letter).write(to: URL(fileURLWithPath: output))
        }
    }

    /// Resizes via sips, macOS's built-in image tool.
    static func resize(_ source: String, to size: Int, output: String) throws {
        _ = try Shell.checked(
            "sips -z \(size) \(size) \(shellQuote(source)) --out \(shellQuote(output))",
            step: "resizing icon to \(size)x\(size)")
    }

    // MARK: - iOS

    /// An asset catalog compiled to Assets.car, which is where current iOS
    /// reads the icon named by CFBundleIconName; without it the home screen
    /// shows the system's blank placeholder. The two loose PNGs stay for
    /// CFBundleIconFiles on older systems.
    ///
    /// `platform` is actool's: "iphoneos" or "iphonesimulator".
    static func writeIOSIcons(source: Source, into bundleDir: String, platform: String,
                              deploymentTarget: String) throws {
        try write(source, size: 120, to: "\(bundleDir)/AppIcon60x60@2x.png")
        try write(source, size: 180, to: "\(bundleDir)/AppIcon60x60@3x.png")

        let fm = FileManager.default
        let work = NSTemporaryDirectory() + "omni-icon-\(UUID().uuidString)"
        defer { try? fm.removeItem(atPath: work) }
        let catalog = "\(work)/Assets.xcassets"
        let iconSet = "\(catalog)/AppIcon.appiconset"
        try fm.createDirectory(atPath: iconSet, withIntermediateDirectories: true)
        try #"{ "info": { "author": "omni", "version": 1 } }"#
            .write(toFile: "\(catalog)/Contents.json", atomically: true, encoding: .utf8)
        // One 1024 image; actool derives every size from it (Xcode 14+).
        try write(source, size: 1024, to: "\(iconSet)/AppIcon-1024.png")
        try #"""
            { "images": [ { "filename": "AppIcon-1024.png", "idiom": "universal",
                            "platform": "ios", "size": "1024x1024" } ],
              "info": { "author": "omni", "version": 1 } }
            """#.write(toFile: "\(iconSet)/Contents.json", atomically: true, encoding: .utf8)

        try Shell.checked("""
            xcrun actool --compile "\(bundleDir)" --platform \(platform) \
              --minimum-deployment-target \(deploymentTarget) --app-icon AppIcon \
              --target-device iphone --target-device ipad \
              --output-partial-info-plist "\(work)/partial.plist" "\(catalog)"
            """, step: "compiling the app icon")
    }

    static let iosInfoPlistFragment = """
        <key>CFBundleIcons</key>
        <dict>
            <key>CFBundlePrimaryIcon</key>
            <dict>
                <key>CFBundleIconFiles</key>
                <array>
                    <string>AppIcon60x60</string>
                </array>
                <key>CFBundleIconName</key>
                <string>AppIcon</string>
            </dict>
        </dict>
        """

    // MARK: - macOS

    /// Builds a standard .iconset folder and runs it through `iconutil`
    /// (also built into macOS) to produce a real .icns.
    static func writeMacIcns(source: Source, into resourcesDir: String) throws {
        let fm = FileManager.default
        let iconset = "\(resourcesDir)/AppIcon.iconset"
        try? fm.removeItem(atPath: iconset)
        try fm.createDirectory(atPath: iconset, withIntermediateDirectories: true)

        // (filename, pixel size); the exact set iconutil requires.
        let sizes: [(String, Int)] = [
            ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
            ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
            ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
            ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
            ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024)
        ]
        for (name, size) in sizes {
            try write(source, size: size, to: "\(iconset)/\(name)")
        }

        _ = try Shell.checked(
            "iconutil -c icns \(shellQuote(iconset)) -o \(shellQuote("\(resourcesDir)/AppIcon.icns"))",
            step: "building AppIcon.icns")
        try? fm.removeItem(atPath: iconset)
    }

    // MARK: - Android

    static func writeAndroidMipmaps(source: Source, into resDir: String) throws {
        let densities: [(String, Int)] = [
            ("mdpi", 48), ("hdpi", 72), ("xhdpi", 96), ("xxhdpi", 144), ("xxxhdpi", 192)
        ]
        for (density, size) in densities {
            let dir = "\(resDir)/mipmap-\(density)"
            try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            try write(source, size: size, to: "\(dir)/ic_launcher.png")
        }
    }

    // MARK: - Windows

    static func writeWindowsIco(source: Source, output: String) throws {
        let sizes = [256, 128, 64, 48, 32, 16]
        let tmp = NSTemporaryDirectory() + "omni-ico-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: tmp) }

        var images: [(size: Int, data: Data)] = []
        for size in sizes {
            let path = "\(tmp)/\(size).png"
            try write(source, size: size, to: path)
            guard let data = FileManager.default.contents(atPath: path) else {
                throw ShellError.failed("packing .ico", "missing resized PNG at \(size)x\(size)")
            }
            images.append((size, data))
        }

        var file = Data()
        // ICONDIR: reserved(2)=0, type(2)=1 (icon), count(2)
        file.append(contentsOf: [0, 0])
        file.append(contentsOf: [1, 0])
        file.append(contentsOf: UInt16(images.count).littleEndianBytes)

        var offset = 6 + images.count * 16
        var entries = Data()
        var payload = Data()
        for (size, data) in images {
            let dim = UInt8(size == 256 ? 0 : size) // 0 means 256 in ICO's 1-byte field
            entries.append(dim)                      // width
            entries.append(dim)                      // height
            entries.append(0)                        // color count (0 = no palette)
            entries.append(0)                        // reserved
            entries.append(contentsOf: UInt16(1).littleEndianBytes)   // color planes
            entries.append(contentsOf: UInt16(32).littleEndianBytes)  // bits per pixel
            entries.append(contentsOf: UInt32(data.count).littleEndianBytes) // data size
            entries.append(contentsOf: UInt32(offset).littleEndianBytes)     // data offset
            payload.append(data)
            offset += data.count
        }

        file.append(entries)
        file.append(payload)
        try file.write(to: URL(fileURLWithPath: output))
    }
}

private func shellQuote(_ value: String) -> String {
    "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
}

private extension FixedWidthInteger {
    var littleEndianBytes: [UInt8] {
        withUnsafeBytes(of: self.littleEndian, Array.init)
    }
}
