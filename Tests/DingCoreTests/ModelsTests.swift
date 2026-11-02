import XCTest
@testable import DingCore

/// Value types: services, links, colors and events.
final class ModelsTests: XCTestCase {
    func testServiceDisplayNames() {
        XCTAssertEqual(MeetingService.zoom.displayName, "Zoom")
        XCTAssertEqual(MeetingService.googleMeet.displayName, "Google Meet")
        XCTAssertEqual(MeetingService.teams.displayName, "Microsoft Teams")
        XCTAssertEqual(MeetingService.webex.displayName, "Webex")
        XCTAssertEqual(MeetingService.other.displayName, "Other link")
    }

    func testDetectableExcludesOther() {
        XCTAssertEqual(Set(MeetingService.detectable), [.zoom, .googleMeet, .teams, .webex])
    }

    func testEveryDetectableServiceHasAPatternRow() {
        let covered = Set(LinkPatterns.table.map(\.service))
        XCTAssertEqual(covered, Set(MeetingService.detectable))
    }

    func testNativeSupport() {
        XCTAssertEqual(MeetingService.allCases.filter(\.supportsNativeApp).count, 3)
        XCTAssertFalse(MeetingService.googleMeet.supportsNativeApp)
        XCTAssertFalse(MeetingService.other.supportsNativeApp)
    }

    func testServiceIDAndCodableRoundTrip() throws {
        for service in MeetingService.allCases {
            XCTAssertEqual(service.id, service.rawValue)
            let data = try JSONEncoder().encode(service)
            XCTAssertEqual(try JSONDecoder().decode(MeetingService.self, from: data), service)
        }
        XCTAssertNotNil(MeetingService(rawValue: "googleMeet"))
        XCTAssertNil(MeetingService(rawValue: "skype"))
    }

    func testEventDefaults() {
        let e = DingEvent(id: "x", title: "T", start: Date(), end: Date())
        XCTAssertFalse(e.hasLink)
        XCTAssertFalse(e.isAllDay)
        XCTAssertEqual(e.response, .accepted)
        XCTAssertEqual(e.calendarColor, .gray)
        XCTAssertEqual(e.calendarID, "")
    }

    func testEventHasLink() {
        var e = DingEvent(id: "x", title: "T", start: Date(), end: Date())
        e.link = MeetingLink(service: .zoom, url: URL(string: "https://zoom.us/j/1")!)
        XCTAssertTrue(e.hasLink)
    }

    func testLinkEqualityAndHashing() {
        let a = MeetingLink(service: .zoom, url: URL(string: "https://zoom.us/j/1")!)
        let b = MeetingLink(service: .zoom, url: URL(string: "https://zoom.us/j/1")!)
        let c = MeetingLink(service: .webex, url: URL(string: "https://zoom.us/j/1")!)
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
        XCTAssertEqual(Set([a, b, c]).count, 2)
    }

    func testCalendarColor() {
        let c = CalendarColor(red: 0.1, green: 0.2, blue: 0.3)
        XCTAssertEqual(c.red, 0.1)
        XCTAssertEqual(c.green, 0.2)
        XCTAssertEqual(c.blue, 0.3)
        XCTAssertNotEqual(c, .gray)
    }

    func testOnlyAcceptedIsConfirmed() {
        XCTAssertFalse(ResponseStatus.accepted.isUnconfirmed)
        XCTAssertTrue(ResponseStatus.maybe.isUnconfirmed)
        XCTAssertTrue(ResponseStatus.notResponded.isUnconfirmed)
        XCTAssertEqual([ResponseStatus.accepted, .maybe, .notResponded].map(\.label), [nil, "Maybe", "Not responded"])
    }
}
