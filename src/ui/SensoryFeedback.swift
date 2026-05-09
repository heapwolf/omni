// src/ui/SensoryFeedback.swift
// SwiftUI's SensoryFeedback and .sensoryFeedback(_:trigger:): a haptic when a
// value changes. omni adds play(), for a feedback that follows an action
// rather than a value.
import Foundation
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#elseif os(Android)
import CAndroid
#endif

public struct SensoryFeedback: Equatable, Sendable {
    public enum Weight: Equatable, Sendable { case light, medium, heavy }
    public enum Flexibility: Equatable, Sendable { case rigid, solid, soft }

    enum Kind: Equatable, Sendable {
        case success, warning, error, selection
        case increase, decrease, start, stop, alignment, levelChange
        case impactWeight(Weight)
        case impactFlexibility(Flexibility)
    }

    let kind: Kind
    /// 0 to 1, for an impact.
    let intensity: Double

    init(_ kind: Kind, intensity: Double = 1) {
        self.kind = kind
        self.intensity = min(max(intensity, 0), 1)
    }

    /// A task completed: money sent, details copied.
    public static let success = SensoryFeedback(.success)
    /// A task produced a warning: a quote expired, a limit reached.
    public static let warning = SensoryFeedback(.warning)
    /// A task failed: a payment, a wrong PIN.
    public static let error = SensoryFeedback(.error)
    /// A selection changed: a tab, a segment, a picker.
    public static let selection = SensoryFeedback(.selection)
    public static let increase = SensoryFeedback(.increase)
    public static let decrease = SensoryFeedback(.decrease)
    public static let start = SensoryFeedback(.start)
    public static let stop = SensoryFeedback(.stop)
    public static let alignment = SensoryFeedback(.alignment)
    public static let levelChange = SensoryFeedback(.levelChange)
    /// A medium impact.
    public static let impact = SensoryFeedback(.impactWeight(.medium))

    public static func impact(weight: Weight = .medium, intensity: Double = 1) -> SensoryFeedback {
        SensoryFeedback(.impactWeight(weight), intensity: intensity)
    }

    public static func impact(flexibility: Flexibility, intensity: Double = 1) -> SensoryFeedback {
        SensoryFeedback(.impactFlexibility(flexibility), intensity: intensity)
    }
}

public extension SensoryFeedback {
    /// Plays it now. Silent where the device has no haptics, and on macOS
    /// without a Force Touch trackpad.
    @MainActor func play() {
        #if os(iOS)
        switch kind {
        case .success: UINotificationFeedbackGenerator().notificationOccurred(.success)
        case .warning: UINotificationFeedbackGenerator().notificationOccurred(.warning)
        case .error: UINotificationFeedbackGenerator().notificationOccurred(.error)
        case .selection, .alignment, .levelChange, .increase, .decrease:
            UISelectionFeedbackGenerator().selectionChanged()
        case .start, .stop:
            UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: intensity)
        case .impactWeight(let weight):
            let style: UIImpactFeedbackGenerator.FeedbackStyle =
                weight == .light ? .light : weight == .heavy ? .heavy : .medium
            UIImpactFeedbackGenerator(style: style).impactOccurred(intensity: intensity)
        case .impactFlexibility(let flexibility):
            let style: UIImpactFeedbackGenerator.FeedbackStyle =
                flexibility == .soft ? .soft : flexibility == .rigid ? .rigid : .medium
            UIImpactFeedbackGenerator(style: style).impactOccurred(intensity: intensity)
        }
        #elseif os(macOS)
        let pattern: NSHapticFeedbackManager.FeedbackPattern
        switch kind {
        case .alignment: pattern = .alignment
        case .levelChange, .increase, .decrease, .selection: pattern = .levelChange
        default: pattern = .generic
        }
        NSHapticFeedbackManager.defaultPerformer.perform(pattern, performanceTime: .now)
        #elseif os(Android)
        omni_jni_haptic(OmniAndroid.env, androidKind)
        #endif
    }

    /// OmniEventBridge.haptic's numbering.
    internal var androidKind: Int32 {
        switch kind {
        case .success: return 1
        case .warning, .error: return 2
        case .selection, .alignment, .levelChange, .increase, .decrease: return 3
        case .impactWeight(.heavy), .impactFlexibility(.rigid): return 4
        case .impactWeight(.light), .impactFlexibility(.soft), .start, .stop: return 5
        case .impactWeight, .impactFlexibility: return 6
        }
    }
}

public extension View {
    /// Plays `feedback` each time `trigger` changes.
    func sensoryFeedback<T: Equatable>(_ feedback: SensoryFeedback, trigger: T) -> some View {
        modifier(OnChangeModifier(value: trigger, change: { _, _ in feedback.play() }))
    }

    /// Plays `feedback` when `trigger` changes and `condition(old, new)` holds:
    /// `.sensoryFeedback(.impact, trigger: isPressed) { _, new in new }`.
    func sensoryFeedback<T: Equatable>(_ feedback: SensoryFeedback, trigger: T,
                                       condition: @escaping (T, T) -> Bool) -> some View {
        modifier(OnChangeModifier(value: trigger, change: { old, new in
            if condition(old, new) { feedback.play() }
        }))
    }

    /// Plays the feedback the closure chooses for the change, if any.
    func sensoryFeedback<T: Equatable>(trigger: T,
                                       _ feedback: @escaping (T, T) -> SensoryFeedback?) -> some View {
        modifier(OnChangeModifier(value: trigger, change: { old, new in feedback(old, new)?.play() }))
    }
}
