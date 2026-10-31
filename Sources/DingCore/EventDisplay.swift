import Foundation

public enum EventDisplay {
    /// "Today", "Tomorrow", or e.g. "Friday, Oct 30".
    public static func dayTitle(_ day: Date, now: Date, calendar: Calendar = .current, locale: Locale = .current) -> String {
        if calendar.isDate(day, inSameDayAs: now) { return "Today" }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(day, inSameDayAs: tomorrow) {
            return "Tomorrow"
        }
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = calendar.timeZone
        formatter.setLocalizedDateFormatFromTemplate("EEEEMMMd")
        return formatter.string(from: day)
    }

    /// "All day", "9:00 AM – 9:30 AM", with " · Maybe" appended for tentative events.
    public static func timeText(for event: DingEvent, use24Hour: Bool, timeZone: TimeZone = .current) -> String {
        var text: String
        if event.isAllDay {
            text = "All day"
        } else {
            let start = TimeFormat.string(event.start, use24Hour: use24Hour, timeZone: timeZone)
            let end = TimeFormat.string(event.end, use24Hour: use24Hour, timeZone: timeZone)
            text = "\(start) – \(end)"
        }
        if event.isMaybe { text += " · Maybe" }
        return text
    }

    /// The full-screen alert's status line.
    public static func startedText(now: Date, start: Date) -> String {
        let elapsed = Int(now.timeIntervalSince(start))
        if elapsed < 5 { return "Starting now" }
        if elapsed < 60 { return "Started \(elapsed)s ago" }
        return "Started \(elapsed / 60) min ago"
    }
}

public enum TimeFormat {
    /// "3:05 PM" or "15:05". The locale is fixed so the user's 12/24-hour choice, not their
    /// region, decides the format.
    public static func string(_ date: Date, use24Hour: Bool, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: use24Hour ? "en_GB" : "en_US")
        formatter.timeZone = timeZone
        formatter.dateFormat = use24Hour ? "HH:mm" : "h:mm a"
        return formatter.string(from: date)
    }
}
