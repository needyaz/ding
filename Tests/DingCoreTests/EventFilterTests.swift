import XCTest
@testable import DingCore

/// The calendar and link/maybe filters.
final class EventFilterTests: DingCoreTestCase {

    func testEventFilter() {
        let t = date(2026, 10, 30, 10)
        let events = [
            event("link", t),
            event("nolink", t, link: false),
            event("maybe", t, maybe: true),
            event("hidden", t, calendarID: "off"),
        ]
        XCTAssertEqual(EventFilter().apply(events).count, 4)
        XCTAssertEqual(EventFilter(disabledCalendarIDs: ["off"]).apply(events).map(\.id), ["link", "nolink", "maybe"])
        XCTAssertEqual(EventFilter(showWithoutLink: false).apply(events).map(\.id), ["link", "maybe", "hidden"])
        XCTAssertEqual(EventFilter(showMaybe: false).apply(events).map(\.id), ["link", "nolink", "hidden"])
    }



    private func e(_ id: String, link: Bool = true, maybe: Bool = false, allDay: Bool = false, cal: String = "c") -> DingEvent {
        DingEvent(id: id, title: id, start: Date(), end: Date(), isAllDay: allDay, calendarID: cal, isMaybe: maybe,
                  link: link ? MeetingLink(service: .zoom, url: URL(string: "https://zoom.us/j/1")!) : nil)
    }

    func testFilterDefaultsShowEverything() {
        let f = EventFilter()
        XCTAssertTrue(f.showWithoutLink)
        XCTAssertTrue(f.showMaybe)
        XCTAssertTrue(f.disabledCalendarIDs.isEmpty)
        XCTAssertEqual(f.apply([e("a"), e("b", link: false), e("c", maybe: true)]).count, 3)
    }

    func testFilterCombinesRules() {
        let events = [
            e("keep"),
            e("maybeNoLink", link: false, maybe: true),
            e("hidden", cal: "off"),
            e("plainAllDay", link: false, allDay: true),
        ]
        let f = EventFilter(showWithoutLink: false, showMaybe: false, disabledCalendarIDs: ["off"])
        XCTAssertEqual(f.apply(events).map(\.id), ["keep"])
    }

    func testFilterHidesAllDayWithoutLinkWhenLinksRequired() {
        let allDay = e("holiday", link: false, allDay: true)
        XCTAssertEqual(EventFilter(showWithoutLink: true).apply([allDay]).count, 1)
        XCTAssertEqual(EventFilter(showWithoutLink: false).apply([allDay]).count, 0)
    }

    func testFilterPreservesOrderAndHandlesEmpty() {
        XCTAssertEqual(EventFilter().apply([]).count, 0)
        XCTAssertEqual(EventFilter().apply([e("z"), e("a"), e("m")]).map(\.id), ["z", "a", "m"])
    }

    func testFilterEquatable() {
        XCTAssertEqual(EventFilter(), EventFilter())
        XCTAssertNotEqual(EventFilter(), EventFilter(showMaybe: false))
    }
}
