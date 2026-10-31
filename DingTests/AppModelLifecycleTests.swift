import XCTest
import AppKit
import DingCore
@testable import Ding

@MainActor
final class AppModelLifecycleTests: IsolatedDefaultsTestCase {
    private var fake: FakeCalendar!
    private var notifier: FakeNotifier!
    private var model: AppModel!
    private var opened: [MeetingLink] = []
    private var alerts: [(DingEvent, AlertMode)] = []
    private var settingsShown = 0

    override func setUp() {
        super.setUp()
        MainActor.assumeIsolated {
            fake = FakeCalendar()
            notifier = FakeNotifier()
            model = AppModel.test(calendar: fake, notifier: notifier)
            model.openLink = { [unowned self] in opened.append($0) }
            model.presentAlert = { [unowned self] in alerts.append(($0, $1)) }
            model.presentSettings = { [unowned self] in settingsShown += 1 }
        }
    }

    /// Lets main-queue notification observers and Tasks run.
    private func settle(_ seconds: TimeInterval = 0.4) {
        RunLoop.current.run(until: Date().addingTimeInterval(seconds))
    }

    // MARK: reload

    func testReloadPullsEventsAccountsAndAccess() {
        fake.access = .denied
        fake.stubEvents = [DingEvent.test("a", startingIn: 600)]
        fake.stubAccounts = [CalendarAccount(title: "iCloud", calendars: [])]
        model.reload()
        XCTAssertEqual(model.access, .denied)
        XCTAssertEqual(model.events.map(\.id), ["a"])
        XCTAssertEqual(model.accounts.map(\.title), ["iCloud"])
    }

    func testReloadFetchesFourteenDaysStartingAtMidnight() throws {
        model.reload()
        let range = try XCTUnwrap(fake.fetchRanges.last)
        XCTAssertEqual(range.start, Calendar.current.startOfDay(for: Date()))
        XCTAssertEqual(Calendar.current.dateComponents([.day], from: range.start, to: range.end).day, 14)
    }

    func testReloadRefreshesNow() {
        model.now = Date(timeIntervalSince1970: 0)
        model.reload()
        XCTAssertLessThan(abs(model.now.timeIntervalSinceNow), 2)
    }

    // MARK: start

    func testStartRequestsAccessWhenUndetermined() {
        fake.access = .notDetermined
        model.start(requestNotificationPermission: false)
        settle()
        XCTAssertEqual(fake.requestCount, 1)
        XCTAssertEqual(model.access, .granted)
    }

    func testStartDoesNotAskWhenAlreadyDecided() {
        for access in [CalendarAccess.granted, .denied] {
            let calendar = FakeCalendar()
            calendar.access = access
            AppModel.test(calendar: calendar).start(requestNotificationPermission: false)
            settle(0.2)
            XCTAssertEqual(calendar.requestCount, 0, "\(access)")
        }
    }

    func testStartIsIdempotent() {
        model.start(requestNotificationPermission: false)
        settle(0.2)
        let fetches = fake.fetchRanges.count
        model.start(requestNotificationPermission: false)
        settle(0.2)
        XCTAssertEqual(fake.fetchRanges.count, fetches)
    }

    func testStartLoadsEventsImmediately() {
        fake.stubEvents = [DingEvent.test("a", startingIn: 600)]
        model.start(requestNotificationPermission: false)
        settle(0.2)
        XCTAssertEqual(model.events.map(\.id), ["a"])
    }

    func testCalendarChangeNotificationTriggersReload() {
        model.start(requestNotificationPermission: false)
        settle(0.2)
        fake.stubEvents = [DingEvent.test("fresh", startingIn: 600)]
        fake.onChange?()
        XCTAssertEqual(model.events.map(\.id), ["fresh"])
    }

    func testRequestCalendarAccessAsksTheSource() {
        fake.access = .notDetermined
        model.requestCalendarAccess()
        settle(0.2)
        XCTAssertEqual(fake.requestCount, 1)
    }

