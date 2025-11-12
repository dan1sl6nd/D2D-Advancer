import SwiftUI
import UserNotifications
import CoreData

class NotificationService: NSObject, ObservableObject {
    static let shared = NotificationService()

    @Published var notificationSettings = NotificationSettings()

    private let userDefaults = UserDefaults.standard
    private let settingsKey = "notification_settings"

    override init() {
        super.init()
        loadSettings()
        setupNotificationDelegate()
    }

    private func setupNotificationDelegate() {
        UNUserNotificationCenter.current().delegate = self
    }

    private func loadSettings() {
        if let data = userDefaults.data(forKey: settingsKey),
           let decoded = try? JSONDecoder().decode(NotificationSettings.self, from: data) {
            notificationSettings = decoded
        }
    }

    private func saveSettings() {
        if let encoded = try? JSONEncoder().encode(notificationSettings) {
            userDefaults.set(encoded, forKey: settingsKey)
        }
    }

    func updateSettings(_ settings: NotificationSettings) {
        notificationSettings = settings
        saveSettings()
    }

    // MARK: - Follow-up Notifications

    func scheduleFollowUpNotification(for lead: Lead) {
        guard let followUpDate = lead.followUpDate,
              notificationSettings.followUpReminders.isEnabled else { return }

        let identifier = "followup_\(lead.id?.uuidString ?? UUID().uuidString)"

        // Cancel existing notification first
        cancelNotification(withIdentifier: identifier)

        // Calculate notification time based on settings
        let notificationDate = calculateNotificationDate(
            targetDate: followUpDate,
            reminderTime: notificationSettings.followUpReminders.reminderTime
        )

        guard notificationDate > Date() else { return }

        let content = UNMutableNotificationContent()
        content.title = "Follow-up Reminder"
        content.body = "Time to follow up with \(lead.displayName)"
        content.sound = notificationSettings.playSound ? .default : nil
        content.categoryIdentifier = "LEAD_FOLLOWUP"

        // Add lead information to user info
        content.userInfo = [
            "type": "followup",
            "leadId": lead.id?.uuidString ?? "",
            "leadName": lead.displayName,
            "leadAddress": lead.address ?? ""
        ]

        // Create trigger
        let trigger = UNCalendarNotificationTrigger(
            dateMatching: Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: notificationDate),
            repeats: false
        )

        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: trigger
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Failed to schedule follow-up notification: \(error)")
            } else {
                print("Scheduled follow-up notification for \(lead.displayName) at \(notificationDate)")
            }
        }
    }

    // MARK: - Appointment Notifications

    func scheduleAppointmentNotifications(for appointment: Appointment) {
        guard notificationSettings.appointmentReminders.isEnabled else { return }

        let baseIdentifier = "appointment_\(appointment.id.uuidString)"

        // Cancel existing notifications for this appointment
        cancelNotificationsForAppointment(appointment.id)

        // Schedule multiple reminders based on settings
        for reminderOffset in notificationSettings.appointmentReminders.reminderTimes {
            let identifier = "\(baseIdentifier)_\(reminderOffset.rawValue)"

            let notificationDate = appointment.startDate.addingTimeInterval(-reminderOffset.timeInterval)

            guard notificationDate > Date() else { continue }

            let content = UNMutableNotificationContent()
            content.title = "Appointment Reminder"
            content.body = "\(appointment.title) in \(reminderOffset.displayName)"
            content.sound = notificationSettings.playSound ? .default : nil
            content.categoryIdentifier = "APPOINTMENT_REMINDER"

            // Add appointment information to user info
            content.userInfo = [
                "type": "appointment",
                "appointmentId": appointment.id.uuidString,
                "appointmentTitle": appointment.title,
                "appointmentDate": appointment.startDate.timeIntervalSince1970,
                "leadId": appointment.leadId?.uuidString ?? ""
            ]

            let trigger = UNCalendarNotificationTrigger(
                dateMatching: Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: notificationDate),
                repeats: false
            )

            let request = UNNotificationRequest(
                identifier: identifier,
                content: content,
                trigger: trigger
            )

            UNUserNotificationCenter.current().add(request) { error in
                if let error = error {
                    print("Failed to schedule appointment notification: \(error)")
                } else {
                    print("Scheduled appointment notification for \(appointment.title) - \(reminderOffset.displayName) before")
                }
            }
        }
    }

    // MARK: - Daily Summary Notifications

    func scheduleDailySummaryNotification() {
        guard notificationSettings.dailySummary.isEnabled else { return }

        let identifier = "daily_summary"

        // Cancel existing daily summary
        cancelNotification(withIdentifier: identifier)

        let content = UNMutableNotificationContent()
        content.title = "Daily Summary"
        content.body = "Check your schedule and follow-ups for today"
        content.sound = notificationSettings.playSound ? .default : nil
        content.categoryIdentifier = "DAILY_SUMMARY"

        content.userInfo = [
            "type": "daily_summary"
        ]

        // Schedule for the time specified in settings
        let components = Calendar.current.dateComponents([.hour, .minute], from: notificationSettings.dailySummary.time)

        let trigger = UNCalendarNotificationTrigger(
            dateMatching: components,
            repeats: true
        )

        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: trigger
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Failed to schedule daily summary notification: \(error)")
            } else {
                print("Scheduled daily summary notification")
            }
        }
    }

    // MARK: - Utility Methods

    private func calculateNotificationDate(targetDate: Date, reminderTime: FollowUpReminderTime) -> Date {
        return targetDate.addingTimeInterval(-reminderTime.timeInterval)
    }

    func cancelNotification(withIdentifier identifier: String) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier])
    }

    func cancelNotificationsForAppointment(_ appointmentId: UUID) {
        let baseIdentifier = "appointment_\(appointmentId.uuidString)"

        // Get all possible appointment reminder identifiers
        let identifiers = AppointmentReminderTime.allCases.map { reminderTime in
            "\(baseIdentifier)_\(reminderTime.rawValue)"
        }

        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    func cancelFollowUpNotification(for leadId: UUID) {
        let identifier = "followup_\(leadId.uuidString)"
        cancelNotification(withIdentifier: identifier)
    }

    func cancelDailySummaryNotification() {
        cancelNotification(withIdentifier: "daily_summary")
    }

    // MARK: - Batch Operations

    func refreshAllNotifications() {
        // Clear all pending notifications
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()

        // Reschedule daily summary
        if notificationSettings.dailySummary.isEnabled {
            scheduleDailySummaryNotification()
        }

        // Reschedule all appointment notifications
        let appointmentManager = AppointmentManager.shared
        for appointment in appointmentManager.appointments {
            if appointment.status == .scheduled || appointment.status == .confirmed {
                scheduleAppointmentNotifications(for: appointment)
            }
        }

        // Reschedule all follow-up notifications
        let context = PersistenceController.shared.container.viewContext
        let fetchRequest: NSFetchRequest<Lead> = Lead.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "followUpDate != nil")

        do {
            let leads = try context.fetch(fetchRequest)
            for lead in leads {
                scheduleFollowUpNotification(for: lead)
            }
        } catch {
            print("Failed to fetch leads for notification refresh: \(error)")
        }
    }

    // MARK: - Permission Management

    func requestNotificationPermission(completion: @escaping (Bool) -> Void) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
            DispatchQueue.main.async {
                completion(granted)
                if let error = error {
                    print("Notification permission error: \(error)")
                }
            }
        }
    }

    func checkNotificationPermission(completion: @escaping (UNAuthorizationStatus) -> Void) {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                completion(settings.authorizationStatus)
            }
        }
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension NotificationService: UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        // Show notification even when app is in foreground
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        let userInfo = response.notification.request.content.userInfo

        switch response.actionIdentifier {
        case "CALL_LEAD":
            handleCallAction(userInfo: userInfo)
        case "MESSAGE_LEAD":
            handleMessageAction(userInfo: userInfo)
        case "MARK_VISITED":
            handleMarkVisitedAction(userInfo: userInfo)
        case "SNOOZE_FOLLOWUP":
            handleSnoozeAction(userInfo: userInfo)
        case "VIEW_APPOINTMENT":
            handleViewAppointmentAction(userInfo: userInfo)
        case "MARK_COMPLETE":
            handleMarkCompleteAction(userInfo: userInfo)
        case UNNotificationDefaultActionIdentifier:
            handleDefaultAction(userInfo: userInfo)
        default:
            break
        }

        completionHandler()
    }

    private func handleCallAction(userInfo: [AnyHashable: Any]) {
        guard let leadId = userInfo["leadId"] as? String,
              let uuid = UUID(uuidString: leadId) else { return }

        // Get lead and make phone call
        let context = PersistenceController.shared.container.viewContext
        let fetchRequest: NSFetchRequest<Lead> = Lead.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "id == %@", uuid as CVarArg)

        do {
            let leads = try context.fetch(fetchRequest)
            if let lead = leads.first, let phone = lead.phone, !phone.isEmpty {
                if let url = URL(string: "tel:\(phone)") {
                    UIApplication.shared.open(url)
                }
            }
        } catch {
            print("Failed to fetch lead for call action: \(error)")
        }
    }

    private func handleMessageAction(userInfo: [AnyHashable: Any]) {
        guard let leadId = userInfo["leadId"] as? String,
              let uuid = UUID(uuidString: leadId) else {
            print("❌ Invalid leadId in message action")
            return
        }
        DispatchQueue.main.async {
            AppRouter.shared.openMessage(forLead: uuid)
        }
    }

    private func handleMarkVisitedAction(userInfo: [AnyHashable: Any]) {
        guard let leadId = userInfo["leadId"] as? String,
              let uuid = UUID(uuidString: leadId) else { return }

        // Mark lead as visited and clear follow-up
        let context = PersistenceController.shared.container.viewContext
        let fetchRequest: NSFetchRequest<Lead> = Lead.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "id == %@", uuid as CVarArg)

        do {
            let leads = try context.fetch(fetchRequest)
            if let lead = leads.first {
                lead.visitCount += 1
                lead.lastContactDate = Date()
                lead.followUpDate = nil

                try context.save()

                // Cancel the follow-up notification
                cancelFollowUpNotification(for: uuid)
            }
        } catch {
            print("Failed to mark lead as visited: \(error)")
        }
    }

    private func handleSnoozeAction(userInfo: [AnyHashable: Any]) {
        guard let leadId = userInfo["leadId"] as? String,
              let uuid = UUID(uuidString: leadId) else { return }

        // Snooze follow-up by 1 hour
        let context = PersistenceController.shared.container.viewContext
        let fetchRequest: NSFetchRequest<Lead> = Lead.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "id == %@", uuid as CVarArg)

        do {
            let leads = try context.fetch(fetchRequest)
            if let lead = leads.first {
                lead.followUpDate = Date().addingTimeInterval(3600) // 1 hour
                try context.save()

                // Reschedule notification
                scheduleFollowUpNotification(for: lead)
            }
        } catch {
            print("Failed to snooze follow-up: \(error)")
        }
    }

    private func handleViewAppointmentAction(userInfo: [AnyHashable: Any]) {
        let appointmentIdStr = userInfo["appointmentId"] as? String
        let uuid = appointmentIdStr.flatMap(UUID.init(uuidString:))
        DispatchQueue.main.async {
            AppRouter.shared.openAppointments(uuid)
        }
    }

    private func handleMarkCompleteAction(userInfo: [AnyHashable: Any]) {
        guard let appointmentId = userInfo["appointmentId"] as? String,
              let uuid = UUID(uuidString: appointmentId) else { return }

        // Mark appointment as completed
        let appointmentManager = AppointmentManager.shared
        if let appointment = appointmentManager.appointments.first(where: { $0.id == uuid }) {
            var updatedAppointment = appointment
            updatedAppointment.status = .completed

            Task {
                await appointmentManager.updateAppointment(updatedAppointment)
            }

            // Cancel any remaining notifications for this appointment
            cancelNotificationsForAppointment(uuid)
        }
    }

    private func handleDefaultAction(userInfo: [AnyHashable: Any]) {
        // Default action when notification is tapped
        // This could open the relevant view in the app
        print("Default notification action triggered for userInfo: \(userInfo)")
    }
}

