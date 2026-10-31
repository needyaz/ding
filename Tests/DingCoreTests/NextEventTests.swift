import XCTest
@testable import DingCore

/// Which meeting counts as "next" in the menu bar.
final class NextEventTests: DingCoreTestCase {
    func testNextEventSkipsAllDayAndEnded() {
        let now = date(2026, 10, 30, 9, 0)
        let events = [
            event("allday", date(2026, 10, 30), minutes: 1440, allDay: true),
            event("done", date(2026, 10, 30, 8, 0), minutes: 30),
            event("later", date(2026, 10, 30, 11, 0)),
            event("soon", date(2026, 10, 30, 9, 30)),
        ]
        XCTAssertEqual(NextEvent.select(from: events, now: now)?.id, "soon")
    }

    func testNextEventGraceKeepsJustStartedMeeting() {
        let events = [event("a", date(2026, 10, 30, 9, 0), minutes: 60), event("b", date(2026, 10, 30, 10, 0))]
        XCTAssertEqual(NextEvent.select(from: events, now: date(2026, 10, 30, 9, 4))?.id, "a")
        XCTAssertEqual(NextEvent.select(from: events, now: date(2026, 10, 30, 9, 6))?.id, "b")
    }

    func testNextEventGraceDoesNotOutliveShortEvent() {
        let events = [event("short", date(2026, 10, 30, 9, 0), minutes: 2), event("b", date(2026, 10, 30, 10, 0))]
        XCTAssertEqual(NextEvent.select(from: events, now: date(2026, 10, 30, 9, 3))?.id, "b")
    }

    func testNextEventNilWhenNothingLeft() {
        XCTAssertNil(NextEvent.select(from: [], now: Date()))
    }
}

/// Which meeting the "join next" hotkey opens.
final class JoinSelectionTests: DingCoreTestCase {
    func testJoinCandidateSkipsEventsWithoutLinks() {
        let now = date(2026, 10, 30, 9)
        let events = [event("plain", date(2026, 10, 30, 9, 30), link: nil), event("linked", date(2026, 10, 30, 10))]
        XCTAssertEqual(JoinSelection.candidate(from: events, now: now)?.id, "linked")
    }

    func testJoinCandidateIncludesRecentlyStartedMeeting() {
        let events = [event("a", date(2026, 10, 30, 9), minutes: 60), event("b", date(2026, 10, 30, 11))]
        XCTAssertEqual(JoinSelection.candidate(from: events, now: date(2026, 10, 30, 9, 10))?.id, "a")
    }

    func testJoinCandidateGivesUpOnMeetingsStartedLongAgo() {
        let events = [event("a", date(2026, 10, 30, 9), minutes: 120), event("b", date(2026, 10, 30, 11))]
        XCTAssertEqual(JoinSelection.candidate(from: events, now: date(2026, 10, 30, 9, 20))?.id, "b")
    }

    func testJoinCandidateNilWithNothingToJoin() {
        XCTAssertNil(JoinSelection.candidate(from: [], now: Date()))
        XCTAssertNil(JoinSelection.candidate(from: [event("a", date(2026, 10, 30, 10), link: nil)], now: date(2026, 10, 30, 9)))
        XCTAssertNil(JoinSelection.candidate(from: [event("d", date(2026, 10, 30), minutes: 1440, allDay: true)], now: date(2026, 10, 30, 9)))
    }
}
