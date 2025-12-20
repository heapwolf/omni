// src/ui/components/DatePicker.swift
import Foundation
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// SwiftUI's DatePickerComponents.
public struct DatePickerComponents: OptionSet, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static let date = DatePickerComponents(rawValue: 1)
    public static let hourAndMinute = DatePickerComponents(rawValue: 2)
}

/// SwiftUI's DatePicker: its title leading, the platform's compact picker
/// trailing. A range limits what can be picked.
public struct DatePicker: View {
    let title: String
    let selection: Binding<Date>
    let minimum: Date?
    let maximum: Date?
    let components: DatePickerComponents

    public init(_ title: String, selection: Binding<Date>,
                displayedComponents: DatePickerComponents = [.date, .hourAndMinute]) {
        self.init(title, selection: selection, minimum: nil, maximum: nil, components: displayedComponents)
    }

    public init(_ title: String, selection: Binding<Date>, in range: ClosedRange<Date>,
                displayedComponents: DatePickerComponents = [.date, .hourAndMinute]) {
        self.init(title, selection: selection, minimum: range.lowerBound, maximum: range.upperBound,
                  components: displayedComponents)
    }

    public init(_ title: String, selection: Binding<Date>, in range: PartialRangeThrough<Date>,
                displayedComponents: DatePickerComponents = [.date, .hourAndMinute]) {
        self.init(title, selection: selection, minimum: nil, maximum: range.upperBound,
                  components: displayedComponents)
    }

    public init(_ title: String, selection: Binding<Date>, in range: PartialRangeFrom<Date>,
                displayedComponents: DatePickerComponents = [.date, .hourAndMinute]) {
        self.init(title, selection: selection, minimum: range.lowerBound, maximum: nil,
                  components: displayedComponents)
    }

    init(_ title: String, selection: Binding<Date>, minimum: Date?, maximum: Date?,
         components: DatePickerComponents) {
        self.title = title
        self.selection = selection
        self.minimum = minimum
        self.maximum = maximum
        self.components = components
    }

    public var body: some View {
        HStack {
            if !title.isEmpty { Text(title) }
            Spacer()
            #if os(iOS) || os(macOS)
            NativeDatePicker(selection: selection, minimum: minimum, maximum: maximum, components: components)
            #else
            // No picker on Android, GTK or Windows yet: the date, read only.
            // omni-work/TODO.md.
            Text(Self.format(selection.wrappedValue))
            #endif
        }
    }

    static func format(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }
}

#if os(iOS) || os(macOS)
public struct NativeDatePicker: NativeComponent {
    let selection: Binding<Date>
    let minimum: Date?
    let maximum: Date?
    let components: DatePickerComponents

    @MainActor public func makeNative() -> NativeView {
        #if os(iOS)
        let picker = UIDatePicker()
        picker.preferredDatePickerStyle = .compact
        picker.translatesAutoresizingMaskIntoConstraints = false
        return picker
        #elseif os(macOS)
        let picker = NSDatePicker()
        picker.datePickerStyle = .textFieldAndStepper
        picker.translatesAutoresizingMaskIntoConstraints = false
        return picker
        #endif
    }

    @MainActor public func updateNative(_ view: NativeView) {
        let binding = selection
        #if os(iOS)
        guard let picker = view as? UIDatePicker else { return }
        picker.datePickerMode = components == .date ? .date
            : components == .hourAndMinute ? .time : .dateAndTime
        picker.minimumDate = minimum
        picker.maximumDate = maximum
        if picker.date != binding.wrappedValue { picker.date = binding.wrappedValue }
        bindAppleEvent(view, "valueChanged") { [weak picker] in
            if let picker { binding.wrappedValue = picker.date }
        }
        #elseif os(macOS)
        guard let picker = view as? NSDatePicker else { return }
        var elements: NSDatePicker.ElementFlags = []
        if components.contains(.date) { elements.insert(.yearMonthDay) }
        if components.contains(.hourAndMinute) { elements.insert(.hourMinute) }
        picker.datePickerElements = elements
        picker.minDate = minimum
        picker.maxDate = maximum
        if picker.dateValue != binding.wrappedValue { picker.dateValue = binding.wrappedValue }
        bindAppleEvent(view, "action") { [weak picker] in
            if let picker { binding.wrappedValue = picker.dateValue }
        }
        #endif
    }
}
#endif
