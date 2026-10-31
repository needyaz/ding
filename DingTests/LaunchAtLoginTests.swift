import XCTest
@testable import Ding

final class LaunchAtLoginTests: XCTestCase {
    private let item = FakeLoginItem()

    override func setUp() {
        super.setUp()
        LaunchAtLogin.service = item
    }

    override func tearDown() {
        LaunchAtLogin.service = MainAppLoginItem()
        super.tearDown()
    }

    func testEnablingRegisters() {
        XCTAssertTrue(LaunchAtLogin.set(true))
        XCTAssertEqual(item.registers, 1)
        XCTAssertTrue(LaunchAtLogin.isEnabled)
    }

    func testDisablingUnregisters() {
        item.isEnabled = true
        XCTAssertTrue(LaunchAtLogin.set(false))
        XCTAssertEqual(item.unregisters, 1)
        XCTAssertFalse(LaunchAtLogin.isEnabled)
    }

    func testFailureIsReportedAndStateIsUnchanged() {
        item.shouldFail = true
        XCTAssertFalse(LaunchAtLogin.set(true))
        XCTAssertFalse(LaunchAtLogin.isEnabled)
        item.isEnabled = true
        XCTAssertFalse(LaunchAtLogin.set(false))
        XCTAssertTrue(LaunchAtLogin.isEnabled)
    }

    func testTheRealServiceIsReadable() {
        _ = MainAppLoginItem().isEnabled  // reading never changes login items
    }
}
