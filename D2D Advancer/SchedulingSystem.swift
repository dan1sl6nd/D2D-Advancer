import SwiftUI
import CoreData
import Firebase
import FirebaseFirestore

// MARK: - Appointment Models

struct Appointment: Identifiable, Equatable, Sendable {
    var id = UUID()
    var title: String
    var notes: String
    var startDate: Date
    var endDate: Date
    var location: String
    var leadId: UUID?
    var calendarEventId: String?
    var appointmentType: AppointmentType
    var customAppointmentTypeId: String? // For storing custom appointment types
    var status: AppointmentStatus

    func applyingCalendarEventStatusPolicy() -> (appointment: Appointment, calendarEventIdToDelete: String?) {
        guard !status.shouldKeepLinkedCalendarEvent else {
            return (self, nil)
        }

        var updated = self
        let calendarEventIdToDelete = updated.calendarEventId
        updated.calendarEventId = nil
        return (updated, calendarEventIdToDelete)
    }
    
    enum AppointmentType: String, CaseIterable, Codable, Sendable {
        case consultation = "Consultation"
        case installation = "Installation"
        case inspection = "Inspection"
        case maintenance = "Maintenance"
        case repair = "Repair"
        case followUp = "Follow-up"
        
        var icon: String {
            switch self {
            case .consultation: return "person.2.circle"
            case .installation: return "wrench.and.screwdriver"
            case .inspection: return "magnifyingglass.circle"
            case .maintenance: return "gear"
            case .repair: return "hammer"
            case .followUp: return "clock.arrow.circlepath"
            }
        }
        
        var color: Color {
            switch self {
            case .consultation: return Color.statusInterested
            case .installation: return Color.electricViolet
            case .inspection: return Color.statusNotHome
            case .maintenance: return Color.electricViolet
            case .repair: return Color.statusNotInterested
            case .followUp: return Color.textSecondary
            }
        }
    }
    
    enum AppointmentStatus: String, CaseIterable, Codable, Sendable {
        case scheduled = "Scheduled"
        case confirmed = "Confirmed"
        case completed = "Completed"
        case cancelled = "Cancelled"
        case rescheduled = "Rescheduled"

        var shouldKeepLinkedCalendarEvent: Bool {
            self != .cancelled && self != .rescheduled
        }
        
        var color: Color {
            switch self {
            case .scheduled: return Color.electricViolet
            case .confirmed: return Color.statusInterested
            case .completed: return Color.statusInterested
            case .cancelled: return Color.statusNotInterested
            case .rescheduled: return Color.statusNotHome
            }
        }
    }
    
    // Helper methods for display
    func displayName(using customTypes: [CustomAppointmentType]) -> String {
        if let customTypeId = customAppointmentTypeId,
           let customType = customTypes.first(where: { $0.id == customTypeId }) {
            return customType.name
        }
        return appointmentType.rawValue
    }
    
    func displayIcon(using customTypes: [CustomAppointmentType]) -> String {
        if let customTypeId = customAppointmentTypeId,
           let customType = customTypes.first(where: { $0.id == customTypeId }) {
            return customType.icon
        }
        return appointmentType.icon
    }
    
    func displayColor(using customTypes: [CustomAppointmentType]) -> Color {
        if let customTypeId = customAppointmentTypeId,
           let customType = customTypes.first(where: { $0.id == customTypeId }) {
            return customType.swiftUIColor
        }
        return appointmentType.color
    }
    
    // Backwards compatibility - these will use the shared manager but won't be reactive
    var displayName: String {
        displayName(using: CustomAppointmentTypeManager.shared.customTypes)
    }
    
    var displayIcon: String {
        displayIcon(using: CustomAppointmentTypeManager.shared.customTypes)
    }
    
    var displayColor: Color {
        displayColor(using: CustomAppointmentTypeManager.shared.customTypes)
    }
}


// MARK: - Appointment Manager

enum AppointmentLocalStore {
    static func loadAppointments(from userDefaults: UserDefaults, key: String) throws -> [Appointment]? {
        guard let data = userDefaults.data(forKey: key) else { return nil }
        return try JSONDecoder().decode([Appointment].self, from: data)
    }
}

enum AppointmentDeletionTombstoneStore {
    static func loadDeletedIds(from userDefaults: UserDefaults, key: String) -> Set<UUID> {
        let values = userDefaults.stringArray(forKey: key) ?? []
        return Set(values.compactMap(UUID.init(uuidString:)))
    }

    static func markDeleted(_ ids: Set<UUID>, in userDefaults: UserDefaults, key: String) {
        guard !ids.isEmpty else { return }
        let existing = loadDeletedIds(from: userDefaults, key: key)
        save(existing.union(ids), to: userDefaults, key: key)
    }

