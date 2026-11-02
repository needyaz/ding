import XCTest
@testable import DingCore

/// Which meetings clash, in what order they are shown, and where the bracket goes.
final class OverlapTests: DingCoreTestCase {
    private func arrange(_ events: [DingEvent]) -> (ids: [String], positions: [String: OverlapPosition]) {
        let result = Overlap.arrange(events)
        return (result.events.map(\.id), result.positions)
    }

    private let nine = Date(timeIntervalSince1970: 0)
    private func at(_ minutes: Int) -> Date { date(2026, 11, 3, 9, 0).addingTimeInterval(Double(minutes) * 60) }

    func testMeetingsThatDoNotOverlapHaveNoBracket() {
        let result = arrange([event("a", at(0)), event("b", at(60))])
        XCTAssertEqual(result.ids, ["a", "b"])
        XCTAssertEqual(result.positions, ["a": .none, "b": .none])
    }

    func testBackToBackMeetingsDoNotOverlap() {
        let result = arrange([event("a", at(0), minutes: 30), event("b", at(30))])
        XCTAssertEqual(result.positions, ["a": .none, "b": .none])
    }

    func testTwoMeetingsAtTheSameTimeFormACluster() {
        let result = arrange([event("a", at(0)), event("b", at(0))])
        XCTAssertEqual(result.positions, ["a": .first, "b": .last])
    }

    func testAChainOverlapsAsOneCluster() {
        // A overlaps B, B overlaps C, but A and C do not overlap each other.
        let result = arrange([event("a", at(0), minutes: 40), event("b", at(30), minutes: 40), event("c", at(60), minutes: 40)])
        XCTAssertEqual(result.positions, ["a": .first, "b": .middle, "c": .last])
    }

    func testALongMeetingSpansShorterOnes() {
        let result = arrange([event("long", at(0), minutes: 180), event("x", at(30)), event("y", at(90)), event("z", at(150))])
        XCTAssertEqual(result.positions, ["long": .first, "x": .middle, "y": .middle, "z": .last])
    }

    func testSeparateClustersAreBracketedSeparately() {
        let result = arrange([
            event("a", at(0)), event("b", at(10)),
            event("solo", at(60)),
            event("c", at(120)), event("d", at(130)),
        ])
        XCTAssertEqual(result.positions, ["a": .first, "b": .last, "solo": .none, "c": .first, "d": .last])
    }

    func testAllDayEventsNeverJoinACluster() {
        let result = arrange([event("holiday", date(2026, 11, 3), minutes: 1440, allDay: true), event("a", at(0)), event("b", at(10))])
        XCTAssertEqual(result.ids.first, "holiday")
        XCTAssertEqual(result.positions["holiday"], OverlapPosition.none)
        XCTAssertEqual(result.positions["a"], .first)
    }

    func testAZeroLengthMeetingOverlapsWhatItSitsInsideButNotWhatItTouches() {
        let inside = arrange([event("long", at(0), minutes: 60), event("ping", at(30), minutes: 0)])
        XCTAssertEqual(inside.positions, ["long": .first, "ping": .last])
        let sameStart = arrange([event("ping", at(0), minutes: 0), event("long", at(0), minutes: 60)])
        XCTAssertEqual(sameStart.positions["ping"], .first)
        let atTheEnd = arrange([event("long", at(0), minutes: 60), event("ping", at(60), minutes: 0)])
        XCTAssertEqual(atTheEnd.positions, ["long": .none, "ping": .none])
    }

    func testInsideAClusterAcceptedMeetingsComeFirst() {
        let result = arrange([
            event("maybe", at(0), response: .maybe), event("unanswered", at(0), response: .notResponded),
            event("accepted", at(5)), event("accepted2", at(10)),
        ])
        XCTAssertEqual(result.ids, ["accepted", "accepted2", "maybe", "unanswered"])
        XCTAssertEqual(result.positions["accepted"], .first)
        XCTAssertEqual(result.positions["unanswered"], .last)
    }

    func testOutsideAClusterTheOrderStaysChronological() {
        let result = arrange([event("maybe", at(0), response: .maybe), event("accepted", at(60))])
        XCTAssertEqual(result.ids, ["maybe", "accepted"])
    }

    func testDayGroupingCarriesTheOverlap() {
        let now = date(2026, 11, 3, 8, 0)
        let groups = DayGrouping.group([event("m", at(0), response: .maybe), event("a", at(10))], now: now, days: 1, calendar: calendar)
        XCTAssertEqual(groups.first?.events.map(\.id), ["a", "m"])
        XCTAssertEqual(groups.first?.position(of: groups.first!.events[0]), .first)
        XCTAssertEqual(groups.first?.position(of: groups.first!.events[1]), .last)
        XCTAssertEqual(DayGroup(day: now, events: []).position(of: event("x", now)), OverlapPosition.none)
    }
}
