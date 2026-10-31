import XCTest
import DingCore
@testable import Ding

/// Runs against an isolated defaults suite so tests never touch the user's real settings.
class IsolatedDefaultsTestCase: XCTestCase {
    private(set) var suite: UserDefaults!
    private var suiteName = ""

    override func setUp() {
        super.setUp()
        suiteName = "blue.luci.DingTests.\(UUID().uuidString)"
        suite = UserDefaults(suiteName: suiteName)
        Pref.defaults = suite
        Pref.registerDefaults()
    }

    override func tearDown() {
        suite.removePersistentDomain(forName: suiteName)
        Pref.defaults = .standard
        super.tearDown()
    }
}

extension AppModel {
    /// A model wired to fakes: no EventKit, no notification center.
    static func test(calendar: CalendarSource? = nil, notifier: NotificationScheduling? = nil) -> AppModel {
        AppModel(calendar: calendar ?? FakeCalendar(), notifier: notifier ?? FakeNotifier())
    }
}

extension DingEvent {
    /// A 30-minute event starting `seconds` from `now`. `link: true` gives it a Zoom link.
    static func test(
        _ id: String, startingIn seconds: TimeInterval, from now: Date = Date(), minutes: Int = 30,
        link: Bool = true, allDay: Bool = false, maybe: Bool = false, calendarID: String = "cal"
    ) -> DingEvent {
        let start = now.addingTimeInterval(seconds)
        return DingEvent(
            id: id, title: "Event \(id)", start: start, end: start.addingTimeInterval(Double(minutes) * 60), isAllDay: allDay,
            calendarID: calendarID, isMaybe: maybe,
            link: link ? MeetingLink(service: .zoom, url: URL(string: "https://zoom.us/j/1")!) : nil
        )
    }
}
