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
        Task { @MainActor in AppModel.shared.start() }
    }
}
