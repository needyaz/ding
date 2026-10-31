import XCTest
import SwiftUI
import DingCore
@testable import Ding

@MainActor
final class SettingsTabTests: IsolatedDefaultsTestCase {
    private func render<V: View>(_ view: V, file: StaticString = #filePath, line: UInt = #line) {
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: 480, height: 440)
        host.layoutSubtreeIfNeeded()
        XCTAssertGreaterThan(host.fittingSize.height, 0, file: file, line: line)
    }

    func testEveryTabRenders() {
        let model = AppModel.test()
        model.accounts = [CalendarAccount(title: "iCloud", calendars: [CalendarInfo(id: "1", title: "Home", color: .gray)])]
        render(GeneralTab())
        render(CalendarsTab(model: model))
        render(MeetingsTab())
        render(AlertsTab(model: model))
        render(ShortcutsTab())
    }

    func testCalendarsTabExplainsWhyItIsEmpty() {
        let model = AppModel.test()
        model.access = .denied
        render(CalendarsTab(model: model))
        model.access = .granted
        render(CalendarsTab(model: model))
    }

    func testEveryServicePickerRendersWithBrowsers() {
        let browsers = [LinkOpener.Browser(bundleID: "com.apple.Safari", name: "Safari"), LinkOpener.Browser(bundleID: "org.mozilla.firefox", name: "Firefox")]
        for service in MeetingService.allCases {
            render(ServiceOpenPicker(service: service, browsers: browsers))
        }
        render(ServiceOpenPicker(service: .zoom, browsers: []))
    }

    func testPickerReflectsTheStoredChoice() {
        suite.set("org.mozilla.firefox", forKey: Pref.openKey(.teams))
        XCTAssertEqual(OpenTarget.current(for: .teams), .browser(bundleID: "org.mozilla.firefox"))
        render(ServiceOpenPicker(service: .teams, browsers: [LinkOpener.Browser(bundleID: "org.mozilla.firefox", name: "Firefox")]))
    }

    func testRootSettingsViewRenders() {
        render(SettingsView(model: AppModel.test()))
    }
}
