#if os(Linux)
import Foundation
import Glibc

nonisolated(unsafe) let gtk_image_new_from_file: @convention(c) (UnsafePointer<CChar>) -> NativeView = fn(libgtk, "gtk_image_new_from_file")
nonisolated(unsafe) let gtk_image_new_from_icon_name: @convention(c) (UnsafePointer<CChar>, Int32) -> NativeView = fn(libgtk, "gtk_image_new_from_icon_name")

private let freedesktopIconNames = [
    "star": "starred",
    "star.fill": "starred",
    "gear": "preferences-system",
    "gearshape": "preferences-system",
    "magnifyingglass": "system-search",
    "person": "avatar-default",
    "person.crop.circle": "avatar-default",
    "envelope": "mail-unread",
    "square.and.pencil": "document-edit",
    "trash": "user-trash",
    "plus": "list-add",
    "chevron.left": "go-previous",
    "chevron.right": "go-next",
]

extension Image {
    @MainActor public func makeNative() -> NativeView {
        guard isSystem else { return gtk_image_new_from_file(name) }
        // GTK_ICON_SIZE_DIALOG (6) is the only stock size big enough to read.
        return gtk_image_new_from_icon_name(freedesktopIconNames[name] ?? name, 6)
    }

    @MainActor public func updateNative(_ view: NativeView) {
        // An Image is fixed once built; a different name is a different view.
    }
}
#endif
