import SwiftUI
import DingCore

/// Shared layout constants for the dropdown.
private enum Metrics {
    static let width: CGFloat = 340
    static let maxListHeight: CGFloat = 460
    static let horizontalPadding: CGFloat = 14
}

struct MenuContentView: View {
    let model: AppModel
    @AppStorage(Pref.use24Hour) private var use24Hour = Pref.Default.use24Hour

    var body: some View {
        VStack(spacing: 0) {
            content
            Divider()
            footer
        }
        .frame(width: Metrics.width)
    }

    @ViewBuilder
    private var content: some View {
        switch model.access {
        case .notDetermined:
            message("Ding needs access to your calendar to show your meetings.", button: "Allow Calendar Access") {
                model.requestCalendarAccess()
            }
        case .denied:
            message("Calendar access is turned off for Ding.", button: "Open Privacy Settings") {
                NSWorkspace.shared.open(AppInfo.calendarPrivacySettingsURL)
            }
        case .granted:
            if model.groups.isEmpty { emptyState } else { eventList }
        }
    }

    private var emptyState: some View {
        Text("No upcoming meetings")
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 28)
    }

    private var eventList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(model.groups) { group in
                    DayHeader(title: EventDisplay.dayTitle(group.day, now: model.now))
                    ForEach(group.events) { event in
                        EventRow(event: event, now: model.now, use24Hour: use24Hour) { model.join(event) }
                    }
                }
            }
            .padding(.vertical, 6)
        }
        .frame(maxHeight: Metrics.maxListHeight)
    }

    private func message(_ text: String, button: String, action: @escaping () -> Void) -> some View {
        VStack(spacing: 12) {
            Text(text).multilineTextAlignment(.center).foregroundStyle(.secondary)
            Button(button, action: action)
        }
        .padding(20)
        .frame(maxWidth: .infinity)
    }

    private var footer: some View {
        HStack(spacing: 14) {
            Button("Preferences…") { model.openSettings() }
            Button("Send Feedback") {
                model.isMenuPresented = false
                NSWorkspace.shared.open(AppInfo.feedbackURL)
            }
            Spacer()
            Button("Quit") { NSApp.terminate(nil) }
        }
        .buttonStyle(.plain)
        .font(.callout)
        .foregroundStyle(.secondary)
        .padding(.horizontal, Metrics.horizontalPadding)
        .padding(.vertical, 10)
    }
}

private struct DayHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .textCase(.uppercase)
            .foregroundStyle(.secondary)
            .padding(.horizontal, Metrics.horizontalPadding)
            .padding(.top, 10)
            .padding(.bottom, 4)
            .accessibilityAddTraits(.isHeader)
    }
}

private struct EventRow: View {
    let event: DingEvent
    let now: Date
    let use24Hour: Bool
    let join: () -> Void
    @State private var isHovering = false

    private var isInProgress: Bool { !event.isAllDay && event.start <= now && event.end > now }

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(event.calendarColor.color)
                .frame(width: 9, height: 9)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(event.title)
                    .font(event.isAllDay ? .callout.italic() : .callout)
                    .lineLimit(1)
                Text(EventDisplay.timeText(for: event, use24Hour: use24Hour))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if let link = event.link {
                Label(link.service.displayName, systemImage: "video.fill")
                    .labelStyle(.iconOnly)
                    .foregroundStyle(isHovering ? Color.accentColor : .secondary)
                    .help("Join \(link.service.displayName)")
            }
        }
        .opacity(event.isMaybe ? 0.6 : 1)
        .padding(.horizontal, Metrics.horizontalPadding)
        .padding(.vertical, 5)
        .background { background }
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .onTapGesture { if event.hasLink { join() } }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(event.hasLink ? .isButton : [])
        .accessibilityHint(event.link.map { "Joins with \($0.service.displayName)" } ?? "")
        .accessibilityAction { if event.hasLink { join() } }
    }

    @ViewBuilder
    private var background: some View {
        if event.isAllDay {
            Color.secondary.opacity(0.08)
        } else if isInProgress {
            Color.accentColor.opacity(0.10)
        }
        if isHovering && event.hasLink { Color.accentColor.opacity(0.18) }
    }
}
