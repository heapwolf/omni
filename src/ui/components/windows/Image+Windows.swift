// src/ui/components/windows/Image+Windows.swift
//
// Images from files, bundles and bytes, drawn by Direct2D. SF Symbols are
// Apple's, so a system image is the nearest glyph in Segoe Fluent Icons,
// Windows 11's own icon font, at the size of the text around it, in its colour.

#if os(Windows)
import Foundation

extension Image {
    @MainActor public func makeNative() -> NativeView {
        WinView.make(isSystem ? "Symbol" : "Image", layout: .leaf)
    }

    @MainActor public func updateNative(_ view: NativeView) {
        let v = winView(view)
        if isSystem {
            applySymbol(v)
        } else {
            applyBitmap(v)
        }
    }

    @MainActor private func applySymbol(_ v: WinView) {
        let font = Tracker.current?.environment.font ?? .body
        let size = WinTextStyle.windowsSize(font)
        let (glyph, isIconFont) = WinSymbols.glyph(for: name)
        var style = WinTextStyle(family: isIconFont ? "Segoe Fluent Icons" : nil, size: isIconFont ? size * 1.1 : size,
                                 weight: isIconFont ? 400 : 600, wraps: false, trim: 0)
        style.alignment = 1
        let resizable = isResizable
        v.measure = { _ in
            let layout = WinTextCache.shared.layout(glyph, style, maxWidth: nil)
            // Square, as a symbol's frame is: the glyph's line height both ways.
            let side = max(layout.width, layout.height)
            return WinSize(width: side, height: layout.height)
        }
        v.hexpand = resizable
        v.vexpand = resizable
        v.draw = { [weak v] canvas, rect in
            var drawn = style
            if resizable { drawn.size = max(4, min(rect.width, rect.height) * 0.8) }
            let layout = WinTextCache.shared.layout(glyph, drawn, maxWidth: rect.width)
            let ink = v?.inheritedForeground ?? v?.inheritedTint ?? .primaryText
            canvas.text(layout, at: 0, ((rect.height - layout.height) / 2).rounded(), ink)
        }
    }

    @MainActor private func applyBitmap(_ v: WinView) {
        let image = WinImageStore.image(named: name, data: data)
        let resizable = isResizable, mode = contentMode
        v.hexpand = resizable
        v.vexpand = resizable
        v.measure = { proposed in
            guard let image else { return .zero }
            guard resizable, let proposed, image.width > 0 else { return WinSize(width: image.width, height: image.height) }
            // Resizable: its aspect ratio at the width it's offered.
            return WinSize(width: proposed, height: proposed * image.height / image.width)
        }
        v.draw = { canvas, rect in
            guard let image, image.width > 0, image.height > 0 else { return }
            guard resizable else {
                canvas.image(image, in: WinRect(x: 0, y: 0, width: image.width, height: image.height))
                return
            }
            let sx = rect.width / image.width, sy = rect.height / image.height
            let s = mode == .fit ? min(sx, sy) : max(sx, sy)
            let w = image.width * s, h = image.height * s
            let target = WinRect(x: (rect.width - w) / 2, y: (rect.height - h) / 2, width: w, height: h)
            if mode == .fill { canvas.clip(rect) }
            canvas.image(image, in: target)
            if mode == .fill { canvas.popClip() }
        }
    }
}

/// Decoded images, by name: each file is read once.
@MainActor
enum WinImageStore {
    private static var named: [String: WinImage?] = [:]

    static func image(named name: String, data: Data?) -> WinImage? {
        if let data { return WinImage(data: data) }
        if let found = named[name] { return found }
        let made = path(for: name).flatMap { WinImage(path: $0) }
        named[name] = made
        return made
    }

    /// A path as given, else the app's resources: beside the .exe, in its
    /// Resources folder, or in a SwiftPM resource bundle.
    private static func path(for name: String) -> String? {
        let fm = FileManager.default
        if fm.fileExists(atPath: name) { return name }
        let extensions = ["", ".png", ".jpg", ".jpeg", ".ico", ".bmp", ".gif"]
        var folders: [URL] = []
        if let exe = Bundle.main.executableURL?.deletingLastPathComponent() {
            folders += [exe, exe.appendingPathComponent("Resources")]
            if let bundles = try? fm.contentsOfDirectory(at: exe, includingPropertiesForKeys: nil) {
                folders += bundles.filter { $0.pathExtension == "resources" }
            }
        }
        if let resources = Bundle.main.resourceURL { folders.append(resources) }
        for folder in folders {
            for ext in extensions {
                let candidate = folder.appendingPathComponent(name + ext).path
                if fm.fileExists(atPath: candidate) { return candidate }
            }
        }
        return nil
    }
}

/// SF Symbol names to Segoe Fluent Icons code points. A name not here falls
/// back to its first part ("person.2.fill" to "person"), then to a dot.
enum WinSymbols {
    static func glyph(for name: String) -> (String, Bool) {
        if let text = textual[name] { return (text, false) }
        var key = name
        while true {
            if let code = icons[key], let scalar = Unicode.Scalar(code) { return (String(Character(scalar)), true) }
            if let suffix = [".fill", ".circle", ".square", ".rectangle"].first(where: { key.hasSuffix($0) }) {
                key.removeLast(suffix.count)
                continue
            }
            guard let dot = key.lastIndex(of: ".") else { break }
            key = String(key[..<dot])
        }
        return ("\u{E91F}", true) // a small dot
    }

