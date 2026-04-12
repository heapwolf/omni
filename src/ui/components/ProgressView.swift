import Foundation

public struct ProgressView: NativeComponent {
    /// nil is the indeterminate spinner; a value makes it a determinate bar.
    public var value: Double?
    public var total: Double

    public var fraction: Double? {
        guard let value, total > 0 else { return nil }
        return min(max(value / total, 0), 1)
    }

    public var body: any View { self }

    public init() {
        self.value = nil
        self.total = 1
    }

    public init(value: Double?, total: Double = 1.0) {
        self.value = value
        self.total = total
    }
}
