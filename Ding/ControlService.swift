import DingCore
import DingIPC
import Foundation

/// Answers requests from the bundled MCP helper. Everything a client can see or do passes through here, so this is
/// where the user's permissions are enforced, on every request (turning a switch off takes effect immediately).
@MainActor
final class ControlService {
    struct Environment {
        /// The meetings the user has chosen to see (their calendar selection and dropdown filters apply).
        var events: () -> [DingEvent]
        var now: () -> Date = { Date() }
        var access: () -> CalendarAccess
        var permissions: () -> ControlPermissions
        var join: (DingEvent) -> Void
        var calendar: () -> Calendar = { .current }
    }

    private let environment: Environment

    init(environment: Environment) {
        self.environment = environment
    }

    func handle(_ request: ControlRequest) -> ControlResponse {
        guard let method = ControlMethod(rawValue: request.method) else {
            return .failure(code: "unknown_method", message: "Unknown method \"\(request.method)\".")
        }
        do {
            try authorize(method)
            return .success(try run(method, params: request.params))
        } catch let failure as ControlFailure {
            return .failure(code: failure.code, message: failure.message)
        } catch {
            return .failure(code: "internal_error", message: "Ding couldn't complete that request.")
        }
    }

    // MARK: Permission

    private func authorize(_ method: ControlMethod) throws {
        let permissions = environment.permissions()
        switch method {
        case .getNextMeeting, .listMeetings:
            guard permissions.canReadSchedule else { throw ControlFailure.scheduleAccessOff }
        case .openMeeting:
            guard permissions.canOpenMeetings else { throw ControlFailure.openingOff }
        }
        guard environment.access() == .granted else { throw ControlFailure.noCalendarAccess }
    }

    // MARK: Methods

    private func run(_ method: ControlMethod, params: [String: JSONValue]) throws -> JSONValue {
        let now = environment.now()
        let calendar = environment.calendar()
        let events = environment.events()

        switch method {
        case .getNextMeeting:
            let next = ControlAPI.nextMeeting(events, now: now, timeZone: calendar.timeZone)
            return .object(["meeting": try next.map(Self.json) ?? .null])

        case .listMeetings:
            let days = try Self.integer(params["days"], named: "days") ?? 1
            let includeAllDay = try Self.boolean(params["include_all_day"], named: "include_all_day") ?? false
            let list = try ControlAPI.upcoming(events, now: now, days: days, includeAllDay: includeAllDay, calendar: calendar)
            return try Self.json(list)

        case .openMeeting:
            let id = try Self.string(params["id"], named: "id")
            let target = try ControlAPI.openTarget(events, now: now, id: id)
            environment.join(target)
            // Opening is allowed without seeing the schedule, so the confirmation mustn't reveal which meeting it was
            // unless the user also allowed that.
            var result: [String: JSONValue] = ["opened": .bool(true)]
            if environment.permissions().canReadSchedule {
                result["meeting"] = try Self.json(ControlAPI.summary(of: target, now: now, timeZone: calendar.timeZone))
            }
            return .object(result)
        }
    }

    // MARK: Helpers

    private static func json<T: Encodable>(_ value: T) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(value))
    }

    private static func integer(_ value: JSONValue?, named name: String) throws -> Int? {
        guard let value else { return nil }
        guard let number = value.intValue else { throw ControlFailure.invalidArgument("\(name) must be an integer.") }
        return number
    }

    private static func boolean(_ value: JSONValue?, named name: String) throws -> Bool? {
        guard let value else { return nil }
        guard let flag = value.boolValue else { throw ControlFailure.invalidArgument("\(name) must be true or false.") }
        return flag
    }

    private static func string(_ value: JSONValue?, named name: String) throws -> String? {
        guard let value else { return nil }
        guard let text = value.stringValue, !text.isEmpty else { throw ControlFailure.invalidArgument("\(name) must be a non-empty string.") }
        return text
    }
}
