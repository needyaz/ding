import XCTest
@testable import DingCore

private final class FakeWorkspace: WorkspaceOpening {
    enum Call: Equatable {
        case open(URL)
        case openWith(URL, String)
    }

    var installedApps: Set<String> = []
    var schemeHandlers: Set<String> = []
    private(set) var calls: [Call] = []

    func open(_ url: URL) { calls.append(.open(url)) }

    func open(_ url: URL, withAppBundleID bundleID: String) -> Bool {
        guard installedApps.contains(bundleID) else { return false }
        calls.append(.openWith(url, bundleID))
        return true
    }

    func hasHandler(for url: URL) -> Bool { schemeHandlers.contains(url.scheme ?? "") }
}

final class OpenTargetTests: XCTestCase {
    func testParsing() {
        XCTAssertEqual(OpenTarget(rawValue: "native"), .nativeApp)
        XCTAssertEqual(OpenTarget(rawValue: "default"), .defaultBrowser)
        XCTAssertEqual(OpenTarget(rawValue: ""), .defaultBrowser)
        XCTAssertEqual(OpenTarget(rawValue: "org.mozilla.firefox"), .browser(bundleID: "org.mozilla.firefox"))
    }

    func testRawValueRoundTrips() {
        for target in [OpenTarget.nativeApp, .defaultBrowser, .browser(bundleID: "com.google.Chrome")] {
            XCTAssertEqual(OpenTarget(rawValue: target.rawValue), target)
        }
    }

    func testDefaults() {
        XCTAssertEqual(OpenTarget.defaultValue(for: .zoom), "native")
        for service in [MeetingService.googleMeet, .teams, .webex, .other] {
            XCTAssertEqual(OpenTarget.defaultValue(for: service), "default", "\(service)")
        }
    }

    func testResolveUsesDefaultWhenUnset() {
        XCTAssertEqual(OpenTarget.resolve(nil, for: .zoom), .nativeApp)
        XCTAssertEqual(OpenTarget.resolve(nil, for: .teams), .defaultBrowser)
    }

    func testResolveHonorsStoredChoice() {
        XCTAssertEqual(OpenTarget.resolve("com.apple.Safari", for: .googleMeet), .browser(bundleID: "com.apple.Safari"))
        XCTAssertEqual(OpenTarget.resolve("default", for: .zoom), .defaultBrowser)
        XCTAssertEqual(OpenTarget.resolve("native", for: .teams), .nativeApp)
    }

    func testResolveRejectsNativeForServicesWithoutAnApp() {
        XCTAssertEqual(OpenTarget.resolve("native", for: .googleMeet), .defaultBrowser)
        XCTAssertEqual(OpenTarget.resolve("native", for: .other), .defaultBrowser)
    }
}

final class MeetingOpenerTests: XCTestCase {
    private let workspace = FakeWorkspace()
    private lazy var opener = MeetingOpener(workspace: workspace)

    private func link(_ service: MeetingService, _ string: String) -> MeetingLink {
        MeetingLink(service: service, url: URL(string: string)!)
    }

    private let zoom = "https://us02web.zoom.us/j/84512345678?pwd=abc"
    private let teams = "https://teams.microsoft.com/l/meetup-join/19%3ameeting_abc/0"
    private let webex = "https://acme.webex.com/meet/nate"
    private let meet = "https://meet.google.com/abc-defg-hij"

    // MARK: Default browser

    func testDefaultBrowserOpensTheWebURL() {
        opener.open(link(.googleMeet, meet), target: .defaultBrowser)
        XCTAssertEqual(workspace.calls, [.open(URL(string: meet)!)])
    }

    // MARK: Specific browser

    func testSpecificBrowserOpensWithThatApp() {
        workspace.installedApps = ["org.mozilla.firefox"]
        opener.open(link(.googleMeet, meet), target: .browser(bundleID: "org.mozilla.firefox"))
        XCTAssertEqual(workspace.calls, [.openWith(URL(string: meet)!, "org.mozilla.firefox")])
    }

    func testMissingBrowserFallsBackToDefault() {
        opener.open(link(.googleMeet, meet), target: .browser(bundleID: "org.mozilla.firefox"))
        XCTAssertEqual(workspace.calls, [.open(URL(string: meet)!)])
    }

    // MARK: Zoom native

