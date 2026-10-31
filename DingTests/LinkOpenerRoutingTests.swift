import XCTest
import DingCore
@testable import Ding

final class LinkOpenerRoutingTests: IsolatedDefaultsTestCase {
    private let workspace = RecordingWorkspace()

    override func setUp() {
        super.setUp()
        LinkOpener.workspace = workspace
    }

    override func tearDown() {
        LinkOpener.workspace = SystemWorkspace()
        super.tearDown()
    }

    private func link(_ service: MeetingService, _ url: String) -> MeetingLink {
        MeetingLink(service: service, url: URL(string: url)!)
    }

    func testZoomDefaultsToTheDesktopApp() {
        workspace.schemeHandlers = ["zoommtg"]
        LinkOpener.open(link(.zoom, "https://us02web.zoom.us/j/84512345678?pwd=abc"))
        XCTAssertEqual(workspace.calls, [.open(URL(string: "zoommtg://us02web.zoom.us/join?confno=84512345678&pwd=abc")!)])
    }

    func testOtherServicesDefaultToTheBrowser() {
        workspace.schemeHandlers = ["zoommtg", "msteams"]
        workspace.installedApps = ["com.microsoft.teams2", "Cisco-Systems.Spark"]
        let urls = [
            link(.googleMeet, "https://meet.google.com/abc-defg-hij"),
            link(.teams, "https://teams.microsoft.com/l/meetup-join/x"),
            link(.webex, "https://acme.webex.com/meet/nate"),
            link(.other, "https://whereby.com/acme"),
        ]
        urls.forEach(LinkOpener.open)
        XCTAssertEqual(workspace.calls, urls.map { .open($0.url) })
    }

    func testChoosingAnotherBrowserForAService() {
        workspace.installedApps = ["org.mozilla.firefox"]
        suite.set("org.mozilla.firefox", forKey: Pref.openKey(.googleMeet))
        let meet = link(.googleMeet, "https://meet.google.com/abc-defg-hij")
        LinkOpener.open(meet)
        XCTAssertEqual(workspace.calls, [.openWith(meet.url, "org.mozilla.firefox")])
    }

    func testChoosingTheDesktopAppForTeams() {
        workspace.schemeHandlers = ["msteams"]
        suite.set("native", forKey: Pref.openKey(.teams))
        LinkOpener.open(link(.teams, "https://teams.microsoft.com/l/meetup-join/x"))
        guard case .open(let url)? = workspace.calls.first else { return XCTFail("expected an open") }
        XCTAssertEqual(url.scheme, "msteams")
    }

    func testZoomSetToBrowserSkipsTheApp() {
        workspace.schemeHandlers = ["zoommtg"]
        workspace.installedApps = ["us.zoom.xos"]
        suite.set("default", forKey: Pref.openKey(.zoom))
        let zoom = link(.zoom, "https://zoom.us/j/1")
        LinkOpener.open(zoom)
        XCTAssertEqual(workspace.calls, [.open(zoom.url)])
    }

    func testAnUninstalledChosenBrowserFallsBackToDefault() {
        suite.set("org.mozilla.firefox", forKey: Pref.openKey(.webex))
        let webex = link(.webex, "https://acme.webex.com/meet/nate")
        LinkOpener.open(webex)
        XCTAssertEqual(workspace.calls, [.open(webex.url)])
    }

    func testNativeIsIgnoredForServicesWithoutADesktopApp() {
        workspace.installedApps = ["us.zoom.xos"]
        suite.set("native", forKey: Pref.openKey(.googleMeet))
        let meet = link(.googleMeet, "https://meet.google.com/abc-defg-hij")
        LinkOpener.open(meet)
        XCTAssertEqual(workspace.calls, [.open(meet.url)])
    }

    func testEachServiceCanBeConfiguredIndependently() {
        workspace.installedApps = ["com.apple.Safari", "org.mozilla.firefox"]
        suite.set("com.apple.Safari", forKey: Pref.openKey(.googleMeet))
        suite.set("org.mozilla.firefox", forKey: Pref.openKey(.other))
        let meet = link(.googleMeet, "https://meet.google.com/abc-defg-hij")
        let other = link(.other, "https://whereby.com/acme")
        LinkOpener.open(meet)
        LinkOpener.open(other)
        XCTAssertEqual(workspace.calls, [.openWith(meet.url, "com.apple.Safari"), .openWith(other.url, "org.mozilla.firefox")])
    }
}
