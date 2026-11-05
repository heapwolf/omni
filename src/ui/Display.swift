import Foundation
#if os(iOS)
import UIKit
#elseif os(Android)
import CAndroid
#endif

/// The screen the app is on.
@MainActor public enum Display {
    /// Its width in points, or nil where there's no one screen (a desktop's windows). On Android,
    /// the display size's: larger, the same pixels are fewer points. Read in a body, it's the
    /// width of that render; a display-size change renders everything again.
    public static var width: Double? {
        #if os(iOS)
        return Double(UIScreen.main.bounds.width)
        #elseif os(Android)
        // Kept: every text's font asks, every render. Forgotten when the density changes.
        if let known { return known }
        let width = omni_jni_screen_width(OmniAndroid.env)
        guard width > 0 else { return nil }
        known = Double(width)
        return known
        #else
        return nil
        #endif
    }

    /// How much bigger the user's text size makes `style` than its default size: as the fonts
    /// scale, on iOS (UIFontMetrics). 1 elsewhere: Android's text is set in points, not scaled.
    public static func textScale(for style: Font.TextStyle) -> Double {
        #if os(iOS)
        return Double(UIFontMetrics(forTextStyle: style.uiTextStyle).scaledValue(for: 100)) / 100
        #else
        return 1
        #endif
    }

    #if os(Android)
    private static var known: Double?

    /// The display size changed (Appearance.swift's omni_swift_density_changed).
    static func forget() { known = nil }
    #endif
}
