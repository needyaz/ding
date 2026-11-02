import Foundation

/// Where a meeting sits in a run of overlapping meetings, for drawing one bracket along their left edge.
public enum OverlapPosition: Equatable, Sendable {
    /// Overlaps nothing.
    case none
    case first, middle, last

    public var overlapsAnother: Bool { self != .none }
}

public enum Overlap {
    /// Orders one day's events for display and marks the runs of overlapping meetings.
    ///
    /// `events` must already be in display order (all-day first, then by start and title). Two timed meetings overlap if
    /// their times intersect, directly or through a chain (A overlaps B, B overlaps C: one cluster). Back-to-back
    /// meetings don't overlap, and all-day events never join a cluster. Inside a cluster accepted meetings come before
    /// unconfirmed ones; outside a cluster the order is unchanged.
    public static func arrange(_ events: [DingEvent]) -> (events: [DingEvent], positions: [String: OverlapPosition]) {
        var ordered: [DingEvent] = []
        var positions: [String: OverlapPosition] = [:]
        var cluster: [DingEvent] = []
        var clusterEnd = Date.distantPast

        func flush() {
            defer { cluster = [] }
            guard cluster.count > 1 else {
                for event in cluster { ordered.append(event); positions[event.id] = OverlapPosition.none }
                return
            }
            let sorted = cluster.filter { !$0.isUnconfirmed } + cluster.filter(\.isUnconfirmed)
            for (index, event) in sorted.enumerated() {
                ordered.append(event)
                positions[event.id] = index == 0 ? .first : (index == sorted.count - 1 ? .last : .middle)
            }
        }

        for event in events {
            if event.isAllDay {
                flush()
                ordered.append(event)
                positions[event.id] = OverlapPosition.none
                continue
            }
            // A zero-length meeting still occupies its instant.
            let end = max(event.end, event.start.addingTimeInterval(1))
            if !cluster.isEmpty, event.start >= clusterEnd { flush() }
            cluster.append(event)
            clusterEnd = cluster.count == 1 ? end : max(clusterEnd, end)
        }
        flush()
        return (ordered, positions)
    }
}
