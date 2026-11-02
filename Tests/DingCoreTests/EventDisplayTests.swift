import XCTest
@testable import DingCore

/// Day titles, time ranges and the alert status line.
final class EventDisplayTests: DingCoreTestCase {
    func testDayTitles() {
        let now = date(2026, 10, 30, 9)
        let us = Locale(identifier: "en_US")
        XCTAssertEqual(EventDisplay.dayTitle(date(2026, 10, 30), now: now, calendar: calendar, locale: us), "Today")
        XCTAssertEqual(EventDisplay.dayTitle(date(2026, 10, 31), now: now, calendar: calendar, locale: us), "Tomorrow")
        XCTAssertEqual(EventDisplay.dayTitle(date(2026, 11, 2), now: now, calendar: calendar, locale: us), "Monday, Nov 2")
    }

    func testDayTitleTomorrowAcrossMonthEndAndDST() {
        let us = Locale(identifier: "en_US")
        XCTAssertEqual(EventDisplay.dayTitle(date(2026, 11, 1), now: date(2026, 10, 31, 23, 30), calendar: calendar, locale: us), "Tomorrow")
        // Fall-back day is 25h long; "tomorrow" is still the next calendar day.
        XCTAssertEqual(EventDisplay.dayTitle(date(2026, 11, 2), now: date(2026, 11, 1, 12), calendar: calendar, locale: us), "Tomorrow")
    }

    func testTimeText() {
        let tz = calendar.timeZone
        let timed = event("a", date(2026, 10, 30, 9), minutes: 30)
        XCTAssertEqual(EventDisplay.timeText(for: timed, use24Hour: false, timeZone: tz), "9:00 AM – 9:30 AM")
        XCTAssertEqual(EventDisplay.timeText(for: timed, use24Hour: true, timeZone: tz), "09:00 – 09:30")
        XCTAssertEqual(EventDisplay.timeText(for: event("b", date(2026, 10, 30, 13), response: .maybe), use24Hour: false, timeZone: tz), "1:00 PM – 1:30 PM · Maybe")
        XCTAssertEqual(EventDisplay.timeText(for: event("c", date(2026, 10, 30), minutes: 1440, allDay: true), use24Hour: false, timeZone: tz), "All day")
        XCTAssertEqual(EventDisplay.timeText(for: event("d", date(2026, 10, 30), minutes: 1440, allDay: true, response: .maybe), use24Hour: false, timeZone: tz), "All day · Maybe")
    }

    func testAlertStatusBeforeTheStartCountsDown() {
        let start = date(2026, 10, 30, 10)
        XCTAssertEqual(EventDisplay.alertStatus(now: start.addingTimeInterval(-300), start: start), "Starts in 5:00")
        XCTAssertEqual(EventDisplay.alertStatus(now: start.addingTimeInterval(-61), start: start), "Starts in 1:01")
        XCTAssertEqual(EventDisplay.alertStatus(now: start.addingTimeInterval(-60), start: start), "Starts in 1:00")
        XCTAssertEqual(EventDisplay.alertStatus(now: start.addingTimeInterval(-9), start: start), "Starts in 0:09")
        XCTAssertEqual(EventDisplay.alertStatus(now: start.addingTimeInterval(-0.4), start: start), "Starts in 0:01")
    }

    func testAlertStatusAfterTheStart() {
        let start = date(2026, 10, 30, 10)
        XCTAssertEqual(EventDisplay.alertStatus(now: start, start: start), "Starting now")
        XCTAssertEqual(EventDisplay.alertStatus(now: start.addingTimeInterval(4), start: start), "Starting now")
        XCTAssertEqual(EventDisplay.alertStatus(now: start.addingTimeInterval(5), start: start), "Started 5s ago")
        XCTAssertEqual(EventDisplay.alertStatus(now: start.addingTimeInterval(59), start: start), "Started 59s ago")
        XCTAssertEqual(EventDisplay.alertStatus(now: start.addingTimeInterval(60), start: start), "Started 1 min ago")
        XCTAssertEqual(EventDisplay.alertStatus(now: start.addingTimeInterval(605), start: start), "Started 10 min ago")
    }

    func testNextMeetingHeadline() {
        let start = date(2026, 10, 30, 10)
        XCTAssertEqual(EventDisplay.nextMeetingHeadline(start: start, now: start.addingTimeInterval(-720)), "Next · in 12m")
        XCTAssertEqual(EventDisplay.nextMeetingHeadline(start: start, now: start.addingTimeInterval(-3700)), "Next · in 1h 2m")
        XCTAssertEqual(EventDisplay.nextMeetingHeadline(start: start, now: start), "Happening now")
        XCTAssertEqual(EventDisplay.nextMeetingHeadline(start: start, now: start.addingTimeInterval(120)), "Happening now")
    }

    func testUnansweredInvitationsGetTheirOwnLabel() {
        let tz = TimeZone(identifier: "America/Los_Angeles")!
        XCTAssertEqual(EventDisplay.timeText(for: event("n", date(2026, 10, 30, 13), response: .notResponded), use24Hour: false, timeZone: tz), "1:00 PM – 1:30 PM · Not responded")
        XCTAssertEqual(EventDisplay.timeText(for: event("a", date(2026, 10, 30, 13)), use24Hour: false, timeZone: tz), "1:00 PM – 1:30 PM")
    }
}
