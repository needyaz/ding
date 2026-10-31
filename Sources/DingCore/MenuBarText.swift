import Foundation

public enum Truncation {
    /// Collapses newlines to spaces and shortens to `maxLength` characters, ending with "…".
    public static func truncate(_ text: String, maxLength: Int) -> String {
        let collapsed = text.split(whereSeparator: \.isNewline).joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
        guard maxLength > 1, collapsed.count > maxLength else { return collapsed }
        return collapsed.prefix(maxLength - 1).trimmingCharacters(in: .whitespaces) + "…"
    }
}

public struct MenuBarOptions: Equatable, Sendable {
    public var showCountdown: Bool
    public var showTitle: Bool
    /// Show nothing beside the icon when the next meeting isn't today.
    public var countdownOnlyToday: Bool
    public var maxTitleLength: Int

    public init(showCountdown: Bool = true, showTitle: Bool = true, countdownOnlyToday: Bool = false, maxTitleLength: Int = 24) {
        self.showCountdown = showCountdown
        self.showTitle = showTitle
        self.countdownOnlyToday = countdownOnlyToday
        self.maxTitleLength = maxTitleLength
    }
}

public enum MenuBarText {
    /// Text beside the menu bar icon, or nil for icon only: "Standup in 12m", "Standup now", "in 12m", "Standup".
    public static func make(next: DingEvent?, now: Date, options: MenuBarOptions, calendar: Calendar = .current) -> String? {
        guard let next else { return nil }
        if options.countdownOnlyToday && !calendar.isDate(next.start, inSameDayAs: now) { return nil }

        let title = options.showTitle ? Truncation.truncate(next.title, maxLength: options.maxTitleLength) : ""
        let hasStarted = next.start <= now
        let countdown = hasStarted ? "now" : "in \(Countdown.text(until: next.start, now: now))"

        switch (title.isEmpty, options.showCountdown) {
        case (false, true): return "\(title) \(countdown)"
        case (false, false): return title
        case (true, true): return countdown
        case (true, false): return nil
        }
    }
}
