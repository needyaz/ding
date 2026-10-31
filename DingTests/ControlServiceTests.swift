import DingCore
import DingIPC
import XCTest
@testable import Ding

@MainActor
final class ControlServiceTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private var permissions = ControlPermissions(canReadSchedule: true, canOpenMeetings: true)
    private var access = CalendarAccess.granted
    private var events: [DingEvent] = []
    private var joined: [DingEvent] = []

    private lazy var service = ControlService(environment: .init(
        events: { [unowned self] in events },
        now: { [unowned self] in now },
        access: { [unowned self] in access },
        permissions: { [unowned self] in permissions },
        join: { [unowned self] in joined.append($0) },
        calendar: { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }
    ))

    private func meeting(_ id: String, in seconds: TimeInterval, minutes: Int = 30, link: Bool = true, allDay: Bool = false) -> DingEvent {
        let start = now.addingTimeInterval(seconds)
        return DingEvent(
            id: id, title: "Meeting \(id)", start: start, end: start.addingTimeInterval(Double(minutes) * 60), isAllDay: allDay,
            calendarTitle: "Work",
            link: link ? MeetingLink(service: .zoom, url: URL(string: "https://acme.zoom.us/j/123?pwd=SECRETPASSCODE")!) : nil
        )
    }

    private func request(_ method: String, _ params: [String: JSONValue] = [:]) -> ControlResponse {
        service.handle(ControlRequest(method: method, params: params))
    }

    private func errorCode(_ response: ControlResponse) -> String? { response.error?.code }

    // MARK: Permissions

    func testNothingIsAllowedByDefault() {
        permissions = ControlPermissions()
        events = [meeting("a", in: 600)]
        XCTAssertEqual(errorCode(request("get_next_meeting")), "schedule_access_off")
        XCTAssertEqual(errorCode(request("list_meetings")), "schedule_access_off")
        XCTAssertEqual(errorCode(request("open_meeting")), "opening_off")
        XCTAssertTrue(joined.isEmpty)
    }

    func testReadingAndJoiningAreSeparatePermissions() {
        events = [meeting("a", in: 600)]
        permissions = ControlPermissions(canReadSchedule: true, canOpenMeetings: false)
        XCTAssertTrue(request("get_next_meeting").ok)
        XCTAssertEqual(errorCode(request("open_meeting")), "opening_off")
        permissions = ControlPermissions(canReadSchedule: false, canOpenMeetings: true)
        XCTAssertEqual(errorCode(request("get_next_meeting")), "schedule_access_off")
        XCTAssertTrue(request("open_meeting").ok)
    }

    func testTurningAPermissionOffTakesEffectOnTheNextRequest() {
        events = [meeting("a", in: 600)]
        XCTAssertTrue(request("get_next_meeting").ok)
        permissions.canReadSchedule = false
        XCTAssertFalse(request("get_next_meeting").ok)
    }

    func testPermissionIsCheckedBeforeAnythingElse() {
        // A refused request must reveal nothing about the calendar, not even whether access exists.
        permissions = ControlPermissions()
        access = .denied
        XCTAssertEqual(errorCode(request("get_next_meeting")), "schedule_access_off")
        XCTAssertEqual(errorCode(request("open_meeting", ["id": .string("anything")])), "opening_off")
    }

    func testWithoutCalendarAccessThereIsNothingToShow() {
        access = .denied
        XCTAssertEqual(errorCode(request("get_next_meeting")), "no_calendar_access")
        access = .notDetermined
        XCTAssertEqual(errorCode(request("list_meetings")), "no_calendar_access")
        XCTAssertEqual(errorCode(request("open_meeting")), "no_calendar_access")
    }

    func testUnknownMethodsAreRefused() {
        XCTAssertEqual(errorCode(request("delete_all_events")), "unknown_method")
        XCTAssertEqual(errorCode(request("")), "unknown_method")
        XCTAssertEqual(errorCode(request("GET_NEXT_MEETING")), "unknown_method")
    }

    // MARK: Next meeting

    func testNextMeeting() throws {
        events = [meeting("later", in: 7200), meeting("soon", in: 600)]
        let response = request("get_next_meeting")
        let meeting = try XCTUnwrap(response.result?.objectValue?["meeting"]?.objectValue)
        XCTAssertEqual(meeting["id"]?.stringValue, "soon")
        XCTAssertEqual(meeting["minutes_until_start"]?.intValue, 10)
        XCTAssertEqual(meeting["service"]?.stringValue, "Zoom")
        XCTAssertEqual(meeting["can_open"]?.boolValue, true)
        XCTAssertEqual(meeting["calendar"]?.stringValue, "Work")
    }

    func testNoUpcomingMeetingIsANullNotAnError() {
        events = []
        let response = request("get_next_meeting")
        XCTAssertTrue(response.ok)
        XCTAssertEqual(response.result?.objectValue?["meeting"], .null)
    }

    // MARK: List

    func testListDefaultsToTheRestOfToday() throws {
        events = [meeting("a", in: 600), meeting("tomorrow", in: 86_400 * 2)]
        let list = try XCTUnwrap(request("list_meetings").result?.objectValue)
        XCTAssertEqual(list["meetings"]?.arrayValueIDs, ["a"])
        XCTAssertEqual(list["truncated"]?.boolValue, false)
    }

    func testListAcceptsDaysAndAllDay() throws {
        events = [meeting("a", in: 600), meeting("later", in: 86_400 * 2), meeting("holiday", in: 0, minutes: 1440, link: false, allDay: true)]
        let wide = try XCTUnwrap(request("list_meetings", ["days": .int(5), "include_all_day": .bool(true)]).result?.objectValue)
        XCTAssertEqual(Set(wide["meetings"]?.arrayValueIDs ?? []), ["a", "later", "holiday"])
        let narrow = try XCTUnwrap(request("list_meetings", ["days": .int(5)]).result?.objectValue)
        XCTAssertEqual(Set(narrow["meetings"]?.arrayValueIDs ?? []), ["a", "later"])
    }

    func testBadListArgumentsAreRefused() {
        XCTAssertEqual(errorCode(request("list_meetings", ["days": .int(0)])), "invalid_argument")
        XCTAssertEqual(errorCode(request("list_meetings", ["days": .int(99)])), "invalid_argument")
        XCTAssertEqual(errorCode(request("list_meetings", ["days": .string("3")])), "invalid_argument")
        XCTAssertEqual(errorCode(request("list_meetings", ["include_all_day": .string("yes")])), "invalid_argument")
    }

    // MARK: Join

    func testJoinWithoutAnIDJoinsTheNextLinkedMeeting() throws {
        events = [meeting("plain", in: 300, link: false), meeting("linked", in: 900)]
        let response = request("open_meeting")
        XCTAssertTrue(response.ok)
        XCTAssertEqual(joined.map(\.id), ["linked"])
        XCTAssertEqual(response.result?.objectValue?["opened"]?.boolValue, true)
        XCTAssertEqual(response.result?.objectValue?["meeting"]?.objectValue?["id"]?.stringValue, "linked")
    }

    func testJoiningWithoutScheduleAccessConfirmsWithoutSayingWhichMeeting() throws {
        permissions = ControlPermissions(canReadSchedule: false, canOpenMeetings: true)
        events = [meeting("secret", in: 600)]
        let response = request("open_meeting")
        XCTAssertTrue(response.ok)
        XCTAssertEqual(joined.map(\.id), ["secret"], "it still joins")
        XCTAssertEqual(response.result, .object(["opened": .bool(true)]))
        let json = String(decoding: try JSONEncoder().encode(response), as: UTF8.self)
        XCTAssertFalse(json.contains("Meeting secret"), "the title must not leak")
        XCTAssertFalse(json.contains("Work"), "nor the calendar")
    }

    func testJoiningWithScheduleAccessAlsoReportsTheMeeting() {
        permissions = ControlPermissions(canReadSchedule: true, canOpenMeetings: true)
        events = [meeting("a", in: 600)]
        XCTAssertNotNil(request("open_meeting").result?.objectValue?["meeting"])
    }

    func testJoinByID() {
        events = [meeting("a", in: 600), meeting("b", in: 1200)]
        XCTAssertTrue(request("open_meeting", ["id": .string("b")]).ok)
        XCTAssertEqual(joined.map(\.id), ["b"])
    }

    func testJoinFailuresDoNotJoinAnything() {
        events = [meeting("plain", in: 600, link: false)]
        XCTAssertEqual(errorCode(request("open_meeting", ["id": .string("ghost")])), "meeting_not_found")
        XCTAssertEqual(errorCode(request("open_meeting", ["id": .string("plain")])), "cannot_open")
        XCTAssertEqual(errorCode(request("open_meeting")), "nothing_to_open")
        XCTAssertEqual(errorCode(request("open_meeting", ["id": .int(5)])), "invalid_argument")
        XCTAssertEqual(errorCode(request("open_meeting", ["id": .string("")])), "invalid_argument")
        XCTAssertTrue(joined.isEmpty)
    }

    func testJoiningOpensTheLinkInDingNotInTheReply() throws {
        events = [meeting("a", in: 600)]
        _ = request("open_meeting")
        XCTAssertEqual(joined.first?.link?.url.absoluteString, "https://acme.zoom.us/j/123?pwd=SECRETPASSCODE", "Ding opens the real link itself")
    }

    // MARK: Privacy

    func testNoResponseEverContainsALinkOrItsPasscode() throws {
        events = [meeting("a", in: 600), meeting("b", in: 1200)]
        let requests = [
            ControlRequest(method: "get_next_meeting"), ControlRequest(method: "list_meetings", params: ["days": .int(7)]),
            ControlRequest(method: "open_meeting"), ControlRequest(method: "open_meeting", params: ["id": .string("b")]),
        ]
        for request in requests {
            let json = String(decoding: try JSONEncoder().encode(service.handle(request)), as: UTF8.self)
            XCTAssertFalse(json.contains("SECRETPASSCODE"), request.method)
            XCTAssertFalse(json.contains("zoom.us"), request.method)
            XCTAssertFalse(json.contains("http"), request.method)
        }
    }

    func testTheSelectionTheUserMadeIsWhatAssistantsSee() {
        // The environment hands over only the visible events; a hidden calendar's meetings never reach the service.
        events = []
        XCTAssertEqual(request("list_meetings").result?.objectValue?["meetings"]?.arrayValueIDs, [])
        XCTAssertNil(request("get_next_meeting").result?.objectValue?["meeting"]?.objectValue)
    }
}

private extension JSONValue {
    /// The `id` of each object in an array value.
    var arrayValueIDs: [String]? {
        guard case .array(let items) = self else { return nil }
        return items.compactMap { $0.objectValue?["id"]?.stringValue }
    }
}
