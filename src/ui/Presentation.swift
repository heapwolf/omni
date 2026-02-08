// SwiftUI's sheet presentation API: detents, the drag indicator, the corner
// radius, and interactive dismissal. Applied to a sheet's content, as in
// SwiftUI:
//
//   .sheet(isPresented: $show) {
//       Terms()
//           .presentationDetents([.medium, .large], selection: $detent)
//           .presentationDragIndicator(.visible)
//   }
//
// SwiftUI carries these up to the sheet as preferences. Omni has no upward
// channel, so the sheet reads them from its content's node tree after each
// render (SheetModifierView, Routing.swift).
//
// iOS applies all of them. macOS ignores detents, as SwiftUI does there;
// Linux, Windows and Android ignore them all for now.

import Foundation

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

public struct PresentationDetent: Hashable, Sendable {
    enum Kind: Hashable, Sendable {
        case medium, large
        case fraction(Double)
        case height(Double)
        case fitted
    }
    let kind: Kind

    /// About half the screen.
    public static let medium = PresentationDetent(kind: .medium)
    /// The full sheet.
    public static let large = PresentationDetent(kind: .large)
    /// A fraction of the full sheet's height, 0...1.
    public static func fraction(_ fraction: Double) -> PresentationDetent {
        PresentationDetent(kind: .fraction(fraction))
    }
    /// A fixed height in points.
    public static func height(_ height: Double) -> PresentationDetent {
        PresentationDetent(kind: .height(height))
    }
    /// The content's own height, up to the full sheet. The content must have a
    /// height of its own: a ScrollView or a Spacer at its root has none.
    public static let fitted = PresentationDetent(kind: .fitted)

    /// For ordering smallest to largest; heights are placed by a nominal
    /// 800pt sheet.
    var approximateFraction: Double {
        switch kind {
        case .medium: return 0.5
        case .large: return 1
        case .fraction(let fraction): return fraction
        case .height(let height): return height / 800
        case .fitted: return 0.4
        }
    }

    var identifier: String {
        switch kind {
        case .medium: return "omni.medium"
        case .large: return "omni.large"
        case .fraction(let fraction): return "omni.fraction.\(fraction)"
        case .height(let height): return "omni.height.\(height)"
        case .fitted: return "omni.fitted"
        }
    }
}

/// SwiftUI's Visibility.
public enum Visibility: Hashable, Sendable {
    case automatic, visible, hidden
}

/// What a sheet's content asked for. The first value found, outermost first, wins.
struct PresentationOptions {
    var detents: Set<PresentationDetent>?
    var selection: Binding<PresentationDetent>?
    var dragIndicator: Visibility?
    var cornerRadius: Double?
    var interactiveDismissDisabled: Bool?
    var background: Color?

    mutating func fill(from other: PresentationOptions) {
        if background == nil { background = other.background }
        if detents == nil { detents = other.detents; selection = other.selection }
        if dragIndicator == nil { dragIndicator = other.dragIndicator }
        if cornerRadius == nil { cornerRadius = other.cornerRadius }
        if interactiveDismissDisabled == nil { interactiveDismissDisabled = other.interactiveDismissDisabled }
    }

    @MainActor static func collect(from node: Node) -> PresentationOptions {
        var options = PresentationOptions()
        func visit(_ node: Node) {
            if let carried = node.presentation { options.fill(from: carried) }
            node.kids.forEach(visit)
        }
        visit(node)
        return options
    }

    var orderedDetents: [PresentationDetent] {
        (detents ?? [.large]).sorted { $0.approximateFraction < $1.approximateFraction }
    }
}

/// Carries options to the enclosing sheet; draws nothing itself. Kept as a
/// node by Omni.unpackViews, so it survives inside a stack.
public struct PresentationModifierView: OmniStructuralView {
    var options: PresentationOptions
    public var content: any View

    init(options: PresentationOptions, content: any View) {
        self.options = options
        self.content = content
    }

    public typealias Body = Never
    public var body: Never { fatalError("Engine unpacks this") }
    public var unpacked: [any View] { [content] }
}

public extension View {
    /// The heights the sheet rests at. One detent fixes it; several let it be dragged.
    func presentationDetents(_ detents: Set<PresentationDetent>) -> some View {
        PresentationModifierView(options: PresentationOptions(detents: detents), content: self)
    }

    /// As above, with the current detent read and written through `selection`.
    func presentationDetents(_ detents: Set<PresentationDetent>,
                             selection: Binding<PresentationDetent>) -> some View {
        PresentationModifierView(options: PresentationOptions(detents: detents, selection: selection),
                                 content: self)
    }

    /// .automatic shows it when there is more than one detent, as UIKit does.
    func presentationDragIndicator(_ visibility: Visibility) -> some View {
        PresentationModifierView(options: PresentationOptions(dragIndicator: visibility), content: self)
    }

