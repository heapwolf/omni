import Foundation

public struct Image: NativeComponent {
    public var name: String
    public var isSystem: Bool
    public var data: Data?

    public init(_ name: String) {
        self.name = name
        self.isSystem = false
        self.data = nil
    }

    public init(systemName: String) {
        self.name = systemName
        self.isSystem = true
        self.data = nil
    }

    public init(data: Data) {
        self.name = ""
        self.isSystem = false
        self.data = data
    }

    public enum ContentMode: Sendable { case fit, fill }

    /// Off: the image is its own size, as in SwiftUI.
    public var isResizable = false
    public var contentMode: ContentMode = .fit

    /// SwiftUI's: the image takes whatever size its frame gives it.
    public func resizable() -> Image {
        var copy = self; copy.isResizable = true; return copy
    }

    public func scaledToFit() -> Image {
        var copy = self; copy.contentMode = .fit; return copy
    }

    /// Fills the frame; the overflow is not cropped until .clipped(), as in SwiftUI.
    public func scaledToFill() -> Image {
        var copy = self; copy.contentMode = .fill; return copy
    }
}
