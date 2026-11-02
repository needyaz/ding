import Foundation

/// How the bolder reminder is shown. The UI calls this the "screen reminder", since "alert" already means
/// a notification style in macOS.
public enum AlertMode: String, CaseIterable, Codable, Sendable, Identifiable {
    case off
    case edgeFlash
    case fullScreen

    public var id: String { rawValue }
}

public struct ScheduledAlert: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        /// A macOS notification, `notificationLeadMinutes` before the start.
        case notification
        /// The edge flash or full-screen takeover, `alertLeadMinutes` before the start.
        case alert
    }

    public let eventID: String
    public let kind: Kind
    public let fireDate: Date

    public init(eventID: String, kind: Kind, fireDate: Date) {
        self.eventID = eventID
        self.kind = kind
        self.fireDate = fireDate
    }
}

public struct AlertSettings: Equatable, Sendable {
    /// Minutes before start for the notification; 0 or less turns notifications off.
    public var notificationLeadMinutes: Int
    public var mode: AlertMode
    /// Minutes before start for the edge flash or full-screen alert; 0 means at the start time.
    /// Independent of the notification's lead time.
    public var alertLeadMinutes: Int
    /// By default only events with a meeting link alert.
    public var includeEventsWithoutLink: Bool
    /// Whether "maybe" and not-yet-answered meetings also get a notification. Never affects accepted meetings.
    public var notifyUnconfirmed: Bool
    /// Whether they also get the edge flash or full-screen reminder. Off by default: those are loud.
    public var alertUnconfirmed: Bool

    public init(
        notificationLeadMinutes: Int = 5,
        mode: AlertMode = .off,
        alertLeadMinutes: Int = 0,
        includeEventsWithoutLink: Bool = false,
        notifyUnconfirmed: Bool = true,
        alertUnconfirmed: Bool = false
    ) {
        self.notificationLeadMinutes = notificationLeadMinutes
        self.mode = mode
        self.alertLeadMinutes = alertLeadMinutes
        self.includeEventsWithoutLink = includeEventsWithoutLink
        self.notifyUnconfirmed = notifyUnconfirmed
        self.alertUnconfirmed = alertUnconfirmed
    }
}

public enum AlertPlanner {
    /// macOS keeps at most 64 pending local notifications per app.
    public static let maxNotifications = 50

    /// Everything that should fire in the future, soonest first. All-day events never alert.
    /// Something whose time has already passed is skipped, even if the meeting hasn't started: the plan is
    /// rebuilt on every reload, so replanning it would show the same alert again each time.
    public static func plan(_ events: [DingEvent], now: Date, settings: AlertSettings) -> [ScheduledAlert] {
        let eligible = events
            .filter { !$0.isAllDay && ($0.hasLink || settings.includeEventsWithoutLink) }
            .sorted { $0.start < $1.start }

        var plan: [ScheduledAlert] = []
        var notificationCount = 0
        for event in eligible {
            if settings.notificationLeadMinutes > 0, notificationCount < maxNotifications,
               settings.notifyUnconfirmed || !event.isUnconfirmed {
                let fireDate = event.start.addingTimeInterval(-Double(settings.notificationLeadMinutes) * 60)
                if fireDate > now {
                    plan.append(ScheduledAlert(eventID: event.id, kind: .notification, fireDate: fireDate))
                    notificationCount += 1
                }
            }
            if settings.mode != .off, settings.alertUnconfirmed || !event.isUnconfirmed {
                let fireDate = event.start.addingTimeInterval(-Double(max(settings.alertLeadMinutes, 0)) * 60)
                if fireDate > now {
                    plan.append(ScheduledAlert(eventID: event.id, kind: .alert, fireDate: fireDate))
                }
            }
        }
        return plan.sorted { $0.fireDate < $1.fireDate }
    }
}

/// Alerts waiting to fire, drained by a single timer.
public struct AlertQueue: Equatable, Sendable {
    public private(set) var pending: [ScheduledAlert]

    public init(_ alerts: [ScheduledAlert] = []) {
        pending = alerts.sorted { $0.fireDate < $1.fireDate }
    }

    public var nextFireDate: Date? { pending.first?.fireDate }

    /// Removes every alert that is due, returning those still worth showing. Alerts that
    /// fire long after their start (a Mac waking from sleep) are dropped silently.
    public mutating func popDue(now: Date, tolerance: TimeInterval = 0.5, staleAfter: TimeInterval = 120) -> [ScheduledAlert] {
        let cutoff = now.addingTimeInterval(tolerance)
        let due = pending.filter { $0.fireDate <= cutoff }
        pending.removeAll { $0.fireDate <= cutoff }
        return due.filter { now.timeIntervalSince($0.fireDate) < staleAfter }
    }
}
