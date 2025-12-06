#if os(macOS) || os(iOS)
import Foundation

#if os(macOS)
import AppKit

public class OmniTextView: NSTextView, NSTextViewDelegate {
    var onChange: ((String) -> Void)?
    /// The text system a view made with a container of its own needs: a view
    /// holds its container weakly up the chain, and given none it had no
    /// storage at all (it showed nothing and took no typing).
    var ownedStorage: NSTextStorage?

    override init(frame frameRect: NSRect, textContainer: NSTextContainer?) {
        super.init(frame: frameRect, textContainer: textContainer)
        delegate = self
    }
    required init?(coder: NSCoder) { fatalError() }

    public func textDidChange(_ notification: Notification) {
        onChange?(string)
    }
}
#elseif os(iOS)
import UIKit

// UITextView is not a UIControl either; self-delegating for the same reason.
public class OmniTextView: UITextView, UITextViewDelegate {
    var onChange: ((String) -> Void)?

    override init(frame: CGRect, textContainer: NSTextContainer?) {
        super.init(frame: frame, textContainer: textContainer)
        delegate = self
    }
    required init?(coder: NSCoder) { fatalError() }

    public func textViewDidChange(_ textView: UITextView) {
        onChange?(textView.text)
    }
}
#endif

extension TextEditor {
    @MainActor public func makeNative() -> NativeView {
        #if os(macOS)
            let scrollView = NSScrollView()
            scrollView.hasVerticalScroller = true
            scrollView.translatesAutoresizingMaskIntoConstraints = false

            // A text system of its own: storage, layout, a container that
            // tracks the view's width so the text wraps. (Given a nil
            // container, NSTextView had no storage: blank, and inert.)
            let storage = NSTextStorage()
            let layout = NSLayoutManager()
            storage.addLayoutManager(layout)
            let container = NSTextContainer(containerSize: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
            container.widthTracksTextView = true
            layout.addTextContainer(container)

            let tv = OmniTextView(frame: .zero, textContainer: container)
            tv.ownedStorage = storage
            tv.isVerticallyResizable = true
            tv.isHorizontallyResizable = false
            tv.autoresizingMask = [.width]
            tv.minSize = NSSize(width: 0, height: 0)
            tv.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
            tv.font = .systemFont(ofSize: NSFont.systemFontSize)
            tv.isRichText = false
            tv.drawsBackground = false

            scrollView.documentView = tv
            scrollView.drawsBackground = false
            // A scroll view has no height of its own: in a stack it was 0
            // tall. As on iOS, at least 120, which a .frame(height:) overrides.
            let least = scrollView.heightAnchor.constraint(greaterThanOrEqualToConstant: 120)
            least.priority = .defaultHigh
            least.isActive = true
            return scrollView

        #elseif os(iOS)
            let tv = OmniTextView()
            tv.translatesAutoresizingMaskIntoConstraints = false
            tv.font = .systemFont(ofSize: 16)
            tv.layer.borderColor = UIColor.separator.cgColor
            tv.layer.borderWidth = 1.0 / UIScreen.main.scale
            tv.layer.cornerRadius = 5.0

            tv.heightAnchor.constraint(greaterThanOrEqualToConstant: 120).isActive = true

            return tv
        #endif
    }

    @MainActor public func updateNative(_ view: NativeView) {
        let binding = text // Capture locally

        #if os(macOS)
            if let sv = view as? NSScrollView, let tv = sv.documentView as? OmniTextView {
                if tv.string != binding.wrappedValue { tv.string = binding.wrappedValue }
                // Swapped, not re-bound: the delegate is set once in
                // makeNative: only the closure it reads changes here.
                tv.onChange = { newText in binding.wrappedValue = newText }
            }
        #elseif os(iOS)
            if let tv = view as? OmniTextView {
                if tv.text != binding.wrappedValue {
                    tv.text = binding.wrappedValue
                }
                tv.onChange = { newText in binding.wrappedValue = newText }
            }
        #endif
    }
}
#endif
