// The app's fonts: `Fonts/<Family>/*.ttf|otf` beside Package.swift, one folder
// per family.
//
//   Fonts/Inter/InterVariable.ttf
//   Fonts/Inter/InterVariable-Italic.ttf
//
// Copied into the bundle under the same layout, where OmniUI registers each
// file under its folder's name before the first render: Font.custom("Inter", ...)
// then picks the face for its weight. Where the build puts them:
//   iOS      Fonts/ in the .app
//   macOS    Fonts/ in Contents/Resources
//   Android  assets/Fonts/ in the APK, registered by the generated activity

import Foundation

struct AppFonts {
    /// Must match OmniUI's Font.bundledDirectory.
    static let directory = "Fonts"

    /// Family name to the font files in its folder, sorted.
    let families: [String: [String]]

    var isEmpty: Bool { families.isEmpty }

    static func find(in appPath: String) -> AppFonts {
        let root = "\(appPath)/\(directory)"
        let fm = FileManager.default
        var families: [String: [String]] = [:]
        for family in (try? fm.contentsOfDirectory(atPath: root)) ?? [] where !family.hasPrefix(".") {
            var isFolder: ObjCBool = false
            guard fm.fileExists(atPath: "\(root)/\(family)", isDirectory: &isFolder), isFolder.boolValue else {
                Console.warning("\(directory)/\(family) is not a folder: fonts go in \(directory)/<Family>/")
                continue
            }
            let files = ((try? fm.contentsOfDirectory(atPath: "\(root)/\(family)")) ?? [])
                .filter { isFontFile($0) }.sorted()
            if files.isEmpty {
                Console.warning("\(directory)/\(family) has no .ttf or .otf")
                continue
            }
            families[family] = files.map { "\(root)/\(family)/\($0)" }
        }
        return AppFonts(families: families)
    }

    static func isFontFile(_ name: String) -> Bool {
        let lowered = name.lowercased()
        return lowered.hasSuffix(".ttf") || lowered.hasSuffix(".otf")
    }

    /// Writes `directory/Fonts/<Family>/...`, replacing what a previous build
    /// left: bundles are reused between builds, and a removed font must go.
    func copy(into directory: String) throws {
        let fm = FileManager.default
        let target = "\(directory)/\(Self.directory)"
        try? fm.removeItem(atPath: target)
        guard !isEmpty else { return }
        for (family, files) in families {
            try fm.createDirectory(atPath: "\(target)/\(family)", withIntermediateDirectories: true)
            for file in files {
                // Contents only: copyItem replicates permissions, which 9p and SMB refuse.
                let data = try Data(contentsOf: URL(fileURLWithPath: file))
                let name = (file as NSString).lastPathComponent
                try data.write(to: URL(fileURLWithPath: "\(target)/\(family)/\(name)"))
            }
        }
    }

    /// Says what it bundled, so a missing face is noticed at build time.
    func announce() {
        guard !isEmpty else { return }
        let list = families.keys.sorted().map { "\($0) (\(families[$0]!.count))" }
        Console.info("fonts: \(list.joined(separator: ", "))")
    }
}
