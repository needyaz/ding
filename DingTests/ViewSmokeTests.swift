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

    /// Roughly a real work calendar: about eight meetings a day for two weeks.
    private func busyCalendar(now: Date) -> [DingEvent] {
        let link = MeetingLink(service: .zoom, url: URL(string: "https://zoom.us/j/1")!)
        return (0..<110).map { i in
            let start = now.addingTimeInterval(Double(i) * 3 * 3600 + 600)
            return DingEvent(id: "busy\(i)", title: "Meeting number \(i)", start: start, end: start.addingTimeInterval(1800), link: i % 2 == 0 ? link : nil)
        }
    }

    func testMenuWithEvents() {
        let model = AppModel.test()
        model.access = .granted
        model.now = Date()
        model.events = sampleEvents(now: model.now)
        render(MenuContentView(model: model))
    }

    /// Height the content asks for when its window sizes itself to fit, as the menu bar window does.
    private func windowHeight<V: View>(_ view: V) -> CGFloat {
        let controller = NSHostingController(rootView: view.fixedSize())
        controller.sizingOptions = [.preferredContentSize]
        let window = NSWindow(contentViewController: controller)
        window.setContentSize(NSSize(width: 340, height: 10))
        controller.view.layoutSubtreeIfNeeded()
        return controller.preferredContentSize.height
    }

    private func menu(events: [DingEvent]) -> MenuContentView {
        let model = AppModel.test()
        model.access = .granted
        model.now = Date()
        model.events = events
        return MenuContentView(model: model)
    }

    // The list once collapsed to zero height inside the real menu bar window (a 340x36 popover with only the
    // footer). That only happens in the real window, so these check the design that prevents it: a short list is
    // a plain stack, a long one scrolls inside an explicit height, and the size is right from the first layout.

    func testALongListIsCappedAndScrolls() {
        let events = busyCalendar(now: Date())
        let long = windowHeight(menu(events: events))
        let empty = windowHeight(menu(events: []))
        XCTAssertGreaterThan(long, empty + 400, "the list collapsed (\(long) vs empty \(empty))")
        XCTAssertLessThan(long, 800, "the list isn't capped")
    }

    func testAShortListShrinksToFitItsContent() {
        let short = windowHeight(menu(events: sampleEvents(now: Date())))
        let long = windowHeight(menu(events: busyCalendar(now: Date())))
        let empty = windowHeight(menu(events: []))
        XCTAssertGreaterThan(short, empty + 100)
        XCTAssertLessThan(short, long - 100, "a short list should not be as tall as a long one")
    }

    func testTheScrollThresholdFollowsTheContent() {
        func groups(rows: Int) -> [DayGroup] {
            let start = Date()
            let events = (0..<rows).map { DingEvent(id: "\($0)", title: "E\($0)", start: start, end: start.addingTimeInterval(60)) }
            return [DayGroup(day: start, events: events)]
        }
        XCTAssertFalse(MenuContentView.needsScrolling([]))
        XCTAssertFalse(MenuContentView.needsScrolling(groups(rows: 4)))
        XCTAssertFalse(MenuContentView.needsScrolling(groups(rows: 10)))
        XCTAssertTrue(MenuContentView.needsScrolling(groups(rows: 12)))
        XCTAssertTrue(MenuContentView.needsScrolling(groups(rows: 100)))
    }

    func testTheNextMeetingCardAddsHeightAboveTheList() {
        let today = Calendar.current.startOfDay(for: Date())
        let calendarWithoutNext = windowHeight(menu(events: [
            DingEvent(id: "allday", title: "Holiday", start: today, end: today.addingTimeInterval(86_399), isAllDay: true),
        ]))
        let calendarWithNext = windowHeight(menu(events: [
            DingEvent(id: "m", title: "Standup", start: Date().addingTimeInterval(600), end: Date().addingTimeInterval(2400),
                      link: MeetingLink(service: .zoom, url: URL(string: "https://zoom.us/j/1")!)),
        ]))
        // An all-day event can't be "next", so no card; a timed one gets the card plus its row.
        XCTAssertGreaterThan(calendarWithNext, calendarWithoutNext + 40)
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
