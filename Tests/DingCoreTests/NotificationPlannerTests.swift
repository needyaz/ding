import XCTest
@testable import DingCore

/// Turning an alert plan into system notifications.
final class NotificationPlannerTests: DingCoreTestCase {
    func testNotificationBuiltFromPlan() {
        let e = event("a", date(2026, 10, 30, 10), link: .googleMeet)
        let plan = AlertPlanner.plan([e], now: date(2026, 10, 30, 9), settings: AlertSettings(leadMinutes: 10))
        let built = NotificationPlanner.build(plan, events: [e], leadMinutes: 10, playSound: true, joinAction: true)
        XCTAssertEqual(built, [PlannedNotification(
            id: "ding.a", title: "a", body: "Starts in 10 minutes · Google Meet",
            fireDate: date(2026, 10, 30, 9, 50), playSound: true, joinAction: true, link: e.link
        )])
    }

    func testNotificationIgnoresAlertKindsAndUnknownEvents() {
        let e = event("a", date(2026, 10, 30, 10))
        let plan = [
            ScheduledAlert(eventID: "a", kind: .alert, fireDate: date(2026, 10, 30, 10)),
            ScheduledAlert(eventID: "ghost", kind: .notification, fireDate: date(2026, 10, 30, 9)),
        ]
        XCTAssertTrue(NotificationPlanner.build(plan, events: [e], leadMinutes: 5, playSound: true, joinAction: true).isEmpty)
    }

    func testJoinActionNeedsALinkAndTheSetting() {
        let withLink = event("a", date(2026, 10, 30, 10))
        let plain = event("b", date(2026, 10, 30, 10), link: nil)
        let plan = [
            ScheduledAlert(eventID: "a", kind: .notification, fireDate: date(2026, 10, 30, 9, 55)),
            ScheduledAlert(eventID: "b", kind: .notification, fireDate: date(2026, 10, 30, 9, 55)),
        ]
        let on = NotificationPlanner.build(plan, events: [withLink, plain], leadMinutes: 5, playSound: false, joinAction: true)
        XCTAssertEqual(on.map(\.joinAction), [true, false])
        let off = NotificationPlanner.build(plan, events: [withLink, plain], leadMinutes: 5, playSound: false, joinAction: false)
        XCTAssertEqual(off.map(\.joinAction), [false, false])
        XCTAssertEqual(off.map(\.playSound), [false, false])
    }

    func testNotificationBodyWording() {
        let linked = event("a", date(2026, 10, 30, 10), link: .zoom)
        let plain = event("b", date(2026, 10, 30, 10), link: nil)
        XCTAssertEqual(NotificationPlanner.body(for: linked, leadMinutes: 1), "Starts in 1 minute · Zoom")
        XCTAssertEqual(NotificationPlanner.body(for: linked, leadMinutes: 15), "Starts in 15 minutes · Zoom")
        XCTAssertEqual(NotificationPlanner.body(for: plain, leadMinutes: 5), "Starts in 5 minutes")
        XCTAssertEqual(NotificationPlanner.body(for: plain, leadMinutes: 0), "Starting now")
    }

    func testRecurringOccurrencesGetDistinctNotificationIDs() {
        let a = event("series@100", date(2026, 10, 30, 10))
        let b = event("series@200", date(2026, 10, 31, 10))
        let plan = AlertPlanner.plan([a, b], now: date(2026, 10, 30, 9), settings: AlertSettings(leadMinutes: 5))
        let ids = NotificationPlanner.build(plan, events: [a, b], leadMinutes: 5, playSound: true, joinAction: true).map(\.id)
        XCTAssertEqual(Set(ids).count, 2)
    }
}
