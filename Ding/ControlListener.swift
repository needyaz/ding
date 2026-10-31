import DingIPC
import Foundation

/// Listens on a Unix socket in the app group container and hands each request to the `ControlService`.
/// Only programs signed by the same team may connect, so in practice that's the MCP helper inside this app.
final class ControlListener {
    private let server: ControlSocketServer

    /// Nil if the app group isn't configured (a build without it).
    convenience init?(service: ControlService, bundle: Bundle = .main) {
        guard let group = bundle.object(forInfoDictionaryKey: DingIPC.appGroupInfoKey) as? String,
              let team = DingIPC.teamID(fromAppGroup: group),
              let url = DingIPC.socketURL(appGroup: group) else { return nil }
        self.init(service: service, path: url.path, requirement: DingIPC.codeSigningRequirement(teamID: team))
    }

    init(service: ControlService, path: String, requirement: String?) {
        server = ControlSocketServer(path: path, requirement: requirement) { data in
            let response: ControlResponse
            if let request = try? JSONDecoder().decode(ControlRequest.self, from: data) {
                response = await MainActor.run { service.handle(request) }
            } else {
                response = .failure(code: "invalid_request", message: "Ding couldn't read that request.")
            }
            return (try? JSONEncoder().encode(response)) ?? Data()
        }
    }

    func start() {
        do { try server.start() } catch { NSLog("Ding: the control socket failed to start: \(error)") }
    }

    func stop() { server.stop() }
}
