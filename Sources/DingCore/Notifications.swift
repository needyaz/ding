import Foundation

/// A system notification ready to hand to UserNotifications.
public struct PlannedNotification: Equatable, Sendable {
    public let id: String
    public let title: String
    public let body: String
    public let fireDate: Date
    public let playSound: Bool
    /// Show the Join action button.
    public let joinAction: Bool
    public let link: MeetingLink?

    public init(id: String, title: String, body: String, fireDate: Date, playSound: Bool, joinAction: Bool, link: MeetingLink?) {
        self.id = id
        self.title = title
        self.body = body
        self.fireDate = fireDate
        self.playSound = playSound
        self.joinAction = joinAction
        self.link = link
    }
}

public enum NotificationPlanner {
    /// Turns the notification entries of an alert plan into ready-to-schedule notifications.
    public static func build(
        _ plan: [ScheduledAlert],
        events: [DingEvent],
        leadMinutes: Int,
        playSound: Bool,
        joinAction: Bool
    ) -> [PlannedNotification] {
        let eventsByID = Dictionary(events.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return plan.compactMap { item in
            guard item.kind == .notification, let event = eventsByID[item.eventID] else { return nil }
            return PlannedNotification(
                id: "ding.\(event.id)",
                title: event.title,
                body: body(for: event, leadMinutes: leadMinutes),
                fireDate: item.fireDate,
                playSound: playSound,
                joinAction: joinAction && event.hasLink,
                link: event.link
            )
        }
    }

    /// "Starts in 5 minutes · Zoom"
    public static func body(for event: DingEvent, leadMinutes: Int) -> String {
        let when: String
        switch leadMinutes {
        case ...0: when = "Starting now"
        case 1: when = "Starts in 1 minute"
        default: when = "Starts in \(leadMinutes) minutes"
        }
        guard let link = event.link else { return when }
        return "\(when) · \(link.service.displayName)"
    }
}
