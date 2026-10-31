import AppKit
import SwiftUI
import DingCore

/// Borderless windows that cover each display: a brief edge pulse, or a full-screen takeover.
/// Window construction is separate from showing so tests can inspect windows without displaying them.
@MainActor
final class AlertController {
    private(set) var windows: [NSWindow] = []
    private var snoozeWork: [String: DispatchWorkItem] = [:]

    // Seams for tests.
    var screens: () -> [NSScreen] = { NSScreen.screens }
    var primaryScreen: () -> NSScreen? = { NSScreen.main ?? NSScreen.screens.first }
    var orderFront: (NSWindow, _ asKey: Bool) -> Void = { window, asKey in
        if asKey { window.makeKeyAndOrderFront(nil) } else { window.orderFrontRegardless() }
    }
    var activateApp: () -> Void = { NSApp.activate(ignoringOtherApps: true) }
    var openLink: (MeetingLink) -> Void = { LinkOpener.open($0) }
    var snoozeInterval: TimeInterval = 60
    var flashDuration: TimeInterval = 2.2

    func show(_ event: DingEvent, mode: AlertMode) {
        switch mode {
        case .off: break
        case .edgeFlash: flash()
        case .fullScreen: takeover(event)
        }
    }

    // MARK: Edge flash

    func makeFlashWindows() -> [NSWindow] {
        screens().map { screen in
            let window = Self.makeWindow(for: screen, ofType: NSWindow.self)
            window.ignoresMouseEvents = true
            window.contentView = NSHostingView(rootView: EdgeFlashView())
            return window
        }
    }

    private func flash() {
        let flashWindows = makeFlashWindows()
        flashWindows.forEach { orderFront($0, false) }
        DispatchQueue.main.asyncAfter(deadline: .now() + flashDuration) {
            flashWindows.forEach { $0.close() }
        }
    }

    // MARK: Full screen

    /// One window per display. Only the primary display gets the card; the rest are dimmed.
    func makeTakeoverWindows(for event: DingEvent) -> [AlertWindow] {
        let primary = primaryScreen()
        return screens().map { screen in
            let window = Self.makeWindow(for: screen, ofType: AlertWindow.self)
            window.onEscape = { [weak self] in self?.dismiss() }
            window.contentView = NSHostingView(rootView: FullScreenAlertView(
                event: screen == primary ? event : nil,
                join: { [weak self] in
                    if let link = event.link { self?.openLink(link) }
                    self?.dismiss()
                },
                snooze: { [weak self] in self?.snooze(event) },
                dismiss: { [weak self] in self?.dismiss() }
            ))
            return window
        }
    }

    private func takeover(_ event: DingEvent) {
        dismiss()
        let takeoverWindows = makeTakeoverWindows(for: event)
        windows = takeoverWindows
        let primary = primaryScreen()
        for window in takeoverWindows { orderFront(window, window.screen == primary) }
        activateApp()
    }

    private func snooze(_ event: DingEvent) {
        dismiss()
        let work = DispatchWorkItem { [weak self] in self?.takeover(event) }
        snoozeWork[event.id]?.cancel()
        snoozeWork[event.id] = work
        DispatchQueue.main.asyncAfter(deadline: .now() + snoozeInterval, execute: work)
    }

    func dismiss() {
        windows.forEach { $0.close() }
        windows.removeAll()
    }

    private static func makeWindow<T: NSWindow>(for screen: NSScreen, ofType: T.Type) -> T {
        let window = T(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false, screen: screen)
        window.setFrame(screen.frame, display: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.level = .screenSaver
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        return window
    }
}

/// A borderless window that can take focus so Esc and Return work.
final class AlertWindow: NSWindow {
    var onEscape: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func cancelOperation(_ sender: Any?) { onEscape?() }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onEscape?() } else { super.keyDown(with: event) }
    }
}

// MARK: - Views

struct EdgeFlashView: View {
    @State private var lit = false

    var body: some View {
        Rectangle()
            .strokeBorder(Color.accentColor, lineWidth: 28)
            .blur(radius: 22)
            .opacity(lit ? 0.9 : 0)
            .ignoresSafeArea()
            .onAppear {
                withAnimation(.easeInOut(duration: 0.45).repeatCount(4, autoreverses: true)) { lit = true }
            }
            .allowsHitTesting(false)
    }
}

struct FullScreenAlertView: View {
    /// Nil on secondary displays, which only get the dimmed backdrop.
    let event: DingEvent?
    let join: () -> Void
    let snooze: () -> Void
    let dismiss: () -> Void

    var body: some View {
        ZStack {
            Rectangle().fill(.black.opacity(0.78)).ignoresSafeArea()
            if let event {
                VStack(spacing: 18) {
                    Text(event.title)
                        .font(.system(size: 44, weight: .semibold))
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Text(EventDisplay.alertStatus(now: context.date, start: event.start))
                            .font(.system(size: 24, weight: .regular).monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    HStack(spacing: 12) {
                        if let link = event.link {
                            Button("Join \(link.service.displayName)", action: join)
                                .keyboardShortcut(.defaultAction)
                                .buttonStyle(.borderedProminent)
                        }
                        Button("Snooze 1 min", action: snooze)
                        Button("Dismiss", action: dismiss)
                            .keyboardShortcut(.cancelAction)
                    }
                    .controlSize(.extraLarge)
                    .padding(.top, 12)
                    Text("Esc to dismiss")
                        .font(.footnote)
                        .foregroundStyle(.tertiary)
                }
                .foregroundStyle(.white)
                .padding(60)
            }
        }
    }
}
