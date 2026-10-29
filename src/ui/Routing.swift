// src/lib/Routing.swift
import Foundation

#if os(macOS) || os(iOS)
    import ObjectiveC
#elseif os(Android)
    import CAndroid
#endif

#if os(macOS)
    import AppKit
#elseif os(iOS)
    import UIKit
#endif

#if os(Linux)
    import Glibc
    let gtk_widget_get_toplevel: @convention(c) (NativeView) -> NativeView = fn(libgtk, "gtk_widget_get_toplevel")
    let gtk_window_set_transient_for: @convention(c) (NativeView, NativeView) -> Void = fn(libgtk, "gtk_window_set_transient_for")
    let gtk_window_set_modal: @convention(c) (NativeView, Int32) -> Void = fn(libgtk, "gtk_window_set_modal")
#endif

// MARK: - State Proxy

#if os(iOS)
extension SheetState {
    /// A sheet dragged down shrinks, and content pinned to both its edges was
    /// squeezed with it: a PIN sheet's title, dots and keys folded onto each
    /// other. Held at its least height (what it measures compressed, so a
    /// Spacer or a list still gives), it slides out of the bottom instead,
    /// laid out as it was, as in SwiftUI. Measured again after each render.
    /// The content in the sheet's view: inside the safe area, and above the
    /// keyboard, as SwiftUI lays out a sheet; the home indicator must not sit
    /// on a button. The bottom gives way to the content's least height.
    /// Again when a render replaces the content's view (a sheet that
    /// switches from one screen to another): left out, the sheet was blank.
    @MainActor func host(_ content: UIView, in host: UIView) {
        if let hosted, hosted !== content { hosted.removeFromSuperview() }
        hosted = content
        minimumHeight = nil
        host.addSubview(content)
        let bottom = content.bottomAnchor.constraint(equalTo: host.keyboardLayoutGuide.topAnchor)
        bottom.priority = .init(rawValue: 999)
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: host.safeAreaLayoutGuide.topAnchor),
            bottom,
            content.leadingAnchor.constraint(equalTo: host.safeAreaLayoutGuide.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: host.safeAreaLayoutGuide.trailingAnchor)
        ])
        holdMinimumHeight(of: content, in: host)
        // The sheet's view takes the content's colour, as the window's does,
        // so the strip under a list that runs past the safe area matches it.
        (host as? OmniRootView)?.scheduleBleedRefresh()
    }

    @MainActor func holdMinimumHeight(of content: UIView, in host: UIView) {
        let width = host.bounds.width > 0 ? host.bounds.width : host.window?.bounds.width ?? UIScreen.main.bounds.width
        let insets = host.safeAreaInsets
        let fitting = content.systemLayoutSizeFitting(
            CGSize(width: width - insets.left - insets.right, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel)
        if let minimumHeight {
            minimumHeight.constant = fitting.height
        } else {
            let constraint = content.heightAnchor.constraint(greaterThanOrEqualToConstant: fitting.height)
            constraint.isActive = true
            minimumHeight = constraint
        }
    }
}
#endif

// The secondary Node tree and native window references.
public class SheetState {
    public var isPresented = false
    public var sheetNode: Node?

    #if os(macOS)
        /// The sheet, drawn inside the parent window (SheetOverlay+Mac.swift).
        var sheetOverlay: SheetOverlay?
    #elseif os(iOS)
        public var sheetController: UIViewController?
        public var delegateProxy: Any? // Holds the UIAdaptivePresentationControllerDelegate
        /// The content's least height; see SheetState.holdMinimumHeight.
        var minimumHeight: NSLayoutConstraint?
        /// The content's view as the sheet holds it; see SheetState.host.
        var hosted: UIView?
        /// Main-loop turns spent waiting for the view to reach a window.
        var presentAttempts = 0
    #elseif os(Linux)
        public var sheetWindow: NativeView?
    #elseif os(Android)
        public var sheetDialog: NativeView?
    #endif

