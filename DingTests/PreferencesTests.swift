import XCTest
import DingCore
@testable import Ding

final class PreferencesTests: IsolatedDefaultsTestCase {
    func testRegisteredDefaults() {
        XCTAssertTrue(suite.bool(forKey: Pref.showCountdown))
        XCTAssertTrue(suite.bool(forKey: Pref.showTitle))
        XCTAssertFalse(suite.bool(forKey: Pref.countdownOnlyToday))
        XCTAssertEqual(suite.integer(forKey: Pref.rangeDays), 3)
        XCTAssertTrue(suite.bool(forKey: Pref.showEventsWithoutLink))
        XCTAssertTrue(suite.bool(forKey: Pref.showMaybe))
        XCTAssertEqual(suite.integer(forKey: Pref.notifyLeadMinutes), 5)
        XCTAssertTrue(suite.bool(forKey: Pref.notifySound))
        XCTAssertTrue(suite.bool(forKey: Pref.notifyJoinAction))
        XCTAssertEqual(suite.string(forKey: Pref.alertMode), "off")
        XCTAssertEqual(suite.integer(forKey: Pref.alertLeadMinutes), 1)
        XCTAssertFalse(suite.bool(forKey: Pref.alertIncludeAll))
    }

    func testHotkeysAndAlertsAreOffByDefault() {
        XCTAssertEqual(Pref.alertSettings.mode, .off)
        XCTAssertFalse(Pref.alertSettings.includeEventsWithoutLink)
    }

    func testOpenDefaultsPerService() {
        XCTAssertEqual(suite.string(forKey: Pref.openKey(.zoom)), "native")
        for service in [MeetingService.googleMeet, .teams, .webex, .other] {
            XCTAssertEqual(suite.string(forKey: Pref.openKey(service)), "default", "\(service)")
        }
    }

    func testOpenKeysAreDistinct() {
        XCTAssertEqual(Set(MeetingService.allCases.map(Pref.openKey)).count, MeetingService.allCases.count)
    }

    func testRegisteringDefaultsDoesNotOverwriteUserChoices() {
        suite.set(14, forKey: Pref.rangeDays)
        Pref.registerDefaults()
        XCTAssertEqual(Pref.days, 14)
    }

    func testEventFilterReadsPreferences() {
        suite.set(false, forKey: Pref.showEventsWithoutLink)
        suite.set(false, forKey: Pref.showMaybe)
        Pref.disabledCalendars = ["a", "b"]
        XCTAssertEqual(Pref.eventFilter, EventFilter(showWithoutLink: false, showMaybe: false, disabledCalendarIDs: ["a", "b"]))
    }

    func testDisabledCalendarsRoundTripAndAreStoredSorted() {
        XCTAssertTrue(Pref.disabledCalendars.isEmpty)
        Pref.disabledCalendars = ["zeta", "alpha", "mid"]
        XCTAssertEqual(suite.stringArray(forKey: Pref.disabledCalendarIDs), ["alpha", "mid", "zeta"])
        XCTAssertEqual(Pref.disabledCalendars, ["zeta", "alpha", "mid"])
        Pref.disabledCalendars = []
        XCTAssertTrue(Pref.disabledCalendars.isEmpty)
    }

    func testMenuBarOptionsReadPreferences() {
        suite.set(false, forKey: Pref.showCountdown)
        suite.set(false, forKey: Pref.showTitle)
        suite.set(true, forKey: Pref.countdownOnlyToday)
        let options = Pref.menuBarOptions
        XCTAssertFalse(options.showCountdown)
        XCTAssertFalse(options.showTitle)
        XCTAssertTrue(options.countdownOnlyToday)
    }

    func testAlertSettingsReadPreferences() {
        suite.set(10, forKey: Pref.notifyLeadMinutes)
        suite.set("fullScreen", forKey: Pref.alertMode)
        suite.set(2, forKey: Pref.alertLeadMinutes)
        suite.set(true, forKey: Pref.alertIncludeAll)
        XCTAssertEqual(
            Pref.alertSettings,
            AlertSettings(notificationLeadMinutes: 10, mode: .fullScreen, alertLeadMinutes: 2, includeEventsWithoutLink: true)
        )
    }

