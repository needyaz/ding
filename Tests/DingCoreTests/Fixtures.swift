import XCTest
@testable import DingCore

/// Shared date and event helpers. Times are in Los Angeles so DST cases are real.
class DingCoreTestCase: XCTestCase {
    let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return calendar
    }()

    func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0, _ second: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute, second: second))!
    }

    /// A 30-minute event; `link: true` gives it a Zoom link.
    func event(
        _ id: String, _ start: Date, minutes: Int = 30, link: Bool = true,
        allDay: Bool = false, response: ResponseStatus = .accepted, calendarID: String = "cal"
    ) -> DingEvent {
        event(id, start, minutes: minutes, link: link ? .zoom : nil, allDay: allDay, response: response, calendarID: calendarID)
    }

    /// Like the above, with a link for a specific service (or none).
    func event(
        _ id: String, _ start: Date, minutes: Int = 30, link: MeetingService?,
        allDay: Bool = false, response: ResponseStatus = .accepted, calendarID: String = "cal"
    ) -> DingEvent {
        DingEvent(
            id: id, title: id, start: start, end: start.addingTimeInterval(Double(minutes) * 60), isAllDay: allDay,
            calendarID: calendarID, response: response,
            link: link.map { MeetingLink(service: $0, url: URL(string: "https://example.com/\(id)")!) }
        )
    }
}
