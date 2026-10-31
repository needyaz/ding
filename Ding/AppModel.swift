import AppKit
import Observation
import KeyboardShortcuts
import DingCore

/// Everything the UI shows, plus the glue between the calendar, timers and alerts.
@MainActor
@Observable
final class AppModel {
    static let shared = AppModel()

    /// Fetched once for this many days so the next meeting can sit beyond the dropdown range.
    private static let fetchDays = 14
    /// A safety net in case a calendar change notification is missed.
    private static let refreshInterval: TimeInterval = 15 * 60
    /// Preference writes (sliders, the hotkey recorder) arrive in bursts.
    private static let preferenceDebounce: Duration = .milliseconds(250)

    var now = Date()
    var events: [DingEvent] = []
    var accounts: [CalendarAccount] = []
    var access: CalendarAccess = .notDetermined
    var isMenuPresented = false
    /// Bumped when any preference changes, so views reading derived state refresh.
    var prefsVersion = 0

    @ObservationIgnored let calendar: CalendarSource
    @ObservationIgnored private let scheduler: Scheduler
    @ObservationIgnored private var started = false
    @ObservationIgnored private var preferencesTask: Task<Void, Never>?
    @ObservationIgnored private var controlListener: ControlListener?
    /// Off in tests: the socket is shared with the running app, so a test must never take it over.
    @ObservationIgnored var startsControlServer = true

    // Side effects, replaceable so tests never open browsers, windows or alerts.
    @ObservationIgnored var openLink: (MeetingLink) -> Void = { LinkOpener.open($0) }
    @ObservationIgnored var presentAlert: (DingEvent, AlertMode) -> Void
    @ObservationIgnored var presentSettings: () -> Void = { SettingsWindowController.shared.show() }

    init(calendar: CalendarSource? = nil, notifier: NotificationScheduling? = nil) {
        self.calendar = calendar ?? CalendarStore()
        self.scheduler = Scheduler(notifier: notifier ?? UserNotificationScheduler())
        let alerts = AlertController()
        self.presentAlert = { alerts.show($0, mode: $1) }
    }

    // MARK: Derived state

    var visibleEvents: [DingEvent] {
        _ = prefsVersion
        return Pref.eventFilter.apply(events)
    }

    var groups: [DayGroup] {
        DayGrouping.group(visibleEvents, now: now, days: Pref.days)
    }

    var nextEvent: DingEvent? {
        NextEvent.select(from: visibleEvents, now: now)
    }

    var menuBarText: String? {
        _ = prefsVersion
        return MenuBarText.make(next: nextEvent, now: now, options: Pref.menuBarOptions)
    }

    // MARK: Lifecycle

    func start(requestNotificationPermission: Bool = true) {
        guard !started else { return }
        started = true
        Pref.registerDefaults()

        calendar.onChange = { [weak self] in self?.reload() }
        scheduler.onTick = { [weak self] in self?.tick() }
        scheduler.onAlert = { [weak self] event in
            self?.presentAlert(event, Pref.alertSettings.mode)
        }
        if requestNotificationPermission { scheduler.requestNotificationPermission() }

        observeSystem()
        registerHotkeys()
        if startsControlServer { startControlServer() }

        Task {
            if calendar.access == .notDetermined { await calendar.requestAccess() }
            reload()
        }
    }

    private func startControlServer() {
        let service = ControlService(environment: .init(
            events: { [weak self] in self?.visibleEvents ?? [] },
            access: { [weak self] in self?.access ?? .notDetermined },
            permissions: { Pref.controlPermissions },
            join: { [weak self] in self?.join($0) }
        ))
        controlListener = ControlListener(service: service)
        controlListener?.start()
    }

    func stopControlServer() {
        controlListener?.stop()
    }

    private func registerHotkeys() {
        KeyboardShortcuts.onKeyUp(for: .openMenu) { [weak self] in
            Task { @MainActor in self?.isMenuPresented.toggle() }
        }
        KeyboardShortcuts.onKeyUp(for: .joinNext) { [weak self] in
            Task { @MainActor in self?.joinNext() }
        }
    }

    private func observeSystem() {
        let center = NotificationCenter.default
        center.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.preferencesChanged() }
        }

        // Wake, clock jumps, time zone changes and midnight all invalidate timers and day grouping. Becoming
        // active covers a calendar or account added in System Settings whose change notification was missed.
        let reloadTriggers: [(NotificationCenter, Notification.Name)] = [
            (NSWorkspace.shared.notificationCenter, NSWorkspace.didWakeNotification),
            (center, .NSSystemClockDidChange),
            (center, .NSSystemTimeZoneDidChange),
            (center, .NSCalendarDayChanged),
            (center, NSApplication.didBecomeActiveNotification),
        ]
        for (source, name) in reloadTriggers {
            source.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.reload() }
            }
        }

        Timer.scheduledTimer(withTimeInterval: Self.refreshInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.reload() }
        }
    }

    // MARK: Updates

    func reload() {
        access = calendar.access
        let start = Calendar.current.startOfDay(for: Date())
        let end = Calendar.current.date(byAdding: .day, value: Self.fetchDays, to: start)
            ?? start.addingTimeInterval(Double(Self.fetchDays) * 24 * 3600)
        events = calendar.events(from: start, to: end)
        accounts = calendar.accounts()
        now = Date()
        rebuildSchedule()
    }

    func requestCalendarAccess() {
        Task { await calendar.requestAccess() }
    }

    private func tick() {
        now = Date()
        scheduler.scheduleTick(next: nextEvent)
    }

    private func rebuildSchedule() {
        scheduler.update(events: visibleEvents, next: nextEvent, settings: Pref.alertSettings)
    }

    private func preferencesChanged() {
        preferencesTask?.cancel()
        preferencesTask = Task { [weak self] in
            try? await Task.sleep(for: Self.preferenceDebounce)
            guard !Task.isCancelled, let self else { return }
            prefsVersion += 1
            now = Date()
            rebuildSchedule()
        }
    }

    // MARK: Actions

    func join(_ event: DingEvent) {
        guard let link = event.link else { return }
        isMenuPresented = false
        openLink(link)
    }

    func joinNext() {
        guard let event = JoinSelection.candidate(from: visibleEvents, now: Date()) else { return }
        join(event)
    }

    /// Shows the configured alert for a made-up meeting, so it can be seen without waiting for one. The
    /// meeting starts when the alert would really appear relative to it, so the countdown looks right.
    func previewAlert() {
        let settings = Pref.alertSettings
        let start = Date().addingTimeInterval(Double(max(settings.alertLeadMinutes, 0)) * 60)
        let sample = DingEvent(
            id: "preview", title: "Preview: Team standup", start: start, end: start.addingTimeInterval(30 * 60),
            link: MeetingLink(service: .zoom, url: URL(string: "https://zoom.us/")!)
        )
        presentAlert(sample, settings.mode)
    }

    func openSettings() {
        isMenuPresented = false
        reload()  // so the calendar list is current even if a change was missed
        presentSettings()
    }
}
