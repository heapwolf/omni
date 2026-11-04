#if os(macOS) || os(iOS)
import Foundation

#if os(macOS)
    import AppKit
#elseif os(iOS)
    import UIKit
#endif

/// The data an image view last decoded: the same data again is not decoded again. A render
/// that moves or fades an image (every frame of a swipe) would otherwise decode it each time,
/// and setting the image dirties layout, which on macOS can lay the tree out again for ever.
nonisolated(unsafe) private var decodedKey: UInt8 = 0

@MainActor private func isDecoded(_ data: Data, in view: NSObject) -> Bool {
    (objc_getAssociatedObject(view, &decodedKey) as? Data) == data
}

@MainActor private func markDecoded(_ data: Data?, in view: NSObject) {
    objc_setAssociatedObject(view, &decodedKey, data, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
}

extension Image {
    @MainActor public func makeNative() -> NativeView {
        #if os(macOS)
            let iv = NSImageView()
            iv.translatesAutoresizingMaskIntoConstraints = false
            if let data {
                iv.image = NSImage(data: data)
                markDecoded(data, in: iv)
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
                markDecoded(data, in: iv)
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
            if let data {
                if !isDecoded(data, in: iv) { iv.image = NSImage(data: data); markDecoded(data, in: iv) }
            } else {
                markDecoded(nil, in: iv)
                if isSystem { iv.image = NSImage(systemSymbolName: name, accessibilityDescription: nil) }
                else { iv.image = NSImage(named: name) }
            }
        #elseif os(iOS)
            guard let iv = view as? UIImageView else { return }
            iv.contentMode = contentMode == .fill ? .scaleAspectFill : .scaleAspectFit
            // Every kind, not only data: a symbol name that changes between
            // renders (eye, eye.slash) must show the new one.
            if let data {
                if !isDecoded(data, in: iv) { iv.image = UIImage(data: data); markDecoded(data, in: iv) }
            } else {
                markDecoded(nil, in: iv)
                if isSystem { iv.image = UIImage(systemName: name) }
                else { iv.image = UIImage(named: name) }
            }
        #endif
    }
}
#endif
