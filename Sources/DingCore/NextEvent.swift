import Foundation

public enum NextEvent {
    /// How long after its start a meeting stays "next", shown as "now" in the menu bar.
    public static let defaultGrace: TimeInterval = 5 * 60

    /// First timed event that hasn't ended and started less than `grace` seconds ago. Meetings that start together are
    /// ordered accepted first, so a "maybe" invitation doesn't take the countdown from one the user accepted.
    public static func select(from events: [DingEvent], now: Date, grace: TimeInterval = defaultGrace) -> DingEvent? {
        events
            .filter { !$0.isAllDay && min($0.end, $0.start.addingTimeInterval(grace)) > now }
            .min { ($0.start, $0.isUnconfirmed ? 1 : 0, $0.title) < ($1.start, $1.isUnconfirmed ? 1 : 0, $1.title) }
    }
}

public enum JoinSelection {
    /// How long after its start a meeting can still be joined with the "join next" hotkey.
    public static let defaultGrace: TimeInterval = 15 * 60

    /// The meeting a "join next" hotkey should open: the next event with a link, or one
    /// with a link that started within `grace` (so a late arrival still joins it).
    public static func candidate(from events: [DingEvent], now: Date, grace: TimeInterval = defaultGrace) -> DingEvent? {
        NextEvent.select(from: events.filter(\.hasLink), now: now, grace: grace)
    }
}
