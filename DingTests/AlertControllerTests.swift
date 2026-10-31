import XCTest
import SwiftUI
import DingCore
@testable import Ding

@MainActor
final class AlertControllerTests: XCTestCase {
    private var controller: AlertController!
    private var ordered: [(window: NSWindow, key: Bool)] = []
    private var activations = 0
    private var opened: [MeetingLink] = []

    private let link = MeetingLink(service: .zoom, url: URL(string: "https://zoom.us/j/1")!)
    private var event: DingEvent {
        DingEvent(id: "a", title: "Standup", start: Date(), end: Date().addingTimeInterval(1800), link: link)
    }

    override func setUp() {
        super.setUp()
        MainActor.assumeIsolated {
            controller = AlertController()
            ordered = []
            activations = 0
            opened = []
            // Nothing is ever put on screen during tests.
            controller.orderFront = { [unowned self] window, key in ordered.append((window, key)) }
            controller.activateApp = { [unowned self] in activations += 1 }
            controller.openLink = { [unowned self] in opened.append($0) }
        }
    }

    override func tearDown() {
        MainActor.assumeIsolated { controller.dismiss() }
        super.tearDown()
    }

    private var screenCount: Int { NSScreen.screens.count }

    // MARK: Window construction

    func testFlashWindowsCoverEveryScreenAndIgnoreTheMouse() {
        let windows = controller.makeFlashWindows()
        XCTAssertEqual(windows.count, screenCount)
        for window in windows {
            XCTAssertTrue(window.ignoresMouseEvents)
            XCTAssertFalse(window.isOpaque)
            XCTAssertEqual(window.level, .screenSaver)
            XCTAssertTrue(window.styleMask == .borderless)
            XCTAssertFalse(window.hasShadow)
            XCTAssertTrue(window.collectionBehavior.contains(.canJoinAllSpaces))
            XCTAssertNotNil(window.contentView)
        }
        zip(windows, NSScreen.screens).forEach { XCTAssertEqual($0.frame, $1.frame) }
    }

    func testTakeoverWindowsCoverEveryScreenAndCanTakeFocus() {
        let windows = controller.makeTakeoverWindows(for: event)
        XCTAssertEqual(windows.count, screenCount)
        for window in windows {
            XCTAssertTrue(window.canBecomeKey)
            XCTAssertTrue(window.canBecomeMain)
            XCTAssertEqual(window.level, .screenSaver)
            XCTAssertFalse(window.ignoresMouseEvents)
        }
    }

    func testTakeoverCanBeBuiltForAMultiDisplaySetup() {
        guard let screen = NSScreen.screens.first else { return }
        controller.screens = { [screen, screen, screen] }
        controller.primaryScreen = { screen }
        XCTAssertEqual(controller.makeTakeoverWindows(for: event).count, 3)
        XCTAssertEqual(controller.makeFlashWindows().count, 3)
    }

    // MARK: Showing

    func testOffShowsNothing() {
        controller.show(event, mode: .off)
        XCTAssertTrue(ordered.isEmpty)
        XCTAssertTrue(controller.windows.isEmpty)
    }

    func testEdgeFlashOrdersFrontEveryScreenWithoutStealingFocus() {
        controller.flashDuration = 0.05
        controller.show(event, mode: .edgeFlash)
        XCTAssertEqual(ordered.count, screenCount)
        XCTAssertTrue(ordered.allSatisfy { !$0.key })
        XCTAssertEqual(activations, 0)
    }

    func testEdgeFlashWindowsCloseThemselves() {
        controller.flashDuration = 0.05
        controller.show(event, mode: .edgeFlash)
        let windows = ordered.map(\.window)
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        XCTAssertTrue(windows.allSatisfy { !$0.isVisible })
    }

    func testFullScreenMakesThePrimaryDisplayKeyAndActivatesTheApp() {
        controller.show(event, mode: .fullScreen)
        XCTAssertEqual(ordered.count, screenCount)
        XCTAssertEqual(ordered.filter(\.key).count, 1)
        XCTAssertEqual(activations, 1)
        XCTAssertEqual(controller.windows.count, screenCount)
    }

    func testShowingAgainReplacesThePreviousTakeover() {
        controller.show(event, mode: .fullScreen)
        let first = controller.windows
        controller.show(event, mode: .fullScreen)
        XCTAssertEqual(controller.windows.count, screenCount)
        XCTAssertTrue(zip(first, controller.windows).allSatisfy { $0 !== $1 })
    }

    // MARK: Dismissing

    func testDismissClosesAndForgetsWindows() {
        controller.show(event, mode: .fullScreen)
        controller.dismiss()
        XCTAssertTrue(controller.windows.isEmpty)
    }

    func testDismissWithNothingShownIsSafe() {
        controller.dismiss()
        XCTAssertTrue(controller.windows.isEmpty)
    }

    func testEscapeDismissesViaCancelOperation() throws {
        controller.show(event, mode: .fullScreen)
        let window = try XCTUnwrap(controller.windows.first as? AlertWindow)
        window.cancelOperation(nil)
        XCTAssertTrue(controller.windows.isEmpty)
    }

    func testEscapeKeyDismisses() throws {
        controller.show(event, mode: .fullScreen)
        let window = try XCTUnwrap(controller.windows.first as? AlertWindow)
        let esc = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0,
            context: nil, characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53
        ))
        window.keyDown(with: esc)
        XCTAssertTrue(controller.windows.isEmpty)
    }

    // MARK: Views

    private func render<V: View>(_ view: V) {
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: 1200, height: 800)
        host.layoutSubtreeIfNeeded()
        XCTAssertGreaterThan(host.fittingSize.width, 0)
    }

    func testAlertViewsRender() {
        render(EdgeFlashView())
        render(FullScreenAlertView(event: event, join: {}, snooze: {}, dismiss: {}))
        render(FullScreenAlertView(event: nil, join: {}, snooze: {}, dismiss: {}))
        var noLink = event
        noLink.link = nil
        render(FullScreenAlertView(event: noLink, join: {}, snooze: {}, dismiss: {}))
    }
}
