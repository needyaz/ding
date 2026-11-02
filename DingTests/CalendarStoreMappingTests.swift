import XCTest
import EventKit
import DingCore
@testable import Ding

final class CalendarStoreMappingTests: XCTestCase {
    private let store = EKEventStore()
    private lazy var calendar: EKCalendar = {
        let c = EKCalendar(for: .event, eventStore: store)
        c.title = "Work"
        c.color = NSColor(srgbRed: 1, green: 0, blue: 0, alpha: 1)
        return c
    }()

    private func makeEvent(
        title: String? = "Standup",
        start: Date = Date(timeIntervalSince1970: 1_800_000_000),
        minutes: Int = 30,
        allDay: Bool = false,
        location: String? = nil,
        notes: String? = nil,
        url: URL? = nil
    ) -> EKEvent {
        let event = EKEvent(eventStore: store)
        event.calendar = calendar
        event.title = title
        event.startDate = start
        event.endDate = start.addingTimeInterval(Double(minutes) * 60)
        event.isAllDay = allDay
        event.location = location
        event.notes = notes
        event.url = url
        return event
    }

    func testBasicFields() throws {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let mapped = try XCTUnwrap(CalendarStore.map(makeEvent(start: start)))
        XCTAssertEqual(mapped.title, "Standup")
        XCTAssertEqual(mapped.start, start)
        XCTAssertEqual(mapped.end, start.addingTimeInterval(1800))
        XCTAssertEqual(mapped.calendarTitle, "Work")
        XCTAssertFalse(mapped.isAllDay)
        XCTAssertEqual(mapped.response, .accepted)
        XCTAssertNil(mapped.link)
    }

    func testParticipantStatusMapsToTheResponse() {
        XCTAssertEqual(CalendarStore.response(for: .tentative), .maybe)
        XCTAssertEqual(CalendarStore.response(for: .pending), .notResponded)
        for status in [EKParticipantStatus.accepted, .delegated, .completed, .inProcess, .unknown] {
            XCTAssertEqual(CalendarStore.response(for: status), .accepted, "\(status.rawValue)")
        }
        XCTAssertEqual(CalendarStore.response(for: nil), .accepted, "an event with no attendee record is the user's own")
    }

    func testMissingOrEmptyTitleBecomesUntitled() throws {
        XCTAssertEqual(try XCTUnwrap(CalendarStore.map(makeEvent(title: nil))).title, "Untitled")
        XCTAssertEqual(try XCTUnwrap(CalendarStore.map(makeEvent(title: ""))).title, "Untitled")
    }

    func testAllDayFlag() throws {
        XCTAssertTrue(try XCTUnwrap(CalendarStore.map(makeEvent(allDay: true))).isAllDay)
    }

    func testIDIncludesTheOccurrenceStart() throws {
        let a = try XCTUnwrap(CalendarStore.map(makeEvent(start: Date(timeIntervalSince1970: 1_800_000_000))))
        let b = try XCTUnwrap(CalendarStore.map(makeEvent(start: Date(timeIntervalSince1970: 1_800_086_400))))
        XCTAssertTrue(a.id.hasSuffix("@1800000000"))
        XCTAssertTrue(b.id.hasSuffix("@1800086400"))
        XCTAssertNotEqual(a.id, b.id)
    }

    func testLinkFromLocation() throws {
        let mapped = try XCTUnwrap(CalendarStore.map(makeEvent(location: "https://acme.zoom.us/j/123")))
        XCTAssertEqual(mapped.link?.service, .zoom)
    }

    func testLinkFromURLField() throws {
        let mapped = try XCTUnwrap(CalendarStore.map(makeEvent(url: URL(string: "https://meet.google.com/abc-defg-hij"))))
        XCTAssertEqual(mapped.link?.service, .googleMeet)
    }

    func testLinkFromNotes() throws {
        let mapped = try XCTUnwrap(CalendarStore.map(makeEvent(notes: "Join: https://acme.webex.com/meet/nate")))
        XCTAssertEqual(mapped.link?.service, .webex)
    }

    func testLocationBeatsNotes() throws {
        let mapped = try XCTUnwrap(CalendarStore.map(makeEvent(location: "https://meet.google.com/abc-defg-hij", notes: "https://acme.zoom.us/j/1")))
        XCTAssertEqual(mapped.link?.service, .googleMeet)
    }

    func testCalendarColorIsConvertedToSRGB() throws {
        let color = try XCTUnwrap(CalendarStore.map(makeEvent())).calendarColor
        XCTAssertEqual(color.red, 1, accuracy: 0.01)
        XCTAssertEqual(color.green, 0, accuracy: 0.01)
        XCTAssertEqual(color.blue, 0, accuracy: 0.01)
    }

    func testGrayColorSpaceIsHandled() {
        let c = EKCalendar(for: .event, eventStore: store)
        c.color = NSColor(white: 0.5, alpha: 1)
        let color = CalendarStore.color(of: c)
        XCTAssertEqual(color.red, color.green, accuracy: 0.01)
    }

    func testMissingCalendarColorFallsBackToGray() {
        let c = EKCalendar(for: .event, eventStore: store)
        c.color = nil
        XCTAssertEqual(CalendarStore.color(of: c), .gray)
    }
}
