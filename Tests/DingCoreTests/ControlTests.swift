import XCTest
@testable import DingCore

final class ControlAPITests: DingCoreTestCase {
    private var la: TimeZone { calendar.timeZone }

    private func meeting(_ id: String, _ start: Date, minutes: Int = 30, link: MeetingService? = .zoom, allDay: Bool = false, maybe: Bool = false) -> DingEvent {
        var e = event(id, start, minutes: minutes, link: link, allDay: allDay, maybe: maybe)
        e.calendarTitle = "Work"
        return e
    }

    // MARK: Summary

    func testSummaryFieldsForAnUpcomingMeeting() {
        let now = date(2026, 10, 31, 9, 0)
        let s = ControlAPI.summary(of: meeting("a", date(2026, 10, 31, 9, 12)), now: now, timeZone: la)
        XCTAssertEqual(s.id, "a")
        XCTAssertEqual(s.title, "a")
        XCTAssertEqual(s.start, "2026-10-31T09:12:00-07:00")
        XCTAssertEqual(s.end, "2026-10-31T09:42:00-07:00")
        XCTAssertEqual(s.minutesUntilStart, 12)
        XCTAssertFalse(s.isInProgress)
        XCTAssertEqual(s.calendar, "Work")
        XCTAssertEqual(s.service, "Zoom")
        XCTAssertTrue(s.canOpen)
        XCTAssertFalse(s.isTentative)
    }

    func testTimesCarryTheLocalOffsetAcrossDST() {
        // US DST ended 2026-11-01: the same wall-clock hour has a different offset the next day.
        let before = ControlAPI.summary(of: meeting("a", date(2026, 10, 31, 12)), now: date(2026, 10, 31), timeZone: la)
        let after = ControlAPI.summary(of: meeting("b", date(2026, 11, 2, 12)), now: date(2026, 10, 31), timeZone: la)
        XCTAssertTrue(before.start.hasSuffix("-07:00"))
        XCTAssertTrue(after.start.hasSuffix("-08:00"))
    }

    func testMinutesUntilStartRoundsUpAndDisappearsOnceStarted() {
        let start = date(2026, 10, 31, 10)
        XCTAssertEqual(ControlAPI.summary(of: meeting("a", start), now: start.addingTimeInterval(-61), timeZone: la).minutesUntilStart, 2)
        XCTAssertEqual(ControlAPI.summary(of: meeting("a", start), now: start.addingTimeInterval(-1), timeZone: la).minutesUntilStart, 1)
        XCTAssertNil(ControlAPI.summary(of: meeting("a", start), now: start, timeZone: la).minutesUntilStart)
    }

    func testInProgressMeansStartedAndNotEnded() {
        let start = date(2026, 10, 31, 10)
        XCTAssertTrue(ControlAPI.summary(of: meeting("a", start), now: start.addingTimeInterval(600), timeZone: la).isInProgress)
        XCTAssertFalse(ControlAPI.summary(of: meeting("a", start), now: start.addingTimeInterval(3600), timeZone: la).isInProgress)
        XCTAssertFalse(ControlAPI.summary(of: meeting("a", start, allDay: true), now: start.addingTimeInterval(600), timeZone: la).isInProgress)
    }

    func testNoLinkMeansNoServiceAndCannotJoin() {
        let s = ControlAPI.summary(of: meeting("a", date(2026, 10, 31, 10), link: nil), now: date(2026, 10, 31), timeZone: la)
        XCTAssertNil(s.service)
        XCTAssertFalse(s.canOpen)
    }

    func testTentativeAndAllDayAreReported() {
        let s = ControlAPI.summary(of: meeting("a", date(2026, 10, 31), minutes: 1440, link: nil, allDay: true, maybe: true), now: date(2026, 10, 31, 9), timeZone: la)
        XCTAssertTrue(s.isTentative)
        XCTAssertTrue(s.isAllDay)
    }

    // MARK: Privacy