    private static func save(_ ids: Set<UUID>, to userDefaults: UserDefaults, key: String) {
        let values = ids
            .map(\.uuidString)
            .sorted()
        userDefaults.set(values, forKey: key)
    }
}

enum AppointmentCloudMergePolicy {
    static func excludingDeletedAppointments(
        _ appointments: [Appointment],
        deletedIds: Set<UUID>
    ) -> [Appointment] {
        guard !deletedIds.isEmpty else { return appointments }
        return appointments.filter { !deletedIds.contains($0.id) }
    }

    static func mergedForMigration(
        local: [Appointment],
        incoming: [Appointment],
        deletedIds: Set<UUID>,
        preferIncoming: Bool
    ) -> [Appointment] {
        var merged = excludingDeletedAppointments(local, deletedIds: deletedIds)
        let incoming = excludingDeletedAppointments(incoming, deletedIds: deletedIds)

        for appointment in incoming {
            if let index = merged.firstIndex(where: { $0.id == appointment.id }) {
                if preferIncoming {
                    merged[index] = appointment
                }
            } else {
                merged.append(appointment)
            }
        }

        return merged
    }
}

enum AppointmentCloudSyncPolicy {
    static let privateCloudKitUserId = "icloudPrivateUser"

    static func firestoreUserId(
        provider: CloudSyncProvider,
        isAuthenticated: Bool,
        currentUserId: String?
    ) -> String? {
        guard provider == .firebase, isAuthenticated else { return nil }
        return currentUserId
    }

    static func cloudKitBackupUserId(
        provider: CloudSyncProvider,
        firebaseUserId: String?
    ) -> String? {
        switch provider {
        case .firebase:
            return firebaseUserId
        case .icloud:
            // CloudKit private databases are already scoped to the Apple ID.
            // Use a stable app namespace so appointments can restore without Firebase.
            return privateCloudKitUserId
        case .off:
            return nil
        }
    }
}

@MainActor
class AppointmentManager: ObservableObject {
    static let shared = AppointmentManager()
    
    @Published var appointments: [Appointment] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    private let userDefaults = UserDefaults.standard
    private let appointmentsKey = "saved_appointments"
    private let deletedAppointmentIdsKey = "deleted_appointment_ids"
    private let db: Firestore
    private var cloudKitBackupService: CloudKitAppointmentBackupService? {
        CloudKitAppointmentBackupService.shared
    }
    private var listener: ListenerRegistration?
    private var isCleared = false  // Flag to prevent reloading after clearing
    
    private init() {
        FirebaseBootstrap.configureIfNeeded()
        db = Firestore.firestore()
        loadAppointments()
        // Firebase listener will be set up only when manually requested
    }
    
    deinit {
        listener?.remove()
    }
    
    @MainActor
    func scheduleAppointment(for lead: Lead, appointment: Appointment) async -> Bool {
        print("🗓️ AppointmentManager: Starting scheduleAppointment for lead: \(lead.displayName)")
        isLoading = true
        errorMessage = nil
        
        // Add to local storage and create updated appointment
        var tempAppointment = appointment
        tempAppointment.leadId = lead.id
        let updatedAppointment = tempAppointment
        
        appointments.append(updatedAppointment)
        guard saveAppointments() else {
            appointments.removeAll { $0.id == updatedAppointment.id }
            isLoading = false
            return false
        }
        
        // Update lead status to interested if it's a consultation
        // Do NOT downgrade terminal states like Sold or Not Interested
        if appointment.appointmentType == .consultation {
            let updatedStatus: Lead.Status = lead.leadStatus.allowsActiveFollowUp ? .interested : lead.leadStatus
            lead.applyLeadStatus(
                updatedStatus,
                followUpDate: appointment.startDate,
                shouldReplaceFollowUpDate: true,
                autoSave: false
            )
            
            // Save Core Data changes
            do {
                try lead.managedObjectContext?.save()
                // Individual sync removed - will sync manually, hourly, or before sign-out
                print("📝 Lead updated from appointment - will sync on next manual/hourly/sign-out sync")
            } catch {
                print("Failed to update lead: \(error)")
            }
        }
        
        // Sync appointment to the selected cloud provider with leadId included.
        await syncAppointmentToFirebase(updatedAppointment)

        // Create an Apple Calendar event if enabled and this appointment still belongs on the calendar.
        if updatedAppointment.status.shouldKeepLinkedCalendarEvent && CalendarService.shared.settings.isEnabled {
            CalendarService.shared.requestAccessIfNeeded { granted in
                guard granted else { return }
                let eventId = CalendarService.shared.createOrUpdateEvent(for: updatedAppointment)
                if let eventId = eventId {
                    Task { @MainActor in
                        if let idx = self.appointments.firstIndex(where: { $0.id == updatedAppointment.id }) {
                            self.appointments[idx].calendarEventId = eventId
                            _ = self.saveAppointments()
                            await self.syncAppointmentToFirebase(self.appointments[idx])
                        }
                    }
                }
            }
        }

        // Schedule notifications for the appointment
        NotificationService.shared.scheduleAppointmentNotifications(for: updatedAppointment)
        NotificationService.shared.requestPermissionAfterSchedulingIfNeeded()

        isLoading = false
        return true
    }
    
