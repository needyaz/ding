import Foundation

// What an AI assistant (any client of the control surface) can see and do. Pure logic: the app feeds it events.
// Privacy is by construction: a summary has no field for notes, attendees, locations or meeting links.

/// One meeting as shared with a client.
public struct MeetingSummary: Codable, Equatable, Sendable {
    public var id: String
    public var title: String
    /// ISO 8601 in the user's time zone, with its UTC offset ("2026-10-31T09:00:00-07:00").
    public var start: String
    public var end: String
    public var isAllDay: Bool
    public var isInProgress: Bool
    /// Whole minutes until the start, rounded up; nil once it has started.
    public var minutesUntilStart: Int?
    public var calendar: String
    /// "Zoom", "Google Meet", "Microsoft Teams", "Webex" or "Other link"; nil if the meeting has no link.
    public var service: String?
    public var canOpen: Bool
    public var isTentative: Bool

    /// Fields that don't apply are written as explicit nulls, so a client always sees the same shape.
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(start, forKey: .start)
        try container.encode(end, forKey: .end)
        try container.encode(isAllDay, forKey: .isAllDay)
        try container.encode(isInProgress, forKey: .isInProgress)
        try container.encode(minutesUntilStart, forKey: .minutesUntilStart)
        try container.encode(calendar, forKey: .calendar)
        try container.encode(service, forKey: .service)
        try container.encode(canOpen, forKey: .canOpen)
        try container.encode(isTentative, forKey: .isTentative)
    }

    enum CodingKeys: String, CodingKey {
        case id, title, start, end, calendar, service
        case isAllDay = "is_all_day"
        case isInProgress = "is_in_progress"
        case minutesUntilStart = "minutes_until_start"
        case canOpen = "can_open"
        case isTentative = "is_tentative"
    }
}

public struct MeetingList: Codable, Equatable, Sendable {
    public var meetings: [MeetingSummary]
    /// True if there were more meetings than `ControlAPI.maxMeetings`.
    public var truncated: Bool
}

/// What the user has allowed. Both default to off.
public struct ControlPermissions: Equatable, Sendable {
    public var canReadSchedule: Bool
    public var canOpenMeetings: Bool

    public init(canReadSchedule: Bool = false, canOpenMeetings: Bool = false) {
        self.canReadSchedule = canReadSchedule
        self.canOpenMeetings = canOpenMeetings
    }
}

/// Why a request couldn't be done. Each has a message written for the person reading it, because it
/// ends up in front of an AI model and then the user.
public enum ControlFailure: Error, Equatable, Sendable {
    case scheduleAccessOff
    case openingOff
    case noCalendarAccess
    case meetingNotFound(String)
    case nothingToOpen
    case cannotOpen
    case invalidArgument(String)

    /// A short, stable code for clients that want to branch on it.
    public var code: String {
        switch self {
        case .scheduleAccessOff: "schedule_access_off"
        case .openingOff: "opening_off"
        case .noCalendarAccess: "no_calendar_access"
        case .meetingNotFound: "meeting_not_found"
        case .nothingToOpen: "nothing_to_open"
        case .cannotOpen: "cannot_open"
        case .invalidArgument: "invalid_argument"
        }
    }

    public var message: String {
        switch self {
        case .scheduleAccessOff:
            "The user hasn't allowed AI assistants to see their schedule. They can turn it on in Ding → Preferences → AI Access."
        case .openingOff:
            "The user hasn't allowed AI assistants to open meetings. They can turn it on in Ding → Preferences → AI Access."
        case .noCalendarAccess:
            "Ding doesn't have access to the user's calendar, so there's nothing to show. Ding needs calendar access in System Settings → Privacy & Security."
        case .meetingNotFound(let id):
            "There's no upcoming meeting with id \"\(id)\". Use list_meetings or get_next_meeting to get a current id."
        case .nothingToOpen:
            "There's no current or upcoming meeting with a link to open."
        case .cannotOpen:
            "That meeting has no Zoom, Google Meet, Microsoft Teams or Webex link, so Ding won't open it for an assistant."
        case .invalidArgument(let detail):
            detail
        }
    }
}

public enum ControlAPI {
    public static let maxMeetings = 50
    public static let maxDays = 14

