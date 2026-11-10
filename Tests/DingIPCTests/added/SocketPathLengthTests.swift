import Darwin
import XCTest
@testable import DingIPC

/// The socket path Ding really uses must fit in a Unix socket address.
final class SocketPathLengthTests: XCTestCase {
    /// Answers the app group container with a fixed path, as long as a real one can be.
    private final class LongContainerFileManager: FileManager {
        let container: URL
        init(container: URL) { self.container = container; super.init() }
        override func containerURL(forSecurityApplicationGroupIdentifier groupIdentifier: String) -> URL? { container }
    }

    private var sunPathSize: Int { MemoryLayout.size(ofValue: sockaddr_un().sun_path) }

    func test_DING_IPC_008_keeps_theRealSocketPathFitsInSunPath() throws {
        let user = String(repeating: "u", count: 32)
        let group = "46XLY7Y9P8.blue.luci.Ding"
        let container = URL(fileURLWithPath: "/Users/\(user)/Library/Group Containers/\(group)", isDirectory: true)
        let url = try XCTUnwrap(DingIPC.socketURL(appGroup: group, fileManager: LongContainerFileManager(container: container)))

        XCTAssertTrue(url.path.hasPrefix(container.path + "/"), "DING-IPC-008: the socket lives in the app group container")
        XCTAssertLessThanOrEqual(url.path.utf8.count + 1, sunPathSize, "DING-IPC-008: the path and its terminating NUL fit in sun_path")
    }
}