    func testASummaryCannotCarryNotesAttendeesLocationsOrLinks() throws {
        let linked = DingEvent(
            id: "x", title: "Secret project", start: date(2026, 10, 31, 10), end: date(2026, 10, 31, 11),
            link: MeetingLink(service: .zoom, url: URL(string: "https://acme.zoom.us/j/123?pwd=SECRETPASSCODE")!)
        )
        let data = try JSONEncoder().encode(ControlAPI.summary(of: linked, now: date(2026, 10, 31), timeZone: la))
        let json = String(decoding: data, as: UTF8.self)
        XCTAssertFalse(json.contains("SECRETPASSCODE"))
        XCTAssertFalse(json.contains("zoom.us"))
        XCTAssertFalse(json.contains("https"))
        let keys = Set((try JSONSerialization.jsonObject(with: data) as! [String: Any]).keys)
        XCTAssertEqual(keys, ["id", "title", "start", "end", "is_all_day", "is_in_progress", "minutes_until_start", "calendar", "service", "can_open", "is_tentative"])
        XCTAssertFalse(keys.contains("notes"))
        XCTAssertFalse(keys.contains("url"))
        XCTAssertFalse(keys.contains("location"))
        XCTAssertFalse(keys.contains("attendees"))
    }

    func testInapplicableFieldsAreExplicitNullsSoTheShapeNeverChanges() throws {
        let started = ControlAPI.summary(of: meeting("a", date(2026, 10, 31, 10), link: nil), now: date(2026, 10, 31, 10, 30), timeZone: la)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(started)) as? [String: Any])
        XCTAssertEqual(object.count, 11)
        XCTAssertTrue(object["minutes_until_start"] is NSNull, "a meeting that has started has no minutes until start")
        XCTAssertTrue(object["service"] is NSNull, "a meeting without a link has no service")
    }

    func testTheEncodedSummaryDecodesBack() throws {
        let original = ControlAPI.summary(of: meeting("a", date(2026, 10, 31, 10), link: nil), now: date(2026, 10, 31, 10, 30), timeZone: la)
        let decoded = try JSONDecoder().decode(MeetingSummary.self, from: JSONEncoder().encode(original))
        XCTAssertEqual(decoded, original)
    }

    func testJSONKeysAreSnakeCase() throws {
        let data = try JSONEncoder().encode(ControlAPI.summary(of: meeting("a", date(2026, 10, 31, 10)), now: date(2026, 10, 31), timeZone: la))
        let json = String(decoding: data, as: UTF8.self)
        for key in ["is_all_day", "is_in_progress", "minutes_until_start", "can_open", "is_tentative"] {
            XCTAssertTrue(json.contains("\"\(key)\""), key)
        }
    }

    // MARK: Next meeting

    func testNextMeetingMatchesTheMenuBar() {
        let now = date(2026, 10, 31, 9, 0)
        let events = [meeting("later", date(2026, 10, 31, 11)), meeting("soon", date(2026, 10, 31, 9, 30)), meeting("holiday", date(2026, 10, 31), minutes: 1440, link: nil, allDay: true)]
        XCTAssertEqual(ControlAPI.nextMeeting(events, now: now, timeZone: la)?.id, "soon")
        XCTAssertNil(ControlAPI.nextMeeting([], now: now, timeZone: la))
    }

    // MARK: Upcoming

    func testUpcomingIsSortedAndSkipsFinishedAndAllDayByDefault() throws {
        let now = date(2026, 10, 31, 12)
        let events = [
            meeting("b", date(2026, 10, 31, 15)), meeting("done", date(2026, 10, 31, 9)),
            meeting("a", date(2026, 10, 31, 13)), meeting("holiday", date(2026, 10, 31), minutes: 1440, link: nil, allDay: true),
        ]
        let list = try ControlAPI.upcoming(events, now: now, days: 1, includeAllDay: false, calendar: calendar)
        XCTAssertEqual(list.meetings.map(\.id), ["a", "b"])
        XCTAssertFalse(list.truncated)
        XCTAssertEqual(try ControlAPI.upcoming(events, now: now, days: 1, includeAllDay: true, calendar: calendar).meetings.map(\.id), ["holiday", "a", "b"])
    }

    func testUpcomingRangeIsCalendarDays() throws {
        let now = date(2026, 10, 31, 22)
        let events = [meeting("tonight", date(2026, 10, 31, 23)), meeting("tomorrow", date(2026, 11, 1, 9)), meeting("dayAfter", date(2026, 11, 2, 9))]
        XCTAssertEqual(try ControlAPI.upcoming(events, now: now, days: 1, includeAllDay: false, calendar: calendar).meetings.map(\.id), ["tonight"])
        XCTAssertEqual(try ControlAPI.upcoming(events, now: now, days: 2, includeAllDay: false, calendar: calendar).meetings.map(\.id), ["tonight", "tomorrow"])
    }

    func testUpcomingValidatesDays() {
        for days in [0, -1, 15, 100] {
            XCTAssertThrowsError(try ControlAPI.upcoming([], now: Date(), days: days, includeAllDay: false, calendar: calendar), "\(days)") { error in
                XCTAssertEqual((error as? ControlFailure)?.code, "invalid_argument")
            }
        }
        XCTAssertNoThrow(try ControlAPI.upcoming([], now: Date(), days: 14, includeAllDay: false, calendar: calendar))
    }

    func testUpcomingIsCappedAndSaysSo() throws {
        let now = date(2026, 10, 31, 0, 1)
        let events = (0..<60).map { meeting("m\($0)", now.addingTimeInterval(Double($0 + 1) * 60 + 3600)) }
        let list = try ControlAPI.upcoming(events, now: now, days: 14, includeAllDay: false, calendar: calendar)
        XCTAssertEqual(list.meetings.count, ControlAPI.maxMeetings)
        XCTAssertTrue(list.truncated)
        XCTAssertEqual(list.meetings.first?.id, "m0")
    }

    // MARK: Join target

    func testJoinWithoutAnIDPicksTheNextLinkedMeeting() throws {
        let now = date(2026, 10, 31, 9)
        let events = [meeting("plain", date(2026, 10, 31, 9, 10), link: nil), meeting("linked", date(2026, 10, 31, 10))]
        XCTAssertEqual(try ControlAPI.openTarget(events, now: now, id: nil).id, "linked")
    }

    func testJoinByID() throws {
        let now = date(2026, 10, 31, 9)
        let events = [meeting("a", date(2026, 10, 31, 10)), meeting("b", date(2026, 10, 31, 11))]
        XCTAssertEqual(try ControlAPI.openTarget(events, now: now, id: "b").id, "b")
    }

    func testJoinByIDFailsForUnknownFinishedOrLinklessMeetings() {
        let now = date(2026, 10, 31, 12)
        let events = [meeting("done", date(2026, 10, 31, 9)), meeting("plain", date(2026, 10, 31, 13), link: nil)]
        XCTAssertThrowsError(try ControlAPI.openTarget(events, now: now, id: "ghost")) { XCTAssertEqual($0 as? ControlFailure, .meetingNotFound("ghost")) }
        XCTAssertThrowsError(try ControlAPI.openTarget(events, now: now, id: "done")) { XCTAssertEqual($0 as? ControlFailure, .meetingNotFound("done")) }
        XCTAssertThrowsError(try ControlAPI.openTarget(events, now: now, id: "plain")) { XCTAssertEqual($0 as? ControlFailure, .cannotOpen) }
    }

    func testAssistantsOnlyOpenKnownServices() throws {
        let now = date(2026, 10, 31, 9)
        let events = [meeting("web", date(2026, 10, 31, 9, 30), link: .other), meeting("zoom", date(2026, 10, 31, 10))]
        XCTAssertFalse(ControlAPI.summary(of: events[0], now: now, timeZone: la).canOpen, "an arbitrary link is not offered")
        XCTAssertTrue(ControlAPI.summary(of: events[1], now: now, timeZone: la).canOpen)
        XCTAssertThrowsError(try ControlAPI.openTarget(events, now: now, id: "web")) { XCTAssertEqual($0 as? ControlFailure, .cannotOpen) }
        XCTAssertEqual(try ControlAPI.openTarget(events, now: now, id: nil).id, "zoom", "with no id it skips the arbitrary link")
    }

    func testJoinWithNothingToJoin() {
        XCTAssertThrowsError(try ControlAPI.openTarget([], now: Date(), id: nil)) { XCTAssertEqual($0 as? ControlFailure, .nothingToOpen) }
    }

    // MARK: Failures

    func testEveryFailureHasACodeAndAReadableMessage() {
        let failures: [ControlFailure] = [.scheduleAccessOff, .openingOff, .noCalendarAccess, .meetingNotFound("x"), .nothingToOpen, .cannotOpen, .invalidArgument("bad"), .tooFast]
        XCTAssertEqual(Set(failures.map(\.code)).count, failures.count, "codes must be distinct")
        for failure in failures {
            XCTAssertFalse(failure.message.isEmpty)
            XCTAssertFalse(failure.code.contains(" "))
        }
        XCTAssertTrue(ControlFailure.scheduleAccessOff.message.contains("Preferences"))
        XCTAssertTrue(ControlFailure.openingOff.message.contains("Preferences"))
    }

    func testPermissionsDefaultToOff() {
        XCTAssertEqual(ControlPermissions(), ControlPermissions(canReadSchedule: false, canOpenMeetings: false))
    }
}