    public static func summary(of event: DingEvent, now: Date, timeZone: TimeZone = .current) -> MeetingSummary {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = timeZone
        formatter.formatOptions = [.withInternetDateTime]
        let started = event.start <= now
        return MeetingSummary(
            id: event.id,
            title: event.title,
            start: formatter.string(from: event.start),
            end: formatter.string(from: event.end),
            isAllDay: event.isAllDay,
            isInProgress: !event.isAllDay && started && event.end > now,
            minutesUntilStart: started ? nil : Int((event.start.timeIntervalSince(now) / 60).rounded(.up)),
            calendar: event.calendarTitle,
            service: event.link?.service.displayName,
            canOpen: canOpen(event),
            isTentative: event.isMaybe
        )
    }

    /// An assistant may open only meetings on a known service. Any other link came from an invitation someone else wrote,
    /// and a prompt-injected assistant must not be able to send the user's browser to it.
    public static func canOpen(_ event: DingEvent) -> Bool {
        event.link.map { $0.service != .other } ?? false
    }

    /// The same meeting the menu bar shows as "next".
    public static func nextMeeting(_ events: [DingEvent], now: Date, timeZone: TimeZone = .current) -> MeetingSummary? {
        NextEvent.select(from: events, now: now).map { summary(of: $0, now: now, timeZone: timeZone) }
    }

    /// Meetings from now through the end of day `days` (1 = today), soonest first. Finished meetings are left out,
    /// all-day events only if asked for.
    public static func upcoming(
        _ events: [DingEvent], now: Date, days: Int, includeAllDay: Bool,
        calendar: Calendar = .current
    ) throws -> MeetingList {
        guard (1...maxDays).contains(days) else {
            throw ControlFailure.invalidArgument("days must be between 1 and \(maxDays), but was \(days).")
        }
        let rangeEnd = calendar.date(byAdding: .day, value: days, to: calendar.startOfDay(for: now)) ?? now
        let matching = events
            .filter { $0.end > now && $0.start < rangeEnd && (includeAllDay || !$0.isAllDay) }
            .sorted { ($0.start, $0.title) < ($1.start, $1.title) }
        return MeetingList(
            meetings: matching.prefix(maxMeetings).map { summary(of: $0, now: now, timeZone: calendar.timeZone) },
            truncated: matching.count > maxMeetings
        )
    }

    /// The meeting to open: the one with `id`, or with no id the next with a link (the same one the "join next" hotkey picks).
    public static func openTarget(_ events: [DingEvent], now: Date, id: String?) throws -> DingEvent {
        if let id {
            guard let event = events.first(where: { $0.id == id && $0.end > now }) else { throw ControlFailure.meetingNotFound(id) }
            guard canOpen(event) else { throw ControlFailure.cannotOpen }
            return event
        }
        guard let event = JoinSelection.candidate(from: events.filter(canOpen), now: now) else { throw ControlFailure.nothingToOpen }
        return event
    }
}

/// Text to paste into a client to connect it to the bundled MCP helper.
public enum MCPConfig {
    /// The `"mcpServers"` entry for Claude Desktop's `claude_desktop_config.json`, without outer braces.
    ///
    /// That file usually already holds Claude Desktop's own settings, so this goes *inside* its top-level `{ }` as
    /// one more entry: before the final `}`, with a comma after the entry above it. A complete `{ "mcpServers": … }`
    /// document pasted there would be a second object and break the file, which is what this shape avoids.
    public static func desktopEntry(command: String) -> String {
        let config: [String: Any] = ["mcpServers": ["ding": ["command": command]]]
        let data = (try? JSONSerialization.data(withJSONObject: config, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])) ?? Data()
        // Drop the first and last lines (the outer braces); the entry keeps its two-space indent.
        let lines = String(decoding: data, as: UTF8.self).components(separatedBy: "\n")
        return lines.dropFirst().dropLast().joined(separator: "\n")
    }

    /// For Claude Code.
    public static func claudeCodeCommand(command: String) -> String {
        "claude mcp add ding -- \(shellQuoted(command))"
    }

    /// Single-quotes `text` for a POSIX shell unless it is plainly safe.
    static func shellQuoted(_ text: String) -> String {
        let safe = text.allSatisfy { $0.isLetter || $0.isNumber || "/._-+@:".contains($0) }
        if safe && !text.isEmpty { return text }
        return "'" + text.replacingOccurrences(of: "'", with: #"'\''"#) + "'"
    }
}