    func testAlertTimingDefaultsToOneMinuteBeforeAndIsIndependentOfTheNotification() {
        XCTAssertEqual(Pref.alertSettings.alertLeadMinutes, 1)
        XCTAssertEqual(Pref.alertSettings.notificationLeadMinutes, 5)
        suite.set(15, forKey: Pref.notifyLeadMinutes)
        XCTAssertEqual(Pref.alertSettings.alertLeadMinutes, 1)
    }

    func testAlertLeadOptionsStartAtTheStartTime() {
        XCTAssertEqual(Pref.alertLeadOptions, [0, 1, 2, 5])
        XCTAssertTrue(Pref.alertLeadOptions.contains(Pref.Default.alertLeadMinutes))
    }

    func testAssistantAccessIsOffUntilTheUserTurnsItOn() {
        XCTAssertEqual(Pref.controlPermissions, ControlPermissions(canReadSchedule: false, canOpenMeetings: false))
        XCTAssertFalse(suite.bool(forKey: Pref.controlReadSchedule))
        XCTAssertFalse(suite.bool(forKey: Pref.controlOpenMeetings))
    }

    func testAssistantPermissionsAreReadLiveAndIndependently() {
        suite.set(true, forKey: Pref.controlReadSchedule)
        XCTAssertEqual(Pref.controlPermissions, ControlPermissions(canReadSchedule: true, canOpenMeetings: false))
        suite.set(true, forKey: Pref.controlOpenMeetings)
        suite.set(false, forKey: Pref.controlReadSchedule)
        XCTAssertEqual(Pref.controlPermissions, ControlPermissions(canReadSchedule: false, canOpenMeetings: true))
    }

    func testUnknownAlertModeFallsBackToOff() {
        suite.set("confetti", forKey: Pref.alertMode)
        XCTAssertEqual(Pref.alertSettings.mode, .off)
    }

    func testDaysIsNeverBelowOne() {
        suite.set(0, forKey: Pref.rangeDays)
        XCTAssertEqual(Pref.days, 1)
        suite.set(-4, forKey: Pref.rangeDays)
        XCTAssertEqual(Pref.days, 1)
        suite.set(7, forKey: Pref.rangeDays)
        XCTAssertEqual(Pref.days, 7)
    }

    func testClockPreference() {
        suite.set(true, forKey: Pref.use24Hour)
        XCTAssertTrue(Pref.uses24Hour)
        suite.set(false, forKey: Pref.use24Hour)
        XCTAssertFalse(Pref.uses24Hour)
    }

    func testDefaultClockMatchesTheSystemLocale() {
        let fresh = UserDefaults(suiteName: "blue.luci.DingTests.clock.\(UUID().uuidString)")!
        Pref.defaults = fresh
        Pref.registerDefaults()
        XCTAssertEqual(Pref.uses24Hour, Pref.systemUses24Hour)
    }

    // MARK: OpenTarget.current

    func testOpenTargetCurrentUsesDefaults() {
        XCTAssertEqual(OpenTarget.current(for: .zoom), .nativeApp)
        XCTAssertEqual(OpenTarget.current(for: .teams), .defaultBrowser)
    }

    func testOpenTargetCurrentHonorsStoredBrowser() {
        suite.set("org.mozilla.firefox", forKey: Pref.openKey(.googleMeet))
        XCTAssertEqual(OpenTarget.current(for: .googleMeet), .browser(bundleID: "org.mozilla.firefox"))
    }

    func testOpenTargetCurrentRefusesNativeWhereThereIsNoApp() {
        suite.set("native", forKey: Pref.openKey(.googleMeet))
        XCTAssertEqual(OpenTarget.current(for: .googleMeet), .defaultBrowser)
    }

    func testFeedbackURLPointsAtGitHubIssues() {
        XCTAssertEqual(AppInfo.feedbackURL.host, "github.com")
        XCTAssertTrue(AppInfo.feedbackURL.path.hasSuffix("/ding/issues"))
    }
}