    /// Symbols that are a character: as text, in the UI font.
    private static let textual: [String: String] = [
        "at": "@", "number": "#", "percent": "%", "dollarsign.circle": "$", "dollarsign": "$",
        "bitcoinsign.circle": "₿", "bitcoinsign": "₿", "eurosign": "€", "sterlingsign": "£",
    ]

    private static let icons: [String: UInt32] = [
        "antenna.radiowaves.left.and.right": 0xE701, "archivebox": 0xE7B8, "arrow.clockwise": 0xE72C,
        "arrow.counterclockwise": 0xE7A7, "arrow.down": 0xE74B, "arrow.down.circle": 0xE74B,
        "arrow.up": 0xE74A, "arrow.up.circle": 0xE74A, "arrow.right": 0xE72A, "arrow.right.circle": 0xE72A,
        "arrow.left": 0xE72B, "arrow.left.arrow.right": 0xE8AB, "arrow.left.arrow.right.circle": 0xE8AB,
        "arrow.triangle.2.circlepath": 0xE895, "arrow.uturn.backward": 0xE7A7, "arrow.uturn.backward.circle": 0xE7A7,
        "arrow.up.right.square": 0xE8A7, "banknote": 0xE8C7, "bell": 0xEA8F, "bell.slash": 0xE7ED,
        "building.columns": 0xE8F1, "calendar": 0xE787, "camera": 0xE722, "chart.bar": 0xE9D2,
        "chart.line.uptrend.xyaxis": 0xE9D9, "chart.pie": 0xEB05, "checklist": 0xE9D5, "checkmark": 0xE73E,
        "checkmark.circle": 0xE930, "checkmark.circle.fill": 0xEC61, "checkmark.seal": 0xEB95,
        "checkmark.shield": 0xEA18, "checkmark.shield.fill": 0xEA18, "chevron.left": 0xE76B,
        "chevron.right": 0xE76C, "chevron.down": 0xE70D, "chevron.up": 0xE70E, "chevron.up.chevron.down": 0xE8CB,
        "clock": 0xE823, "clock.arrow.circlepath": 0xE81C, "creditcard": 0xE8C7, "crown": 0xE734,
        "doc": 0xE8A5, "doc.on.clipboard": 0xE77F, "doc.on.doc": 0xE8C8, "doc.text": 0xE8A5,
        "doc.text.magnifyingglass": 0xE721, "ellipsis": 0xE712, "ellipsis.circle": 0xE712, "envelope": 0xE715,
        "exclamationmark.triangle": 0xE7BA, "exclamationmark.triangle.fill": 0xE7BA,
        "exclamationmark.circle": 0xE783, "eye": 0xE890, "eye.slash": 0xED1A, "flag": 0xE7C1, "folder": 0xE8B7,
        "gear": 0xE713, "gearshape": 0xE713, "gift": 0xE719, "globe": 0xE774, "hand.raised": 0xE8D7,
        "heart": 0xEB51, "house": 0xE80F, "info.circle": 0xE946, "iphone": 0xE8EA, "iphone.slash": 0xE8EA,
        "key": 0xE8D7, "link": 0xE71B, "link.badge.plus": 0xE71B, "link.circle": 0xE71B,
        "list.bullet": 0xE8FD, "list.bullet.rectangle": 0xE8FD, "list.bullet.rectangle.portrait": 0xE8FD,
        "location": 0xE81D, "location.slash": 0xE81D, "lock": 0xE72E, "lock.open": 0xE785,
        "magnifyingglass": 0xE721, "minus": 0xE738, "minus.circle": 0xE738, "nosign": 0xE733,
        "paperplane": 0xE724, "pencil": 0xE70F, "person": 0xE77B, "person.2": 0xE716,
        "person.2.badge.gearshape": 0xE716, "person.badge.key": 0xE8D7, "person.badge.plus": 0xE8FA,
        "person.crop.circle": 0xE77B, "person.text.rectangle": 0xE779, "photo": 0xEB9F, "play": 0xE768,
        "pause": 0xE769, "plus": 0xE710, "plus.circle": 0xE710, "point.3.connected.trianglepath.dotted": 0xE968,
        "power": 0xE7E8, "qrcode": 0xED14, "questionmark.circle": 0xE9CE, "shippingbox": 0xE7B8,
        "sidebar.left": 0xE8A0, "slider.horizontal.3": 0xE9E9, "square.and.arrow.down": 0xE896,
        "square.and.arrow.up": 0xE72D, "square.and.pencil": 0xE70F, "star": 0xE734, "star.fill": 0xE735,
        "star.circle": 0xE734, "stethoscope": 0xE95E, "tablecells": 0xE80A, "tag": 0xE8EC, "trash": 0xE74D,
        "tray": 0xE715, "waveform.path.ecg": 0xE95E, "wifi": 0xE701, "xmark": 0xE711, "xmark.circle": 0xE711,
        "xmark.circle.fill": 0xE711,
    ]
}
#endif