    func updateAppointment(_ appointment: Appointment) async -> Bool {
        await MainActor.run {
            isLoading = true
            errorMessage = nil
        }
        
        let calendarPolicy = appointment.applyingCalendarEventStatusPolicy()
        let appointmentToStore = calendarPolicy.appointment
        let calendarEventIdToDelete = calendarPolicy.calendarEventIdToDelete

        // Update local storage
        guard let index = appointments.firstIndex(where: { $0.id == appointment.id }) else {
            errorMessage = "Could not save appointment because it no longer exists."
            isLoading = false
            return false
        }

        let previousAppointment = appointments[index]
        appointments[index] = appointmentToStore
        guard saveAppointments() else {
            appointments[index] = previousAppointment
            isLoading = false
            return false
        }
        
        // Sync appointment to the selected cloud provider.
        await syncAppointmentToFirebase(appointmentToStore)

        if let calendarEventIdToDelete {
            CalendarService.shared.deleteEvent(withIdentifier: calendarEventIdToDelete)
        }

        // Update Apple Calendar event if enabled
        if appointmentToStore.status.shouldKeepLinkedCalendarEvent && CalendarService.shared.settings.isEnabled {
            CalendarService.shared.requestAccessIfNeeded { granted in
                guard granted else { return }
                let eventId = CalendarService.shared.createOrUpdateEvent(for: appointmentToStore)
                if let eventId = eventId {
                    Task { @MainActor in
                        if let idx = self.appointments.firstIndex(where: { $0.id == appointmentToStore.id }) {
                            self.appointments[idx].calendarEventId = eventId
                            _ = self.saveAppointments()
                            await self.syncAppointmentToFirebase(self.appointments[idx])
                        }
                    }
                }
            }
        }

        // Update notifications for the appointment
        NotificationService.shared.scheduleAppointmentNotifications(for: appointmentToStore)
        if appointmentToStore.status.shouldKeepLinkedCalendarEvent {
            NotificationService.shared.requestPermissionAfterSchedulingIfNeeded()
        }

        await MainActor.run {
            isLoading = false
        }
        return true
    }
    
    func cancelAppointment(_ appointment: Appointment) async -> Bool {
        await MainActor.run {
            isLoading = true
            errorMessage = nil
        }
        
        // Update local storage
        var tempAppointment = appointment
        tempAppointment.status = .cancelled
        let calendarPolicy = tempAppointment.applyingCalendarEventStatusPolicy()
        let updatedAppointment = calendarPolicy.appointment
        let calendarEventIdToDelete = calendarPolicy.calendarEventIdToDelete
        
        guard let index = appointments.firstIndex(where: { $0.id == appointment.id }) else {
            errorMessage = "Could not cancel appointment because it no longer exists."
            isLoading = false
            return false
        }

        let previousAppointment = appointments[index]
        appointments[index] = updatedAppointment
        guard saveAppointments() else {
            appointments[index] = previousAppointment
            isLoading = false
            return false
        }
        
        // Sync appointment to the selected cloud provider.
        await syncAppointmentToFirebase(updatedAppointment)

        // Remove Apple Calendar event if it exists
        if let eventId = calendarEventIdToDelete {
            CalendarService.shared.deleteEvent(withIdentifier: eventId)
        }

        // Cancel notifications for cancelled appointment
        NotificationService.shared.cancelNotificationsForAppointment(appointment.id)

        await MainActor.run {
            isLoading = false
        }
        return true
    }
    
    func getAppointments(for lead: Lead) -> [Appointment] {
        return appointments.filter { $0.leadId == lead.id }
    }
    
    func getUpcomingAppointments() -> [Appointment] {
        let now = Date()
        return appointments
            .filter { $0.startDate > now && $0.status != .cancelled && $0.status != .completed }
            .sorted { $0.startDate < $1.startDate }
    }
    