    deinit {
        // Unmount on the main actor.
        if let node = sheetNode {
            Task { @MainActor in
                node.unmount()
            }
        }
    }
}

#if os(macOS) || os(iOS)
    // Only the address is used as an associated-object key. &key needs a mutable
    // lvalue.
    nonisolated(unsafe) private var sheetKey: UInt8 = 0
#endif

#if os(iOS)
    // Catches a swipe-down dismissal on iOS, and a drag to another detent.
    class SheetDelegateProxy: NSObject, UISheetPresentationControllerDelegate {
        var onDismiss: () -> Void
        var onDetentChange: ((UISheetPresentationController.Detent.Identifier?) -> Void)?
        init(onDismiss: @escaping () -> Void) { self.onDismiss = onDismiss }
        func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
            onDismiss()
        }
        func sheetPresentationControllerDidChangeSelectedDetentIdentifier(
            _ sheetPresentationController: UISheetPresentationController
        ) {
            onDetentChange?(sheetPresentationController.selectedDetentIdentifier)
        }
    }
#endif

// MARK: - The Modifier View

#if os(iOS)
/// Where a sheet or an alert is presented from, and when.
@MainActor enum Presenting {
    /// The nearest view controller in a window, not already presenting one.
    /// One on its way out doesn't count: UIKit won't present from it.
    @MainActor static func presenter(of view: UIView) -> UIViewController? {
        guard view.window != nil else { return nil }
        var responder: UIResponder? = view
        while let r = responder {
            if let viewController = r as? UIViewController {
                var top = viewController
                while let presented = top.presentedViewController, !presented.isBeingDismissed { top = presented }
                return top
            }
            responder = r.next
        }
        return nil
    }

    /// Presents `vc` once nothing above the presenter is still on its way
    /// out. A sheet opened as another closed (Card Info's details after its
    /// PIN) was presented from the closing one, or over it: UIKit refused,
    /// silently, and the sheet counted as shown never came.
    @MainActor static func present(_ vc: UIViewController, from view: UIView, _ fallback: UIViewController,
                                   isWanted: @escaping @MainActor () -> Bool, attempts: Int = 0) {
        // Closed again in the meantime: nothing to show.
        guard isWanted(), vc.presentingViewController == nil else { return }
        let presenter = Presenting.presenter(of: view) ?? fallback
        if let leaving = presenter.presentedViewController, leaving.isBeingDismissed, attempts < 40 {
            let again = { present(vc, from: view, fallback, isWanted: isWanted, attempts: attempts + 1) }
            if let coordinator = leaving.transitionCoordinator {
                coordinator.animate(alongsideTransition: nil) { _ in DispatchQueue.main.async { again() } }
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { again() }
            }
            return
        }
        presenter.present(vc, animated: true)
    }
}
#endif

public struct SheetModifierView<SheetContent: View>: NativeComponent {
    public var content: any View
    public var isPresented: Binding<Bool>
    public var sheetContent: () -> SheetContent

    public var children: [any View] { [content] }

    public init(content: any View, isPresented: Binding<Bool>, @ViewBuilder sheetContent: @escaping () -> SheetContent) {
        self.content = content
        self.isPresented = isPresented
        self.sheetContent = sheetContent
    }

