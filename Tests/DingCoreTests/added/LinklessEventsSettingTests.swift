import XCTest
@testable import DingCore

/// One setting decides whether events without a meeting link get reminders of either kind.
final class LinklessEventsSettingTests: DingCoreTestCase {
    func test_DING_NOTIF_016_keeps_theLinklessSettingCoversNotificationsAndScreenReminders() {
        let now = date(2026, 11, 9, 9, 0)
        let plain = event("plain", date(2026, 11, 9, 10, 0), link: false)
        let off = AlertSettings(notificationLeadMinutes: 5, mode: .fullScreen, includeEventsWithoutLink: false)
        XCTAssertTrue(AlertPlanner.plan([plain], now: now, settings: off).isEmpty, "DING-NOTIF-016: off means neither kind")
        let on = AlertSettings(notificationLeadMinutes: 5, mode: .fullScreen, includeEventsWithoutLink: true)
        XCTAssertEqual(AlertPlanner.plan([plain], now: now, settings: on).map(\.kind), [.notification, .alert], "DING-NOTIF-016: on means both kinds")
    }
}
