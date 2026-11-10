import XCTest
import DingCore
import DingIPC
@testable import Ding

/// What assistants see through the control service is what the user's calendar selection and dropdown filters leave.
@MainActor
final class AssistantVisibilityTests: IsolatedDefaultsTestCase {
    private var calendar: FakeCalendar!
    private var model: AppModel!
    private var now = Date()

    override func setUp() {
        super.setUp()
        MainActor.assumeIsolated {
            now = Date()
            calendar = FakeCalendar()
            model = AppModel.test(calendar: calendar)
        }
    }

    override func tearDown() {
        MainActor.assumeIsolated {
            model = nil
            calendar = nil
        }
        super.tearDown()
    }

    /// The service the app itself starts, with the permissions the user would have switched on.
    private func service() -> ControlService {
        suite.set(true, forKey: Pref.controlReadSchedule)
        suite.set(true, forKey: Pref.controlOpenMeetings)
        return model.makeControlService()
    }

    private func load(_ events: [DingEvent]) {
        calendar.stubEvents = events
        model.reload()
    }

    private func listedIDs(_ service: ControlService) throws -> [String] {
        let response = service.handle(ControlRequest(method: "list_meetings", params: ["days": .int(7)]))
        XCTAssertTrue(response.ok, "list_meetings succeeds")
        guard case .array(let items) = try XCTUnwrap(response.result?.objectValue?["meetings"]) else {
            XCTFail("meetings is an array"); return []
        }
        return items.compactMap { $0.objectValue?["id"]?.stringValue }
    }

    private func nextID(_ service: ControlService) -> String? {
        service.handle(ControlRequest(method: "get_next_meeting")).result?.objectValue?["meeting"]?.objectValue?["id"]?.stringValue
    }

    func test_DING_CTRL_016_keeps_onlyTheSelectedAndFilteredEventsReachAssistants() throws {
        Pref.disabledCalendars = ["hidden"]
        suite.set(false, forKey: Pref.showEventsWithoutLink)
        suite.set(false, forKey: Pref.showMaybe)
        // Every excluded event starts before the visible one, so a leak would also become the next meeting.
        load([
            .test("visible", startingIn: 3600, from: now, calendarID: "work"),
            .test("inHiddenCalendar", startingIn: 600, from: now, calendarID: "hidden"),
            .test("withoutLink", startingIn: 900, from: now, link: false, calendarID: "work"),
            .test("unconfirmed", startingIn: 1200, from: now, response: .maybe, calendarID: "work"),
        ])
        let service = service()

        XCTAssertEqual(try listedIDs(service), ["visible"], "DING-CTRL-016: list_meetings holds only the visible event")
        XCTAssertEqual(nextID(service), "visible", "DING-CTRL-016: get_next_meeting never returns an excluded event")
        for id in ["inHiddenCalendar", "withoutLink", "unconfirmed"] {
            let response = service.handle(ControlRequest(method: "open_meeting", params: ["id": .string(id)]))
            XCTAssertEqual(response.error?.code, "meeting_not_found", "DING-CTRL-016: \(id) cannot be opened by id")
        }
    }

    func test_DING_CTRL_016_keeps_eachExcludedKindAppearsOnceItsToggleAllowsIt() throws {
        Pref.disabledCalendars = ["hidden"]
        suite.set(false, forKey: Pref.showEventsWithoutLink)
        suite.set(false, forKey: Pref.showMaybe)
        load([
            .test("visible", startingIn: 3600, from: now, calendarID: "work"),
            .test("inHiddenCalendar", startingIn: 600, from: now, calendarID: "hidden"),
            .test("withoutLink", startingIn: 900, from: now, link: false, calendarID: "work"),
            .test("unconfirmed", startingIn: 1200, from: now, response: .notResponded, calendarID: "work"),
        ])
        let service = service()
        XCTAssertEqual(Set(try listedIDs(service)), ["visible"], "DING-CTRL-016")

        suite.set(true, forKey: Pref.showEventsWithoutLink)
        XCTAssertEqual(Set(try listedIDs(service)), ["visible", "withoutLink"], "DING-CTRL-016: the linkless switch lets that event through")

        suite.set(true, forKey: Pref.showMaybe)
        XCTAssertEqual(Set(try listedIDs(service)), ["visible", "withoutLink", "unconfirmed"], "DING-CTRL-016: the unconfirmed switch lets that event through")

        Pref.disabledCalendars = []
        XCTAssertEqual(
            Set(try listedIDs(service)), ["visible", "withoutLink", "unconfirmed", "inHiddenCalendar"],
            "DING-CTRL-016: selecting the calendar again lets its event through"
        )
        XCTAssertEqual(nextID(service), "inHiddenCalendar", "DING-CTRL-016: and it can then be the next meeting")
    }
}