    // MARK: System events

    func testSystemEventsTriggerReload() {
        model.start(requestNotificationPermission: false)
        settle(0.2)
        let posts: [(NotificationCenter, Notification.Name)] = [
            (NSWorkspace.shared.notificationCenter, NSWorkspace.didWakeNotification),
            (.default, .NSSystemClockDidChange),
            (.default, .NSSystemTimeZoneDidChange),
            (.default, .NSCalendarDayChanged),
        ]
        for (center, name) in posts {
            let before = fake.fetchRanges.count
            center.post(name: name, object: nil)
            settle(0.2)
            XCTAssertGreaterThan(fake.fetchRanges.count, before, "\(name.rawValue)")
        }
    }

    // MARK: Preferences

    func testPreferenceChangesBumpTheVersionAfterADebounce() {
        model.start(requestNotificationPermission: false)
        settle(0.2)
        let before = model.prefsVersion
        suite.set(7, forKey: Pref.rangeDays)
        settle(0.8)
        XCTAssertGreaterThan(model.prefsVersion, before)
    }

    func testBurstsOfPreferenceChangesCoalesce() {
        model.start(requestNotificationPermission: false)
        settle(0.2)
        let before = model.prefsVersion
        for day in 1...10 { suite.set(day, forKey: Pref.rangeDays) }
        settle(0.8)
        XCTAssertEqual(model.prefsVersion, before + 1)
    }

    // MARK: Actions

    func testJoinOpensTheLinkAndClosesTheMenu() throws {
        let e = DingEvent.test("a", startingIn: 600)
        model.isMenuPresented = true
        model.join(e)
        XCTAssertFalse(model.isMenuPresented)
        XCTAssertEqual(opened, [try XCTUnwrap(e.link)])
    }

    func testJoinWithoutALinkDoesNothing() {
        model.isMenuPresented = true
        model.join(DingEvent.test("plain", startingIn: 600, link: false))
        XCTAssertTrue(model.isMenuPresented)
        XCTAssertTrue(opened.isEmpty)
    }

    func testJoinNextOpensTheNextLinkedMeeting() throws {
        let linked = DingEvent.test("linked", startingIn: 1200)
        model.events = [DingEvent.test("plain", startingIn: 600, link: false), linked]
        model.joinNext()
        XCTAssertEqual(opened, [try XCTUnwrap(linked.link)])
    }

    func testJoinNextCatchesAMeetingThatJustStarted() throws {
        let running = DingEvent.test("running", startingIn: -600, minutes: 60)
        model.events = [running, DingEvent.test("later", startingIn: 3600)]
        model.joinNext()
        XCTAssertEqual(opened, [try XCTUnwrap(running.link)])
    }

    func testJoinNextWithNothingToJoin() {
        model.events = [DingEvent.test("plain", startingIn: 600, link: false)]
        model.joinNext()
        XCTAssertTrue(opened.isEmpty)
    }

    func testJoinNextRespectsHiddenCalendars() throws {
        let shown = DingEvent.test("shown", startingIn: 1200)
        model.events = [DingEvent.test("hidden", startingIn: 600, calendarID: "off"), shown]
        Pref.disabledCalendars = ["off"]
        model.joinNext()
        XCTAssertEqual(opened, [try XCTUnwrap(shown.link)])
    }

    func testOpenSettingsClosesTheMenuAndPresentsSettings() {
        model.isMenuPresented = true
        model.openSettings()
        XCTAssertFalse(model.isMenuPresented)
        XCTAssertEqual(settingsShown, 1)
    }

    // MARK: Alert routing

    func testAlertIsPresentedAtStartWithTheConfiguredMode() {
        suite.set("fullScreen", forKey: Pref.alertMode)
        suite.set(0, forKey: Pref.notifyLeadMinutes)
        fake.stubEvents = [DingEvent.test("a", startingIn: 1)]
        model.start(requestNotificationPermission: false)
        settle(2.5)
        XCTAssertEqual(alerts.map(\.0.id), ["a"])
        XCTAssertEqual(alerts.first?.1, .fullScreen)
    }

