import XCTest
import AppKit
@testable import Ding

@MainActor
final class SettingsWindowTests: XCTestCase {
    func testWindowIsBuiltOnceWithExpectedChrome() {
        let controller = SettingsWindowController()
        let window = controller.makeWindow()
        XCTAssertEqual(window.title, "Ding Preferences")
        XCTAssertTrue(window.styleMask.contains(.titled))
        XCTAssertTrue(window.styleMask.contains(.closable))
        XCTAssertFalse(window.styleMask.contains(.resizable))
        XCTAssertFalse(window.isReleasedWhenClosed)
        XCTAssertFalse(window.isVisible)
        XCTAssertTrue(controller.makeWindow() === window)
    }

    func testShowActivatesTheAppAndOrdersTheWindowFront() {
        var activations = 0
        var ordered: [NSWindow] = []
        let controller = SettingsWindowController(activate: { activations += 1 })
        controller.show { ordered.append($0) }
        XCTAssertEqual(activations, 1)
        XCTAssertEqual(ordered.count, 1)
        XCTAssertTrue(ordered.first === controller.makeWindow())
    }

    func testShowingTwiceReusesTheWindow() {
        var ordered: [NSWindow] = []
        let controller = SettingsWindowController(activate: {})
        controller.show { ordered.append($0) }
        controller.show { ordered.append($0) }
        XCTAssertTrue(ordered[0] === ordered[1])
    }
}