final class MCPConfigTests: XCTestCase {
    private let helper = "/Applications/Ding.app/Contents/Helpers/ding-mcp"

    private func parse(_ text: String) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any], text)
    }

    private func command(in object: [String: Any]) -> String? {
        ((object["mcpServers"] as? [String: Any])?["ding"] as? [String: Any])?["command"] as? String
    }

    func testTheEntryHasNoOuterBraces() {
        let entry = MCPConfig.desktopEntry(command: helper)
        XCTAssertTrue(entry.hasPrefix("  \"mcpServers\""), entry)
        XCTAssertFalse(entry.hasPrefix("{"))
        XCTAssertFalse(entry.trimmingCharacters(in: .whitespacesAndNewlines).hasSuffix("}\n}"))
        XCTAssertTrue(entry.contains(helper), "slashes aren't escaped")
    }

    func testTheEntryIsAValidObjectOnceWrappedInBraces() throws {
        // How it parses on its own: as the contents of an object.
        XCTAssertEqual(command(in: try parse("{\n\(MCPConfig.desktopEntry(command: helper))\n}")), helper)
    }

    func testPastedIntoABlankConfig() throws {
        // A fresh install: the file is just `{}`. Paste between the braces, no comma needed.
        let file = "{\n\(MCPConfig.desktopEntry(command: helper))\n}\n"
        XCTAssertEqual(command(in: try parse(file)), helper)
    }

    func testPastedIntoAConfigThatAlreadyHasSettings() throws {
        // What Claude Desktop writes today: other top-level keys. Paste before the final brace, comma after the last entry.
        let existing = """
        {
          "coworkUserFilesPath": "/Users/me/Claude",
          "preferences": {
            "sidebarMode": "chat",
            "nested": { "list": [1, 2, 3] }
          }
        """
        let file = existing + ",\n" + MCPConfig.desktopEntry(command: helper) + "\n}\n"
        let object = try parse(file)
        XCTAssertEqual(command(in: object), helper)
        XCTAssertEqual(object["coworkUserFilesPath"] as? String, "/Users/me/Claude", "existing settings are untouched")
        XCTAssertNotNil(object["preferences"])
    }

    func testAddedToAConfigThatAlreadyHasOtherMCPServersIsNotCovered() throws {
        // Documented limit: the entry always starts a new "mcpServers" key. Pasting it beside an existing "mcpServers"
        // would repeat the key, so the footer in Preferences says to merge by hand in that case.
        let entry = MCPConfig.desktopEntry(command: helper)
        XCTAssertEqual(entry.components(separatedBy: "\"mcpServers\"").count - 1, 1)
    }

    func testTheWholeDocumentFormIsGone() {
        // The old shape (a complete document) broke real files; make sure nothing offers it again.
        XCTAssertFalse(MCPConfig.desktopEntry(command: helper).hasPrefix("{"))
    }

    func testAwkwardPathsAreEscaped() throws {
        let path = #"/Users/o"brien/My Apps/Ding.app/Contents/Helpers/ding-mcp"#
        XCTAssertEqual(command(in: try parse("{\n\(MCPConfig.desktopEntry(command: path))\n}")), path)
        let backslash = #"/Users/a\b/ding-mcp"#
        XCTAssertEqual(command(in: try parse("{\n\(MCPConfig.desktopEntry(command: backslash))\n}")), backslash)
    }

    func testClaudeCodeCommandLeavesPlainPathsAlone() {
        XCTAssertEqual(MCPConfig.claudeCodeCommand(command: "/Applications/Ding.app/Contents/Helpers/ding-mcp"),
                       "claude mcp add ding -- /Applications/Ding.app/Contents/Helpers/ding-mcp")
    }

    func testClaudeCodeCommandQuotesSpacesAndQuotes() {
        XCTAssertEqual(MCPConfig.claudeCodeCommand(command: "/Users/me/My Apps/Ding.app/ding-mcp"),
                       "claude mcp add ding -- '/Users/me/My Apps/Ding.app/ding-mcp'")
        XCTAssertEqual(MCPConfig.shellQuoted("it's"), #"'it'\''s'"#)
        XCTAssertEqual(MCPConfig.shellQuoted(""), "''")
        XCTAssertEqual(MCPConfig.shellQuoted("a;b"), "'a;b'")
        XCTAssertEqual(MCPConfig.shellQuoted("$(rm -rf)"), "'$(rm -rf)'")
    }
}
