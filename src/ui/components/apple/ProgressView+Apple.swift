#if os(macOS) || os(iOS)
import Foundation

#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

extension ProgressView {
    @MainActor public func makeNative() -> NativeView {
        #if os(macOS)
            let pi = NSProgressIndicator()
            pi.translatesAutoresizingMaskIntoConstraints = false
            if fraction == nil {
                pi.style = .spinning
                pi.isIndeterminate = true
                pi.startAnimation(nil)
            } else {
                pi.style = .bar
                pi.isIndeterminate = false
                pi.minValue = 0
                pi.maxValue = 1
            }
            return pi

        #elseif os(iOS)
            // UIActivityIndicatorView cannot show progress and UIProgressView
            // cannot spin, so the determinate case is a different class.
            if fraction == nil {
                let ai = UIActivityIndicatorView(style: .medium)
                ai.translatesAutoresizingMaskIntoConstraints = false
                ai.startAnimating()
                return ai
            }
            let pv = UIProgressView(progressViewStyle: .default)
            pv.translatesAutoresizingMaskIntoConstraints = false
            return pv
        #endif
    }

    @MainActor public func updateNative(_ view: NativeView) {
        guard let fraction else { return }  // indeterminate spinners never change
        #if os(macOS)
            (view as? NSProgressIndicator)?.doubleValue = fraction
        #elseif os(iOS)
            (view as? UIProgressView)?.progress = Float(fraction)
        #endif
    }
}
#endif
