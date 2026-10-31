import XCTest
@testable import DingCore

/// What fires, and when, for a set of events.
final class AlertPlannerTests: DingCoreTestCase {
    func testPlanSchedulesNotificationAndAlert() {
        let now = date(2026, 10, 30, 9, 0)
        let e = event("a", date(2026, 10, 30, 10, 0))
        let plan = AlertPlanner.plan([e], now: now, settings: AlertSettings(leadMinutes: 5, mode: .fullScreen))
        XCTAssertEqual(plan, [
            ScheduledAlert(eventID: "a", kind: .notification, fireDate: date(2026, 10, 30, 9, 55)),
            ScheduledAlert(eventID: "a", kind: .alert, fireDate: date(2026, 10, 30, 10, 0)),
        ])
    }

    func testPlanSkipsPastFireDates() {
        let now = date(2026, 10, 30, 9, 58)
        let e = event("a", date(2026, 10, 30, 10, 0))
        let plan = AlertPlanner.plan([e], now: now, settings: AlertSettings(leadMinutes: 5, mode: .edgeFlash))
        XCTAssertEqual(plan.map(\.kind), [.alert])
        XCTAssertTrue(AlertPlanner.plan([e], now: date(2026, 10, 30, 10, 1), settings: AlertSettings(mode: .fullScreen)).isEmpty)
    }

    func testPlanOnlyEventsWithLinkByDefault() {
        let now = date(2026, 10, 30, 9, 0)
        let e = event("plain", date(2026, 10, 30, 10, 0), link: false)
        XCTAssertTrue(AlertPlanner.plan([e], now: now, settings: AlertSettings(mode: .fullScreen)).isEmpty)
        XCTAssertEqual(AlertPlanner.plan([e], now: now, settings: AlertSettings(mode: .fullScreen, includeEventsWithoutLink: true)).count, 2)
    }

    func testPlanIgnoresAllDayAndHonorsOffSettings() {
        let now = date(2026, 10, 30, 9, 0)
        let allDay = event("d", date(2026, 10, 31), minutes: 1440, allDay: true)
        let timed = event("t", date(2026, 10, 30, 10, 0))
        XCTAssertTrue(AlertPlanner.plan([allDay], now: now, settings: AlertSettings(mode: .fullScreen)).isEmpty)
        XCTAssertEqual(AlertPlanner.plan([timed], now: now, settings: AlertSettings(leadMinutes: 0, mode: .off)), [])
        XCTAssertEqual(AlertPlanner.plan([timed], now: now, settings: AlertSettings(leadMinutes: 0, mode: .edgeFlash)).map(\.kind), [.alert])
    }

    func testPlanIsSortedAndCapped() {
        let now = date(2026, 10, 30, 0, 0)
        let events = (0..<80).map { event("e\($0)", now.addingTimeInterval(Double(3600 + $0 * 3600))) }
        let plan = AlertPlanner.plan(events.reversed(), now: now, settings: AlertSettings(leadMinutes: 5, mode: .off))
        XCTAssertEqual(plan.count, AlertPlanner.maxNotifications)
        XCTAssertEqual(plan.map(\.fireDate), plan.map(\.fireDate).sorted())
        XCTAssertEqual(plan.first?.eventID, "e0")
    }


    func testAlertModeIDs() {
        XCTAssertEqual(AlertMode.allCases.map(\.id), ["off", "edgeFlash", "fullScreen"])
    }
}

/// The queue of alerts waiting for their start time.
final class AlertQueueTests: DingCoreTestCase {
    private func alert(_ id: String, _ fire: Date) -> ScheduledAlert {
        ScheduledAlert(eventID: id, kind: .alert, fireDate: fire)
    }

    func testQueueSortsAndExposesNextFireDate() {
        let queue = AlertQueue([alert("b", date(2026, 10, 30, 11)), alert("a", date(2026, 10, 30, 10))])
        XCTAssertEqual(queue.nextFireDate, date(2026, 10, 30, 10))
        XCTAssertEqual(queue.pending.map(\.eventID), ["a", "b"])
        XCTAssertNil(AlertQueue().nextFireDate)
    }

    func testPopDueReturnsOnlyDueAlerts() {
        var queue = AlertQueue([alert("a", date(2026, 10, 30, 10)), alert("b", date(2026, 10, 30, 11))])
        let fired = queue.popDue(now: date(2026, 10, 30, 10, 0, 1))
        XCTAssertEqual(fired.map(\.eventID), ["a"])
        XCTAssertEqual(queue.pending.map(\.eventID), ["b"])
    }

    func testPopDueFiresSlightlyEarlyTimers() {
        var queue = AlertQueue([alert("a", date(2026, 10, 30, 10))])
        XCTAssertEqual(queue.popDue(now: date(2026, 10, 30, 10).addingTimeInterval(-0.3)).count, 1)
    }

    func testPopDueNotYetDueLeavesQueueAlone() {
        var queue = AlertQueue([alert("a", date(2026, 10, 30, 10))])
        XCTAssertTrue(queue.popDue(now: date(2026, 10, 30, 9)).isEmpty)
        XCTAssertEqual(queue.pending.count, 1)
    }

    func testPopDueDropsStaleAlertsButStillRemovesThem() {
        // The Mac slept through the start time and woke 10 minutes later.
        var queue = AlertQueue([alert("a", date(2026, 10, 30, 10))])
        XCTAssertTrue(queue.popDue(now: date(2026, 10, 30, 10, 10)).isEmpty)
        XCTAssertTrue(queue.pending.isEmpty)
    }

    func testPopDueKeepsAlertsJustInsideTheStaleWindow() {
        var queue = AlertQueue([alert("a", date(2026, 10, 30, 10))])
        XCTAssertEqual(queue.popDue(now: date(2026, 10, 30, 10, 1, 59)).count, 1)
    }

    func testPopDueHandlesSimultaneousAlerts() {
        var queue = AlertQueue([alert("a", date(2026, 10, 30, 10)), alert("b", date(2026, 10, 30, 10))])
        XCTAssertEqual(queue.popDue(now: date(2026, 10, 30, 10)).count, 2)
        XCTAssertTrue(queue.pending.isEmpty)
    }
}
