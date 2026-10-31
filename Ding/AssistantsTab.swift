import AppKit
import DingCore
import SwiftUI

/// Where the MCP helper lives inside the app bundle.
enum ControlHelper {
    static let relativePath = "Contents/Helpers/ding-mcp"

    /// The helper's absolute path, or nil if this build doesn't include it.
    static func path(bundleURL: URL = Bundle.main.bundleURL, fileManager: FileManager = .default) -> String? {
        let url = bundleURL.appendingPathComponent(relativePath)
        return fileManager.isExecutableFile(atPath: url.path) ? url.path : nil
    }
}

/// Preferences → AI Access: what an AI assistant (any MCP app) may do, and how to connect one.
struct AssistantsTab: View {
    @AppStorage(Pref.controlReadSchedule) private var readSchedule = Pref.Default.controlReadSchedule
    @AppStorage(Pref.controlOpenMeetings) private var openMeetings = Pref.Default.controlOpenMeetings
    @State private var copied: String?

    let helperPath: String?
    let copy: (String) -> Void

    init(
        helperPath: String? = ControlHelper.path(),
        copy: @escaping (String) -> Void = { text in
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        }
    ) {
        self.helperPath = helperPath
        self.copy = copy
    }

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $readSchedule) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Let AI assistants see my schedule")
                        Text("An assistant can ask for your next meeting and what's coming up: titles, times, calendar names, and whether each is Zoom, Meet, Teams or Webex.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Toggle(isOn: $openMeetings) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Let AI assistants open my meetings")
                        Text("An assistant can make Ding open a meeting in the app or browser you've chosen, such as \"open my next meeting\". This works without seeing your schedule, and the assistant only learns that it happened.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Allow")
            } footer: {
                Text("Assistants never see notes, attendees, locations or meeting links, and can't change your calendar.")
            }

            Section {
                if let helperPath {
                    copyRow("Claude Desktop", button: "Copy Entry", text: MCPConfig.desktopEntry(command: helperPath))
                    copyRow("Claude Code", button: "Copy Command", text: MCPConfig.claudeCodeCommand(command: helperPath))
                    copyRow("Other MCP apps", button: "Copy Path", text: helperPath)
                    Text(helperPath)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                } else {
                    Text("This build of Ding doesn't include the assistant helper.")
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Connect")
            } footer: {
                Text("Claude Desktop: choose Settings → Developer → Edit Config, paste the entry just before the final }, and put a comma after the entry above it (no comma if the file is just { }). If it already has an \"mcpServers\" section, add only the \"ding\" part inside it. Then quit and reopen Claude Desktop. Claude Code: run the command in a terminal. Any other app that supports MCP servers can use the path as the command to run. Ding has to be running for an assistant to reach it.")
            }
        }
        .formStyle(.grouped)
    }

    private func copyRow(_ title: String, button: String, text: String) -> some View {
        LabeledContent(title) {
            HStack(spacing: 8) {
                if copied == title {
                    Text("Copied").font(.caption).foregroundStyle(.secondary)
                }
                Button(button) {
                    copy(text)
                    copied = title
                }
            }
        }
    }
}
