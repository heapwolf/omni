// src/lib/components/TimelineView.swift
// SwiftUI's TimelineView: content that renders again on a schedule, given the
// time it is for. Platform-neutral: a task ticks a @State clock.
import Foundation

/// When a TimelineView renders: SwiftUI's TimelineSchedule.
public protocol TimelineSchedule: Sendable {
    /// The first render at or after `date`.
    func nextDate(after date: Date) -> Date
}

/// Every `interval` seconds, counted from `start`.
public struct PeriodicTimelineSchedule: TimelineSchedule {
    let start: Date
    let interval: TimeInterval

    public init(from start: Date, by interval: TimeInterval) {
        self.start = start
        self.interval = max(interval, 0.01)
    }

    public func nextDate(after date: Date) -> Date {
        guard date >= start else { return start }
        let ticks = ((date.timeIntervalSince(start)) / interval).rounded(.down) + 1
        return start.addingTimeInterval(ticks * interval)
    }
}

/// On each minute boundary.
public struct EveryMinuteTimelineSchedule: TimelineSchedule {
    public init() {}

    public func nextDate(after date: Date) -> Date {
        let seconds = date.timeIntervalSinceReferenceDate
        return Date(timeIntervalSinceReferenceDate: ((seconds / 60).rounded(.down) + 1) * 60)
    }
}

public extension TimelineSchedule where Self == PeriodicTimelineSchedule {
    static func periodic(from start: Date, by interval: TimeInterval) -> PeriodicTimelineSchedule {
        PeriodicTimelineSchedule(from: start, by: interval)
    }
}

public extension TimelineSchedule where Self == EveryMinuteTimelineSchedule {
    static var everyMinute: EveryMinuteTimelineSchedule { EveryMinuteTimelineSchedule() }
}

/// What a TimelineView's content is rendered for. Outside the generic view, as
/// SwiftUI's is: nested, its type would depend on the Content it helps infer.
public struct TimelineViewDefaultContext {
    public let date: Date
}

public struct TimelineView<Schedule: TimelineSchedule, Content: View>: View {
    public typealias Context = TimelineViewDefaultContext

    let schedule: Schedule
    let content: @MainActor (Context) -> Content

    @State private var date = Date()

    public init(_ schedule: Schedule, @ViewBuilder content: @escaping @MainActor (Context) -> Content) {
        self.schedule = schedule
        self.content = content
    }

    public var body: some View {
        let schedule = self.schedule
        let clock = $date
        return content(Context(date: date)).task {
            while !Task.isCancelled {
                let now = Date()
                let wait = max(schedule.nextDate(after: now).timeIntervalSince(now), 0.01)
                try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
                if Task.isCancelled { return }
                await MainActor.run { clock.wrappedValue = Date() }
            }
        }
    }
}