    func testEdgeFlashModeIsPassedThrough() {
        suite.set("edgeFlash", forKey: Pref.alertMode)
        suite.set(0, forKey: Pref.notifyLeadMinutes)
        fake.stubEvents = [DingEvent.test("a", startingIn: 1)]
        model.start(requestNotificationPermission: false)
        settle(2.5)
        XCTAssertEqual(alerts.first?.1, .edgeFlash)
    }

    func testNoAlertWhenOff() {
        suite.set(0, forKey: Pref.notifyLeadMinutes)
        fake.stubEvents = [DingEvent.test("a", startingIn: 1)]
        model.start(requestNotificationPermission: false)
        settle(2.5)
        XCTAssertTrue(alerts.isEmpty)
    }

    func testNoAlertForHiddenCalendars() {
        suite.set("fullScreen", forKey: Pref.alertMode)
        suite.set(0, forKey: Pref.notifyLeadMinutes)
        Pref.disabledCalendars = ["off"]
        fake.stubEvents = [DingEvent.test("a", startingIn: 1, calendarID: "off")]
        model.start(requestNotificationPermission: false)
        settle(2.5)
        XCTAssertTrue(alerts.isEmpty)
    }

    func testChangingTheAlertModeReschedules() {
        suite.set(0, forKey: Pref.notifyLeadMinutes)
        fake.stubEvents = [DingEvent.test("a", startingIn: 3)]
        model.start(requestNotificationPermission: false)
        settle(0.3)
        suite.set("fullScreen", forKey: Pref.alertMode)  // debounce 250ms, then the plan is rebuilt
        settle(4)
        XCTAssertEqual(alerts.map(\.0.id), ["a"])
    }

    // MARK: Notifications reach the notifier, never the real center

    func testStartRequestsNotificationPermissionOnlyWhenAsked() {
        model.start(requestNotificationPermission: false)
        XCTAssertEqual(notifier.permissionRequests, 0)

        let other = FakeNotifier()
        AppModel.test(calendar: FakeCalendar(), notifier: other).start(requestNotificationPermission: true)
        XCTAssertEqual(other.permissionRequests, 1)
    }

    func testReloadHandsPlannedNotificationsToTheNotifier() {
        suite.set(5, forKey: Pref.notifyLeadMinutes)
        fake.stubEvents = [DingEvent.test("a", startingIn: 1800)]
        model.reload()
        XCTAssertEqual(notifier.latest.map(\.title), ["Event a"])
        XCTAssertEqual(notifier.latest.first?.body.hasPrefix("Starts in 5 minutes"), true)
    }

    func testChangingLeadTimeRebuildsNotifications() {
        suite.set(5, forKey: Pref.notifyLeadMinutes)
        fake.stubEvents = [DingEvent.test("a", startingIn: 3600)]
        model.start(requestNotificationPermission: false)
        settle(0.2)
        let first = notifier.latest.first?.fireDate
        suite.set(15, forKey: Pref.notifyLeadMinutes)
        settle(0.8)
        let second = notifier.latest.first?.fireDate
        XCTAssertNotNil(first)
        XCTAssertNotEqual(first, second)
        XCTAssertEqual(try XCTUnwrap(first).timeIntervalSince(try XCTUnwrap(second)), 600, accuracy: 2)
    }

    func testTurningNotificationsOffClearsThem() {
        suite.set(5, forKey: Pref.notifyLeadMinutes)
        fake.stubEvents = [DingEvent.test("a", startingIn: 3600)]
        model.reload()
        XCTAssertEqual(notifier.latest.count, 1)
        suite.set(0, forKey: Pref.notifyLeadMinutes)
        model.reload()
        XCTAssertTrue(notifier.latest.isEmpty)
    }
}