    /// nil is the system's radius.
    func presentationCornerRadius(_ radius: Double?) -> some View {
        PresentationModifierView(options: PresentationOptions(cornerRadius: radius ?? -1), content: self)
    }

    /// SwiftUI's: the sheet's own colour, under its content and to its edges.
    func presentationBackground(_ color: Color) -> some View {
        PresentationModifierView(options: PresentationOptions(background: color), content: self)
    }

    /// Stops a swipe down from dismissing the sheet; the binding still can.
    func interactiveDismissDisabled(_ isDisabled: Bool = true) -> some View {
        PresentationModifierView(options: PresentationOptions(interactiveDismissDisabled: isDisabled),
                                 content: self)
    }
}

#if os(macOS)
extension PresentationOptions {
    /// A sheet's size on macOS: the parent's width, and the first (smallest) detent's
    /// height (a fitted one measures `content`). No detents is the full height.
    @MainActor func sheetSize(content: NSView, in parent: NSWindow?) -> NSSize {
        let full = parent?.contentLayoutRect.size ?? NSSize(width: 400, height: 600)
        let height: CGFloat
        switch orderedDetents.first?.kind ?? .large {
        case .large: height = full.height
        case .medium: height = full.height * 0.5
        case .fraction(let fraction): height = full.height * fraction
        case .height(let points): height = points
        case .fitted:
            // Measured at the sheet's width: unpinned, the content is as narrow (and tall) as it can be.
            let width = content.widthAnchor.constraint(equalToConstant: full.width)
            width.isActive = true
            height = content.fittingSize.height
            width.isActive = false
        }
        return NSSize(width: full.width, height: min(max(height, 120), full.height))
    }
}
#endif

#if os(iOS)
extension PresentationDetent {
    /// `controller`: the sheet's, which a fitted detent measures.
    @MainActor func uiDetent(for controller: UIViewController) -> UISheetPresentationController.Detent {
        switch kind {
        case .fitted:
            if #available(iOS 16.0, *) {
                return .custom(identifier: .init(identifier)) { [weak controller] context in
                    guard let view = controller?.view, view.bounds.width > 0 else { return context.maximumDetentValue }
                    let size = view.systemLayoutSizeFitting(
                        CGSize(width: view.bounds.width, height: UIView.layoutFittingCompressedSize.height),
                        withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel)
                    // The detent's height doesn't include the bottom safe area.
                    return min(size.height - view.safeAreaInsets.bottom, context.maximumDetentValue)
                }
            }
            return .medium()
        case .medium: return .medium()
        case .large: return .large()
        case .fraction(let fraction):
            if #available(iOS 16.0, *) {
                return .custom(identifier: .init(identifier)) { $0.maximumDetentValue * fraction }
            }
            return fraction <= 0.6 ? .medium() : .large()
        case .height(let height):
            if #available(iOS 16.0, *) {
                return .custom(identifier: .init(identifier)) { _ in height }
            }
            return height <= 450 ? .medium() : .large()
        }
    }

    /// UIKit's own identifiers for its two, ours for the custom ones.
    var uiIdentifier: UISheetPresentationController.Detent.Identifier {
        switch kind {
        case .medium: return .medium
        case .large: return .large
        case .fraction, .height, .fitted: return .init(identifier)
        }
    }
}

extension PresentationOptions {
    @MainActor func apply(to controller: UIViewController, animated: Bool) {
        controller.isModalInPresentation = interactiveDismissDisabled ?? false
        if let background, let root = controller.view as? OmniRootView {
            root.fixedBackground = background.uiColor
        }
        guard let sheet = controller.sheetPresentationController else { return }
        let detents = orderedDetents
        let update = {
            sheet.detents = detents.map { $0.uiDetent(for: controller) }
            switch dragIndicator ?? .automatic {
            case .visible: sheet.prefersGrabberVisible = true
            case .hidden: sheet.prefersGrabberVisible = false
            case .automatic: sheet.prefersGrabberVisible = detents.count > 1
            }
            if #available(iOS 16.0, *) {
                // -1 is "nil was passed": the system's radius.
                sheet.preferredCornerRadius = cornerRadius.flatMap { $0 < 0 ? nil : CGFloat($0) }
            }
            if let selection, detents.contains(selection.wrappedValue) {
                sheet.selectedDetentIdentifier = selection.wrappedValue.uiIdentifier
            }
        }
        if animated { sheet.animateChanges(update) } else { update() }
    }

    /// The detent UIKit reports, mapped back.
    func detent(for identifier: UISheetPresentationController.Detent.Identifier?) -> PresentationDetent? {
        orderedDetents.first { $0.uiIdentifier == identifier }
    }
}
#endif
