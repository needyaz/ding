import XCTest
import DingCore
@testable import Ding

final class SystemWorkspaceTests: XCTestCase {
    private let workspace = SystemWorkspace()

    func testWebURLsHaveAHandler() {
        XCTAssertTrue(workspace.hasHandler(for: URL(string: "https://example.com")!))
    }

    func testUnregisteredSchemesHaveNoHandler() {
        XCTAssertFalse(workspace.hasHandler(for: URL(string: "ding-test-no-such-scheme://x")!))
    }

    func testOpeningWithAnUninstalledAppReportsFailureWithoutOpeningAnything() {
        XCTAssertFalse(workspace.open(URL(string: "https://example.com")!, withAppBundleID: "com.example.not-installed.\(UUID().uuidString)"))
    }
}

final class InstalledBrowsersTests: XCTestCase {
    func testListsSafariAndNotDing() {
        let browsers = LinkOpener.installedBrowsers()
        XCTAssertTrue(browsers.contains { $0.bundleID == "com.apple.Safari" })
        XCTAssertFalse(browsers.contains { $0.bundleID == Bundle.main.bundleIdentifier })
    }

    func testBrowsersAreUniqueAndSortedByName() {
        let browsers = LinkOpener.installedBrowsers()
        XCTAssertEqual(Set(browsers.map(\.bundleID)).count, browsers.count)
        let names = browsers.map(\.name)
        XCTAssertEqual(names, names.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending })
        XCTAssertFalse(browsers.contains { $0.name.hasSuffix(".app") })
    }
}
