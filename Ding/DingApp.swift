import SwiftUI
import MenuBarExtraAccess

@main
struct DingApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    private let model = AppModel.shared

    var body: some Scene {
        MenuBarExtra {
            MenuContentView(model: model)
        } label: {
            MenuBarLabel(model: model)
        }
        // Must be the first modifier after MenuBarExtra.
        .menuBarExtraAccess(isPresented: Binding(
            get: { model.isMenuPresented },
            set: { model.isMenuPresented = $0 }
        ))
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // The unit-test host must not prompt for calendar access or schedule alerts.
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil { return }
        #if DEBUG
        // `make screenshots`: render the App Store screenshots from fixtures, then quit.
        if ScreenshotMode.isRequested {
            Task { @MainActor in ScreenshotMode.run() }
            return
        }
        #endif
        Task { @MainActor in AppModel.shared.start() }
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Leave no stale socket behind for the helper to mistake for a running app.
        MainActor.assumeIsolated { AppModel.shared.stopControlServer() }
    }
}
