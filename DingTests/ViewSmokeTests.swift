import XCTest
import SwiftUI
import DingCore
@testable import Ding

/// Renders each screen so a crash or layout trap in a view fails a test.
@MainActor
final class ViewSmokeTests: IsolatedDefaultsTestCase {
    private func render<V: View>(_ view: V, file: StaticString = #filePath, line: UInt = #line) {
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: 480, height: 600)
        host.layoutSubtreeIfNeeded()
        XCTAssertGreaterThan(host.fittingSize.height, 0, file: file, line: line)
    }

    private func sampleEvents(now: Date) -> [DingEvent] {
        let zoom = MeetingLink(service: .zoom, url: URL(string: "https://zoom.us/j/1")!)
        return [
            DingEvent(id: "1", title: "A meeting with a very long title that should be truncated by the row", start: now.addingTimeInterval(600), end: now.addingTimeInterval(2400), calendarColor: CalendarColor(red: 1, green: 0, blue: 0), link: zoom),
            DingEvent(id: "2", title: "Maybe", start: now.addingTimeInterval(7200), end: now.addingTimeInterval(9000), isMaybe: true),
            DingEvent(id: "3", title: "Holiday", start: Calendar.current.startOfDay(for: now), end: Calendar.current.startOfDay(for: now).addingTimeInterval(86_399), isAllDay: true),
            DingEvent(id: "4", title: "Tomorrow", start: now.addingTimeInterval(90_000), end: now.addingTimeInterval(91_800), link: zoom),
        ]
    }

    func testMenuWithEvents() {
        let model = AppModel.test()
        model.access = .granted
        model.now = Date()
        model.events = sampleEvents(now: model.now)
        render(MenuContentView(model: model))
    }

    func testMenuWithNoEvents() {
        let model = AppModel.test()
        model.access = .granted
        render(MenuContentView(model: model))
    }

    func testMenuBeforeCalendarAccessIsDecided() {
        let model = AppModel.test()
        model.access = .notDetermined
        render(MenuContentView(model: model))
    }

    func testMenuWhenCalendarAccessIsDenied() {
        let model = AppModel.test()
        model.access = .denied
        render(MenuContentView(model: model))
    }

    func testMenuBarLabelWithAndWithoutText() {
        let model = AppModel.test()
        model.now = Date()
        render(MenuBarLabel(model: model))
        model.events = sampleEvents(now: model.now)
        XCTAssertNotNil(model.menuBarText)
        render(MenuBarLabel(model: model))
    }

    func testSettingsRendersWithAndWithoutCalendars() {
        let model = AppModel.test()
        render(SettingsView(model: model))
        model.access = .granted
        model.accounts = [
            CalendarAccount(title: "iCloud", calendars: [CalendarInfo(id: "1", title: "Home", color: .gray)]),
            CalendarAccount(title: "Work", calendars: [CalendarInfo(id: "2", title: "Calendar", color: CalendarColor(red: 0, green: 0.5, blue: 1))]),
        ]
        render(SettingsView(model: model))
    }

    func testCalendarColorConversion() {
        _ = CalendarColor(red: 0.2, green: 0.4, blue: 0.6).color
    }
}
