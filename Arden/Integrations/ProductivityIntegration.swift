import Foundation
import EventKit

@MainActor
class ProductivityIntegration {
    private let eventStore = EKEventStore()
    private var timers: [UUID: Timer] = [:]

    func createCalendarEvent(params: [String: Any]) async throws -> ExecutionResult {
        let status = await requestCalendarAccess()
        guard status else {
            throw IntegrationError.permissionDenied("Calendar access denied")
        }

        guard let title = params["title"] as? String else {
            throw IntegrationError.missingParameter("title")
        }

        let event = EKEvent(eventStore: eventStore)
        event.title = title
        event.calendar = eventStore.defaultCalendarForNewEvents

        if let dateString = params["date"] as? String,
           let date = ISO8601DateFormatter().date(from: dateString) {
            event.startDate = date

            if let duration = params["duration"] as? Int {
                event.endDate = date.addingTimeInterval(TimeInterval(duration * 60))
            } else {
                event.endDate = date.addingTimeInterval(3600)
            }
        } else {
            event.startDate = Date()
            event.endDate = Date().addingTimeInterval(3600)
        }

        if let location = params["location"] as? String {
            event.location = location
        }

        do {
            try eventStore.save(event, span: .thisEvent)
            return ExecutionResult(
                success: true,
                message: "Created calendar event: \(title)"
            )
        } catch {
            throw IntegrationError.executionFailed("Failed to create event: \(error.localizedDescription)")
        }
    }

    func createReminder(params: [String: Any]) async throws -> ExecutionResult {
        let status = await requestRemindersAccess()
        guard status else {
            throw IntegrationError.permissionDenied("Reminders access denied")
        }

        guard let title = params["title"] as? String else {
            throw IntegrationError.missingParameter("title")
        }

        let reminder = EKReminder(eventStore: eventStore)
        reminder.title = title
        reminder.calendar = eventStore.defaultCalendarForNewReminders()

        if let dateString = params["date"] as? String,
           let date = ISO8601DateFormatter().date(from: dateString) {
            let alarm = EKAlarm(absoluteDate: date)
            reminder.addAlarm(alarm)
        }

        if let priorityString = params["priority"] as? String {
            switch priorityString.lowercased() {
            case "high":
                reminder.priority = 1
            case "medium":
                reminder.priority = 5
            case "low":
                reminder.priority = 9
            default:
                reminder.priority = 0
            }
        }

        do {
            try eventStore.save(reminder, commit: true)
            return ExecutionResult(
                success: true,
                message: "Created reminder: \(title)"
            )
        } catch {
            throw IntegrationError.executionFailed("Failed to create reminder: \(error.localizedDescription)")
        }
    }

    func startTimer(params: [String: Any]) async throws -> ExecutionResult {
        guard let duration = params["duration"] as? Int else {
            throw IntegrationError.missingParameter("duration")
        }

        let label = params["label"] as? String ?? "Timer"
        let timerId = UUID()

        let timer = Timer.scheduledTimer(withTimeInterval: TimeInterval(duration), repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.timerCompleted(id: timerId, label: label)
            }
        }

        timers[timerId] = timer

        let minutes = duration / 60
        let seconds = duration % 60

        var timeString = ""
        if minutes > 0 {
            timeString += "\(minutes) minute\(minutes != 1 ? "s" : "")"
        }
        if seconds > 0 {
            if !timeString.isEmpty {
                timeString += " and "
            }
            timeString += "\(seconds) second\(seconds != 1 ? "s" : "")"
        }

        return ExecutionResult(
            success: true,
            message: "Timer started for \(timeString)",
            data: ["timerId": timerId.uuidString]
        )
    }

    private func timerCompleted(id: UUID, label: String) {
        timers.removeValue(forKey: id)
        print("Timer '\(label)' completed")
    }

    func createNote(params: [String: Any]) async throws -> ExecutionResult {
        guard let title = params["title"] as? String else {
            throw IntegrationError.missingParameter("title")
        }

        let content = params["content"] as? String ?? ""

        return ExecutionResult(
            success: true,
            message: "Note created: \(title). (Note: Full Notes integration requires additional setup)",
            data: ["title": title, "content": content]
        )
    }

    func createAlarm(params: [String: Any]) async throws -> ExecutionResult {
        guard let timeString = params["time"] as? String else {
            throw IntegrationError.missingParameter("time")
        }

        let label = params["label"] as? String ?? "Alarm"
        let recurring = params["recurring"] as? Bool ?? false

        return ExecutionResult(
            success: true,
            message: "Alarm set for \(timeString). (Note: Full Alarm integration requires Clock app URL scheme or Shortcuts)",
            data: ["time": timeString, "label": label, "recurring": recurring]
        )
    }

    private func requestCalendarAccess() async -> Bool {
        if #available(iOS 17.0, *) {
            return await withCheckedContinuation { continuation in
                eventStore.requestFullAccessToEvents { granted, error in
                    continuation.resume(returning: granted)
                }
            }
        } else {
            return await withCheckedContinuation { continuation in
                eventStore.requestAccess(to: .event) { granted, error in
                    continuation.resume(returning: granted)
                }
            }
        }
    }

    private func requestRemindersAccess() async -> Bool {
        if #available(iOS 17.0, *) {
            return await withCheckedContinuation { continuation in
                eventStore.requestFullAccessToReminders { granted, error in
                    continuation.resume(returning: granted)
                }
            }
        } else {
            return await withCheckedContinuation { continuation in
                eventStore.requestAccess(to: .reminder) { granted, error in
                    continuation.resume(returning: granted)
                }
            }
        }
    }
}

enum IntegrationError: LocalizedError {
    case permissionDenied(String)
    case missingParameter(String)
    case executionFailed(String)

    var errorDescription: String? {
        switch self {
        case .permissionDenied(let message):
            return message
        case .missingParameter(let param):
            return "Missing required parameter: \(param)"
        case .executionFailed(let message):
            return message
        }
    }
}
