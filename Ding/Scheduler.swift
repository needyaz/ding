import Foundation
import DingCore

/// Owns every timer: the countdown refresh and in-app alerts at start time. System
/// notifications go through `notifier`. Rebuilt whenever events or settings change and after wake.
@MainActor
final class Scheduler {
    var onTick: (() -> Void)?
    var onAlert: ((DingEvent) -> Void)?

    private let notifier: NotificationScheduling
    private var tickTimer: Timer?
    private var alertTimer: Timer?
    private var queue = AlertQueue()
    private var eventsByID: [String: DingEvent] = [:]

    init(notifier: NotificationScheduling) {
        self.notifier = notifier
    }

    func requestNotificationPermission() {
        notifier.requestPermission()
    }

    /// `next` drives the countdown refresh cadence.
    func update(events: [DingEvent], next: DingEvent?, settings: AlertSettings) {
        let now = Date()
        eventsByID = Dictionary(events.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let plan = AlertPlanner.plan(events, now: now, settings: settings)

        notifier.replaceAll(with: NotificationPlanner.build(
            plan,
            events: events,
            leadMinutes: settings.leadMinutes,
            playSound: Pref.defaults.bool(forKey: Pref.notifySound),
            joinAction: Pref.defaults.bool(forKey: Pref.notifyJoinAction)
        ))
        queue = AlertQueue(plan.filter { $0.kind == .alert })
        armAlertTimer()
        scheduleTick(next: next)
    }

    // MARK: Countdown refresh

    func scheduleTick(next: DingEvent?) {
        tickTimer?.invalidate()
        let delay = TickPlanner.delay(now: Date(), next: next)
        tickTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.onTick?() }
        }
    }

    // MARK: Alerts

    private func armAlertTimer() {
        alertTimer?.invalidate()
        guard let fireDate = queue.nextFireDate else { return }
        let delay = max(fireDate.timeIntervalSinceNow, 0.1)
        alertTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.fireDueAlerts() }
        }
    }

    private func fireDueAlerts() {
        for alert in queue.popDue(now: Date()) {
            if let event = eventsByID[alert.eventID] { onAlert?(event) }
        }
        armAlertTimer()
    }
}
