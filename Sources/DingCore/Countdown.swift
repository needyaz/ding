import Foundation

public enum Countdown {
    private static let minutesPerHour = 60
    private static let minutesPerDay = 24 * 60

    /// "now", "12m", "2h", "1h 5m", "2d 3h". Minutes round up so the label never
    /// reads "0m" before the event starts.
    public static func text(until start: Date, now: Date) -> String {
        let remaining = start.timeIntervalSince(now)
        guard remaining > 0 else { return "now" }
        let minutes = Int((remaining / 60).rounded(.up))

        if minutes < minutesPerHour { return "\(minutes)m" }
        if minutes < minutesPerDay {
            let (hours, rest) = minutes.quotientAndRemainder(dividingBy: minutesPerHour)
            return rest == 0 ? "\(hours)h" : "\(hours)h \(rest)m"
        }
        let (days, rest) = minutes.quotientAndRemainder(dividingBy: minutesPerDay)
        let hours = rest / minutesPerHour
        return hours == 0 ? "\(days)d" : "\(days)d \(hours)h"
    }

    /// The next moment `text(until:now:)` changes value, or nil once the event has started.
    public static func nextChange(until start: Date, now: Date) -> Date? {
        let remaining = start.timeIntervalSince(now)
        guard remaining > 0 else { return nil }
        let minutesShown = (remaining / 60).rounded(.up)
        return start.addingTimeInterval(-(minutesShown - 1) * 60)
    }
}

public enum TickPlanner {
    /// Seconds until the next countdown refresh: when the label changes, and at least
    /// once per `maxInterval` so day changes and finished events get picked up.
    public static func delay(now: Date, next: DingEvent?, maxInterval: TimeInterval = 60) -> TimeInterval {
        var fire = now.addingTimeInterval(maxInterval)
        if let next, let change = Countdown.nextChange(until: next.start, now: now) {
            fire = min(fire, change)
        }
        // The floor avoids a spin loop, and the pad lands just after the label flips.
        return max(fire.timeIntervalSince(now), 0.5) + 0.1
    }
}
