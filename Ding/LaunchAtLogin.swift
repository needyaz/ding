import ServiceManagement

/// The slice of `SMAppService` Ding uses.
protocol LoginItemService {
    var isEnabled: Bool { get }
    func register() throws
    func unregister() throws
}

struct MainAppLoginItem: LoginItemService {
    var isEnabled: Bool { SMAppService.mainApp.status == .enabled }
    func register() throws { try SMAppService.mainApp.register() }
    func unregister() throws { try SMAppService.mainApp.unregister() }
}

enum LaunchAtLogin {
    /// Swapped for a fake in tests so they never touch the user's login items.
    nonisolated(unsafe) static var service: LoginItemService = MainAppLoginItem()

    static var isEnabled: Bool { service.isEnabled }

    /// Returns whether the change succeeded.
    @discardableResult
    static func set(_ enabled: Bool) -> Bool {
        do {
            if enabled { try service.register() } else { try service.unregister() }
            return true
        } catch {
            NSLog("Ding: launch at login change failed: \(error.localizedDescription)")
            return false
        }
    }
}