// MARK: - Notification Settings Models

struct NotificationSettings: Codable {
    var followUpReminders = FollowUpReminderSettings()
    var appointmentReminders = AppointmentReminderSettings()
    var dailySummary = DailySummarySettings()
    var playSound = true
}

struct FollowUpReminderSettings: Codable {
    var isEnabled = true
    var reminderTime = FollowUpReminderTime.fifteenMinutesBefore
}

struct AppointmentReminderSettings: Codable {
    var isEnabled = true
    var reminderTimes: [AppointmentReminderTime] = [.fifteenMinutesBefore, .oneHourBefore]
}

struct DailySummarySettings: Codable {
    var isEnabled = true
    var time: Date

    init() {
        // Create a date representing 8:00 AM today
        let calendar = Calendar.current
        let now = Date()
        let components = calendar.dateComponents([.year, .month, .day], from: now)
        var targetComponents = components
        targetComponents.hour = 8
        targetComponents.minute = 0
        targetComponents.second = 0

        self.time = calendar.date(from: targetComponents) ?? Date()
    }
}

enum FollowUpReminderTime: String, CaseIterable, Codable {
    case atTime = "at_time"
    case fifteenMinutesBefore = "15_minutes_before"
    case thirtyMinutesBefore = "30_minutes_before"
    case oneHourBefore = "1_hour_before"

