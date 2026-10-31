import UserNotifications
import DingCore

/// What the scheduler needs from the system notification center; a fake in tests so
/// they can never post or clear the user's real notifications.
@MainActor
protocol NotificationScheduling: AnyObject {
    func requestPermission()
    /// Replaces every pending notification with `notifications`.
    func replaceAll(with notifications: [PlannedNotification])
}

/// The slice of `UNUserNotificationCenter` Ding uses, so the scheduler can be driven by a fake.
protocol NotificationCenterProviding: AnyObject {
    func install(delegate: UNUserNotificationCenterDelegate, categories: Set<UNNotificationCategory>)
    func requestAuthorization(options: UNAuthorizationOptions)
    func removeAllPending()
    func add(_ request: UNNotificationRequest)
}

extension UNUserNotificationCenter: NotificationCenterProviding {
    func install(delegate: UNUserNotificationCenterDelegate, categories: Set<UNNotificationCategory>) {
        self.delegate = delegate
        setNotificationCategories(categories)
    }

    func requestAuthorization(options: UNAuthorizationOptions) {
        requestAuthorization(options: options) { _, _ in }
    }

    func removeAllPending() { removeAllPendingNotificationRequests() }

    func add(_ request: UNNotificationRequest) { add(request, withCompletionHandler: nil) }
}

@MainActor
final class UserNotificationScheduler: NSObject, NotificationScheduling, UNUserNotificationCenterDelegate {
    nonisolated static let category = "ding.meeting"
    nonisolated static let joinAction = "ding.join"

    private let center: NotificationCenterProviding

    init(center: NotificationCenterProviding? = nil) {
        self.center = center ?? UNUserNotificationCenter.current()
        super.init()
        let join = UNNotificationAction(identifier: Self.joinAction, title: "Join", options: [])
        self.center.install(
            delegate: self,
            categories: [UNNotificationCategory(identifier: Self.category, actions: [join], intentIdentifiers: [])]
        )
    }

    func requestPermission() {
        center.requestAuthorization(options: [.alert, .sound])
    }

    func replaceAll(with notifications: [PlannedNotification]) {
        center.removeAllPending()
        for item in notifications {
            center.add(Self.makeRequest(for: item))
        }
    }

    // MARK: Pure helpers (tested)

    nonisolated static func makeRequest(for item: PlannedNotification, calendar: Calendar = .current) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = item.title
        content.body = item.body
        if item.playSound { content.sound = .default }
        if let link = item.link {
            content.userInfo = ["url": link.url.absoluteString, "service": link.service.rawValue]
        }
        if item.joinAction { content.categoryIdentifier = category }
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: item.fireDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
        return UNNotificationRequest(identifier: item.id, content: content, trigger: trigger)
    }

    nonisolated static func link(from userInfo: [AnyHashable: Any]) -> MeetingLink? {
        guard let urlString = userInfo["url"] as? String, let url = URL(string: urlString),
              let service = (userInfo["service"] as? String).flatMap(MeetingService.init(rawValue:)) else { return nil }
        return MeetingLink(service: service, url: url)
    }

    /// The Join button and a plain click on the banner both join.
    nonisolated static func isJoin(actionIdentifier: String) -> Bool {
        actionIdentifier == joinAction || actionIdentifier == UNNotificationDefaultActionIdentifier
    }

    /// The link to open for a click on the banner or its Join button, if any.
    nonisolated static func linkToJoin(actionIdentifier: String, userInfo: [AnyHashable: Any]) -> MeetingLink? {
        isJoin(actionIdentifier: actionIdentifier) ? link(from: userInfo) : nil
    }

    nonisolated static let presentationOptions: UNNotificationPresentationOptions = [.banner, .sound]

    // MARK: UNUserNotificationCenterDelegate

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        Self.presentationOptions
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard let link = Self.linkToJoin(
            actionIdentifier: response.actionIdentifier,
            userInfo: response.notification.request.content.userInfo
        ) else { return }
        await MainActor.run { LinkOpener.open(link) }
    }
}
