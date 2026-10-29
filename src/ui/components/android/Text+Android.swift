#if os(Android)
import Foundation
import CAndroid

/// Texts drawn as .redacted blocks, to put their colour back when it lifts.
@MainActor private var redactedTexts: Set<UnsafeMutableRawPointer> = []

extension Text {
    public func makeNative() -> NativeView {
        let env = OmniAndroid.env
        let view = OmniAndroid.createView(env, "android/widget/TextView")
        // The scheme's text colour until its own or a .foregroundColor's, as
        // iOS's .label: the theme's is always dark. Set once, here, as an
        // ancestor's .foregroundColor is set before this view's updates.
        OmniAndroid.setTextColor(view, .primaryText)
        return view
    }

    public func updateNative(_ view: NativeView) {
        let env = OmniAndroid.env

        // 1. Set Text
        omni_jni_call_void_method_string(env, view, "setText", text)

        // 2. Set Typography. The resolved font: one set on an ancestor counts.
        let font = resolvedFont
        let size = Float(font.size)
        omni_jni_set_text_size(env, view, size)
        if let family = font.family {
            family.withCString { familyName in
                omni_jni_set_typeface(env, view, familyName, Int32(font.weight.rawValue),
                                      font.isItalic ? 1 : 0, isMonospaced ? 1 : 0)
            }
        } else {
            omni_jni_set_typeface(env, view, nil, Int32(font.weight.rawValue),
                                  font.isItalic ? 1 : 0, isMonospaced ? 1 : 0)
        }

        // Figures of one width, in whatever face: OpenType's tnum.
        omni_jni_call_void_method_string(env, view, "setFontFeatureSettings",
                                         font.hasMonospacedDigits ? "tnum" : "")

        // .textSelection: selectable with a long press, and the system's copy
        // handles, or not, both ways as on iOS. Selectable makes a TextView
        // clickable too, which would take the taps of a Button around it.
        let selectable = Tracker.current?.environment.isTextSelectable == true
        omni_jni_call_void_method_bool(env, view, "setTextIsSelectable", selectable ? 1 : 0)
        if selectable { omni_jni_call_void_method_bool(env, view, "setClickable", 0) }

        // 3. Set Color. .redacted: the text kept for its size, clear, on a
        // rounded block of its colour; and put back when it is lifted.
        let redaction = redactionFill
        if let redaction {
            redactedTexts.insert(view)
            omni_jni_set_text_color(env, view, 0, 0, 0, 0)
            omni_jni_set_glass(env, view, EffectBackgroundView.argb(redaction), 0, 4, 0)
        } else if redactedTexts.remove(view) != nil {
            omni_jni_set_background_color(env, view, 0, 0, 0, 0)
            let c = (textColor ?? .primaryText).rgbaComponents
            omni_jni_set_text_color(env, view, Int32(c.a * 255), Int32(c.r * 255), Int32(c.g * 255), Int32(c.b * 255))
        }
        if redaction == nil, let color = textColor {
            let c = color.rgbaComponents
            omni_jni_set_text_color(env, view,
                Int32(c.a * 255),
                Int32(c.r * 255),
                Int32(c.g * 255),
                Int32(c.b * 255)
            )
        }

        // 4. Set Alignment
        let gravity: Int32
        switch alignment {
        case .leading: gravity = 3
        case .center: gravity = 17
        case .trailing: gravity = 5
        }
        omni_jni_set_gravity(env, view, gravity)

        // 5. Spacing
        if lineSpacing != 0 || tracking != 0 {
            omni_jni_set_text_spacing(env, view, Float(lineSpacing),
                                      Float(tracking / max(font.size, 1)))
        }

        // 6. Lines and Truncation
        if let limit = lineLimit {
            omni_jni_call_void_method_int(env, view, "setMaxLines", Int32(limit))
        }
    }
}
#endif
