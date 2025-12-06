#if os(macOS) || os(iOS)
import Foundation

#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

extension Slider {
    @MainActor public func makeNative() -> NativeView {
        #if os(macOS)
            let slider = NSSlider(value: value.wrappedValue, minValue: range.lowerBound, maxValue: range.upperBound, target: nil, action: nil)
            slider.translatesAutoresizingMaskIntoConstraints = false

            bindAppleEvent(slider, "action") { [value, weak slider] in
                if let s = slider { value.wrappedValue = s.doubleValue }
            }
            return slider

        #elseif os(iOS)
            let slider = UISlider()
            slider.minimumValue = Float(range.lowerBound)
            slider.maximumValue = Float(range.upperBound)
            slider.translatesAutoresizingMaskIntoConstraints = false

            bindAppleEvent(slider, "valueChanged") { [value, weak slider] in
                if let s = slider { value.wrappedValue = Double(s.value) }
            }
            return slider
        #endif
    }

    @MainActor public func updateNative(_ view: NativeView) {
        let current = value.wrappedValue

        #if os(macOS)
            if let s = view as? NSSlider, s.doubleValue != current {
                s.doubleValue = current
            }
        #elseif os(iOS)
            if let s = view as? UISlider, Double(s.value) != current {
                s.value = Float(current)
            }
        #endif
    }
}
#endif
