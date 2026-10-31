import Foundation

public struct DayGroup: Identifiable, Equatable, Sendable {
    /// Start of the day in the calendar used for grouping.
    public let day: Date
    public let events: [DingEvent]
    public var id: Date { day }

    public init(day: Date, events: [DingEvent]) {
        self.day = day
        self.events = events
    }
}

public enum DayGrouping {
    /// Groups events that overlap the next `days` days (today included) by day.
    /// Finished events are dropped; multi-day all-day events appear on each day they cover.
    public static func group(_ events: [DingEvent], now: Date, days: Int, calendar: Calendar = .current) -> [DayGroup] {
        let rangeStart = calendar.startOfDay(for: now)
        guard days > 0, let rangeEnd = calendar.date(byAdding: .day, value: days, to: rangeStart) else { return [] }

        var eventsByDay: [Date: [DingEvent]] = [:]
        for event in events where event.end > now && event.start < rangeEnd {
            for day in daysShown(for: event, from: rangeStart, before: rangeEnd, calendar: calendar) {
                eventsByDay[day, default: []].append(event)
            }
        }

        return eventsByDay.keys.sorted().map { day in
            DayGroup(day: day, events: eventsByDay[day, default: []].sorted(by: isDisplayedBefore))
        }
    }

    /// A timed event belongs to the day it starts (or today, if it started earlier).
    /// An all-day event belongs to every day it covers within the range.
    private static func daysShown(for event: DingEvent, from rangeStart: Date, before rangeEnd: Date, calendar: Calendar) -> [Date] {
        let firstDay = calendar.startOfDay(for: max(event.start, rangeStart))
        guard event.isAllDay else { return [firstDay] }

        // EventKit ends an all-day event at 23:59:59 on its last day; ICS-style feeds end it at the next
        // midnight. Backing off one second maps both to the same last day.
        let lastDay = calendar.startOfDay(for: max(event.end.addingTimeInterval(-1), event.start))
        var days: [Date] = []
        var day = firstDay
        while day <= lastDay && day < rangeEnd {
            days.append(day)
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return days
    }

    /// All-day events first, then by start time, then by title.
    private static func isDisplayedBefore(_ a: DingEvent, _ b: DingEvent) -> Bool {
        if a.isAllDay != b.isAllDay { return a.isAllDay }
        if a.start != b.start { return a.start < b.start }
        return a.title < b.title
    }
}
