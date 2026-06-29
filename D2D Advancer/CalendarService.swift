import Foundation
import EventKit
import SwiftUI

enum CalendarSettingsLocalStore {
    static func loadSettings(from userDefaults: UserDefaults, key: String) throws -> CalendarIntegrationSettings? {
        guard let data = userDefaults.data(forKey: key) else { return nil }
        return try JSONDecoder().decode(CalendarIntegrationSettings.self, from: data)
    }

    static func save(_ settings: CalendarIntegrationSettings, to userDefaults: UserDefaults, key: String) throws {
        let encoded = try JSONEncoder().encode(settings)
        userDefaults.set(encoded, forKey: key)
    }
}

// Calendar integration for Apple Calendar (EventKit)
final class CalendarService: ObservableObject {
    static let shared = CalendarService()

    private let eventStore = EKEventStore()
    private let settingsKey = "calendar_integration_settings"

    @Published private(set) var authorizationStatus: EKAuthorizationStatus = .notDetermined
    @Published private(set) var settings: CalendarIntegrationSettings = CalendarIntegrationSettings()
    @Published var lastErrorMessage: String?

    private init() {
        self.authorizationStatus = EKEventStore.authorizationStatus(for: .event)
        loadSettings()
    }

    // MARK: - Permissions
    func requestAccessIfNeeded(completion: @escaping (Bool) -> Void) {
        let status = EKEventStore.authorizationStatus(for: .event)
        authorizationStatus = status

        switch status {
        case .notDetermined:
            eventStore.requestFullAccessToEvents { [weak self] _, _ in
                DispatchQueue.main.async {
                    let newStatus = EKEventStore.authorizationStatus(for: .event)
                    self?.authorizationStatus = newStatus
                    completion(self?.hasWriteAccessOrBetter ?? false)
                }
            }
        case .denied, .restricted:
            completion(false)
        case .fullAccess, .writeOnly:
            completion(true)
        default:
            // Treat any other (legacy) state as granted
            completion(true)
        }
    }

    // MARK: - Access Helpers
    var hasWriteAccessOrBetter: Bool {
        let status = EKEventStore.authorizationStatus(for: .event)
        return status == .fullAccess || status == .writeOnly
    }

    var hasFullAccess: Bool {
        let status = EKEventStore.authorizationStatus(for: .event)
        return status == .fullAccess
    }

    // MARK: - Calendars
    func allEventCalendars() -> [EKCalendar] {
        guard hasFullAccess else { return [] }
        return eventStore.calendars(for: .event)
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    func selectedCalendar() -> EKCalendar? {
        if hasFullAccess, let id = settings.selectedCalendarIdentifier, let cal = eventStore.calendar(withIdentifier: id) {
            return cal
        }
        return eventStore.defaultCalendarForNewEvents
    }

    func setSelectedCalendar(_ calendar: EKCalendar?) {
        var updated = settings
        updated.selectedCalendarIdentifier = calendar?.calendarIdentifier
        _ = updateSettings(updated)
    }

    func reloadSettingsFromUserDefaults() {
        loadSettings()
    }

    // MARK: - Events
    @discardableResult
    func createOrUpdateEvent(for appointment: Appointment) -> String? {
        guard settings.isEnabled else { return nil }
        guard appointment.status.shouldKeepLinkedCalendarEvent else { return nil }

        let calendar = selectedCalendar() ?? eventStore.defaultCalendarForNewEvents

        // If no calendar available (e.g., no permissions), abort
        guard hasWriteAccessOrBetter else { return nil }

        let event: EKEvent
        if let eventId = appointment.calendarEventId, let existing = eventStore.event(withIdentifier: eventId) {
            event = existing
        } else {
            event = EKEvent(eventStore: eventStore)
            event.calendar = calendar
        }

        event.title = appointment.title
        event.location = appointment.location
        event.notes = appointment.notes
        event.startDate = appointment.startDate
        event.endDate = appointment.endDate

        // Clear any existing alarms and apply selected alerts
        event.alarms = nil
        let offsets = settings.alertOffsets
        if !offsets.isEmpty {
            event.alarms = offsets.map { EKAlarm(relativeOffset: -$0.timeInterval) }
        }

        do {
            try eventStore.save(event, span: .thisEvent, commit: true)
            return event.eventIdentifier
        } catch {
            print("❌ CalendarService: Failed to save event: \(error)")
            return nil
        }
    }

    func deleteEvent(withIdentifier id: String) {
        guard hasWriteAccessOrBetter else { return }
        guard let event = eventStore.event(withIdentifier: id) else { return }
        do {
            try eventStore.remove(event, span: .thisEvent, commit: true)
        } catch {
            print("❌ CalendarService: Failed to delete event: \(error)")
        }
    }

    // MARK: - Settings Persistence
    private func loadSettings() {
        do {
            guard let decoded = try CalendarSettingsLocalStore.loadSettings(from: .standard, key: settingsKey) else { return }
            settings = decoded
            lastErrorMessage = nil
        } catch {
            let message = "Calendar settings could not be loaded: \(error.localizedDescription)"
            lastErrorMessage = message
            print("⚠️ \(message)")
        }
    }

    @discardableResult
    func updateSettings(_ updatedSettings: CalendarIntegrationSettings) -> Bool {
        do {
            try CalendarSettingsLocalStore.save(updatedSettings, to: .standard, key: settingsKey)
            settings = updatedSettings
            lastErrorMessage = nil
            return true
        } catch {
            let message = "Calendar settings could not be saved: \(error.localizedDescription)"
            lastErrorMessage = message
            print("⚠️ \(message)")
            return false
        }
    }
}

// MARK: - Settings Model
struct CalendarIntegrationSettings: Codable {
    var isEnabled: Bool = true
    var selectedCalendarIdentifier: String? = nil
    var alertOffsets: [AppointmentReminderTime] = [.fifteenMinutesBefore, .oneHourBefore]
}
