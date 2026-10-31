import Foundation
import DingCore

/// UserDefaults keys, their defaults, and typed accessors. Views bind the same keys with `@AppStorage`
/// and use `Pref.Default` for the initial value, so each default is written once.
enum Pref {
    /// Swapped for an isolated suite in tests.
    nonisolated(unsafe) static var defaults: UserDefaults = .standard

    // MARK: Keys

    static let showCountdown = "showCountdown"
    static let showTitle = "showTitle"
    static let countdownOnlyToday = "countdownOnlyToday"
    static let rangeDays = "rangeDays"
    static let showEventsWithoutLink = "showEventsWithoutLink"
    static let showMaybe = "showMaybe"
    static let disabledCalendarIDs = "disabledCalendarIDs"
    static let use24Hour = "use24Hour"
    static let notifyLeadMinutes = "notifyLeadMinutes"
    static let notifySound = "notifySound"
    static let notifyJoinAction = "notifyJoinAction"
    static let alertMode = "alertMode"
    static let alertLeadMinutes = "alertLeadMinutes"
    static let alertIncludeAll = "alertIncludeAll"
    static let controlReadSchedule = "controlReadSchedule"
    static let controlOpenMeetings = "controlOpenMeetings"

    /// How links for `service` open: "native", "default", or a browser's bundle ID.
    static func openKey(_ service: MeetingService) -> String { "open.\(service.rawValue)" }

    // MARK: Defaults

    enum Default {
        static let showCountdown = true
        static let showTitle = true
        static let countdownOnlyToday = false
        static let rangeDays = 3
        static let showEventsWithoutLink = true
        static let showMaybe = true
        static var use24Hour: Bool { Pref.systemUses24Hour }
        static let notifyLeadMinutes = 5
        static let notifySound = true
        static let notifyJoinAction = true
        static let alertMode = AlertMode.off
        /// Early enough to join without being late, and clear of the 5-minute notification.
        static let alertLeadMinutes = 1
        static let alertIncludeAll = false
        /// An assistant can do nothing until the user turns it on.
        static let controlReadSchedule = false
        static let controlOpenMeetings = false
    }

    /// Choices offered in Preferences.
    static let rangeDayOptions = [1, 3, 7, 14]
    static let leadMinuteOptions = [1, 2, 5, 10, 15]
    /// 0 means at the start time.
    static let alertLeadOptions = [0, 1, 2, 5]

    static func registerDefaults() {
        var values: [String: Any] = [
            showCountdown: Default.showCountdown,
            showTitle: Default.showTitle,
            countdownOnlyToday: Default.countdownOnlyToday,
            rangeDays: Default.rangeDays,
            showEventsWithoutLink: Default.showEventsWithoutLink,
            showMaybe: Default.showMaybe,
            use24Hour: Default.use24Hour,
            notifyLeadMinutes: Default.notifyLeadMinutes,
            notifySound: Default.notifySound,
            notifyJoinAction: Default.notifyJoinAction,
            alertMode: Default.alertMode.rawValue,
            alertLeadMinutes: Default.alertLeadMinutes,
            alertIncludeAll: Default.alertIncludeAll,
            controlReadSchedule: Default.controlReadSchedule,
            controlOpenMeetings: Default.controlOpenMeetings,
        ]
        for service in MeetingService.allCases {
            values[openKey(service)] = OpenTarget.defaultValue(for: service)
        }
        defaults.register(defaults: values)
    }

    static var systemUses24Hour: Bool {
        let format = DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: .current) ?? ""
        return !format.contains("a")
    }

    // MARK: Typed reads

    /// Stored as the *disabled* set so calendars that appear later default to on.
    static var disabledCalendars: Set<String> {
        get { Set(defaults.stringArray(forKey: disabledCalendarIDs) ?? []) }
        set { defaults.set(Array(newValue).sorted(), forKey: disabledCalendarIDs) }
    }

    static var eventFilter: EventFilter {
        EventFilter(
            showWithoutLink: defaults.bool(forKey: showEventsWithoutLink),
            showMaybe: defaults.bool(forKey: showMaybe),
            disabledCalendarIDs: disabledCalendars
        )
    }

    static var menuBarOptions: MenuBarOptions {
        MenuBarOptions(
            showCountdown: defaults.bool(forKey: showCountdown),
            showTitle: defaults.bool(forKey: showTitle),
            countdownOnlyToday: defaults.bool(forKey: countdownOnlyToday)
        )
    }

    static var alertSettings: AlertSettings {
        AlertSettings(
            notificationLeadMinutes: defaults.integer(forKey: notifyLeadMinutes),
            mode: AlertMode(rawValue: defaults.string(forKey: alertMode) ?? "") ?? .off,
            alertLeadMinutes: defaults.integer(forKey: alertLeadMinutes),
            includeEventsWithoutLink: defaults.bool(forKey: alertIncludeAll)
        )
    }

    static var controlPermissions: ControlPermissions {
        ControlPermissions(
            canReadSchedule: defaults.bool(forKey: controlReadSchedule),
            canOpenMeetings: defaults.bool(forKey: controlOpenMeetings)
        )
    }

    /// Days shown in the dropdown, never fewer than one.
    static var days: Int { max(1, defaults.integer(forKey: rangeDays)) }
    static var uses24Hour: Bool { defaults.bool(forKey: use24Hour) }
}

extension OpenTarget {
    /// The user's current choice for `service`.
    static func current(for service: MeetingService) -> OpenTarget {
        resolve(Pref.defaults.string(forKey: Pref.openKey(service)), for: service)
    }
}
