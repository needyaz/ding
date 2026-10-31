#if DEBUG
import DingCore
import Foundation

// Made-up data for the App Store screenshots. Nothing here comes from a real calendar, and the screenshot mode
// never reads one: it runs the real views against these fixtures and a frozen clock.

@MainActor
final class ScreenshotCalendar: CalendarSource {
    var access: CalendarAccess { .granted }
    var onChange: (() -> Void)?
    func requestAccess() async {}
    func events(from start: Date, to end: Date) -> [DingEvent] { ScreenshotFixtures.events }
    func accounts() -> [CalendarAccount] { ScreenshotFixtures.accounts }
}

@MainActor
final class SilentNotifier: NotificationScheduling {
    func requestPermission() {}
    func replaceAll(with notifications: [PlannedNotification]) {}
}

final class OffLoginItem: LoginItemService {
    var isEnabled = false
    func register() throws {}
    func unregister() throws {}
}

enum ScreenshotFixtures {
    /// Tuesday 3 November 2026, 9:48 AM in the machine's time zone: Team standup is 12 minutes away.
    static let now = at(day: 0, hour: 9, minute: 48)

    static func at(day: Int, hour: Int, minute: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 3 + day, hour: hour, minute: minute))!
    }

    private struct Calendar_ {
        let id: String
        let title: String
        let color: CalendarColor
    }

    private static let work = Calendar_(id: "work", title: "Work", color: CalendarColor(red: 0.20, green: 0.48, blue: 0.95))
    private static let personal = Calendar_(id: "personal", title: "Personal", color: CalendarColor(red: 0.20, green: 0.70, blue: 0.40))
    private static let family = Calendar_(id: "family", title: "Family", color: CalendarColor(red: 0.90, green: 0.35, blue: 0.40))
    private static let team = Calendar_(id: "team", title: "Team Events", color: CalendarColor(red: 0.62, green: 0.40, blue: 0.85))

    private static func meeting(
        _ title: String, day: Int, _ hour: Int, _ minute: Int, minutes: Int,
        in calendar: Calendar_, service: MeetingService? = nil, maybe: Bool = false
    ) -> DingEvent {
        let start = at(day: day, hour: hour, minute: minute)
        return DingEvent(
            id: "\(day)-\(hour)-\(minute)-\(title)", title: title, start: start, end: start.addingTimeInterval(Double(minutes) * 60),
            calendarID: calendar.id, calendarTitle: calendar.title, calendarColor: calendar.color, isMaybe: maybe,
            link: service.map { MeetingLink(service: $0, url: URL(string: "https://example.com/\(title.hashValue.magnitude)")!) }
        )
    }

    private static func allDay(_ title: String, day: Int, in calendar: Calendar_) -> DingEvent {
        let start = Calendar.current.startOfDay(for: at(day: day, hour: 0, minute: 0))
        return DingEvent(
            id: "allday-\(day)-\(title)", title: title, start: start, end: start.addingTimeInterval(86_399), isAllDay: true,
            calendarID: calendar.id, calendarTitle: calendar.title, calendarColor: calendar.color
        )
    }

    static let events: [DingEvent] = [
        meeting("Team standup", day: 0, 10, 0, minutes: 15, in: work, service: .googleMeet),
        meeting("Design review", day: 0, 11, 0, minutes: 60, in: work, service: .zoom),
        meeting("Lunch with Maya", day: 0, 12, 30, minutes: 60, in: personal),
        meeting("1:1 with Jordan", day: 0, 14, 0, minutes: 30, in: work, service: .teams),
        meeting("Quarterly planning", day: 0, 15, 30, minutes: 60, in: team, service: .webex, maybe: true),
        allDay("Mom's birthday", day: 1, in: family),
        meeting("Product sync", day: 1, 9, 0, minutes: 30, in: work, service: .zoom),
        meeting("Dentist", day: 1, 13, 0, minutes: 45, in: personal),
        meeting("Customer call", day: 1, 15, 0, minutes: 45, in: work, service: .googleMeet),
        meeting("Offsite planning", day: 2, 10, 30, minutes: 60, in: team, service: .teams),
        meeting("Piano lesson", day: 2, 16, 0, minutes: 45, in: family),
    ]

    static var accounts: [CalendarAccount] {
        func info(_ c: Calendar_) -> CalendarInfo { CalendarInfo(id: c.id, title: c.title, color: c.color) }
        return [
            CalendarAccount(title: "iCloud", calendars: [info(family), info(personal)]),
            CalendarAccount(title: "Work", calendars: [info(team), info(work)]),
        ]
    }

    /// Preferences as the screenshots show them, in a private suite so the real settings are never touched.
    static func makeDefaults() -> UserDefaults {
        let name = "blue.luci.Ding.screenshots"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @MainActor
    static func configure(_ defaults: UserDefaults) {
        Pref.defaults = defaults
        Pref.registerDefaults()
        defaults.set(false, forKey: Pref.use24Hour)
        defaults.set(2, forKey: Pref.rangeDays)
        defaults.set(AlertMode.fullScreen.rawValue, forKey: Pref.alertMode)
        defaults.set(1, forKey: Pref.alertLeadMinutes)
        defaults.set(5, forKey: Pref.notifyLeadMinutes)
        defaults.set(true, forKey: Pref.controlReadSchedule)
        defaults.set(true, forKey: Pref.controlOpenMeetings)
    }
}
#endif
