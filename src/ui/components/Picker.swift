import Foundation

// MARK: - 1. Type Erasure for Tags

/// @MainActor: conformers wrap View content, so the conformance would
/// otherwise cross the boundary the View protocol draws.
@MainActor
public protocol AnyTaggedView {
    var anyTag: AnyHashable { get }
    var anyContent: any View { get }
}

public struct TaggedView<V: Hashable, Content: View>: View, AnyTaggedView {
    public var tag: V
    public var content: Content

    public var anyTag: AnyHashable { AnyHashable(tag) }
    public var anyContent: any View { content }

    public init(tag: V, content: Content) {
        self.tag = tag
        self.content = content
    }

    public var body: some View { content }
}

public extension View {
    /// Tags a view for identification, critical for Pickers and TabViews
    func tag<V: Hashable>(_ tag: V) -> TaggedView<V, Self> {
        TaggedView(tag: tag, content: self)
    }
}

// Helper to extract the string out of the AI's generated `Text("Label").tag(1)`
@MainActor
fileprivate func extractPickerLabel(_ view: any View) -> String {
    if let t = view as? Text { return t.text }
    if let anyV = view as? AnyView { return extractPickerLabel(anyV.content) }
    return "Option"
}

// MARK: - 2. Native Dropdown Component Base

public struct NativePicker<SelectionValue: Hashable>: NativeComponent {
    public var options: [(label: String, tag: SelectionValue)]
    public var selection: Binding<SelectionValue>

    public init(options: [(label: String, tag: SelectionValue)], selection: Binding<SelectionValue>) {
        self.options = options
        self.selection = selection
    }
}

// MARK: - 3. SwiftUI Picker Component

public struct Picker<SelectionValue: Hashable, Content: View>: View {
    public var title: String
    public var selection: Binding<SelectionValue>
    public var content: Content

    public init(_ title: String, selection: Binding<SelectionValue>, @ViewBuilder content: () -> Content) {
        self.title = title
        self.selection = selection
        self.content = content()
    }

    public var body: some View {
        // Unpack all views (this automatically resolves ForEach loops as well!)
        let views = Omni.unpackViews(content)
        var options: [(label: String, tag: SelectionValue)] = []

        // Extract tags and text labels
        for v in views {
            if let tagged = v as? AnyTaggedView,
               let concreteTag = tagged.anyTag.base as? SelectionValue {
                let label = extractPickerLabel(tagged.anyContent)
                options.append((label, concreteTag))
            }
        }

        // Render the native layout
        return HStack {
            Text(title)
            Spacer()
            NativePicker(options: options, selection: selection)
        }
    }
}
