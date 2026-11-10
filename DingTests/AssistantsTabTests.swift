import SwiftUI
import XCTest
@testable import Ding

@MainActor
final class AssistantsTabTests: IsolatedDefaultsTestCase {
    private func render<V: View>(_ view: V) {
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: 480, height: 440)
        host.layoutSubtreeIfNeeded()
        XCTAssertGreaterThan(host.fittingSize.height, 0)
    }

    func testTheTabRendersWithAndWithoutTheHelper() {
        render(AssistantsTab(helperPath: "/Applications/Ding.app/Contents/Helpers/ding-mcp", copy: { _ in }))
        render(AssistantsTab(helperPath: nil, copy: { _ in }))
    }

    func testTheSettingsWindowHasAnAssistantsTab() {
        render(SettingsView(model: AppModel.test()))
    }

    func testTheHelperIsFoundInsideAnAppBundle() throws {
        let app = FileManager.default.temporaryDirectory.appendingPathComponent("Fake\(UUID().uuidString.prefix(6)).app")
        let helper = app.appendingPathComponent(ControlHelper.relativePath)
        try FileManager.default.createDirectory(at: helper.deletingLastPathComponent(), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: app) }

        XCTAssertNil(ControlHelper.path(bundleURL: app), "no helper yet")
        FileManager.default.createFile(atPath: helper.path, contents: Data("#!/bin/sh\n".utf8), attributes: [.posixPermissions: 0o644])
        XCTAssertNil(ControlHelper.path(bundleURL: app), "present but not executable")
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: helper.path)
        XCTAssertEqual(ControlHelper.path(bundleURL: app), helper.path)
    }

    func testTheHelperPathEndsWhereTheProjectPutsIt() {
        XCTAssertEqual(ControlHelper.relativePath, "Contents/Helpers/ding-mcp")
    }

    func testTheRealBuildIncludesTheHelper() {
        // The app under test is the real bundle, so the embed step in project.yml is what makes this true.
        XCTAssertNotNil(ControlHelper.path(), "ding-mcp should be embedded in Ding.app/Contents/Helpers")
    }

    func testControlServerIsNotStartedByTestModels() {
        XCTAssertFalse(AppModel.test().startsControlServer)
        XCTAssertTrue(AppModel(calendar: FakeCalendar(), notifier: FakeNotifier()).startsControlServer, "but a normal model starts it")
    }
}
