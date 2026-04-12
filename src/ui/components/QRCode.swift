// src/ui/components/QRCode.swift
// A QR code for a piece of text: a deposit address, a link. SwiftUI has none
// (apps reach for CoreImage), so this is omni's own. Square, filling the
// width it is given; set a frame.
import Foundation
#if os(iOS)
import UIKit
import CoreImage
#elseif os(macOS)
import AppKit
import CoreImage
#endif

#if os(iOS) || os(macOS)
public struct QRCode: NativeComponent {
    let text: String

    public init(_ text: String) { self.text = text }

    @MainActor public func makeNative() -> NativeView {
        #if os(iOS)
        let view = UIImageView()
        view.contentMode = .scaleAspectFit
        // Crisp modules: no smoothing when the small image is scaled up.
        view.layer.magnificationFilter = .nearest
        #else
        let view = NSImageView()
        view.imageScaling = .scaleProportionallyUpOrDown
        view.wantsLayer = true
        view.layer?.magnificationFilter = .nearest
        #endif
        view.translatesAutoresizingMaskIntoConstraints = false
        view.widthAnchor.constraint(equalTo: view.heightAnchor).isActive = true
        // Claims fill, as a stack that wants the room does: a frame then
        // stretches it to its size. Left at an image view's own, it sat at
        // the code's few dozen pixels in the middle of its frame.
        view.setContentHuggingPriority(.init(rawValue: 1), for: .horizontal)
        view.setContentHuggingPriority(.init(rawValue: 1), for: .vertical)
        view.setContentCompressionResistancePriority(.init(rawValue: 1), for: .horizontal)
        view.setContentCompressionResistancePriority(.init(rawValue: 1), for: .vertical)
        return view
    }

    @MainActor public func updateNative(_ view: NativeView) {
        guard let image = Self.cgImage(for: text) else { return }
        #if os(iOS)
        (view as? UIImageView)?.image = UIImage(cgImage: image)
        #else
        (view as? NSImageView)?.image = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
        #endif
        view.setAccessibilityLabelIfAvailable(text)
    }

    /// One pixel per module, with the standard quiet zone; nil for text too
    /// long to encode.
    nonisolated static func cgImage(for text: String) -> CGImage? {
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(Data(text.utf8), forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let output = filter.outputImage else { return nil }
        return CIContext().createCGImage(output, from: output.extent)
    }
}

private extension NativeView {
    @MainActor func setAccessibilityLabelIfAvailable(_ text: String) {
        #if os(iOS)
        accessibilityLabel = text
        #else
        setAccessibilityLabel(text)
        #endif
    }
}
#else
/// No QR on Android, GTK or Windows yet: the text itself. omni-work/TODO.md.
public struct QRCode: View {
    let text: String
    public init(_ text: String) { self.text = text }
    public var body: some View { Text(text) }
}
#endif
