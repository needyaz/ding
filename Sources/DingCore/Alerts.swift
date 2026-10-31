import Foundation

public enum AlertMode: String, CaseIterable, Codable, Sendable, Identifiable {
    case off
    case edgeFlash
    case fullScreen

    public var id: String { rawValue }
}

public struct ScheduledAlert: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        /// A macOS notification, `leadMinutes` before the start.
        case notification
        /// The edge flash or full-screen takeover, at the start.
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
    public var leadMinutes: Int
    public var mode: AlertMode
    /// By default only events with a meeting link alert.
    public var includeEventsWithoutLink: Bool

    public init(leadMinutes: Int = 5, mode: AlertMode = .off, includeEventsWithoutLink: Bool = false) {
        self.leadMinutes = leadMinutes
        self.mode = mode
        self.includeEventsWithoutLink = includeEventsWithoutLink
    }
}

public enum AlertPlanner {
    /// macOS keeps at most 64 pending local notifications per app.
    public static let maxNotifications = 50

    /// Everything that should fire in the future, soonest first. All-day events never alert.
    public static func plan(_ events: [DingEvent], now: Date, settings: AlertSettings) -> [ScheduledAlert] {
        let eligible = events
            .filter { !$0.isAllDay && ($0.hasLink || settings.includeEventsWithoutLink) }
            .sorted { $0.start < $1.start }

        var plan: [ScheduledAlert] = []
        var notificationCount = 0
        for event in eligible {
            if settings.leadMinutes > 0, notificationCount < maxNotifications {
                let fireDate = event.start.addingTimeInterval(-Double(settings.leadMinutes) * 60)
                if fireDate > now {
                    plan.append(ScheduledAlert(eventID: event.id, kind: .notification, fireDate: fireDate))
                    notificationCount += 1
                }
            }
            if settings.mode != .off, event.start > now {
                plan.append(ScheduledAlert(eventID: event.id, kind: .alert, fireDate: event.start))
            }
        }
        return plan.sorted { $0.fireDate < $1.fireDate }
    }
}

/// Alerts waiting for their start time, drained by a single timer.
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
