import Foundation

/// Names and rules shared by the app and its bundled MCP helper.
public enum DingIPC {
    /// Info.plist key, in both the app and the helper's bundle, holding the app group ID (team-prefixed).
    public static let appGroupInfoKey = "DingAppGroup"

    /// App group IDs on macOS start with the team ID: "46XLY7Y9P8.blue.luci.Ding" -> "46XLY7Y9P8".
    public static func teamID(fromAppGroup appGroup: String) -> String? {
        let team = appGroup.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init)
        return team.flatMap { $0.isEmpty ? nil : $0 }
    }

    /// The code signing identifier of the bundled helper, the only program that has a reason to connect: the app's
    /// own bundle ID plus ".mcp", so a copy built under another ID still works.
    public static func helperIdentifier(forApp bundleID: String) -> String { bundleID + ".mcp" }

    /// Only the helper, signed by the same team, may talk to Ding: another app of the same developer can't.
    /// Works for development, Developer ID and App Store signing.
    public static func codeSigningRequirement(teamID: String, helperIdentifier: String) -> String {
        #"anchor apple generic and certificate leaf[subject.OU] = "\#(teamID)" and identifier "\#(helperIdentifier)""#
    }

    /// The socket lives in the app group container, which only the app and its helper can reach.
    /// Unix socket paths are limited to about 100 bytes, so the file name is short.
    public static func socketURL(appGroup: String, fileManager: FileManager = .default) -> URL? {
        fileManager.containerURL(forSecurityApplicationGroupIdentifier: appGroup)?.appendingPathComponent("c.sock")
    }
}
