import XCTest
import DingCore
@testable import Ding

/// The reminders tab layout, the shipped defaults and the test models, as settled in ding-20261109-1.
@MainActor
final class SettledSpecConflictsTests: IsolatedDefaultsTestCase {
    private let linklessLabel = "Remind me about events without a meeting link"

    private func index(ofSectionContaining row: String) -> Int? {
        AlertsTab.sections.firstIndex { $0.rows.contains(row) }
    }

    private func index(ofSectionTitled title: String) -> Int? {
        AlertsTab.sections.firstIndex { $0.title == title }
    }

    // MARK: DING-NOTIF-016

    func test_DING_NOTIF_016_theLinklessSwitchComesBeforeBothReminderSections() throws {
        let sections = AlertsTab.sections
        XCTAssertFalse(sections.isEmpty, "DING-NOTIF-016: the reminders tab lays out its sections from AlertsTab.sections")
        let linkless = try XCTUnwrap(index(ofSectionContaining: linklessLabel), "DING-NOTIF-016: the linkless-events row carries its new label")
        let notification = try XCTUnwrap(index(ofSectionTitled: "Notification"), "DING-NOTIF-016: there is a Notification section")
        let screen = try XCTUnwrap(index(ofSectionTitled: "Screen reminder"), "DING-NOTIF-016: there is a Screen reminder section")
        XCTAssertLessThan(linkless, notification, "DING-NOTIF-016: the switch sits above the Notification section")
        XCTAssertLessThan(notification, screen, "DING-NOTIF-016: Notification comes before Screen reminder")
    }

    func test_DING_NOTIF_016_theScreenReminderSectionNoLongerHoldsTheSwitch() throws {
        let screen = try XCTUnwrap(AlertsTab.sections.first { $0.title == "Screen reminder" }, "DING-NOTIF-016: there is a Screen reminder section")
        XCTAssertFalse(screen.rows.contains(linklessLabel), "DING-NOTIF-016: the switch is not inside the Screen reminder section")
        XCTAssertFalse(screen.rows.contains("Also for events without a meeting link"), "DING-NOTIF-016: the old screen-reminder-only row is gone")
    }

    func test_DING_NOTIF_016_keeps_theStoredChoiceCarriesOver() {
        XCTAssertEqual(Pref.alertIncludeAll, "alertIncludeAll", "DING-NOTIF-016: the stored key is unchanged")
        suite.set(true, forKey: Pref.alertIncludeAll)
        XCTAssertTrue(Pref.alertSettings.includeEventsWithoutLink, "DING-NOTIF-016: an existing choice still applies")
    }

    // MARK: DING-NOTIF-013

    func test_DING_NOTIF_013_keeps_aFreshInstallNotifiesFiveMinutesBeforeWithNoScreenReminder() {
        XCTAssertEqual(Pref.Default.notifyLeadMinutes, 5, "DING-NOTIF-013")
        XCTAssertEqual(Pref.Default.alertMode, .off, "DING-NOTIF-013")
        XCTAssertEqual(suite.integer(forKey: Pref.notifyLeadMinutes), 5, "DING-NOTIF-013")
        XCTAssertEqual(suite.string(forKey: Pref.alertMode), AlertMode.off.rawValue, "DING-NOTIF-013")
    }

    // MARK: DING-TEST-001

    func test_DING_TEST_001_keeps_aModelBuiltWithFakesStartsTheControlServerUnlessATestTurnsItOff() {
        let normal = AppModel(calendar: FakeCalendar(), notifier: FakeNotifier())
        XCTAssertTrue(normal.startsControlServer, "DING-TEST-001: a normal model starts the control server")
        XCTAssertFalse(AppModel.test().startsControlServer, "DING-TEST-001: a test model does not")
    }
}
