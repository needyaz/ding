import SwiftUI
import KeyboardShortcuts
import DingCore

enum SettingsTab: String, CaseIterable {
    case general, calendars, meetings, notifications, shortcuts, aiAccess
}

struct SettingsView: View {
    let model: AppModel
    /// The helper path shown on the AI Access tab; nil looks it up in this app's bundle.
    var helperPath: String?? = nil
    var contentHeight: CGFloat = 440
    @State private var selection: SettingsTab

    init(model: AppModel, initialTab: SettingsTab = .general, helperPath: String?? = nil, contentHeight: CGFloat = 440) {
        self.model = model
        self.helperPath = helperPath
        self.contentHeight = contentHeight
        _selection = State(initialValue: initialTab)
    }

    var body: some View {
        TabView(selection: $selection) {
            GeneralTab()
                .tabItem { Label("General", systemImage: "gearshape") }
                .tag(SettingsTab.general)
            CalendarsTab(model: model)
                .tabItem { Label("Calendars", systemImage: "calendar") }
                .tag(SettingsTab.calendars)
            MeetingsTab()
                .tabItem { Label("Meetings", systemImage: "video") }
                .tag(SettingsTab.meetings)
            AlertsTab(model: model)
                .tabItem { Label("Notifications", systemImage: "bell") }
                .tag(SettingsTab.notifications)
            ShortcutsTab()
                .tabItem { Label("Shortcuts", systemImage: "keyboard") }
                .tag(SettingsTab.shortcuts)
            assistantsTab
                .tabItem { Label("AI Access", systemImage: "sparkles") }
                .tag(SettingsTab.aiAccess)
        }
        .frame(width: 480, height: contentHeight)
        .scenePadding()
    }

    @ViewBuilder
    private var assistantsTab: some View {
        if let helperPath {
            AssistantsTab(helperPath: helperPath)
        } else {
            AssistantsTab()
        }
    }
}

// MARK: - General

struct GeneralTab: View {
    @AppStorage(Pref.showCountdown) private var showCountdown = Pref.Default.showCountdown
    @AppStorage(Pref.showTitle) private var showTitle = Pref.Default.showTitle
    @AppStorage(Pref.countdownOnlyToday) private var countdownOnlyToday = Pref.Default.countdownOnlyToday
    @AppStorage(Pref.rangeDays) private var rangeDays = Pref.Default.rangeDays
    @AppStorage(Pref.showEventsWithoutLink) private var showWithoutLink = Pref.Default.showEventsWithoutLink
    @AppStorage(Pref.showMaybe) private var showMaybe = Pref.Default.showMaybe
    @AppStorage(Pref.use24Hour) private var use24Hour = Pref.Default.use24Hour
    @State private var launchAtLogin = LaunchAtLogin.isEnabled

