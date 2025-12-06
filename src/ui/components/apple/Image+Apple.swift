#if os(macOS) || os(iOS)
import Foundation

#if os(macOS)
    import AppKit
#elseif os(iOS)
    import UIKit
#endif

extension Image {
    @MainActor public func makeNative() -> NativeView {
        #if os(macOS)
            let iv = NSImageView()
            iv.translatesAutoresizingMaskIntoConstraints = false
            if let data {
                iv.image = NSImage(data: data)
            } else if isSystem {
                iv.image = NSImage(systemSymbolName: name, accessibilityDescription: nil)
            } else {
                iv.image = NSImage(named: name)
            }
            return iv

        #elseif os(iOS)
            let iv = UIImageView()
            iv.contentMode = .scaleAspectFit
            iv.translatesAutoresizingMaskIntoConstraints = false
            if let data {
                iv.image = UIImage(data: data)
            } else if isSystem {
                iv.image = UIImage(systemName: name)
            } else {
                iv.image = UIImage(named: name)
            }
            return iv
        #endif
    }

    @MainActor public func updateNative(_ view: NativeView) {
        // Resizable: the frame decides the size, so the image's own must not
        // resist it.
        // Spelled per axis: the axis type is Axis on UIKit, Orientation on AppKit.
        let hugging: Float = isResizable ? 1 : 250
        let resistance: Float = isResizable ? 1 : 750
        view.setContentHuggingPriority(.init(rawValue: hugging), for: .horizontal)
        view.setContentHuggingPriority(.init(rawValue: hugging), for: .vertical)
        view.setContentCompressionResistancePriority(.init(rawValue: resistance), for: .horizontal)
        view.setContentCompressionResistancePriority(.init(rawValue: resistance), for: .vertical)

        #if os(macOS)
            guard let iv = view as? NSImageView else { return }
            iv.imageScaling = isResizable ? .scaleProportionallyUpOrDown : .scaleProportionallyDown
            // Every kind, not only data: a symbol name that changes between
            // renders (eye, eye.slash) must show the new one.
            if let data { iv.image = NSImage(data: data) }
            else if isSystem { iv.image = NSImage(systemSymbolName: name, accessibilityDescription: nil) }
            else { iv.image = NSImage(named: name) }
        #elseif os(iOS)
            guard let iv = view as? UIImageView else { return }
            iv.contentMode = contentMode == .fill ? .scaleAspectFill : .scaleAspectFit
            // Every kind, not only data: a symbol name that changes between
            // renders (eye, eye.slash) must show the new one.
            if let data { iv.image = UIImage(data: data) }
            else if isSystem { iv.image = UIImage(systemName: name) }
            else { iv.image = UIImage(named: name) }
        #endif
    }
}
#endif
