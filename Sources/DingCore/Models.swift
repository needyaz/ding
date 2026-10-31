import Foundation

public enum MeetingService: String, CaseIterable, Codable, Sendable, Identifiable {
    case zoom
    case googleMeet
    case teams
    case webex
    case other

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .zoom: "Zoom"
        case .googleMeet: "Google Meet"
        case .teams: "Microsoft Teams"
        case .webex: "Webex"
        case .other: "Other link"
        }
    }

    /// Services with a link-pattern entry (everything except the `.other` fallback).
    public static var detectable: [MeetingService] { allCases.filter { $0 != .other } }

    /// Whether Ding knows how to hand the link to a desktop app.
    public var supportsNativeApp: Bool {
        switch self {
        case .zoom, .teams, .webex: true
        case .googleMeet, .other: false
        }
    }
}

public struct MeetingLink: Equatable, Hashable, Sendable {
    public let service: MeetingService
    public let url: URL

    public init(service: MeetingService, url: URL) {
        self.service = service
        self.url = url
    }
}

public struct CalendarColor: Equatable, Hashable, Sendable {
    public let red: Double
    public let green: Double
    public let blue: Double

    public init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    public static let gray = CalendarColor(red: 0.55, green: 0.55, blue: 0.55)
}

/// A calendar event reduced to what Ding needs. The app maps `EKEvent` into this.
public struct DingEvent: Identifiable, Equatable, Sendable {
    public let id: String
    public var title: String
    public var start: Date
    public var end: Date
    public var isAllDay: Bool
    public var calendarID: String
    public var calendarTitle: String
    public var calendarColor: CalendarColor
    /// The user marked "maybe" / tentative.
    public var isMaybe: Bool
    public var link: MeetingLink?

    public var hasLink: Bool { link != nil }

    public init(
        id: String,
        title: String,
        start: Date,
        end: Date,
        isAllDay: Bool = false,
        calendarID: String = "",
        calendarTitle: String = "",
        calendarColor: CalendarColor = .gray,
        isMaybe: Bool = false,
        link: MeetingLink? = nil
    ) {
        self.id = id
        self.title = title
        self.start = start
        self.end = end
        self.isAllDay = isAllDay
        self.calendarID = calendarID
        self.calendarTitle = calendarTitle
        self.calendarColor = calendarColor
        self.isMaybe = isMaybe
        self.link = link
    }
}

public struct EventFilter: Equatable, Sendable {
    public var showWithoutLink: Bool
    public var showMaybe: Bool
    /// Stored as the *excluded* set so calendars that appear later default to on.
    public var disabledCalendarIDs: Set<String>

    public init(showWithoutLink: Bool = true, showMaybe: Bool = true, disabledCalendarIDs: Set<String> = []) {
        self.showWithoutLink = showWithoutLink
        self.showMaybe = showMaybe
        self.disabledCalendarIDs = disabledCalendarIDs
    }

    public func apply(_ events: [DingEvent]) -> [DingEvent] {
        events.filter { event in
            if disabledCalendarIDs.contains(event.calendarID) { return false }
            if !showMaybe && event.isMaybe { return false }
            if !showWithoutLink && !event.hasLink { return false }
            return true
        }
    }
}
