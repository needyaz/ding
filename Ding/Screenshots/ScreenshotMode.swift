#if DEBUG
import AppKit
import SwiftUI
import DingCore

/// Renders the App Store screenshots from the real views, with fixture data and a frozen clock.
///
/// Debug builds only. `Ding --screenshots` writes one PNG per scene into the app's temporary directory and quits;
/// `make screenshots` runs it and copies the PNGs into `listing/screenshots/`. It never reads a calendar and never
/// touches the real preferences.
/// Reports itself as the key and main window, so controls draw in their live colors. macOS won't activate an app that
/// was started from a background session, and a dimmed, inactive-looking control is the wrong thing to put in a store listing.
private final class AlwaysActiveWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    override var isKeyWindow: Bool { true }
    override var isMainWindow: Bool { true }
}

@MainActor
enum ScreenshotMode {
    static var isRequested: Bool { CommandLine.arguments.contains("--screenshots") }

    /// The size every screenshot is delivered at: the largest Mac App Store size, 16:10.
    static let pixelSize = CGSize(width: 2880, height: 1800)
    /// Scenes are laid out in this many points (the smallest Mac App Store size); 2.25x gives the delivered size.
    static let pointSize = CGSize(width: 1280, height: 800)
    static var scale: CGFloat { pixelSize.width / pointSize.width }

    static var outputDirectory: URL {
        URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("shots", isDirectory: true)
    }

    static func run() {
        waitUntilActive()
        let defaults = ScreenshotFixtures.makeDefaults()
        ScreenshotFixtures.configure(defaults)
        LaunchAtLogin.service = OffLoginItem()
        NSApp.appearance = NSAppearance(named: .aqua)

        let model = AppModel(calendar: ScreenshotCalendar(), notifier: SilentNotifier())
        model.startsControlServer = false
        model.access = .granted
        model.now = ScreenshotFixtures.now
        model.events = ScreenshotFixtures.events
        model.accounts = ScreenshotFixtures.accounts

        let directory = outputDirectory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for old in (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? [] {
            try? FileManager.default.removeItem(at: old)
        }

        for scene in ScreenshotScene.all(model: model) {
            let view = scene.view.defaultAppStorage(defaults)
            guard let png = render(view) else {
                NSLog("Ding screenshots: could not render \(scene.name)")
                continue
            }
            let file = directory.appendingPathComponent("\(scene.name).png")
            do { try png.write(to: file) } catch { NSLog("Ding screenshots: \(scene.name): \(error)") }
        }
        defaults.removePersistentDomain(forName: "blue.luci.Ding.screenshots")
        NSApp.terminate(nil)
    }

    /// Waits while processing real application events (a plain run-loop spin doesn't deliver "the app became active").
    private static func pump(for seconds: TimeInterval) {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if let event = NSApp.nextEvent(matching: .any, until: Date().addingTimeInterval(0.05), inMode: .default, dequeue: true) {
                NSApp.sendEvent(event)
            }
        }
    }

    /// Controls draw dimmed unless the app itself is active, and macOS won't activate an app that was started from a
    /// background session. So this shows a small window for `make screenshots` to click (see
    /// scripts/bring_ding_forward.sh), then waits for the click to make Ding the active app.
    private static func waitUntilActive(timeout: TimeInterval = 15) {
        NSApp.setActivationPolicy(.regular)  // a menu bar app can't be brought forward; a regular one can. Only for this run.
        let window = NSWindow(contentRect: .zero, styleMask: [.titled], backing: .buffered, defer: false)
        window.title = "Ding"
        window.isReleasedWhenClosed = false  // Swift owns it; AppKit releasing it as well would over-release
        window.contentView = NSHostingView(rootView: Text("Preparing screenshots…").padding(28))
        window.center()
        window.makeKeyAndOrderFront(nil)
        defer { window.close() }

        let deadline = Date().addingTimeInterval(timeout)
        while !NSApp.isActive && Date() < deadline { pump(for: 0.1) }
        if !NSApp.isActive { NSLog("Ding screenshots: the app never became active, so controls will look dimmed") }
        pump(for: 0.5)  // let the active look settle
    }

    /// Lays the view out in an off-screen window and draws it at `scale`, so controls backed by AppKit are included.
    static func render<V: View>(_ view: V) -> Data? {
        let host = NSHostingView(rootView: view
            .environment(\.controlActiveState, .key)
            .frame(width: pointSize.width, height: pointSize.height))
        let window = AlwaysActiveWindow(contentRect: NSRect(origin: .zero, size: pointSize), styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = host
        window.isReleasedWhenClosed = false  // Swift owns it; AppKit releasing it as well would over-release
        window.isOpaque = true
        window.setFrameOrigin(NSPoint(x: -30_000, y: -30_000))
        // Key and active, so controls draw in their live colors (accent blue) and not their dimmed, inactive ones.
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        defer { window.close() }
        for _ in 0..<3 {  // let SwiftUI finish its layout passes
            host.layoutSubtreeIfNeeded()
            pump(for: 0.25)
        }

        // Recorded next to the images so a run that looks dimmed can be explained (read by `make screenshots`).
        let status = "active=\(NSApp.isActive) windowKey=\(window.isKeyWindow) windowVisible=\(window.isVisible) appearance=\(window.effectiveAppearance.name.rawValue)\n"
        try? status.write(to: outputDirectory.appendingPathComponent("status.txt"), atomically: true, encoding: .utf8)

        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(pixelSize.width), pixelsHigh: Int(pixelSize.height), bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ) else { return nil }
        rep.size = pointSize
        host.cacheDisplay(in: host.bounds, to: rep)
        return rep.representation(using: .png, properties: [:])
    }
}
#endif
