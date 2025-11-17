import Foundation

public enum HorizontalAlignment: Hashable, Sendable {
    case leading, center, trailing
}

public enum VerticalAlignment: Hashable, Sendable {
    case top, center, bottom
}

public struct Alignment: Hashable, Sendable {
    public var horizontal: HorizontalAlignment
    public var vertical: VerticalAlignment

    public init(horizontal: HorizontalAlignment, vertical: VerticalAlignment) {
        self.horizontal = horizontal
        self.vertical = vertical
    }

    public static let center = Alignment(horizontal: .center, vertical: .center)
    public static let topLeading = Alignment(horizontal: .leading, vertical: .top)
    public static let top = Alignment(horizontal: .center, vertical: .top)
    public static let topTrailing = Alignment(horizontal: .trailing, vertical: .top)
    public static let leading = Alignment(horizontal: .leading, vertical: .center)
    public static let trailing = Alignment(horizontal: .trailing, vertical: .center)
    public static let bottomLeading = Alignment(horizontal: .leading, vertical: .bottom)
    public static let bottom = Alignment(horizontal: .center, vertical: .bottom)
    public static let bottomTrailing = Alignment(horizontal: .trailing, vertical: .bottom)
}

#if os(Android)
// android.view.Gravity
extension HorizontalAlignment {
    var androidGravity: Int32 {
        switch self {
        case .leading: return 3  // LEFT
        case .center: return 1   // CENTER_HORIZONTAL
        case .trailing: return 5 // RIGHT
        }
    }
}

extension VerticalAlignment {
    var androidGravity: Int32 {
        switch self {
        case .top: return 48    // TOP
        case .center: return 16 // CENTER_VERTICAL
        case .bottom: return 80 // BOTTOM
        }
    }
}

extension Alignment {
    var androidGravity: Int32 { horizontal.androidGravity | vertical.androidGravity }
}
#endif
