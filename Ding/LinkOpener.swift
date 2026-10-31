import AppKit
import DingCore

/// NSWorkspace-backed implementation of the routing in `MeetingOpener`.
struct SystemWorkspace: WorkspaceOpening {
    func open(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

    func open(_ url: URL, withAppBundleID bundleID: String) -> Bool {
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return false }
        NSWorkspace.shared.open([url], withApplicationAt: appURL, configuration: NSWorkspace.OpenConfiguration())
        return true
    }

    func hasHandler(for url: URL) -> Bool {
        NSWorkspace.shared.urlForApplication(toOpen: url) != nil
    }
}

enum LinkOpener {
    /// Swapped for a fake in tests.
    nonisolated(unsafe) static var workspace: WorkspaceOpening = SystemWorkspace()

    static func open(_ link: MeetingLink) {
        MeetingOpener(workspace: workspace).open(link, target: .current(for: link.service))
    }

    // MARK: Installed browsers (for Preferences)

    struct Browser: Identifiable, Hashable {
        let bundleID: String
        let name: String
        var id: String { bundleID }
    }

    static func installedBrowsers() -> [Browser] {
        guard let probe = URL(string: "https://example.com") else { return [] }
        let own = Bundle.main.bundleIdentifier
        var seen = Set<String>()
        return NSWorkspace.shared.urlsForApplications(toOpen: probe).compactMap { appURL in
            guard let bundle = Bundle(url: appURL), let id = bundle.bundleIdentifier,
                  id != own, seen.insert(id).inserted else { return nil }
            let name = FileManager.default.displayName(atPath: appURL.path).replacingOccurrences(of: ".app", with: "")
            return Browser(bundleID: id, name: name)
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}
