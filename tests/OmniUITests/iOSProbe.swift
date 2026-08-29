#if os(iOS)
import UIKit
@testable import OmniUI


func labels(in view: NativeView) -> [String] {
    var found: [String] = []
    if let label = view as? UILabel, let text = label.text {
        found.append(text)
    } else if let button = view as? UIButton, let title = button.title(for: .normal) {
        found.append(title)
    }
    return found + view.subviews.flatMap { labels(in: $0) }
}

func button(titled title: String, in view: NativeView) -> UIButton? {
    if let button = view as? UIButton, button.title(for: .normal) == title {
        return button
    }
    for subview in view.subviews {
        if let match = button(titled: title, in: subview) { return match }
    }
    return nil
}

func widgetCount(in view: NativeView) -> Int {
    1 + view.subviews.reduce(0) { $0 + widgetCount(in: $1) }
}
#endif