    var body: some View {
        Form {
            Section("Menu bar") {
                Toggle("Show countdown", isOn: $showCountdown)
                Toggle("Show meeting title", isOn: $showTitle)
                Toggle("Only show the countdown for today's meetings", isOn: $countdownOnlyToday)
            }
            Section("Dropdown") {
                Picker("Upcoming range", selection: $rangeDays) {
                    ForEach(Pref.rangeDayOptions, id: \.self) { Text($0 == 1 ? "1 day" : "\($0) days").tag($0) }
                }
                Toggle("Show events without a meeting link", isOn: $showWithoutLink)
                Toggle("Show meetings marked “maybe” or not yet answered", isOn: $showMaybe)
            }
            Section("General") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        // Skip the echo when a failed change is reverted below.
                        guard enabled != LaunchAtLogin.isEnabled else { return }
                        LaunchAtLogin.set(enabled)
                        launchAtLogin = LaunchAtLogin.isEnabled
                    }
                Picker("Clock", selection: $use24Hour) {
                    Text("12-hour").tag(false)
                    Text("24-hour").tag(true)
                }
                .pickerStyle(.segmented)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Calendars

struct CalendarsTab: View {
    let model: AppModel

    var body: some View {
        // Reading prefsVersion refreshes the toggles after a change.
        let _ = model.prefsVersion
        Form {
            if model.accounts.isEmpty {
                Text(model.access == .granted ? "No calendars found." : "Grant calendar access to choose calendars.")
                    .foregroundStyle(.secondary)
            }
            ForEach(model.accounts) { account in
                Section(account.title) {
                    ForEach(account.calendars) { calendar in
                        Toggle(isOn: binding(for: calendar)) {
                            HStack(spacing: 8) {
                                Circle().fill(calendar.color.color).frame(width: 9, height: 9)
                                Text(calendar.title)
                            }
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func binding(for calendar: CalendarInfo) -> Binding<Bool> {
        Binding(
            get: { !Pref.disabledCalendars.contains(calendar.id) },
            set: { enabled in
                var disabled = Pref.disabledCalendars
                if enabled { disabled.remove(calendar.id) } else { disabled.insert(calendar.id) }
                Pref.disabledCalendars = disabled
            }
        )
    }
}

// MARK: - Meetings

struct MeetingsTab: View {
    private let browsers = LinkOpener.installedBrowsers()

    var body: some View {
        Form {
            Section {
                ForEach(MeetingService.allCases) { service in
                    ServiceOpenPicker(service: service, browsers: browsers)
                }
            } header: {
                Text("Open links with")
            } footer: {
                Text("If a desktop app isn't installed, Ding falls back to your default browser.")
            }
        }
        .formStyle(.grouped)
    }
}

struct ServiceOpenPicker: View {
    let service: MeetingService
    let browsers: [LinkOpener.Browser]
    @AppStorage private var value: String

    init(service: MeetingService, browsers: [LinkOpener.Browser]) {
        self.service = service
        self.browsers = browsers
        _value = AppStorage(wrappedValue: OpenTarget.defaultBrowserValue, Pref.openKey(service))
    }

    var body: some View {
        Picker(service.displayName, selection: $value) {
            if service.supportsNativeApp { Text("Desktop app").tag(OpenTarget.nativeValue) }
            Text("Default browser").tag(OpenTarget.defaultBrowserValue)
            Divider()
            ForEach(browsers) { Text($0.name).tag($0.bundleID) }
        }
    }
}

// MARK: - Alerts

struct AlertsTab: View {
    let model: AppModel
    @AppStorage(Pref.notifyLeadMinutes) private var lead = Pref.Default.notifyLeadMinutes
    @AppStorage(Pref.notifySound) private var sound = Pref.Default.notifySound
    @AppStorage(Pref.notifyJoinAction) private var joinAction = Pref.Default.notifyJoinAction
    @AppStorage(Pref.alertMode) private var mode = Pref.Default.alertMode
    @AppStorage(Pref.alertLeadMinutes) private var alertLead = Pref.Default.alertLeadMinutes
    @AppStorage(Pref.alertIncludeAll) private var includeAll = Pref.Default.alertIncludeAll
    @AppStorage(Pref.notifyUnconfirmed) private var notifyUnconfirmed = Pref.Default.notifyUnconfirmed
    @AppStorage(Pref.alertUnconfirmed) private var alertUnconfirmed = Pref.Default.alertUnconfirmed

    var body: some View {
        Form {
            Section("Notification") {
                Picker("Notify me", selection: $lead) {
                    Text("Off").tag(0)
                    ForEach(Pref.leadMinuteOptions, id: \.self) { Text("\($0) min before").tag($0) }
                }
                Toggle("Play a sound", isOn: $sound)
                Toggle("Show a Join button", isOn: $joinAction)
                Toggle("Also for meetings marked “maybe” or not yet answered", isOn: $notifyUnconfirmed)
            }
            Section {
                Picker("Style", selection: $mode) {
                    Text("None").tag(AlertMode.off)
                    Text("Flash the screen edges").tag(AlertMode.edgeFlash)
                    Text("Full-screen alert").tag(AlertMode.fullScreen)
                }
                .pickerStyle(.radioGroup)
                Picker("Show it", selection: $alertLead) {
                    Text("At the start time").tag(0)
                    ForEach(Pref.alertLeadOptions.filter { $0 > 0 }, id: \.self) {
                        Text($0 == 1 ? "1 min before" : "\($0) min before").tag($0)
                    }
                }
                .disabled(mode == .off)
                Toggle("Also for events without a meeting link", isOn: $includeAll)
                Toggle("Also for meetings marked “maybe” or not yet answered", isOn: $alertUnconfirmed)
                Button("Preview") { model.previewAlert() }
                    .disabled(mode == .off)
            } header: {
                Text("Screen reminder")
            } footer: {
                Text("A bigger reminder on top of the notification, with its own timing. Full screen counts down to the start and shows Join, Snooze and Dismiss. Press Esc to dismiss.")
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Shortcuts

struct ShortcutsTab: View {
    var body: some View {
        Form {
            Section {
                KeyboardShortcuts.Recorder("Open Ding menu", name: .openMenu)
                KeyboardShortcuts.Recorder("Join next meeting", name: .joinNext)
            } footer: {
                Text("Both are off until you record a shortcut.")
            }
        }
        .formStyle(.grouped)
    }
}
