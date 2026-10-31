#if DEBUG
import AppKit
import DingCore
import SwiftUI

/// One App Store screenshot: a file name and the SwiftUI view to render at `ScreenshotMode.pointSize`.
struct ScreenshotScene {
    let name: String
    let view: AnyView

    @MainActor
    static func all(model: AppModel) -> [ScreenshotScene] {
        let helper = "/Applications/Ding.app/Contents/Helpers/ding-mcp"
        func preferences(_ tab: SettingsTab, height: CGFloat = 440) -> some View {
            MacWindow(title: "Ding Preferences") {
                SettingsView(model: model, initialTab: tab, helperPath: .some(helper), contentHeight: height)
            }
            .fixedSize()
        }

        return [
            ScreenshotScene(name: "01_menu-bar", view: AnyView(
                ShotLayout(
                    caption: "Your next meeting, always in view.",
                    subtitle: "A live countdown in the menu bar, and one click to see what's next and join it."
                ) { MenuBarPanel(model: model) }
            )),
            ScreenshotScene(name: "02_meetings", view: AnyView(
                ShotLayout(
                    caption: "Join the way you like.",
                    subtitle: "Zoom, Meet, Teams and Webex open in their app or the browser you pick."
                ) { preferences(.meetings, height: 300) }
            )),
            ScreenshotScene(name: "03_full-screen", view: AnyView(
                StackedShotLayout(
                    caption: "A reminder you won't miss.",
                    subtitle: "Flash the screen edges or take over the screen, with a live countdown, Join and Snooze."
                ) { FullScreenPreview() }
            )),
            ScreenshotScene(name: "04_notifications", view: AnyView(
                ShotLayout(
                    caption: "Reminders on your terms.",
                    subtitle: "A notification and a bigger reminder, each with its own timing."
                ) { preferences(.notifications, height: 540) }
            )),
            ScreenshotScene(name: "05_calendars", view: AnyView(
                ShotLayout(
                    caption: "Uses the calendars you already have.",
                    subtitle: "iCloud, Google, Exchange and more, with nothing new to sign in to."
                ) { preferences(.calendars, height: 290) }
            )),
            ScreenshotScene(name: "06_ai-access", view: AnyView(
                ShotLayout(
                    caption: "Works with your AI assistant.",
                    subtitle: "Optional and off by default. It never sees notes, attendees or meeting links."
                ) { preferences(.aiAccess, height: 610) }
            )),
        ]
    }
}

// MARK: - Layout

private extension Color {
    init(hex: UInt32) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}

/// Caption on the left, the real UI on the right, over the site's cream-to-blue background.
private struct ShotLayout<Content: View>: View {
    let caption: String
    let subtitle: String
    @ViewBuilder var content: Content

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: 0xFAF7F2), Color(hex: 0xD3E0FA)], startPoint: .top, endPoint: .bottom)
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 14) {
                    Text(caption)
                        .font(.system(size: 50, weight: .semibold, design: .serif))
                        .foregroundStyle(Color(hex: 0x1A3A8F))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(subtitle)
                        .font(.system(size: 20))
                        .foregroundStyle(Color(hex: 0x4A5A7A))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.leading, 64)
                .padding(.trailing, 24)
                .frame(width: 470, alignment: .leading)
                content.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

// MARK: - Mac chrome

/// Caption centered above the content, for wide content such as a whole screen.
private struct StackedShotLayout<Content: View>: View {
    let caption: String
    let subtitle: String
    @ViewBuilder var content: Content

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: 0xFAF7F2), Color(hex: 0xD3E0FA)], startPoint: .top, endPoint: .bottom)
            VStack(spacing: 10) {
                Text(caption)
                    .font(.system(size: 50, weight: .semibold, design: .serif))
                    .foregroundStyle(Color(hex: 0x1A3A8F))
                Text(subtitle)
                    .font(.system(size: 20))
                    .foregroundStyle(Color(hex: 0x4A5A7A))
                content.padding(.top, 22)
                Spacer(minLength: 0)
            }
            .padding(.top, 54)
        }
    }
}

/// A window with a title bar and traffic lights around real content. The real window frame can't be captured
/// off-screen, so this draws a faithful one.
private struct MacWindow<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    ForEach([0xFF5F57, 0xFEBC2E, 0x28C840] as [UInt32], id: \.self) { Circle().fill(Color(hex: $0)).frame(width: 12, height: 12) }
                    Spacer()
                }
                .padding(.leading, 14)
            }
            .frame(height: 28)
            content
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 11))
        .overlay(RoundedRectangle(cornerRadius: 11).stroke(.black.opacity(0.18), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.28), radius: 22, y: 12)
    }
}

/// A wallpaper with a menu bar and the real dropdown under Ding's item.
private struct MenuBarPanel: View {
    let model: AppModel

    var body: some View {
        ZStack(alignment: .topTrailing) {
            LinearGradient(colors: [Color(hex: 0x2F3E9E), Color(hex: 0x7A5BB0), Color(hex: 0xE59BB8)], startPoint: .topLeading, endPoint: .bottomTrailing)
            VStack(spacing: 0) {
                HStack(spacing: 14) {
                    Spacer()
                    MenuBarLabel(model: model).font(.system(size: 13, weight: .medium))
                    Image(systemName: "wifi")
                    Image(systemName: "battery.100")
                    Text("Tue 9:48 AM")
                }
                .font(.system(size: 13))
                .foregroundStyle(.black.opacity(0.85))
                .padding(.horizontal, 14)
                .frame(height: 26)
                .background(.white.opacity(0.62))
                MenuContentView(model: model)
                    .background(Color(nsColor: .windowBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(.black.opacity(0.14), lineWidth: 0.5))
                    .shadow(color: .black.opacity(0.35), radius: 18, y: 8)
                    .padding(.top, 8)
                    .padding(.trailing, 90)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .frame(width: 640, height: 800)
        .clipped()
        .frame(maxWidth: .infinity, alignment: .trailing)
    }
}

/// The full-screen reminder over a wallpaper, zoomed in on the middle of the screen so it reads at this size.
private struct FullScreenPreview: View {
    private let screen = CGSize(width: 1440, height: 900)
    private let zoom: CGFloat = 0.86

    var body: some View {
        let start = ScreenshotFixtures.at(day: 0, hour: 10, minute: 0)
        let event = ScreenshotFixtures.events.first { $0.start == start }!
        ZStack {
            LinearGradient(colors: [Color(hex: 0x4A6FE3), Color(hex: 0x9C7BD6), Color(hex: 0xF3A6B8)], startPoint: .topLeading, endPoint: .bottomTrailing)
            FullScreenAlertView(event: event, join: {}, snooze: {}, dismiss: {}, fixedNow: start.addingTimeInterval(-59))
        }
        .frame(width: screen.width, height: screen.height)
        .scaleEffect(zoom)
        .frame(width: 1120, height: 560)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.black.opacity(0.2), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.3), radius: 22, y: 12)
    }
}
#endif
