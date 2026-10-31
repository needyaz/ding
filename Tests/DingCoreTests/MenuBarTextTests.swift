import XCTest
@testable import DingCore

/// Text beside the menu bar icon, and title truncation.
final class MenuBarTextTests: DingCoreTestCase {
    func testMenuBarText() {
        let now = date(2026, 10, 30, 9, 0)
        let next = event("Standup", date(2026, 10, 30, 9, 12))
        XCTAssertEqual(MenuBarText.make(next: next, now: now, options: MenuBarOptions(), calendar: calendar), "Standup in 12m")
        XCTAssertEqual(MenuBarText.make(next: next, now: now, options: MenuBarOptions(showTitle: false), calendar: calendar), "in 12m")
        XCTAssertEqual(MenuBarText.make(next: next, now: now, options: MenuBarOptions(showCountdown: false), calendar: calendar), "Standup")
        XCTAssertNil(MenuBarText.make(next: next, now: now, options: MenuBarOptions(showCountdown: false, showTitle: false), calendar: calendar))
        XCTAssertNil(MenuBarText.make(next: nil, now: now, options: MenuBarOptions(), calendar: calendar))
    }

    func testMenuBarTextNow() {
        let start = date(2026, 10, 30, 9, 0)
        let next = event("Standup", start)
        XCTAssertEqual(MenuBarText.make(next: next, now: start, options: MenuBarOptions(), calendar: calendar), "Standup now")
        XCTAssertEqual(MenuBarText.make(next: next, now: start, options: MenuBarOptions(showTitle: false), calendar: calendar), "now")
    }

    func testMenuBarTextCountdownOnlyToday() {
        let now = date(2026, 10, 30, 17, 0)
        let tomorrow = event("Standup", date(2026, 10, 31, 9, 0))
        let options = MenuBarOptions(countdownOnlyToday: true)
        XCTAssertNil(MenuBarText.make(next: tomorrow, now: now, options: options, calendar: calendar))
        XCTAssertNotNil(MenuBarText.make(next: tomorrow, now: now, options: MenuBarOptions(), calendar: calendar))
    }

    func testTruncation() {
        XCTAssertEqual(Truncation.truncate("Short", maxLength: 24), "Short")
        XCTAssertEqual(Truncation.truncate("Quarterly business review with everyone", maxLength: 12), "Quarterly b…")
        XCTAssertEqual(Truncation.truncate("Line one\nLine two", maxLength: 40), "Line one Line two")
        XCTAssertEqual(Truncation.truncate("Trailing space here ok", maxLength: 9), "Trailing…")
        XCTAssertEqual(Truncation.truncate("  padded  ", maxLength: 24), "padded")
    }
}
