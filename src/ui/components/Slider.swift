import Foundation

public struct Slider: NativeComponent {
    public var value: Binding<Double>
    public var range: ClosedRange<Double>

    public init(value: Binding<Double>, in range: ClosedRange<Double> = 0...1) {
        self.value = value
        self.range = range
    }
}