    func getTodaysAppointments() -> [Appointment] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) ?? Date()
        
        return appointments
            .filter { $0.startDate >= today && $0.startDate < tomorrow }
            .sorted { $0.startDate < $1.startDate }
    }
    
    func deleteAppointment(_ appointment: Appointment) async -> Bool {
        await MainActor.run {
            isLoading = true
            errorMessage = nil
        }
        
        // Remove from local storage
        let previousAppointments = appointments
        appointments.removeAll { $0.id == appointment.id }
        guard saveAppointments() else {
            appointments = previousAppointments
            isLoading = false
            return false
        }
        markAppointmentDeleted(appointment.id)
        
        // Delete from the selected cloud provider.
        await deleteAppointmentFromFirebase(appointment.id)

        // Delete Apple Calendar event if present
        if let eventId = appointment.calendarEventId {
            CalendarService.shared.deleteEvent(withIdentifier: eventId)
        }

        // Cancel all notifications for deleted appointment
        NotificationService.shared.cancelNotificationsForAppointment(appointment.id)

        await MainActor.run {
            isLoading = false
        }
        return true
    }
    
    @discardableResult
    private func saveAppointments() -> Bool {
        do {
            let encoded = try JSONEncoder().encode(appointments)
            userDefaults.set(encoded, forKey: appointmentsKey)
            return true
        } catch {
            let message = "Failed to save appointments: \(error.localizedDescription)"
            errorMessage = message
            print("❌ \(message)")
            return false
        }
    }
    
    private func loadAppointments() {
        guard !isCleared else {
            print("🗓️ Skipping appointment loading - appointments were cleared")
            return
        }

        do {
            guard let decoded = try AppointmentLocalStore.loadAppointments(from: userDefaults, key: appointmentsKey) else {
                print("🗓️ No appointments found in UserDefaults")
                return
            }

            appointments = decoded
            errorMessage = nil
            print("🗓️ Loaded \(appointments.count) appointments from UserDefaults")
        } catch {
            let message = "Saved appointments could not be loaded: \(error.localizedDescription)"
            errorMessage = message
            print("❌ \(message)")
        }
    }
    
    // MARK: - Appointment Cloud Sync Methods
    
    private func setupFirestoreListener() {
        guard let userId = FirebaseService.shared.currentUser?.uid else {
            print("🗓️ No current user, skipping Firestore listener setup")
            return
        }
        
        print("🗓️ Setting up Firestore listener for user: \(userId)")
        
        listener = db.collection("users").document(userId).collection("appointments")
            .addSnapshotListener { [weak self] querySnapshot, error in
                if let error = error {
                    print("🗓️ Error listening to appointments: \(error)")
                    return
                }
                
                guard let querySnapshot = querySnapshot else {
                    print("🗓️ QuerySnapshot is nil")
                    return
                }
                
                print("🗓️ Firebase listener triggered - found \(querySnapshot.documents.count) documents")
                
                if querySnapshot.documents.isEmpty {
                    print("🗓️ No appointment documents found in Firebase")
                    Task {
                        await self?.restoreAppointmentsFromCloudKitIfNeeded(userId: userId, backfillFirebase: true)
                    }
                    return
                }
                
                let firestoreAppointments = querySnapshot.documents.compactMap { document -> Appointment? in
                    print("🗓️ Processing appointment document: \(document.documentID)")
                    do {
                        let appointment = try document.data(as: Appointment.self)
                        print("🗓️ Successfully decoded appointment: \(appointment.title)")
                        return appointment
                    } catch {
                        print("🗓️ Failed to decode appointment \(document.documentID): \(error)")
                        return nil
                    }
                }
                
                print("🗓️ Decoded \(firestoreAppointments.count) appointments from Firebase")
                
                DispatchQueue.main.async {
                    // Merge Firestore data with local data
                    self?.mergeFirestoreAppointments(firestoreAppointments)
                }
            }
        
        print("🗓️ Firestore listener set up successfully")
    }
    
    private func mergeFirestoreAppointments(_ firestoreAppointments: [Appointment]) {
        let deletedIds = deletedAppointmentIds()
        let firestoreAppointments = AppointmentCloudMergePolicy.excludingDeletedAppointments(
            firestoreAppointments,
            deletedIds: deletedIds
        )
        print("🗓️ Merging \(firestoreAppointments.count) appointments from Firestore")
        
        // If we have no local appointments and Firestore has appointments, this is a normal download
        if appointments.isEmpty && !firestoreAppointments.isEmpty {
            appointments = firestoreAppointments
            _ = saveAppointments()
            print("🗓️ Downloaded \(firestoreAppointments.count) appointments from Firestore")
            return
        }
        
        // If Firestore is empty, don't touch local data - this could be a timing issue
        if firestoreAppointments.isEmpty {
            print("🗓️ Skipping merge - Firestore returned empty (possible timing issue)")
            return
        }
        
        // Keep track of which appointments were found in Firestore
        var foundAppointmentIds = Set<UUID>()
        
        for firestoreAppointment in firestoreAppointments {
            foundAppointmentIds.insert(firestoreAppointment.id)
            
            if let localIndex = appointments.firstIndex(where: { $0.id == firestoreAppointment.id }) {
                // Update existing appointment
                appointments[localIndex] = firestoreAppointment
            } else {
                // Add new appointment from Firestore
                appointments.append(firestoreAppointment)
            }
        }
        
        _ = saveAppointments()
        print("🗓️ Merge completed - now have \(appointments.count) appointments locally")
        
        // Force UI refresh by explicitly notifying observers
        DispatchQueue.main.async {
            self.objectWillChange.send()
        }
    }
    
    func syncAppointmentToFirebase(_ appointment: Appointment) async {
        let provider = CloudSyncProvider.current
        let firebaseUserId = AppointmentCloudSyncPolicy.firestoreUserId(
            provider: CloudSyncProvider.current,
            isAuthenticated: FirebaseService.shared.isAuthenticated,
            currentUserId: FirebaseService.shared.currentUser?.uid
        )
        let cloudKitUserId = AppointmentCloudSyncPolicy.cloudKitBackupUserId(
            provider: provider,
            firebaseUserId: firebaseUserId
        )

        if let firebaseUserId {
            do {
                let appointmentData = try Firestore.Encoder().encode(appointment)
                try await db.collection("users").document(firebaseUserId).collection("appointments").document(appointment.id.uuidString).setData(appointmentData)
                print("🗓️ Appointment synced to Firebase: \(appointment.title)")
            } catch {
                print("🗓️ Failed to sync appointment to Firebase: \(error)")
                await MainActor.run {
                    errorMessage = "Failed to sync appointment: \(error.localizedDescription)"
                }
            }
        } else {
            print("🗓️ Firebase appointment sync skipped: \(provider.displayName) sync mode active")
        }

        if let cloudKitUserId {
            await backupAppointmentToCloudKit(appointment, userId: cloudKitUserId)
        }
    }
    
    func deleteAppointmentFromFirebase(_ appointmentId: UUID) async {
        let provider = CloudSyncProvider.current
        let firebaseUserId = AppointmentCloudSyncPolicy.firestoreUserId(
            provider: CloudSyncProvider.current,
            isAuthenticated: FirebaseService.shared.isAuthenticated,
            currentUserId: FirebaseService.shared.currentUser?.uid
        )
        let cloudKitUserId = AppointmentCloudSyncPolicy.cloudKitBackupUserId(
            provider: provider,
            firebaseUserId: firebaseUserId
        )

        if let firebaseUserId {
            do {
                try await db.collection("users").document(firebaseUserId).collection("appointments").document(appointmentId.uuidString).delete()
                print("🗓️ Appointment deleted from Firebase: \(appointmentId)")
            } catch {
                print("🗓️ Failed to delete appointment from Firebase: \(error)")
                await MainActor.run {
                    errorMessage = "Failed to delete appointment: \(error.localizedDescription)"
                }
            }
        } else {
            print("🗓️ Firebase appointment delete skipped: \(provider.displayName) sync mode active")
        }

        if let cloudKitUserId {
            do {
                guard let cloudKitBackupService else {
                    throw CloudKitLeadBackupError.containerUnavailable(CloudKitLeadBackupService.containerIdentifier)
                }

                try await cloudKitBackupService.deleteAppointment(appointmentId, for: cloudKitUserId)
                print("☁️ Appointment deleted from CloudKit backup: \(appointmentId)")
            } catch {
                print("⚠️ Failed to delete appointment from CloudKit backup: \(error.localizedDescription)")
            }
        }
    }
    
    func deleteAllAppointmentsFromFirebase() async {
        let provider = CloudSyncProvider.current
        let firebaseUserId = AppointmentCloudSyncPolicy.firestoreUserId(
            provider: CloudSyncProvider.current,
            isAuthenticated: FirebaseService.shared.isAuthenticated,
            currentUserId: FirebaseService.shared.currentUser?.uid
        )
        let cloudKitUserId = AppointmentCloudSyncPolicy.cloudKitBackupUserId(
            provider: provider,
            firebaseUserId: firebaseUserId
        )

        if let firebaseUserId {
            print("🗓️ Deleting all appointments from Firebase...")

            do {
                // Get all appointment documents
                let querySnapshot = try await db.collection("users").document(firebaseUserId).collection("appointments").getDocuments()

                // Delete each document
                for document in querySnapshot.documents {
                    try await document.reference.delete()
                    print("🗓️ Deleted appointment from Firebase: \(document.documentID)")
                }

                print("✅ All appointments deleted from Firebase (\(querySnapshot.documents.count) deleted)")
            } catch {
                print("❌ Failed to delete all appointments from Firebase: \(error)")
            }
        } else {
            print("🗓️ Firebase appointment delete all skipped: \(provider.displayName) sync mode active")
        }

        if let cloudKitUserId {
            do {
                guard let cloudKitBackupService else {
                    throw CloudKitLeadBackupError.containerUnavailable(CloudKitLeadBackupService.containerIdentifier)
                }

                try await cloudKitBackupService.deleteAllAppointments(for: cloudKitUserId)
                print("✅ All appointments deleted from CloudKit backup")
            } catch {
                print("⚠️ Failed to delete appointments from CloudKit backup: \(error.localizedDescription)")
            }
        }
    }
    
    func clearAllAppointments() {
        print("🗓️ Clearing all appointments...")
        
        // Clear local data first
        appointments.removeAll()
        
        // Clear from UserDefaults
        userDefaults.removeObject(forKey: appointmentsKey)
        
        // Stop listening to Firebase changes
        listener?.remove()
        listener = nil
        
        print("✅ All appointments cleared locally")
    }
    
    func removeDuplicateAppointments() {
        print("🗓️ Removing duplicate appointments...")
        
        let originalCount = appointments.count
        var uniqueAppointments: [Appointment] = []
        var seenIds = Set<UUID>()
        
        for appointment in appointments {
            if !seenIds.contains(appointment.id) {
                seenIds.insert(appointment.id)
                uniqueAppointments.append(appointment)
            } else {
                print("🗓️ Removing duplicate: \(appointment.title) (ID: \(appointment.id))")
            }
        }
        
        appointments = uniqueAppointments
        _ = saveAppointments()
        
        let removedCount = originalCount - uniqueAppointments.count
        print("✅ Removed \(removedCount) duplicate appointments. Now have \(uniqueAppointments.count) unique appointments.")
        
        // Debug: Print all appointments after cleanup
        printAppointmentDetails()
    }
    
    func printAppointmentDetails() {
        print("🗓️ === APPOINTMENT DEBUG INFO ===")
        print("🗓️ Total appointments loaded: \(appointments.count)")
        for (index, appointment) in appointments.enumerated() {
            print("🗓️ [\(index + 1)] \(appointment.title)")
            print("🗓️     Status: \(appointment.status.rawValue)")
            print("🗓️     Type: \(appointment.appointmentType.rawValue)")
            print("🗓️     Date: \(appointment.startDate)")
            print("🗓️     ID: \(appointment.id)")
            print("🗓️     Lead ID: \(appointment.leadId?.uuidString ?? "nil")")
        }
        print("🗓️ === END DEBUG INFO ===")
    }
    
    func fixCancelledAppointments() {
        let cancelledCount = appointments.filter { $0.status == .cancelled }.count
        guard cancelledCount > 0 else { return }
        print("🗓️ Preserving \(cancelledCount) cancelled appointment(s); cancelled appointments are visible in the Cancelled tab.")
    }
    
    func clearAppointmentsLocalOnly() {
        print("🗓️ Clearing appointments locally only (preserving Firebase data)...")
        print("🗓️ Current appointments count before clearing: \(appointments.count)")
        
        // Set flag to prevent reloading
        isCleared = true
        
        // Stop listening to Firebase changes FIRST
        listener?.remove()
        listener = nil
        print("🗓️ Firebase listener removed")
        
        // Clear local data (assuming we're already on main thread from sign-out)
        print("🗓️ About to clear appointments array (current count: \(appointments.count))")
        
        // Clear local data only
        appointments.removeAll()
        
        // Force UI update
        objectWillChange.send()
        
        print("🗓️ Appointments array cleared: \(appointments.count) remaining")
        
        // Clear from UserDefaults
        userDefaults.removeObject(forKey: appointmentsKey)
        print("🗓️ UserDefaults cleared for key: \(appointmentsKey)")
        
        // Verify UserDefaults was actually cleared
        if let _ = userDefaults.data(forKey: appointmentsKey) {
            print("⚠️ UserDefaults still contains data after clearing attempt!")
        } else {
            print("✅ UserDefaults successfully cleared")
        }
        
        print("✅ Appointments cleared locally (Firebase data preserved) - final count: \(appointments.count)")
    }
    
    func clearAllAppointmentsIncludingFirebase() async {
        print("🗓️ Clearing all appointments including Firebase...")
        
        // Clear local data first
        await MainActor.run {
            markAppointmentsDeleted(Set(appointments.map(\.id)))
            appointments.removeAll()
            
            // Clear from UserDefaults
            userDefaults.removeObject(forKey: appointmentsKey)
            
            // Stop listening to Firebase changes
            listener?.remove()
            listener = nil
        }
        
        // Delete all appointments from Firebase and wait for completion
        await deleteAllAppointmentsFromFirebase()
        
        print("✅ All appointments cleared from local and Firebase")
    }
    
    func stopFirebaseListener() {
        // Stop existing listener
        listener?.remove()
        listener = nil
        
        print("🗓️ Firebase listener stopped for appointments")
    }
    
    func restartFirebaseSync() {
        let provider = CloudSyncProvider.current
        guard UserDataSyncManager.shouldUseFirebasePersonalSync(
            provider: CloudSyncProvider.current,
            isAuthenticated: FirebaseService.shared.isAuthenticated
        ) else {
            stopFirebaseListener()
            if provider == .icloud {
                Task {
                    await restoreAppointmentsFromCloudKitBackupIfNeeded()
                }
            }
            print("🗓️ Firebase sync not restarted for appointments in \(provider.displayName) sync mode")
            return
        }

        // Only restart if we don't already have an active listener
        guard listener == nil else {
            print("🗓️ Firebase listener already active - skipping restart")
            return
        }
        
        // Reset cleared flag to allow appointments to be loaded again
        isCleared = false
        
        // Stop existing listener (just in case)
        stopFirebaseListener()
        
        // Restart the Firebase listener for the current user
        setupFirestoreListener()
        
        print("🗓️ Firebase sync restarted for appointments")
    }
    
    func syncAllAppointmentsToFirebase() async {
        let provider = CloudSyncProvider.current
        let firebaseUserId = AppointmentCloudSyncPolicy.firestoreUserId(
            provider: provider,
            isAuthenticated: FirebaseService.shared.isAuthenticated,
            currentUserId: FirebaseService.shared.currentUser?.uid
        )
        let cloudKitUserId = AppointmentCloudSyncPolicy.cloudKitBackupUserId(
            provider: provider,
            firebaseUserId: firebaseUserId
        )

        guard firebaseUserId != nil || cloudKitUserId != nil else {
            print("🗓️ Appointment cloud sync skipped: \(provider.displayName) sync mode active")
            return
        }
        
        print("🗓️ Syncing \(appointments.count) appointments to \(provider.displayName)")
        
        // Temporarily pause the Firebase listener to prevent conflicts during sync
        let wasListening = listener != nil
        if firebaseUserId != nil {
            listener?.remove()
            listener = nil
        }
        
        for appointment in appointments {
            await syncAppointmentToFirebase(appointment)
        }
        
        if firebaseUserId != nil {
            // Wait a moment for Firebase to propagate the changes
            try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
        }

        // Restart the listener if it was active before
        if firebaseUserId != nil && wasListening {
            setupFirestoreListener()
        }
        
        print("🗓️ Appointment cloud sync completed")
    }

    @discardableResult
    func mergeAppointmentsForMigration(
        _ incomingAppointments: [Appointment],
        preferIncoming: Bool
    ) -> Int {
        let previousIds = Set(appointments.map(\.id))
        let merged = AppointmentCloudMergePolicy.mergedForMigration(
            local: appointments,
            incoming: incomingAppointments,
            deletedIds: deletedAppointmentIds(),
            preferIncoming: preferIncoming
        )
        appointments = merged

        if !incomingAppointments.isEmpty {
            _ = saveAppointments()
            objectWillChange.send()
        }

        return merged.reduce(into: 0) { count, appointment in
            if !previousIds.contains(appointment.id) { count += 1 }
        }
    }

    func migrateAppointmentsToPrivateICloud() async throws -> Int {
        guard let cloudKitBackupService else {
            throw CloudKitLeadBackupError.containerUnavailable(CloudKitLeadBackupService.containerIdentifier)
        }

        let userId = UserDataSyncManager.privateCloudKitUserId
        let existingPayloads = try await cloudKitBackupService.fetchAppointments(for: userId)
        _ = mergeAppointmentsForMigration(
            existingPayloads.map(\.appointment),
            preferIncoming: false
        )

        for appointment in appointments {
            try await cloudKitBackupService.uploadAppointment(
                AppointmentSyncPayload(appointment: appointment),
                for: userId
            )
        }

        return appointments.count
    }

    private func backupAppointmentToCloudKit(_ appointment: Appointment, userId: String) async {
        do {
            guard let cloudKitBackupService else {
                throw CloudKitLeadBackupError.containerUnavailable(CloudKitLeadBackupService.containerIdentifier)
            }

            try await cloudKitBackupService.uploadAppointment(AppointmentSyncPayload(appointment: appointment), for: userId)
            print("☁️ Appointment synced to CloudKit backup: \(appointment.title)")
        } catch {
            print("⚠️ Failed to sync appointment to CloudKit backup: \(error.localizedDescription)")
        }
    }

    func restoreAppointmentsFromCloudKitBackupIfNeeded() async {
        let provider = CloudSyncProvider.current
        let firebaseUserId = AppointmentCloudSyncPolicy.firestoreUserId(
            provider: provider,
            isAuthenticated: FirebaseService.shared.isAuthenticated,
            currentUserId: FirebaseService.shared.currentUser?.uid
        )
        guard let cloudKitUserId = AppointmentCloudSyncPolicy.cloudKitBackupUserId(
            provider: provider,
            firebaseUserId: firebaseUserId
        ) else {
            return
        }

        await restoreAppointmentsFromCloudKitIfNeeded(
            userId: cloudKitUserId,
            backfillFirebase: provider == .firebase
        )
    }

    private func restoreAppointmentsFromCloudKitIfNeeded(userId: String, backfillFirebase: Bool) async {
        let hasLocalAppointments = await MainActor.run { !appointments.isEmpty }
        guard !hasLocalAppointments else { return }

        do {
            guard let cloudKitBackupService else {
                throw CloudKitLeadBackupError.containerUnavailable(CloudKitLeadBackupService.containerIdentifier)
            }

            let backupPayloads = try await cloudKitBackupService.fetchAppointments(for: userId)
            guard !backupPayloads.isEmpty else {
                print("☁️ No CloudKit appointment backup found")
                return
            }

            let restoredAppointments = backupPayloads.map(\.appointment)
            let filteredAppointments = AppointmentCloudMergePolicy.excludingDeletedAppointments(
                restoredAppointments,
                deletedIds: deletedAppointmentIds()
            )
            guard !filteredAppointments.isEmpty else {
                print("☁️ CloudKit appointment backup only contained locally deleted appointments")
                return
            }

            await MainActor.run {
                mergeFirestoreAppointments(filteredAppointments)
            }
            print("☁️ Restored \(filteredAppointments.count) appointments from CloudKit backup")

            if backfillFirebase {
                // Backfill Firebase so both cloud stores converge.
                for appointment in filteredAppointments {
                    await syncAppointmentToFirebase(appointment)
                }
            }
        } catch {
            print("⚠️ Failed to restore appointments from CloudKit backup: \(error.localizedDescription)")
        }
    }

    private func deletedAppointmentIds() -> Set<UUID> {
        AppointmentDeletionTombstoneStore.loadDeletedIds(
            from: userDefaults,
            key: deletedAppointmentIdsKey
        )
    }

    private func markAppointmentDeleted(_ id: UUID) {
        markAppointmentsDeleted([id])
    }

    private func markAppointmentsDeleted(_ ids: Set<UUID>) {
        AppointmentDeletionTombstoneStore.markDeleted(
            ids,
            in: userDefaults,
            key: deletedAppointmentIdsKey
        )
    }
}

