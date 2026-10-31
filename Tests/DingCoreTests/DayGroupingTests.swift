import XCTest
@testable import DingCore

/// Grouping events by day for the dropdown.
final class DayGroupingTests: DingCoreTestCase {
    func testGroupsByDaySortedWithAllDayFirst() {
        let now = date(2026, 10, 30, 9, 0)
        let events = [
            event("b", date(2026, 10, 30, 14, 0)),
            event("a", date(2026, 10, 30, 10, 0)),
            event("holiday", date(2026, 10, 30), minutes: 1440, allDay: true),
            event("tomorrow", date(2026, 10, 31, 9, 0)),
        ]
        let groups = DayGrouping.group(events, now: now, days: 7, calendar: calendar)
        XCTAssertEqual(groups.map(\.day), [date(2026, 10, 30), date(2026, 10, 31)])
        XCTAssertEqual(groups[0].events.map(\.id), ["holiday", "a", "b"])
        XCTAssertEqual(groups[1].events.map(\.id), ["tomorrow"])
    }

    func testGroupingRespectsRangeAndDropsEnded() {
        let now = date(2026, 10, 30, 12, 0)
        let events = [
            event("ended", date(2026, 10, 30, 9, 0)),
            event("inProgress", date(2026, 10, 30, 11, 45)),
            event("lastDay", date(2026, 11, 1, 23, 0)),
            event("outOfRange", date(2026, 11, 2, 0, 0)),
        ]
        let groups = DayGrouping.group(events, now: now, days: 3, calendar: calendar)
        XCTAssertEqual(groups.flatMap(\.events).map(\.id), ["inProgress", "lastDay"])
    }

    func testMultiDayAllDayAppearsOnEachDay() {
        let now = date(2026, 10, 30, 9, 0)
        // EventKit-style end: 23:59:59 on the last day.
        let trip = event("trip", date(2026, 10, 30), minutes: 0, allDay: true)
        var multi = trip
        multi.end = date(2026, 11, 1, 23, 59, 59)
        let groups = DayGrouping.group([multi], now: now, days: 7, calendar: calendar)
        XCTAssertEqual(groups.map(\.day), [date(2026, 10, 30), date(2026, 10, 31), date(2026, 11, 1)])
    }

    func testAllDayWithExclusiveMidnightEndDoesNotSpillOver() {
        let now = date(2026, 10, 30, 9, 0)
        var allDay = event("holiday", date(2026, 10, 30), allDay: true)
        allDay.end = date(2026, 10, 31, 0, 0)
        let groups = DayGrouping.group([allDay], now: now, days: 7, calendar: calendar)
        XCTAssertEqual(groups.map(\.day), [date(2026, 10, 30)])
    }

    func testGroupingAcrossDSTFallBack() {
        // US DST ends 2026-11-01: that local day is 25 hours long.
        let now = date(2026, 10, 31, 12, 0)
        let events = [event("sunday", date(2026, 11, 1, 9, 0)), event("monday", date(2026, 11, 2, 9, 0))]
        let groups = DayGrouping.group(events, now: now, days: 3, calendar: calendar)
        XCTAssertEqual(groups.map(\.day), [date(2026, 11, 1), date(2026, 11, 2)])
        XCTAssertEqual(groups.map { $0.events.map(\.id) }, [["sunday"], ["monday"]])
    }

    func testGroupingZeroDays() {
        XCTAssertTrue(DayGrouping.group([event("a", Date())], now: Date(), days: 0, calendar: calendar).isEmpty)
    }


    func testSameStartSortsByTitleAndGroupHasStableID() {
        let cal = Calendar(identifier: .gregorian)
        let start = cal.date(from: DateComponents(year: 2026, month: 10, day: 30, hour: 10))!
        let end = start.addingTimeInterval(1800)
        let events = [
            DingEvent(id: "2", title: "Beta", start: start, end: end),
            DingEvent(id: "1", title: "Alpha", start: start, end: end),
        ]
        let groups = DayGrouping.group(events, now: start.addingTimeInterval(-3600), days: 1, calendar: cal)
        XCTAssertEqual(groups.first?.events.map(\.title), ["Alpha", "Beta"])
        XCTAssertEqual(groups.first?.id, groups.first?.day)
    }
}
