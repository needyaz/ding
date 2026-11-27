import Foundation
import DingCore

enum AppInfo {
    static let reportProblemURL = URL(string: "https://github.com/needyaz/feedback/issues/new?template=bug.yml&app=Ding%20%28Mac%29")!
    static let suggestIdeaURL = URL(string: "https://github.com/needyaz/feedback/issues/new?template=feature.yml&app=Ding%20%28Mac%29")!
    static let websiteURL = URL(string: "https://luci.blue/ding")!
    static let feedbackURL = reportProblemURL
    static let calendarPrivacySettingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")!

    /// Swapped for a fake bundle in tests; read on every access.
    nonisolated(unsafe) static var bundle: Bundle = .main

    static var versionLine: String {
        let info = bundle.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? "?"
        let build = info["CFBundleVersion"] as? String ?? "?"
        return "Version \(version) (\(build))"
    }
}

/// The links in the About section of Settings.
enum AboutLink: CaseIterable {
    case reportProblem, suggestIdea, website

    var title: String {
        switch self {
        case .reportProblem: "Report a problem"
        case .suggestIdea: "Suggest an idea"
        case .website: "luci.blue"
        }
    }

    var url: URL {
        switch self {
        case .reportProblem: AppInfo.reportProblemURL
        case .suggestIdea: AppInfo.suggestIdeaURL
        case .website: AppInfo.websiteURL
        }
    }

    func open() {
        LinkOpener.workspace.open(url)
    }
}