    func testZoomNativeUsesDeepLinkWhenSchemeIsHandled() {
        workspace.schemeHandlers = ["zoommtg"]
        opener.open(link(.zoom, zoom), target: .nativeApp)
        XCTAssertEqual(workspace.calls, [.open(URL(string: "zoommtg://us02web.zoom.us/join?confno=84512345678&pwd=abc")!)])
    }

    func testZoomNativeWithoutSchemeHandlerTriesAppBundle() {
        workspace.installedApps = ["us.zoom.xos"]
        opener.open(link(.zoom, zoom), target: .nativeApp)
        XCTAssertEqual(workspace.calls, [.openWith(URL(string: zoom)!, "us.zoom.xos")])
    }

    func testZoomPersonalRoomHasNoDeepLinkSoItUsesTheApp() {
        let personal = "https://acme.zoom.us/my/nate"
        workspace.schemeHandlers = ["zoommtg"]
        workspace.installedApps = ["us.zoom.xos"]
        opener.open(link(.zoom, personal), target: .nativeApp)
        XCTAssertEqual(workspace.calls, [.openWith(URL(string: personal)!, "us.zoom.xos")])
    }

    func testZoomNativeFallsBackToBrowserWhenNothingInstalled() {
        opener.open(link(.zoom, zoom), target: .nativeApp)
        XCTAssertEqual(workspace.calls, [.open(URL(string: zoom)!)])
    }

    // MARK: Teams native

    func testTeamsNativeUsesMsteamsScheme() {
        workspace.schemeHandlers = ["msteams"]
        opener.open(link(.teams, teams), target: .nativeApp)
        XCTAssertEqual(workspace.calls.count, 1)
        guard case .open(let url) = workspace.calls[0] else { return XCTFail("expected a plain open") }
        XCTAssertEqual(url.scheme, "msteams")
        XCTAssertEqual(url.path, URL(string: teams)!.path)
    }

    func testTeamsNativePrefersNewTeamsBundleThenClassic() {
        workspace.installedApps = ["com.microsoft.teams2", "com.microsoft.teams"]
        opener.open(link(.teams, teams), target: .nativeApp)
        XCTAssertEqual(workspace.calls, [.openWith(URL(string: teams)!, "com.microsoft.teams2")])

        let classic = FakeWorkspace()
        classic.installedApps = ["com.microsoft.teams"]
        MeetingOpener(workspace: classic).open(link(.teams, teams), target: .nativeApp)
        XCTAssertEqual(classic.calls, [.openWith(URL(string: teams)!, "com.microsoft.teams")])
    }

    func testTeamsNativeFallsBackToBrowser() {
        opener.open(link(.teams, teams), target: .nativeApp)
        XCTAssertEqual(workspace.calls, [.open(URL(string: teams)!)])
    }

    // MARK: Webex and others

    func testWebexNativeOpensWebURLInTheApp() {
        workspace.installedApps = ["Cisco-Systems.Spark"]
        opener.open(link(.webex, webex), target: .nativeApp)
        XCTAssertEqual(workspace.calls, [.openWith(URL(string: webex)!, "Cisco-Systems.Spark")])
    }

    func testWebexNativeFallsBackToBrowser() {
        opener.open(link(.webex, webex), target: .nativeApp)
        XCTAssertEqual(workspace.calls, [.open(URL(string: webex)!)])
    }

    func testServicesWithoutAppsAlwaysFallBackToBrowserOnNative() {
        workspace.schemeHandlers = ["zoommtg", "msteams", "https"]
        workspace.installedApps = ["us.zoom.xos"]
        opener.open(link(.googleMeet, meet), target: .nativeApp)
        opener.open(link(.other, "https://whereby.com/acme"), target: .nativeApp)
        XCTAssertEqual(workspace.calls, [.open(URL(string: meet)!), .open(URL(string: "https://whereby.com/acme")!)])
    }

    func testNativeOpensExactlyOnce() {
        workspace.schemeHandlers = ["zoommtg"]
        workspace.installedApps = ["us.zoom.xos"]
        opener.open(link(.zoom, zoom), target: .nativeApp)
        XCTAssertEqual(workspace.calls.count, 1)
    }

    func testEveryServiceReachesTheBrowserWithNothingInstalled() {
        for service in MeetingService.allCases {
            let ws = FakeWorkspace()
            let url = URL(string: "https://example.com/\(service.rawValue)")!
            MeetingOpener(workspace: ws).open(MeetingLink(service: service, url: url), target: .nativeApp)
            XCTAssertEqual(ws.calls, [.open(url)], "\(service)")
        }
    }
}