// MARK: - Extensions

extension Appointment: Codable {
    enum CodingKeys: String, CodingKey {
        case id, title, notes, startDate, endDate, location, leadId, calendarEventId, appointmentType, customAppointmentTypeId, status
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        // Handle UUID decoding for Firestore compatibility
        if let idString = try? container.decode(String.self, forKey: .id),
           let uuid = UUID(uuidString: idString) {
            id = uuid
        } else {
            id = UUID()
        }
        
        title = try container.decode(String.self, forKey: .title)
        notes = try container.decode(String.self, forKey: .notes)
        startDate = try container.decode(Date.self, forKey: .startDate)
        endDate = try container.decode(Date.self, forKey: .endDate)
        location = try container.decode(String.self, forKey: .location)
        
        // Handle UUID decoding for leadId
        if let leadIdString = try? container.decode(String.self, forKey: .leadId),
           let leadUuid = UUID(uuidString: leadIdString) {
            leadId = leadUuid
        } else {
            leadId = try container.decodeIfPresent(UUID.self, forKey: .leadId)
        }
        
        calendarEventId = try container.decodeIfPresent(String.self, forKey: .calendarEventId)
        
        let typeString = try container.decode(String.self, forKey: .appointmentType)
        appointmentType = AppointmentType(rawValue: typeString) ?? .consultation
        
        customAppointmentTypeId = try container.decodeIfPresent(String.self, forKey: .customAppointmentTypeId)
        
        let statusString = try container.decode(String.self, forKey: .status)
        status = AppointmentStatus(rawValue: statusString) ?? .scheduled
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id.uuidString, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(notes, forKey: .notes)
        try container.encode(startDate, forKey: .startDate)
        try container.encode(endDate, forKey: .endDate)
        try container.encode(location, forKey: .location)
        try container.encodeIfPresent(leadId?.uuidString, forKey: .leadId)
        try container.encodeIfPresent(calendarEventId, forKey: .calendarEventId)
        try container.encode(appointmentType.rawValue, forKey: .appointmentType)
        try container.encodeIfPresent(customAppointmentTypeId, forKey: .customAppointmentTypeId)
        try container.encode(status.rawValue, forKey: .status)
    }
}
