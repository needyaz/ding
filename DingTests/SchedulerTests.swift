import XCTest
import DingCore
@testable import Ding

@MainActor
final class SchedulerTests: IsolatedDefaultsTestCase {
    func testTickFiresWhenTheCountdownLabelChanges() {
        let scheduler = Scheduler(notifier: FakeNotifier())
        let ticked = expectation(description: "tick")
        scheduler.onTick = { ticked.fulfill() }
        // Under a minute out, the label next changes at the start itself.
        scheduler.scheduleTick(next: DingEvent.test("a", startingIn: 1))
        wait(for: [ticked], timeout: 4)
    }

    func testReschedulingReplacesThePreviousTick() {
        let scheduler = Scheduler(notifier: FakeNotifier())
        var count = 0
        scheduler.onTick = { count += 1 }
        scheduler.scheduleTick(next: DingEvent.test("a", startingIn: 1))
        scheduler.scheduleTick(next: nil)  // heartbeat: a minute away
        RunLoop.current.run(until: Date().addingTimeInterval(2))
        XCTAssertEqual(count, 0)
    }

    func testAlertFiresAtStartTime() {
        let scheduler = Scheduler(notifier: FakeNotifier())
        let fired = expectation(description: "alert")
        var alerted: DingEvent?
        scheduler.onAlert = { alerted = $0; fired.fulfill() }
        let e = DingEvent.test("a", startingIn: 1)
        scheduler.update(events: [e], next: e, settings: AlertSettings(notificationLeadMinutes: 0, mode: .fullScreen))
        wait(for: [fired], timeout: 4)
        XCTAssertEqual(alerted?.id, "a")
    }

    func testNoAlertWhenModeIsOff() {
        let scheduler = Scheduler(notifier: FakeNotifier())
        var fired = false
        scheduler.onAlert = { _ in fired = true }
        let e = DingEvent.test("a", startingIn: 1)
        scheduler.update(events: [e], next: e, settings: AlertSettings(notificationLeadMinutes: 0, mode: .off))
        RunLoop.current.run(until: Date().addingTimeInterval(2.5))
        XCTAssertFalse(fired)
    }

    func testEventsWithoutLinksDoNotAlertByDefault() {
        let scheduler = Scheduler(notifier: FakeNotifier())
        var fired = false
        scheduler.onAlert = { _ in fired = true }
        let e = DingEvent.test("a", startingIn: 1, link: false)
        scheduler.update(events: [e], next: e, settings: AlertSettings(notificationLeadMinutes: 0, mode: .edgeFlash))
        RunLoop.current.run(until: Date().addingTimeInterval(2.5))
        XCTAssertFalse(fired)
    }

    func testRebuildingDropsAlertsForRemovedEvents() {
        let scheduler = Scheduler(notifier: FakeNotifier())
        var fired = false
        scheduler.onAlert = { _ in fired = true }
        let e = DingEvent.test("a", startingIn: 1.5)
        scheduler.update(events: [e], next: e, settings: AlertSettings(notificationLeadMinutes: 0, mode: .fullScreen))
        scheduler.update(events: [], next: nil, settings: AlertSettings(notificationLeadMinutes: 0, mode: .fullScreen))
        RunLoop.current.run(until: Date().addingTimeInterval(3))
        XCTAssertFalse(fired)
    }

    func testMultipleAlertsFireInOrder() {
        let scheduler = Scheduler(notifier: FakeNotifier())
        let both = expectation(description: "both")
        both.expectedFulfillmentCount = 2
        var order: [String] = []
        scheduler.onAlert = { order.append($0.id); both.fulfill() }
        let first = DingEvent.test("first", startingIn: 1)
        let second = DingEvent.test("second", startingIn: 2)
        scheduler.update(events: [second, first], next: first, settings: AlertSettings(notificationLeadMinutes: 0, mode: .fullScreen))
        wait(for: [both], timeout: 5)
        XCTAssertEqual(order, ["first", "second"])
    }

    // MARK: Notifier handoff

    func testUpdateReplacesNotificationsEveryTime() {
        let notifier = FakeNotifier()
        let scheduler = Scheduler(notifier: notifier)
        let e = DingEvent.test("a", startingIn: 3600)
        scheduler.update(events: [e], next: e, settings: AlertSettings(notificationLeadMinutes: 5))
        scheduler.update(events: [], next: nil, settings: AlertSettings(notificationLeadMinutes: 5))
        XCTAssertEqual(notifier.replacements.map(\.count), [1, 0])
    }

    func testNotificationsFireLeadMinutesBeforeStart() throws {
        let notifier = FakeNotifier()
        let e = DingEvent.test("a", startingIn: 3600)
        Scheduler(notifier: notifier).update(events: [e], next: e, settings: AlertSettings(notificationLeadMinutes: 10))
        let fire = try XCTUnwrap(notifier.latest.first).fireDate
        XCTAssertEqual(e.start.timeIntervalSince(fire), 600, accuracy: 0.001)
    }

    func testNotificationSettingsAreReadFromPreferences() {
        suite.set(false, forKey: Pref.notifySound)
        suite.set(false, forKey: Pref.notifyJoinAction)
        let notifier = FakeNotifier()
        let e = DingEvent.test("a", startingIn: 3600)
        Scheduler(notifier: notifier).update(events: [e], next: e, settings: AlertSettings(notificationLeadMinutes: 5))
        XCTAssertEqual(notifier.latest.first?.playSound, false)
        XCTAssertEqual(notifier.latest.first?.joinAction, false)
    }

    func testNoNotificationsWhenLeadIsZeroOrEventHasNoLink() {
        let notifier = FakeNotifier()
        let scheduler = Scheduler(notifier: notifier)
        let linked = DingEvent.test("a", startingIn: 3600)
        scheduler.update(events: [linked], next: linked, settings: AlertSettings(notificationLeadMinutes: 0))
        XCTAssertTrue(notifier.latest.isEmpty)
        let plain = DingEvent.test("b", startingIn: 3600, link: false)
        scheduler.update(events: [plain], next: plain, settings: AlertSettings(notificationLeadMinutes: 5))
        XCTAssertTrue(notifier.latest.isEmpty)
    }

    func testPermissionRequestIsForwarded() {
        let notifier = FakeNotifier()
        Scheduler(notifier: notifier).requestNotificationPermission()
        XCTAssertEqual(notifier.permissionRequests, 1)
    }
}
