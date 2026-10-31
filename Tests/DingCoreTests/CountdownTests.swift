import XCTest
@testable import DingCore

/// Countdown labels and the moments they change.
final class CountdownTests: DingCoreTestCase {
    func testCountdownText() {
        let now = date(2026, 10, 30, 9, 0)
        XCTAssertEqual(Countdown.text(until: now, now: now), "now")
        XCTAssertEqual(Countdown.text(until: now.addingTimeInterval(-30), now: now), "now")
        XCTAssertEqual(Countdown.text(until: now.addingTimeInterval(1), now: now), "1m")
        XCTAssertEqual(Countdown.text(until: now.addingTimeInterval(60), now: now), "1m")
        XCTAssertEqual(Countdown.text(until: now.addingTimeInterval(61), now: now), "2m")
        XCTAssertEqual(Countdown.text(until: now.addingTimeInterval(59 * 60), now: now), "59m")
        XCTAssertEqual(Countdown.text(until: now.addingTimeInterval(60 * 60), now: now), "1h")
        XCTAssertEqual(Countdown.text(until: now.addingTimeInterval(65 * 60), now: now), "1h 5m")
        XCTAssertEqual(Countdown.text(until: now.addingTimeInterval(26 * 3600), now: now), "1d 2h")
        XCTAssertEqual(Countdown.text(until: now.addingTimeInterval(48 * 3600), now: now), "2d")
    }

    func testCountdownNextChange() {
        let start = date(2026, 10, 30, 10, 0)
        // 12m30s out reads "13m"; it becomes "12m" at 12m out.
        let now = start.addingTimeInterval(-750)
        XCTAssertEqual(Countdown.nextChange(until: start, now: now), start.addingTimeInterval(-720))
        // Under a minute, the next change is the start itself.
        XCTAssertEqual(Countdown.nextChange(until: start, now: start.addingTimeInterval(-20)), start)
        XCTAssertNil(Countdown.nextChange(until: start, now: start))
        // At exactly a boundary the text has already changed.
        let boundary = start.addingTimeInterval(-720)
        XCTAssertEqual(Countdown.text(until: start, now: boundary), "12m")
        XCTAssertEqual(Countdown.nextChange(until: start, now: boundary), start.addingTimeInterval(-660))
    }
}

/// How often the menu bar countdown refreshes.
final class TickPlannerTests: DingCoreTestCase {
    func testTickDelayFollowsTheCountdownLabel() {
        let start = date(2026, 10, 30, 10)
        // 12m30s out reads "13m" and flips at 12m: 30s away.
        XCTAssertEqual(TickPlanner.delay(now: start.addingTimeInterval(-750), next: event("a", start)), 30.1, accuracy: 0.001)
    }

    func testTickDelayCapsAtOneMinuteWhenFarAway() {
        let now = date(2026, 10, 30, 9)
        XCTAssertEqual(TickPlanner.delay(now: now, next: event("a", date(2026, 10, 31, 9))), 60.1, accuracy: 0.001)
    }

    func testTickDelayWithNoEventIsTheHeartbeat() {
        XCTAssertEqual(TickPlanner.delay(now: Date(), next: nil), 60.1, accuracy: 0.001)
        XCTAssertEqual(TickPlanner.delay(now: Date(), next: nil, maxInterval: 10), 10.1, accuracy: 0.001)
    }

    func testTickDelayNeverSpins() {
        let start = date(2026, 10, 30, 10)
        XCTAssertGreaterThanOrEqual(TickPlanner.delay(now: start.addingTimeInterval(-0.01), next: event("a", start)), 0.6)
        XCTAssertGreaterThanOrEqual(TickPlanner.delay(now: start, next: event("a", start)), 0.6)
    }
}
