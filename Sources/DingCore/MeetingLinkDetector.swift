import Foundation

/// Every link pattern Ding knows, in one table. To support a new service add a
/// `MeetingService` case and a row here. Patterns are matched at the start of a URL.
enum LinkPatterns {
    /// Whatever follows the identifying prefix: path remainder, query string, fragment.
    private static let tail = #"[^\s<>"'`]*"#

    static let table: [(service: MeetingService, pattern: String)] = [
        // https://us02web.zoom.us/j/84512345678?pwd=abc  ·  https://acme.zoom.us/my/nate
        (.zoom, #"https?://(?:[\w-]+\.)*(?:zoom\.us|zoomgov\.com)/(?:j|my|s|w|wc/join)/"# + tail),
        // zoommtg://zoom.us/join?confno=84512345678
        (.zoom, #"zoommtg://"# + tail),
        // https://meet.google.com/abc-defg-hij  ·  https://meet.google.com/lookup/abc123
        (.googleMeet, #"https?://meet\.google\.com/(?:lookup/)?[\w-]+"# + tail),
        // https://teams.microsoft.com/l/meetup-join/...  ·  https://teams.microsoft.com/meet/123  ·  https://teams.live.com/meet/123
        (.teams, #"https?://teams\.(?:microsoft|live)\.com/(?:l/meetup-join|meet|meetup-join)/"# + tail),
        // https://acme.webex.com/meet/nate  ·  https://acme.webex.com/join/nate  ·  https://acme.webex.com/acme/j.php?MTID=...
        (.webex, #"https?://(?:[\w-]+\.)*webex\.com/(?:meet/|join/|wbxmjs/|[\w.-]+/(?:j|m)\.php|[\w.-]+/(?:meet|join)/)"# + tail),
    ]

    // The patterns are static literals, so a failure here is a programmer error caught by the tests.
    private static let compiled: [(service: MeetingService, regex: NSRegularExpression)] = table.map {
        ($0.service, try! NSRegularExpression(pattern: "^" + $0.pattern, options: [.caseInsensitive]))
    }

    static func service(for url: URL) -> MeetingService? {
        let string = url.absoluteString
        let range = NSRange(string.startIndex..., in: string)
        return compiled.first { $0.regex.firstMatch(in: string, options: [.anchored], range: range) != nil }?.service
    }
}

/// The places Ding looks for a link, already pulled off the event.
public struct LinkSource: Equatable, Sendable {
    /// Structured conference data, when the calendar exposes any.
    public var conferenceURLs: [URL]
    public var location: String?
    public var url: URL?
    public var notes: String?

    public init(conferenceURLs: [URL] = [], location: String? = nil, url: URL? = nil, notes: String? = nil) {
        self.conferenceURLs = conferenceURLs
        self.location = location
        self.url = url
        self.notes = notes
    }
}

public enum MeetingLinkDetector {
    /// Search order: conference data, location, URL field, notes. The first known
    /// service wins; otherwise a single distinct URL becomes an "Other link".
    public static func detect(_ source: LinkSource) -> MeetingLink? {
        let fields: [String] = source.conferenceURLs.map(\.absoluteString)
            + [source.location, source.url?.absoluteString, source.notes].compactMap { $0 }

        var unknown: [URL] = []
        var seen = Set<String>()
        for field in fields {
            for url in extractURLs(from: field) {
                if let service = LinkPatterns.service(for: url) {
                    return MeetingLink(service: service, url: url)
                }
                if seen.insert(url.absoluteString).inserted { unknown.append(url) }
            }
        }
        guard unknown.count == 1, let only = unknown.first, isWebURL(only) else { return nil }
        return MeetingLink(service: .other, url: only)
    }

    // MARK: - Extraction

    /// A web or Zoom URL, ending before whitespace, quotes, angle brackets or closing brackets.
    private static let urlRegex = try! NSRegularExpression(
        pattern: #"(?:https?|zoommtg)://[^\s<>"'`\]\)\}]+"#,
        options: [.caseInsensitive]
    )
    private static let trailingPunctuation = CharacterSet(charactersIn: ".,;:!?")

    static func extractURLs(from text: String) -> [URL] {
        let decoded = text.replacingOccurrences(of: "&amp;", with: "&")
        let range = NSRange(decoded.startIndex..., in: decoded)
        return urlRegex.matches(in: decoded, range: range).compactMap { match in
            guard let r = Range(match.range, in: decoded) else { return nil }
            var string = String(decoded[r])
            while let last = string.unicodeScalars.last, trailingPunctuation.contains(last) {
                string.removeLast()
            }
            guard let url = URL(string: string) else { return nil }
            return unwrap(url)
        }
    }

    private static func isWebURL(_ url: URL) -> Bool {
        url.scheme == "http" || url.scheme == "https"
    }

    /// Outlook SafeLinks and Google redirect wrappers hide the real meeting URL in a query item.
    static func unwrap(_ url: URL) -> URL {
        guard let keys = redirectQueryKeys(for: url),
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
        for key in keys {
            if let value = components.queryItems?.first(where: { $0.name == key })?.value,
               let inner = URL(string: value), isWebURL(inner) {
                return inner
            }
        }
        return url
    }

    /// The query items that may carry the real URL, if `url` is a known redirect wrapper.
    private static func redirectQueryKeys(for url: URL) -> [String]? {
        guard let host = url.host?.lowercased() else { return nil }
        if host.hasSuffix("safelinks.protection.outlook.com") { return ["url"] }
        if (host == "www.google.com" || host == "google.com") && url.path == "/url" { return ["q", "url"] }
        return nil
    }
}

/// Native-app deep links derived from a web meeting URL.
public enum NativeLinks {
    /// `https://us02web.zoom.us/j/123?pwd=abc` -> `zoommtg://us02web.zoom.us/join?confno=123&pwd=abc`
    public static func zoom(from url: URL) -> URL? {
        if url.scheme == "zoommtg" { return url }
        let parts = url.pathComponents
        guard parts.count >= 3, parts[1] == "j",
              let source = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let host = source.host else { return nil }
        var components = URLComponents()
        components.scheme = "zoommtg"
        components.host = host
        components.path = "/join"
        components.queryItems = [URLQueryItem(name: "confno", value: parts[2])] + (source.queryItems ?? [])
        return components.url
    }

    /// `https://teams.microsoft.com/l/meetup-join/...` -> `msteams://teams.microsoft.com/l/meetup-join/...`
    public static func teams(from url: URL) -> URL? {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme == "https" || components.scheme == "http" else { return nil }
        components.scheme = "msteams"
        return components.url
    }
}