    var displayName: String {
        switch self {
        case .atTime: return "At scheduled time"
        case .fifteenMinutesBefore: return "15 minutes before"
        case .thirtyMinutesBefore: return "30 minutes before"
        case .oneHourBefore: return "1 hour before"
        }
    }

    var timeInterval: TimeInterval {
        switch self {
        case .atTime: return 0
        case .fifteenMinutesBefore: return 15 * 60
        case .thirtyMinutesBefore: return 30 * 60
        case .oneHourBefore: return 60 * 60
        }
    }
}

enum AppointmentReminderTime: String, CaseIterable, Codable {
    case fiveMinutesBefore = "5_minutes_before"
    case fifteenMinutesBefore = "15_minutes_before"
    case thirtyMinutesBefore = "30_minutes_before"
    case oneHourBefore = "1_hour_before"
    case oneDayBefore = "1_day_before"

    var displayName: String {
        switch self {
        case .fiveMinutesBefore: return "5 minutes"
        case .fifteenMinutesBefore: return "15 minutes"
        case .thirtyMinutesBefore: return "30 minutes"
        case .oneHourBefore: return "1 hour"
        case .oneDayBefore: return "1 day"
        }
    }

    var timeInterval: TimeInterval {
        switch self {
        case .fiveMinutesBefore: return 5 * 60
        case .fifteenMinutesBefore: return 15 * 60
        case .thirtyMinutesBefore: return 30 * 60
        case .oneHourBefore: return 60 * 60
        case .oneDayBefore: return 24 * 60 * 60
        }
    }
}
