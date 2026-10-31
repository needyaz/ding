import Foundation
import DingCore

struct CalendarInfo: Identifiable, Equatable {
    let id: String
    let title: String
    let color: CalendarColor
}

/// A calendar source (iCloud, Google, Exchange, ...) and the calendars it holds.
struct CalendarAccount: Identifiable, Equatable {
    let title: String
    let calendars: [CalendarInfo]
    var id: String { title }
}

enum CalendarAccess: Equatable {
    case notDetermined
    case granted
    case denied
}

/// What `AppModel` needs from a calendar backend: EventKit in the app, a fake in tests.
@MainActor
protocol CalendarSource: AnyObject {
    var access: CalendarAccess { get }
    var onChange: (() -> Void)? { get set }
    func requestAccess() async
    func events(from start: Date, to end: Date) -> [DingEvent]
    func accounts() -> [CalendarAccount]
}
