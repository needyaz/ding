import AppKit
import SwiftUI

/// A plain window instead of a SwiftUI `Settings` scene, which is unreliable from an
/// agent (menu bar only) app.
@MainActor
final class SettingsWindowController {
    static let shared = SettingsWindowController()
    private var window: NSWindow?
    private let activate: () -> Void

    init(activate: (() -> Void)? = nil) {
        self.activate = activate ?? { NSApp.activate(ignoringOtherApps: true) }
    }

    /// The window, built on first use. Separate from `show()` so it can be inspected without displaying it.
    func makeWindow() -> NSWindow {
        if let window { return window }
        let hosting = NSHostingController(rootView: SettingsView(model: AppModel.shared))
        let window = NSWindow(contentViewController: hosting)
        window.title = "Ding Preferences"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.center()
        self.window = window
        return window
    }

    /// `order` is a seam so tests can show without putting a window on screen.
    func show(order: ((NSWindow) -> Void)? = nil) {
        let window = makeWindow()
        activate()
        (order ?? { $0.makeKeyAndOrderFront(nil) })(window)
    }
}