    @MainActor public func makeNative() -> NativeView {
        #if os(Linux)
            let v = gtk_box_new(0, 0)
            let state = SheetState()
            let ptr = Unmanaged.passRetained(state).toOpaque()
            g_object_set_data_full(v, "sheet_state", ptr) { pPtr in
                if let p = pPtr { Unmanaged<SheetState>.fromOpaque(p).release() }
            }
            return v
        #elseif os(macOS)
            let v = NSView()
            v.translatesAutoresizingMaskIntoConstraints = false
            objc_setAssociatedObject(v, &sheetKey, SheetState(), .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            return v
        #elseif os(iOS)
            let v = UIView()
            v.translatesAutoresizingMaskIntoConstraints = false
            objc_setAssociatedObject(v, &sheetKey, SheetState(), .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            return v
        #elseif os(Android)
            let v = OmniAndroid.makeContainer()
            AndroidModifierState.set(SheetState(), for: v)
            return v
        #else
        #error("no implementation for this platform")
        #endif
    }

    @MainActor public func updateNative(_ view: NativeView) {
        #if os(Linux)
            let ptr = g_object_get_data(view, "sheet_state")
            let state = Unmanaged<SheetState>.fromOpaque(ptr!).takeUnretainedValue()
        #elseif os(macOS) || os(iOS)
            guard let state = objc_getAssociatedObject(view, &sheetKey) as? SheetState else { return }
        #elseif os(Android)
            let state = AndroidModifierState.ensure(for: view) { SheetState() }
        #else
        #error("no implementation for this platform")
        #endif

        let shouldShow = isPresented.wrappedValue

        if shouldShow && !state.isPresented {
            #if os(iOS)
            // Presented while the view is not yet in a window (a sheet that
            // starts open, say) there is nothing to present from. SwiftUI shows
            // it once the view is on screen; so does this, a turn later.
            guard let presenter = Presenting.presenter(of: view) else {
                if state.presentAttempts < 20 {
                    state.presentAttempts += 1
                    DispatchQueue.main.async { [weak view] in
                        if let view { self.updateNative(view) }
                    }
                }
                return
            }
            state.presentAttempts = 0
            #endif

            // Present Sheet
            state.isPresented = true

            // A new node tree, inheriting the environment.
            let node = Node(sheetContent())
            node.isDetachedRoot = true
            if let parentNode = Tracker.current {
                node.environment = parentNode.environment
            }
            node.environment.isPresented = true
            node.onRootNativeChange = { [weak state] native, removal, insertion in
                guard let state, let native else { return }
                #if os(iOS)
                if let host = state.sheetController?.view, native !== state.hosted {
                    let old = state.hosted
                    let oldFrame = old?.frame ?? .zero
                    state.host(native, in: host)
                    // In an animated change, the screens move as they would
                    // inside any other view: the old one leaves with the
                    // transition it last rendered, the new one arrives with its own.
                    if let animation = Transaction.currentAnimation {
                        TransitionAnimator.run(animation, in: host, new: native, insertion: insertion,
                                               old: old, oldFrame: oldFrame, removal: removal)
                    }
                }
                #elseif os(macOS)
                state.sheetOverlay?.setContent(native)
                #elseif os(Android)
                if let dialog = state.sheetDialog { omni_jni_set_sheet_content(OmniAndroid.getEnv(), dialog, native) }
                #endif
            }
            state.sheetNode = node
            // Rendered with no animation current: presented from inside an
            // animated change (a tap whose press animates, say), its views
            // were laid out inside that animation, and grew out of a corner
            // rather than coming up with the sheet.
            let animation = Transaction.currentAnimation
            Transaction.currentAnimation = nil
            #if os(iOS)
            UIView.performWithoutAnimation { Engine.render(node) }
            #else
            Engine.render(node)
            #endif
            Transaction.currentAnimation = animation

            guard let sheetNative = node.native else { return }

            #if os(macOS)
                let options = PresentationOptions.collect(from: node)
                let height = options.sheetSize(content: sheetNative, in: view.window).height
                let overlay = SheetOverlay(content: sheetNative, height: height)
                overlay.onDismiss = { self.isPresented.wrappedValue = false }
                overlay.isDismissable = { [weak node] in
                    node.map { !(PresentationOptions.collect(from: $0).interactiveDismissDisabled ?? false) } ?? true
                }
                state.sheetOverlay = overlay
                // Over everything in the window, earlier sheets included.
                if let host = view.window?.contentView { overlay.present(over: host) }

            #elseif os(iOS)
                let vc = UIViewController()
                // The window's root view, which takes on the content's own
                // background, so the insets below match it rather than white.
                vc.view = OmniRootView()
                vc.view.backgroundColor = .systemBackground
                OmniSceneDelegate.current?.installKeyboardDismiss(on: vc.view)
                state.host(sheetNative, in: vc.view)
                state.sheetController = vc

                let proxy = SheetDelegateProxy { self.isPresented.wrappedValue = false }
                vc.presentationController?.delegate = proxy
                state.delegateProxy = proxy // Retain it

                // Detents and the rest, from .presentationDetents & co. on the content.
                let options = PresentationOptions.collect(from: node)
                options.apply(to: vc, animated: false)
                proxy.onDetentChange = { [weak node] identifier in
                    guard let node else { return }
                    let current = PresentationOptions.collect(from: node)
                    if let detent = current.detent(for: identifier) {
                        current.selection?.wrappedValue = detent
                    }
                }

                // Laid out at the screen's size before it moves, and presented
                // a turn later, outside any animation block this render is
                // in: the system's slide up is then the only animation.
                vc.view.frame = presenter.view.window?.bounds ?? presenter.view.bounds
                UIView.performWithoutAnimation { vc.view.layoutIfNeeded() }
                DispatchQueue.main.async { [weak view] in
                    guard let view else { return }
                    Presenting.present(vc, from: view, presenter, isWanted: { state.sheetController === vc })
                }

            #elseif os(Linux)
                let dialog = gtk_window_new(0) // GTK_WINDOW_TOPLEVEL
                gtk_window_set_default_size(dialog, 400, 400)
                gtk_container_add(dialog, sheetNative)
                state.sheetWindow = dialog

                let parentWin = gtk_widget_get_toplevel(view)
                gtk_window_set_transient_for(dialog, parentWin)
                gtk_window_set_modal(dialog, 1)

                bindLinuxEvent(dialog, "destroy") {
                    // Dropped before the state flips: GTK is already destroying this window.
                    state.sheetWindow = nil
                    self.isPresented.wrappedValue = false
                }

                gtk_widget_show_all(dialog)
            #elseif os(Android)
                // A bottom sheet at one height: the selected detent, else the
                // smallest, which is where iOS opens.
                let options = PresentationOptions.collect(from: node)
                let detent = options.selection?.wrappedValue ?? options.orderedDetents.first ?? .large
                var heightDp: Float = 0
                if case .height(let height) = detent.kind { heightDp = Float(height) }
                let showsIndicator = options.dragIndicator == .visible
                    || (options.dragIndicator != .hidden && options.orderedDetents.count > 1)

                let dismissed = EventHandlerVoid { self.isPresented.wrappedValue = false }
                state.sheetDialog = omni_jni_present_sheet(
                    OmniAndroid.getEnv(), sheetNative,
                    Unmanaged.passRetained(dismissed).toOpaque(),
                    Float(detent.approximateFraction), heightDp,
                    // Unless one is given, the app's sheets' (the PIN sheet's 24).
                    Float(options.cornerRadius ?? 24),
                    showsIndicator ? 1 : 0,
                    options.interactiveDismissDisabled == true ? 0 : 1,
                    // iOS's sheet colours, as the scheme has them, unless one is given.
                    EffectBackgroundView.argb(options.background
                        ?? Color(light: .white, dark: .rgba(r: 0.11, g: 0.11, b: 0.12))))
            #endif

        } else if shouldShow && state.isPresented {
            // State changed while the sheet is open.
            if let node = state.sheetNode {
                node.view = sheetContent()
                Engine.render(node)
                #if os(macOS)
                // A render that replaced the content's view: the sheet shows the new one.
                if let native = node.native { state.sheetOverlay?.setContent(native) }
                #endif
                #if os(Android)
                if let native = node.native, let dialog = state.sheetDialog {
                    omni_jni_set_sheet_content(OmniAndroid.getEnv(), dialog, native)
                }
                #endif
                #if os(iOS)
                if let native = node.native, let host = state.sheetController?.view {
                    if native === state.hosted {
                        state.holdMinimumHeight(of: native, in: host)
                        (host as? OmniRootView)?.scheduleBleedRefresh()
                    } else {
                        state.host(native, in: host)
                    }
                }
                // Detents may have changed, or the selection been set from code.
                if let controller = state.sheetController {
                    PresentationOptions.collect(from: node).apply(to: controller, animated: true)
                }
                #endif
            }

        } else if !shouldShow && state.isPresented {
            // Dismiss the Sheet
            state.isPresented = false

            #if os(macOS)
                state.sheetOverlay?.dismiss()
                state.sheetOverlay = nil
            #elseif os(iOS)
                state.sheetController?.dismiss(animated: true)
                state.sheetController = nil
                state.delegateProxy = nil
            #elseif os(Linux)
                if let win = state.sheetWindow {
                    gtk_widget_destroy(win)
                }
                state.sheetWindow = nil
            #elseif os(Android)
                if let dialog = state.sheetDialog {
                    omni_jni_dismiss_dialog(OmniAndroid.getEnv(), dialog)
                }
                state.sheetDialog = nil
            #endif

            state.sheetNode?.unmount()
            state.sheetNode = nil
        }
    }

    /// A sheet goes with the view that presented it, as in SwiftUI. Without
    /// this, a screen change under an open sheet leaves the sheet up.
    @MainActor public func unmountNative(_ view: NativeView) {
        #if os(iOS)
        guard let state = objc_getAssociatedObject(view, &sheetKey) as? SheetState,
              state.isPresented else { return }
        state.isPresented = false
        state.sheetController?.dismiss(animated: true)
        state.sheetController = nil
        state.delegateProxy = nil
        state.sheetNode?.unmount()
        state.sheetNode = nil
        #elseif os(macOS)
        guard let state = objc_getAssociatedObject(view, &sheetKey) as? SheetState,
              state.isPresented else { return }
        state.isPresented = false
        state.sheetOverlay?.dismiss()
        state.sheetOverlay = nil
        state.sheetNode?.unmount()
        state.sheetNode = nil
        #elseif os(Android)
        guard let state = AndroidModifierState.get(SheetState.self, for: view),
              state.isPresented else { return }
        state.isPresented = false
        if let dialog = state.sheetDialog { omni_jni_dismiss_dialog(OmniAndroid.getEnv(), dialog) }
        state.sheetDialog = nil
        state.sheetNode?.unmount()
        state.sheetNode = nil
        #endif
    }


    @MainActor public func insertChild(_ child: NativeView, into parent: NativeView) {
        #if os(Linux)
            packFill(child, into: parent)
        #elseif os(macOS) || os(iOS)
            parent.addSubview(child)
            adoptSizing(of: child, into: parent)
            NSLayoutConstraint.activate([
                child.topAnchor.constraint(equalTo: parent.topAnchor),
                child.bottomAnchor.constraint(equalTo: parent.bottomAnchor),
                child.leadingAnchor.constraint(equalTo: parent.leadingAnchor),
                child.trailingAnchor.constraint(equalTo: parent.trailingAnchor)
            ])
        #elseif os(Android)
            OmniAndroid.addChild(child, to: parent)
        #else
        #error("no implementation for this platform")
        #endif
    }
}

// MARK: - Standard SwiftUI Modifier

public struct SheetModifier<SheetContent: View>: ViewModifier {
    public var isPresented: Binding<Bool>
    public var sheetContent: () -> SheetContent

    public func body(content: Content) -> some View {
        SheetModifierView(content: content, isPresented: isPresented, sheetContent: sheetContent)
    }
}

public extension View {
    /// Presents a modal sheet while the binding is true.
    func sheet<SheetContent: View>(
        isPresented: Binding<Bool>,
        @ViewBuilder content: @escaping () -> SheetContent
    ) -> ModifiedContent<Self, SheetModifier<SheetContent>> {
        self.modifier(SheetModifier(isPresented: isPresented, sheetContent: content))
    }
}

// MARK: - 4. Alert Modifier

#if os(Linux)
    let gtk_dialog_new: @convention(c) () -> NativeView = fn(libgtk, "gtk_dialog_new")
    let gtk_dialog_get_content_area: @convention(c) (NativeView) -> NativeView = fn(libgtk, "gtk_dialog_get_content_area")
    let gtk_dialog_add_button: @convention(c) (NativeView, UnsafePointer<CChar>, Int32) -> NativeView = fn(libgtk, "gtk_dialog_add_button")
    let gtk_widget_set_margin_top: @convention(c) (NativeView, Int32) -> Void = fn(libgtk, "gtk_widget_set_margin_top")
    let gtk_widget_set_margin_bottom: @convention(c) (NativeView, Int32) -> Void = fn(libgtk, "gtk_widget_set_margin_bottom")
#endif

public class AlertState {
    public var isPresented = false

    #if os(macOS)
        public var alert: NSAlert?
    #elseif os(iOS)
        public var alertController: UIAlertController?
    #elseif os(Linux)
        public var dialog: NativeView?
    #elseif os(Android)
        public var dialog: NativeView?
    #endif
}

/// One of an alert's buttons: SwiftUI builds them from the Buttons in
/// `actions`.
public struct AlertAction {
    public let title: String
    public let role: ButtonRole?
    public let action: () -> Void

    /// The Buttons in an alert's `actions`, in order. A label that is not a
    /// plain Text is skipped: an alert button is text only.
    @MainActor static func from(_ view: any View) -> [AlertAction] {
        // Before unpacking: Omni.unpackViews would flatten a Button into its
        // styled label and lose the action.
        if let source = view as? any AlertActionSource { return source.alertAction.map { [$0] } ?? [] }
        if let structural = view as? any OmniStructuralView { return structural.unpacked.flatMap { from($0) } }
        return []
    }

    /// What the platform shows: the declared order, a cancel button last,
    /// and an OK when none was given, as SwiftUI does.
    static func shown(_ actions: [AlertAction]) -> [AlertAction] {
        guard !actions.isEmpty else { return [AlertAction(title: "OK", role: .cancel, action: {})] }
        return actions.filter { $0.role != .cancel } + actions.filter { $0.role == .cancel }
    }
}

@MainActor protocol AlertActionSource { var alertAction: AlertAction? { get } }

extension Button: AlertActionSource {
    var alertAction: AlertAction? {
        guard let text = label as? Text else { return nil }
        return AlertAction(title: text.text, role: role, action: action)
    }
}

public struct AlertModifierView: NativeComponent {
    public var content: any View
    public var isPresented: Binding<Bool>
    public var title: String
    public var actions: [AlertAction]
    public var message: String?

    public var children: [any View] { [content] }

    public init(content: any View, isPresented: Binding<Bool>, title: String,
                actions: [AlertAction] = [], message: String? = nil) {
        self.content = content
        self.isPresented = isPresented
        self.title = title
        self.actions = actions
        self.message = message
    }

    /// A button was chosen: the alert is gone before its action runs, so the
    /// action may present another.
    @MainActor func respond(_ index: Int) {
        let shown = AlertAction.shown(actions)
        isPresented.wrappedValue = false
        if shown.indices.contains(index) { shown[index].action() }
    }

    @MainActor public func makeNative() -> NativeView {
        #if os(Linux)
            let v = gtk_box_new(0, 0)
            let state = AlertState()
            let ptr = Unmanaged.passRetained(state).toOpaque()
            g_object_set_data_full(v, "alert_state", ptr) { pPtr in
                if let p = pPtr { Unmanaged<AlertState>.fromOpaque(p).release() }
            }
            return v
        #elseif os(macOS) || os(iOS)
            let v = NSViewOrUIView()
            // Left at the default, UIKit generates constraints pinning this view to its
            // current (zero) frame, which conflicts with whatever sizes it.
            v.translatesAutoresizingMaskIntoConstraints = false
            objc_setAssociatedObject(v, &sheetKey, AlertState(), .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            return v
        #elseif os(Android)
            let v = OmniAndroid.makeContainer()
            AndroidModifierState.set(AlertState(), for: v)
            return v
        #else
        #error("no implementation for this platform")
        #endif
    }

    #if os(macOS)
        typealias NSViewOrUIView = NSView
    #elseif os(iOS)
        typealias NSViewOrUIView = UIView
    #endif

    @MainActor public func updateNative(_ view: NativeView) {
        #if os(Linux)
            let ptr = g_object_get_data(view, "alert_state")
            let state = Unmanaged<AlertState>.fromOpaque(ptr!).takeUnretainedValue()
        #elseif os(macOS) || os(iOS)
            guard let state = objc_getAssociatedObject(view, &sheetKey) as? AlertState else { return }
        #elseif os(Android)
            let state = AndroidModifierState.ensure(for: view) { AlertState() }
        #else
        #error("no implementation for this platform")
        #endif

        let shouldShow = isPresented.wrappedValue

        #if os(macOS) || os(iOS)
        // Asked for before the view is on screen, as on a first render: try
        // again next turn. Presenting then would find no window (a modal run
        // loop on macOS, which blocks) or no view controller (nothing on iOS).
        if shouldShow && !state.isPresented && view.window == nil {
            DispatchQueue.main.async { [weak view] in
                guard let view, view.window != nil else { return }
                self.updateNative(view)
            }
            return
        }
        #endif

        if shouldShow && !state.isPresented {
            state.isPresented = true

            #if os(macOS)
                let alert = NSAlert()
                alert.messageText = title
                if let message { alert.informativeText = message }
                for action in AlertAction.shown(actions) {
                    let button = alert.addButton(withTitle: action.title)
                    if action.role == .cancel { button.keyEquivalent = "\u{1b}" }
                    if action.role == .destructive { button.hasDestructiveAction = true }
                }
                state.alert = alert

                let first = NSApplication.ModalResponse.alertFirstButtonReturn.rawValue
                if let win = view.window {
                    alert.beginSheetModal(for: win) { response in
                        self.respond(response.rawValue - first)
                    }
                }

            #elseif os(iOS)
                let ac = UIAlertController(title: title, message: message, preferredStyle: .alert)
                for (index, action) in AlertAction.shown(actions).enumerated() {
                    let style: UIAlertAction.Style = action.role == .cancel ? .cancel
                        : action.role == .destructive ? .destructive : .default
                    ac.addAction(UIAlertAction(title: action.title, style: style) { _ in self.respond(index) })
                }
                state.alertController = ac

                // Over whatever is up, once what is closing has: a failure
                // shown as its PIN sheet went down never came.
                if let presenter = Presenting.presenter(of: view) {
                    Presenting.present(ac, from: view, presenter, isWanted: { [weak state] in state?.alertController === ac })
                }

            #elseif os(Linux)
                let dialog = gtk_dialog_new()
                let contentArea = gtk_dialog_get_content_area(dialog)

                let label = gtk_label_new(title)
                gtk_widget_set_margin_top(label, 20)
                gtk_widget_set_margin_bottom(label, 20)
                gtk_box_pack_start(contentArea, label, 1, 1, 0)

                gtk_dialog_add_button(dialog, "OK", 1) // 1 = GTK_RESPONSE_ACCEPT

                let parentWin = gtk_widget_get_toplevel(view)
                gtk_window_set_transient_for(dialog, parentWin)
                gtk_window_set_modal(dialog, 1)

                bindLinuxEvent(dialog, "response") {
                    self.isPresented.wrappedValue = false
                }

                gtk_widget_show_all(dialog)
                state.dialog = dialog
            #elseif os(Android)
                // Every button, in the order shown, and the one chosen back: -1
                // when the dialog went without a choice.
                let shown = AlertAction.shown(actions)
                let titles = shown.map(\.title).joined(separator: "\u{1F}")
                let roles = shown.map { $0.role == .destructive ? "1" : $0.role == .cancel ? "2" : "0" }.joined()
                let chosen = EventHandlerInt { index in
                    if index >= 0 { self.respond(index) } else { self.isPresented.wrappedValue = false }
                }
                let message: String? = self.message
                state.dialog = omni_jni_present_alert(
                    OmniAndroid.getEnv(), view, title, message, titles, roles,
                    Unmanaged.passRetained(chosen).toOpaque())
            #endif

        } else if !shouldShow && state.isPresented {
            state.isPresented = false

            #if os(macOS)
                if let alert = state.alert, let win = alert.window.sheetParent {
                    win.endSheet(alert.window)
                }
                state.alert = nil
            #elseif os(iOS)
                state.alertController?.dismiss(animated: true)
                state.alertController = nil
            #elseif os(Linux)
                if let dialog = state.dialog {
                    gtk_widget_destroy(dialog)
                }
                state.dialog = nil
            #elseif os(Android)
                if let dialog = state.dialog {
                    omni_jni_dismiss_dialog(OmniAndroid.getEnv(), dialog)
                }
                state.dialog = nil
            #endif
        }
    }

    @MainActor public func insertChild(_ child: NativeView, into parent: NativeView) {
        #if os(Linux)
            packFill(child, into: parent)
        #elseif os(macOS) || os(iOS)
            parent.addSubview(child)
            adoptSizing(of: child, into: parent)
            NSLayoutConstraint.activate([
                child.topAnchor.constraint(equalTo: parent.topAnchor),
                child.bottomAnchor.constraint(equalTo: parent.bottomAnchor),
                child.leadingAnchor.constraint(equalTo: parent.leadingAnchor),
                child.trailingAnchor.constraint(equalTo: parent.trailingAnchor)
            ])
        #elseif os(Android)
            OmniAndroid.addChild(child, to: parent)
        #else
        #error("no implementation for this platform")
        #endif
    }
}

public struct AlertModifier: ViewModifier {
    public var title: String
    public var isPresented: Binding<Bool>
    public var actions: [AlertAction] = []
    public var message: String?

    public func body(content: Content) -> some View {
        AlertModifierView(content: content, isPresented: isPresented, title: title,
                          actions: actions, message: message)
    }
}

public extension View {
    /// An alert with an OK button.
    func alert(_ title: String, isPresented: Binding<Bool>) -> ModifiedContent<Self, AlertModifier> {
        self.modifier(AlertModifier(title: title, isPresented: isPresented))
    }

    /// SwiftUI's: `actions` are Buttons, a `.cancel` role placed as the
    /// platform places it and `.destructive` drawn as such.
    func alert<A: View>(_ title: String, isPresented: Binding<Bool>,
                        @ViewBuilder actions: () -> A) -> ModifiedContent<Self, AlertModifier> {
        self.modifier(AlertModifier(title: title, isPresented: isPresented,
                                    actions: AlertAction.from(actions())))
    }

    /// SwiftUI's, with a message under the title.
    func alert<A: View, M: View>(_ title: String, isPresented: Binding<Bool>,
                                 @ViewBuilder actions: () -> A,
                                 @ViewBuilder message: () -> M) -> ModifiedContent<Self, AlertModifier> {
        self.modifier(AlertModifier(title: title, isPresented: isPresented,
                                    actions: AlertAction.from(actions()),
                                    message: Omni.unpackViews(message()).compactMap { ($0 as? Text)?.text }.first))
    }
}
