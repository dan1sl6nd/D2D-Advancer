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
            case .consultation: return Color.themeSuccess
            case .installation: return Color.themePrimary
            case .inspection: return Color.themeWarning
            case .maintenance: return Color.themeAccent
            case .repair: return Color.themeError
            case .followUp: return Color.themeTextSecondary
            }
        }
    }
    
    enum AppointmentStatus: String, CaseIterable, Codable, Sendable {
        case scheduled = "Scheduled"
        case confirmed = "Confirmed"
        case completed = "Completed"
        case cancelled = "Cancelled"
        case rescheduled = "Rescheduled"
        
        var color: Color {
            switch self {
            case .scheduled: return Color.themePrimary
            case .confirmed: return Color.themeSuccess
            case .completed: return Color.themeSuccess
            case .cancelled: return Color.themeError
            case .rescheduled: return Color.themeWarning
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

@MainActor
class AppointmentManager: ObservableObject {
    static let shared = AppointmentManager()
    
    @Published var appointments: [Appointment] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    private let userDefaults = UserDefaults.standard
    private let appointmentsKey = "saved_appointments"
    private let db = Firestore.firestore()
    private let cloudKitBackupService = CloudKitAppointmentBackupService.shared
    private var listener: ListenerRegistration?
    private var isCleared = false  // Flag to prevent reloading after clearing
    
    private init() {
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
        saveAppointments()
        
        // Update lead status to interested if it's a consultation
        // Do NOT downgrade terminal states like Sold or Not Interested
        if appointment.appointmentType == .consultation {
            if lead.leadStatus != .converted && lead.leadStatus != .notInterested {
                lead.leadStatus = .interested
            }
            // Always set follow-up date for consultations
            lead.followUpDate = appointment.startDate
            lead.updatedDate = Date()
            
            // Save Core Data changes
            do {
                try lead.managedObjectContext?.save()
                // Individual sync removed - will sync manually, hourly, or before sign-out
                print("📝 Lead updated from appointment - will sync on next manual/hourly/sign-out sync")
            } catch {
                print("Failed to update lead: \(error)")
            }
        }
        
        // Sync to Firebase with leadId included
        await syncAppointmentToFirebase(updatedAppointment)

        // Create an Apple Calendar event if enabled
        if CalendarService.shared.settings.isEnabled {
            CalendarService.shared.requestAccessIfNeeded { granted in
                guard granted else { return }
                let eventId = CalendarService.shared.createOrUpdateEvent(for: updatedAppointment)
                if let eventId = eventId {
                    Task { @MainActor in
                        if let idx = self.appointments.firstIndex(where: { $0.id == updatedAppointment.id }) {
                            self.appointments[idx].calendarEventId = eventId
                            self.saveAppointments()
                            await self.syncAppointmentToFirebase(self.appointments[idx])
                        }
                    }
                }
            }
        }

        // Schedule notifications for the appointment
        NotificationService.shared.scheduleAppointmentNotifications(for: updatedAppointment)

        isLoading = false
        return true
    }
    
    func updateAppointment(_ appointment: Appointment) async -> Bool {
        await MainActor.run {
            isLoading = true
            errorMessage = nil
        }
        
        // Update local storage
        await MainActor.run {
            if let index = appointments.firstIndex(where: { $0.id == appointment.id }) {
                appointments[index] = appointment
                saveAppointments()
            }
        }
        
        // Sync to Firebase
        await syncAppointmentToFirebase(appointment)

        // Update Apple Calendar event if enabled
        if CalendarService.shared.settings.isEnabled {
            CalendarService.shared.requestAccessIfNeeded { granted in
                guard granted else { return }
                let eventId = CalendarService.shared.createOrUpdateEvent(for: appointment)
                if let eventId = eventId {
                    Task { @MainActor in
                        if let idx = self.appointments.firstIndex(where: { $0.id == appointment.id }) {
                            self.appointments[idx].calendarEventId = eventId
                            self.saveAppointments()
                            await self.syncAppointmentToFirebase(self.appointments[idx])
                        }
                    }
                }
            }
        }

        // Update notifications for the appointment
        NotificationService.shared.scheduleAppointmentNotifications(for: appointment)

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
        let updatedAppointment = tempAppointment
        
        await MainActor.run {
            if let index = appointments.firstIndex(where: { $0.id == appointment.id }) {
                appointments[index] = updatedAppointment
                saveAppointments()
            }
        }
        
        // Sync to Firebase
        await syncAppointmentToFirebase(updatedAppointment)

        // Remove Apple Calendar event if it exists
        if let eventId = appointment.calendarEventId {
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
        await MainActor.run {
            appointments.removeAll { $0.id == appointment.id }
            saveAppointments()
        }
        
        // Delete from Firebase
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
    
    private func saveAppointments() {
        if let encoded = try? JSONEncoder().encode(appointments) {
            userDefaults.set(encoded, forKey: appointmentsKey)
        }
    }
    
    private func loadAppointments() {
        guard !isCleared else {
            print("🗓️ Skipping appointment loading - appointments were cleared")
            return
        }
        
        if let data = userDefaults.data(forKey: appointmentsKey),
           let decoded = try? JSONDecoder().decode([Appointment].self, from: data) {
            appointments = decoded
            print("🗓️ Loaded \(appointments.count) appointments from UserDefaults")
        } else {
            print("🗓️ No appointments found in UserDefaults")
        }
    }
    
    // MARK: - Firebase Sync Methods
    
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
                        await self?.restoreAppointmentsFromCloudKitIfNeeded(userId: userId)
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
        print("🗓️ Merging \(firestoreAppointments.count) appointments from Firestore")
        
        // If we have no local appointments and Firestore has appointments, this is a normal download
        if appointments.isEmpty && !firestoreAppointments.isEmpty {
            appointments = firestoreAppointments
            saveAppointments()
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
        
        saveAppointments()
        print("🗓️ Merge completed - now have \(appointments.count) appointments locally")
        
        // Force UI refresh by explicitly notifying observers
        DispatchQueue.main.async {
            self.objectWillChange.send()
        }
    }
    
    func syncAppointmentToFirebase(_ appointment: Appointment) async {
        guard let userId = FirebaseService.shared.currentUser?.uid else {
            print("🗓️ No current user, skipping Firebase sync")
            return
        }
        
        do {
            let appointmentData = try Firestore.Encoder().encode(appointment)
            try await db.collection("users").document(userId).collection("appointments").document(appointment.id.uuidString).setData(appointmentData)
            print("🗓️ Appointment synced to Firebase: \(appointment.title)")
        } catch {
            print("🗓️ Failed to sync appointment to Firebase: \(error)")
            await MainActor.run {
                errorMessage = "Failed to sync appointment: \(error.localizedDescription)"
            }
        }

        await backupAppointmentToCloudKit(appointment, userId: userId)
    }
    
    func deleteAppointmentFromFirebase(_ appointmentId: UUID) async {
        guard let userId = FirebaseService.shared.currentUser?.uid else {
            print("🗓️ No current user, skipping Firebase delete")
            return
        }
        
        do {
            try await db.collection("users").document(userId).collection("appointments").document(appointmentId.uuidString).delete()
            print("🗓️ Appointment deleted from Firebase: \(appointmentId)")
        } catch {
            print("🗓️ Failed to delete appointment from Firebase: \(error)")
            await MainActor.run {
                errorMessage = "Failed to delete appointment: \(error.localizedDescription)"
            }
        }

        do {
            try await cloudKitBackupService.deleteAppointment(appointmentId, for: userId)
            print("☁️ Appointment deleted from CloudKit backup: \(appointmentId)")
        } catch {
            print("⚠️ Failed to delete appointment from CloudKit backup: \(error.localizedDescription)")
        }
    }
    
    func deleteAllAppointmentsFromFirebase() async {
        guard let userId = FirebaseService.shared.currentUser?.uid else {
            print("🗓️ No current user, skipping Firebase delete all")
            return
        }
        
        print("🗓️ Deleting all appointments from Firebase...")
        
        do {
            // Get all appointment documents
            let querySnapshot = try await db.collection("users").document(userId).collection("appointments").getDocuments()
            
            // Delete each document
            for document in querySnapshot.documents {
                try await document.reference.delete()
                print("🗓️ Deleted appointment from Firebase: \(document.documentID)")
            }
            
            print("✅ All appointments deleted from Firebase (\(querySnapshot.documents.count) deleted)")
        } catch {
            print("❌ Failed to delete all appointments from Firebase: \(error)")
        }

        do {
            try await cloudKitBackupService.deleteAllAppointments(for: userId)
            print("✅ All appointments deleted from CloudKit backup")
        } catch {
            print("⚠️ Failed to delete appointments from CloudKit backup: \(error.localizedDescription)")
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
        saveAppointments()
        
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
        var updatedCount = 0
        
        for index in appointments.indices {
            if appointments[index].status == .cancelled {
                appointments[index].status = .scheduled
                updatedCount += 1
            }
        }
        
        if updatedCount > 0 {
            saveAppointments()
            print("✅ Fixed \(updatedCount) cancelled appointments")
            
            // Sync the status changes to Firebase
            Task {
                await syncAllAppointmentsToFirebase()
            }
        }
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
        guard FirebaseService.shared.currentUser?.uid != nil else {
            print("🗓️ No current user, skipping Firebase sync")
            return
        }
        
        print("🗓️ Syncing \(appointments.count) appointments to Firebase")
        
        // Temporarily pause the Firebase listener to prevent conflicts during sync
        let wasListening = listener != nil
        listener?.remove()
        listener = nil
        
        for appointment in appointments {
            await syncAppointmentToFirebase(appointment)
        }
        
        // Wait a moment for Firebase to propagate the changes
        try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
        
        // Restart the listener if it was active before
        if wasListening {
            setupFirestoreListener()
        }
        
        print("🗓️ Firebase sync completed and listener restarted")
    }

    private func backupAppointmentToCloudKit(_ appointment: Appointment, userId: String) async {
        do {
            try await cloudKitBackupService.uploadAppointment(AppointmentSyncPayload(appointment: appointment), for: userId)
            print("☁️ Appointment synced to CloudKit backup: \(appointment.title)")
        } catch {
            print("⚠️ Failed to sync appointment to CloudKit backup: \(error.localizedDescription)")
        }
    }

    private func restoreAppointmentsFromCloudKitIfNeeded(userId: String) async {
        let hasLocalAppointments = await MainActor.run { !appointments.isEmpty }
        guard !hasLocalAppointments else { return }

        do {
            let backupPayloads = try await cloudKitBackupService.fetchAppointments(for: userId)
            guard !backupPayloads.isEmpty else {
                print("☁️ No CloudKit appointment backup found")
                return
            }

            let restoredAppointments = backupPayloads.map(\.appointment)

            await MainActor.run {
                mergeFirestoreAppointments(restoredAppointments)
            }
            print("☁️ Restored \(restoredAppointments.count) appointments from CloudKit backup")

            // Backfill Firebase so both cloud stores converge.
            for appointment in restoredAppointments {
                await syncAppointmentToFirebase(appointment)
            }
        } catch {
            print("⚠️ Failed to restore appointments from CloudKit backup: \(error.localizedDescription)")
        }
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
