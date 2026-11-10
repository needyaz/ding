import XCTest
import KeyboardShortcuts
@testable import Ding

/// Both global hotkeys stay off until the user records a shortcut on the Shortcuts tab.
@MainActor
final class HotkeyDefaultsTests: IsolatedDefaultsTestCase {
    private let names: [KeyboardShortcuts.Name] = [.openMenu, .joinNext]
    private var saved: [KeyboardShortcuts.Name: KeyboardShortcuts.Shortcut] = [:]

    override func setUp() {
        super.setUp()
        // The package stores shortcuts in the standard defaults; keep a developer's recorded ones safe.
        MainActor.assumeIsolated {
            saved = [:]
            for name in names {
                if let shortcut = KeyboardShortcuts.getShortcut(for: name) { saved[name] = shortcut }
            }
        }
    }

    override func tearDown() {
        MainActor.assumeIsolated {
            for name in names {
                if let shortcut = saved[name] { KeyboardShortcuts.setShortcut(shortcut, for: name) }
            }
        }
        super.tearDown()
    }

    func test_DING_HOTKEY_001_keeps_neitherHotkeyHasADefaultShortcut() {
        XCTAssertNil(KeyboardShortcuts.Name.openMenu.defaultShortcut, "DING-HOTKEY-001: Open Ding menu ships without a shortcut")
        XCTAssertNil(KeyboardShortcuts.Name.joinNext.defaultShortcut, "DING-HOTKEY-001: Join next meeting ships without a shortcut")
    }

    func test_DING_HOTKEY_001_keeps_withNothingRecordedNeitherHotkeyHasAShortcut() {
        KeyboardShortcuts.reset(names)
        XCTAssertNil(KeyboardShortcuts.getShortcut(for: .openMenu), "DING-HOTKEY-001: Open Ding menu is off until recorded")
        XCTAssertNil(KeyboardShortcuts.getShortcut(for: .joinNext), "DING-HOTKEY-001: Join next meeting is off until recorded")
    }
}
