import Foundation

/// How a service's links get opened.
public enum OpenTarget: Equatable, Sendable {
    case nativeApp
    case defaultBrowser
    case browser(bundleID: String)

    public static let nativeValue = "native"
    public static let defaultBrowserValue = "default"

    /// Parses the stored preference string.
    public init(rawValue: String) {
        switch rawValue {
        case Self.nativeValue: self = .nativeApp
        case Self.defaultBrowserValue, "": self = .defaultBrowser
        default: self = .browser(bundleID: rawValue)
        }
    }

    public var rawValue: String {
        switch self {
        case .nativeApp: Self.nativeValue
        case .defaultBrowser: Self.defaultBrowserValue
        case .browser(let bundleID): bundleID
        }
    }

    /// Zoom opens in its app out of the box; everything else uses the default browser.
    public static func defaultValue(for service: MeetingService) -> String {
        service == .zoom ? nativeValue : defaultBrowserValue
    }

    /// The effective target for a stored value. A service with no desktop app can't be native.
    public static func resolve(_ stored: String?, for service: MeetingService) -> OpenTarget {
        let target = OpenTarget(rawValue: stored ?? defaultValue(for: service))
        return target == .nativeApp && !service.supportsNativeApp ? .defaultBrowser : target
    }
}

/// The slice of NSWorkspace that joining needs, so routing can be tested.
public protocol WorkspaceOpening {
    /// Opens a URL with the system default handler.
    func open(_ url: URL)
    /// Opens a URL with a specific app. False when that app isn't installed.
    func open(_ url: URL, withAppBundleID bundleID: String) -> Bool
    /// Whether any installed app is registered for the URL's scheme.
    func hasHandler(for url: URL) -> Bool
}

/// Resolves a meeting link plus its open target to an app or browser, and opens it.
public struct MeetingOpener {
    /// Desktop app bundle IDs per service, newest first.
    public static let nativeBundleIDs: [MeetingService: [String]] = [
        .zoom: ["us.zoom.xos"],
        .teams: ["com.microsoft.teams2", "com.microsoft.teams"],
        .webex: ["Cisco-Systems.Spark", "com.cisco.webexmeetingsapp"],
    ]

    private let workspace: WorkspaceOpening

    public init(workspace: WorkspaceOpening) {
        self.workspace = workspace
    }

    public func open(_ link: MeetingLink, target: OpenTarget) {
        switch target {
        case .nativeApp:
            if !openNative(link) { workspace.open(link.url) }
        case .defaultBrowser:
            workspace.open(link.url)
        case .browser(let bundleID):
            if !workspace.open(link.url, withAppBundleID: bundleID) { workspace.open(link.url) }
        }
    }

    private func openNative(_ link: MeetingLink) -> Bool {
        let deepLink: URL? = switch link.service {
        case .zoom: NativeLinks.zoom(from: link.url)
        case .teams: NativeLinks.teams(from: link.url)
        default: nil
        }
        // Deep links only help if something is registered for the scheme.
        if let deepLink, workspace.hasHandler(for: deepLink) {
            workspace.open(deepLink)
            return true
        }
        for bundleID in Self.nativeBundleIDs[link.service] ?? [] where workspace.open(link.url, withAppBundleID: bundleID) {
            return true
        }
        return false
    }
}
