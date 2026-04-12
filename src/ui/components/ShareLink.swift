// src/ui/components/ShareLink.swift
import Foundation
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#elseif os(Android)
import CAndroid
#endif

/// SwiftUI's ShareLink, for text and URLs: a button that opens the system
/// share sheet.
public struct ShareLink<Label: View>: View {
    let items: [Any]
    let label: Label

    public init(item: String, @ViewBuilder label: () -> Label) {
        self.items = [item]
        self.label = label()
    }

    public init(item: URL, @ViewBuilder label: () -> Label) {
        self.items = [item]
        self.label = label()
    }

    public var body: some View {
        let items = self.items
        return Button(action: { ShareSheet.present(items) }) { label }
    }
}

public extension ShareLink where Label == Text {
    init(_ title: String, item: String) {
        self.init(item: item) { Text(title) }
    }
}

enum ShareSheet {
    /// Over whatever is on screen, a sheet included.
    @MainActor static func present(_ items: [Any]) {
        #if os(iOS)
        let window = UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.windows.first { $0.isKeyWindow } }.first
        var top = window?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        guard let top else { return }
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        // An iPad shows it as a popover, which needs an anchor.
        controller.popoverPresentationController?.sourceView = top.view
        controller.popoverPresentationController?.sourceRect = CGRect(x: top.view.bounds.midX, y: top.view.bounds.midY,
                                                                      width: 0, height: 0)
        top.present(controller, animated: true)
        #elseif os(macOS)
        guard let view = NSApp.keyWindow?.contentView else { return }
        NSSharingServicePicker(items: items).show(relativeTo: .zero, of: view, preferredEdge: .minY)
        #elseif os(Android)
        // Text and links, as ShareLink takes them: each as its text, one a line.
        let text = items.map { ($0 as? URL)?.absoluteString ?? "\($0)" }.joined(separator: "\n")
        omni_jni_send_text(OmniAndroid.env, "share", text)
        #else
        Omni.log("ShareLink is not supported on this platform yet")
        #endif
    }
}
