import Foundation
import CoreData
import Combine
import FirebaseFirestore
import FirebaseAuth

enum SyncError: Error {
    case notAuthenticated
    case networkError(String)
    case dataCorruption(String)
}

class UserDataSyncManager: ObservableObject {
    static let shared = UserDataSyncManager()
    
    @Published var syncStatus: SyncStatus = .idle
    @Published var lastSyncDate: Date?
    @Published var isAutoSyncEnabled = false  // Disabled by default
    @Published var syncInterval: SyncInterval = .oneHour  // Default to 1 hour
    
    private let db = Firestore.firestore()
    private let firebaseService = FirebaseService.shared
    private var syncTimer: Timer?
    
    enum SyncInterval: String, CaseIterable {
        case thirtyMinutes = "30min"
        case oneHour = "1hour"
        case threeHours = "3hours"
        case sixHours = "6hours"
        case oneDay = "1day"
        
        var displayName: String {
            switch self {
            case .thirtyMinutes: return "Every 30 minutes"
            case .oneHour: return "Every hour"
            case .threeHours: return "Every 3 hours"
            case .sixHours: return "Every 6 hours"
            case .oneDay: return "Once daily"
            }
        }
        
        var shortDisplayName: String {
            switch self {
            case .thirtyMinutes: return "30min"
            case .oneHour: return "1hr"
            case .threeHours: return "3hr"
            case .sixHours: return "6hr"
            case .oneDay: return "Daily"
            }
        }
        
        var timeInterval: TimeInterval {
            switch self {
            case .thirtyMinutes: return 30 * 60      // 30 minutes
            case .oneHour: return 60 * 60           // 1 hour
            case .threeHours: return 3 * 60 * 60    // 3 hours
            case .sixHours: return 6 * 60 * 60      // 6 hours
            case .oneDay: return 24 * 60 * 60       // 24 hours
            }
        }
    }
    
    private init() {
        loadSyncSettings()
        startSyncTimer()
    }
    
    enum SyncStatus: Equatable {
        case idle
        case syncing
        case completed
        case failed(String)
    }
    
    func startSync(includeAppointments: Bool = true) {
        guard firebaseService.isAuthenticated else {
            DispatchQueue.main.async {
                // Only show failed status if user was previously syncing or if they had a last sync
                // This prevents showing "Failed" on app launch when user hasn't signed in yet
                if self.syncStatus == .syncing || self.lastSyncDate != nil {
                    self.syncStatus = .idle
                }
                // Otherwise keep current status (likely .idle on first launch)
            }
            print("⏭️ Sync skipped: User not authenticated")
            return
        }

        guard let currentUser = firebaseService.currentUser else {
            DispatchQueue.main.async {
                // Only show failed if we were actively trying to sync
                if self.syncStatus == .syncing {
                    self.syncStatus = .failed("No current user available")
                }
            }
            print("❌ Sync failed: No current user")
            return
        }

        print("🔄 Starting sync for user: \(currentUser.uid)")
        Task {
            await performSync(includeAppointments: includeAppointments)
        }
    }
    
    func pauseSync() {
        DispatchQueue.main.async {
            self.syncStatus = .idle
        }
    }
    
    func resumeSync() {
        if isAutoSyncEnabled {
            startSync()
        }
    }
    
    func autoSyncIfEnabled() {
        // Auto-sync is now disabled - only manual, hourly, and before sign-out sync
        print("🔕 Auto-sync disabled - sync only happens manually, hourly, or before sign-out")
    }
    
    private func loadSyncSettings() {
        // Load sync interval from UserDefaults
        if let savedInterval = UserDefaults.standard.object(forKey: "sync_interval") as? String,
           let interval = SyncInterval(rawValue: savedInterval) {
            syncInterval = interval
        }
        
        // Load auto-sync enabled state
        isAutoSyncEnabled = UserDefaults.standard.bool(forKey: "auto_sync_enabled")
    }
    
    private func saveSyncSettings() {
        UserDefaults.standard.set(syncInterval.rawValue, forKey: "sync_interval")
        UserDefaults.standard.set(isAutoSyncEnabled, forKey: "auto_sync_enabled")
        UserDefaults.standard.synchronize()
    }
    
    func updateSyncInterval(_ interval: SyncInterval) {
        syncInterval = interval
        saveSyncSettings()
        restartSyncTimer()
        print("⏰ Sync interval updated to: \(interval.displayName)")
    }
    
    func toggleAutoSync(_ enabled: Bool) {
        isAutoSyncEnabled = enabled
        saveSyncSettings()
        
        if enabled {
            startSyncTimer()
        } else {
            stopSyncTimer()
        }
        
        print("🔄 Auto-sync \(enabled ? "enabled" : "disabled")")
    }
    
    private func startSyncTimer() {
        guard isAutoSyncEnabled else { return }
        
        stopSyncTimer() // Stop existing timer first
        
        syncTimer = Timer.scheduledTimer(withTimeInterval: syncInterval.timeInterval, repeats: true) { [weak self] _ in
            self?.performScheduledSync()
        }
        print("⏰ Sync timer started: \(syncInterval.displayName)")
    }
    
    private func stopSyncTimer() {
        syncTimer?.invalidate()
        syncTimer = nil
    }
    
    private func restartSyncTimer() {
        stopSyncTimer()
        startSyncTimer()
    }
    
    private func performScheduledSync() {
        guard firebaseService.isAuthenticated else {
            print("⏰ Skipping scheduled sync - user not authenticated")
            return
        }
        
        print("⏰ Performing scheduled sync (\(syncInterval.displayName))...")
        startSync()
    }
    
    func syncBeforeSignOut() {
        guard firebaseService.isAuthenticated else {
            print("🚪 Skipping sign-out sync - user not authenticated")
            return
        }
        
        print("🚪 Performing sync before sign out...")
        startSync()
    }
    
    func syncWithServer() {
        // Start appointment Firebase listener for complete sync
        AppointmentManager.shared.restartFirebaseSync()
        
        // Start general data sync (including appointments)
        startSync()
    }
    
    private func performSync(includeAppointments: Bool = true) async {
        // Update status on main thread
        await MainActor.run {
            syncStatus = .syncing
        }
        
        let retryOperation = RetryableOperation(maxRetries: 3, retryDelay: 2.0)
        
        do {
            try await retryOperation.execute(
                operation: { [self] in
                    // Check authentication before each operation
                    guard firebaseService.isAuthenticated, let userId = firebaseService.currentUser?.uid else {
                        throw SyncError.notAuthenticated
                    }
                    
                    // Perform sync operations on background thread
                    print("🔄 Starting background sync operations...")
                    
                    // Clean up any corrupted leads first
                    await self.cleanupCorruptedLeads()
                    
                    // Check auth again before upload
                    guard firebaseService.isAuthenticated else {
                        throw SyncError.notAuthenticated
                    }
                    
                    try await self.uploadLeadsToFirestore(userId: userId)
                    
                    // Check auth again before download
                    guard firebaseService.isAuthenticated else {
                        throw SyncError.notAuthenticated
                    }
                    
                    // Download leads from Firebase (background operation)
                    try await self.downloadLeadsFromFirestore(userId: userId)
                    
                    // Check auth again before appointment sync
                    guard firebaseService.isAuthenticated else {
                        throw SyncError.notAuthenticated
                    }
                    
                    // Sync appointments only if requested
                    if includeAppointments {
                        try await self.syncAppointments(userId: userId)
                    } else {
                        print("🗓️ Skipping appointment sync as requested")
                    }
                },
                onError: { error, attempt in
                    print("🔄 Sync attempt \(attempt) failed: \(error.localizedDescription)")
                }
            )
            
            // Update sync status on main thread
            await MainActor.run {
                syncStatus = .completed
                lastSyncDate = Date()
            }
            print("✅ Data sync completed successfully")
            
        } catch {
            await MainActor.run {
                // Handle authentication errors gracefully during sign-out
                if case SyncError.notAuthenticated = error {
                    print("ℹ️ Sync stopped due to authentication change")
                    syncStatus = .idle
                } else {
                    ErrorHandler.shared.handle(error, context: "Data Sync")
                    syncStatus = .failed(error.localizedDescription)
                }
            }
        }
    }
    
    private func uploadLeadsToFirestore(userId: String) async throws {
        print("📤 Uploading leads to Firebase...")
        
        // Use background context for better performance
        let container = PersistenceController.shared.container
        let backgroundContext = container.newBackgroundContext()
        
        let leads = try await backgroundContext.perform {
            // Fetch leads from Core Data on background context
            let fetchRequest: NSFetchRequest<Lead> = Lead.fetchRequest()
            return try backgroundContext.fetch(fetchRequest)
        }
        
        // Simplified sync summary
        let namedLeads = leads.filter { !($0.name?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) }
        let unnamedLeads = leads.filter { ($0.name?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) }
        
        print("📤 Syncing \(leads.count) leads: \(namedLeads.count) contacts, \(unnamedLeads.count) visited houses")
        
        // Sync each lead to Firestore
        for lead in leads {
            var leadData: [String: Any] = [
                "name": lead.name ?? "",
                "address": lead.address ?? "",
                "phone": lead.phone ?? "",
                "email": lead.email ?? "",
                "latitude": lead.latitude,
                "longitude": lead.longitude,
                "status": lead.status ?? "not_contacted",
                "notes": lead.notes ?? "",
                "dateCreated": lead.createdDate ?? Date(),
                "dateModified": lead.updatedDate ?? Date(),
                "priority": lead.priority,
                "source": lead.source ?? "",
                "estimatedValue": lead.estimatedValue,
                "tags": lead.tags ?? "",
                "visitCount": lead.visitCount
            ]
            
            // Handle optional dates properly for Firebase
            if let lastContactDate = lead.lastContactDate {
                leadData["lastContactDate"] = lastContactDate
            }
            
            // Only sync follow-up date if it exists - don't delete existing Firebase data
            if let followUpDate = lead.followUpDate {
                leadData["followUpDate"] = followUpDate
            }
            // If no follow-up date locally, don't modify the Firebase field
            // This preserves existing follow-up dates that might be set in Firebase
            
            // Use lead's UUID as document ID, or create one if missing
            let documentId = lead.id?.uuidString ?? UUID().uuidString
            
            try await db.collection("users")
                .document(userId)
                .collection("leads")
                .document(documentId)
                .setData(leadData, merge: true)
        }
        // Debug: Check for potential issues with leads
        let leadsWithoutId = leads.filter { $0.id == nil }
        let leadsWithoutName = leads.filter { $0.name?.isEmpty != false }
        let duplicateIds = Dictionary(grouping: leads.compactMap { $0.id }, by: { $0 })
            .filter { $1.count > 1 }
        
        if !leadsWithoutId.isEmpty {
            print("⚠️ Found \(leadsWithoutId.count) leads without IDs")
        }
        if !leadsWithoutName.isEmpty {
            print("⚠️ Found \(leadsWithoutName.count) leads without names")
        }
        if !duplicateIds.isEmpty {
            print("⚠️ Found duplicate IDs: \(duplicateIds.keys)")
        }
        
        print("📤 Upload completed: \(leads.count) leads")
    }
    
    func deleteLeadFromFirebase(leadId: String) async throws {
        guard let currentUser = Auth.auth().currentUser else {
            throw SyncError.notAuthenticated
        }
        
        let userId = currentUser.uid
        print("🗑️ Deleting lead \(leadId) from Firebase...")
        
        try await db.collection("users")
            .document(userId)
            .collection("leads")
            .document(leadId)
            .delete()
        
        print("✅ Lead \(leadId) deleted from Firebase")
    }
    
    func clearSyncState() {
        print("🔄 Clearing sync manager state...")
        
        // Stop sync timer
        stopSyncTimer()
        
        DispatchQueue.main.async {
            self.syncStatus = .idle
            self.lastSyncDate = nil
            self.isAutoSyncEnabled = false  // Keep auto-sync disabled
        }
        
        print("✅ Sync manager state cleared")
    }
    
    deinit {
        stopSyncTimer()
    }
    
    private func downloadLeadsFromFirestore(userId: String) async throws {
        print("📥 Downloading leads from Firebase...")
        
        // Get leads from Firestore
        let snapshot = try await db.collection("users")
            .document(userId)
            .collection("leads")
            .getDocuments()
        
        // Clean up any existing leads with nil IDs before processing new data
        await cleanupCorruptedLeads()
        
        // Use background context for better performance
        let container = PersistenceController.shared.container
        let backgroundContext = container.newBackgroundContext()
        
        try await backgroundContext.perform {
            var downloadedCount = 0
            var updatedCount = 0
            
            for document in snapshot.documents {
                let data = document.data()
                
                // Debug follow-up dates only if there are issues
                // (Removed verbose logging)
                
                // Check if lead already exists
                let fetchRequest: NSFetchRequest<Lead> = Lead.fetchRequest()
                if let documentUUID = UUID(uuidString: document.documentID) {
                    fetchRequest.predicate = NSPredicate(format: "id == %@", documentUUID as CVarArg)
                } else {
                    // Skip invalid document ID
                    continue
                }
                
                do {
                    let existingLeads = try backgroundContext.fetch(fetchRequest)
                    let lead: Lead
                    
                    if let existingLead = existingLeads.first {
                        // Check if local lead was recently modified (within last 5 minutes)
                        let fiveMinutesAgo = Date().addingTimeInterval(-300)
                        let localModified = existingLead.updatedDate ?? Date.distantPast
                        let firebaseModified = data["dateModified"] as? Date ?? Date.distantPast
                        
                        // Only update if Firebase data is newer or local wasn't recently modified
                        if firebaseModified > localModified || localModified < fiveMinutesAgo {
                            lead = existingLead
                            updatedCount += 1
                        } else {
                            // Skip update to preserve recent local changes
                            print("🔄 Skipping update for recently modified lead: \(existingLead.displayName)")
                            continue
                        }
                    } else {
                        // Create new lead
                        lead = Lead(context: backgroundContext)
                        // Ensure we always have a valid UUID, either from document ID or create new one
                        if let validUUID = UUID(uuidString: document.documentID) {
                            lead.id = validUUID
                        } else {
                            lead.id = UUID()
                        }
                        downloadedCount += 1
                    }
                    
                    // Update lead properties from Firebase data
                    lead.name = data["name"] as? String
                    lead.address = data["address"] as? String
                    lead.phone = data["phone"] as? String
                    lead.email = data["email"] as? String
                    lead.latitude = data["latitude"] as? Double ?? 0.0
                    lead.longitude = data["longitude"] as? Double ?? 0.0
                    if let rawStatus = data["status"] as? String, !rawStatus.isEmpty {
                        lead.status = UserDataSyncManager.normalizeLeadStatus(rawStatus)
                    } else {
                        // Ensure we always have a valid status
                        lead.status = Lead.Status.notContacted.rawValue
                    }
                    lead.notes = data["notes"] as? String
                    lead.createdDate = data["dateCreated"] as? Date ?? Date()
                    lead.updatedDate = data["dateModified"] as? Date ?? Date()
                    lead.lastContactDate = data["lastContactDate"] as? Date
                    
                    // Handle follow-up date - preserve local data if Firebase doesn't have it
                    if let followUpDate = data["followUpDate"] as? Date {
                        lead.followUpDate = followUpDate
                    } else if let followUpValue = data["followUpDate"], !(followUpValue is NSNull) {
                        // Try to handle Firebase timestamp
                        if let timestamp = followUpValue as? Timestamp {
                            lead.followUpDate = timestamp.dateValue()
                        }
                        // Try to handle timestamp conversion if it's stored as a number
                        else if let timestamp = followUpValue as? TimeInterval {
                            lead.followUpDate = Date(timeIntervalSince1970: timestamp)
                        }
                        // Don't modify the local follow-up date if we can't parse Firebase data
                    }
                    // Don't set to nil - this preserves any existing local follow-up date
                    
                    lead.priority = data["priority"] as? Int16 ?? 0
                    lead.source = data["source"] as? String
                    lead.estimatedValue = data["estimatedValue"] as? Double ?? 0.0
                    lead.tags = data["tags"] as? String
                    lead.visitCount = data["visitCount"] as? Int16 ?? 0
                } catch {
                    print("❌ Failed to fetch existing leads: \(error)")
                    throw error
                }
            }
            
            // Save the background context
            try backgroundContext.save()
            print("📥 Download completed: \(downloadedCount) new leads, \(updatedCount) updated leads")
        }
    }

    // Normalize remote status strings to current app values
    private static func normalizeLeadStatus(_ status: String) -> String {
        let s = status.lowercased()
        switch s {
        case "sold", "closed", "close", "won":
            return Lead.Status.converted.rawValue
        case "not_interested", "no_interest", "lost":
            return Lead.Status.notInterested.rawValue
        case "not_home", "no_answer":
            return Lead.Status.notHome.rawValue
        case "interested", "prospect":
            return Lead.Status.interested.rawValue
        case "not_contacted", "new", "cold":
            return Lead.Status.notContacted.rawValue
        default:
            // Fallback to existing string; if unknown, the Lead.leadStatus getter will handle
            return status
        }
    }
    
    private func cleanupCorruptedLeads() async {
        print("🧹 Cleaning up corrupted leads...")
        
        let container = PersistenceController.shared.container
        let backgroundContext = container.newBackgroundContext()
        
        await backgroundContext.perform {
            let fetchRequest: NSFetchRequest<Lead> = Lead.fetchRequest()
            
            do {
                let allLeads = try backgroundContext.fetch(fetchRequest)
                var corruptedCount = 0
                
                for lead in allLeads {
                    let hasName = lead.name?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                    let hasAddress = lead.address?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                    let hasId = lead.id != nil
                    
                    // Remove leads that are truly corrupted:
                    // 1. No ID (database corruption)
                    // 2. No name AND no address (no useful location data)
                    let shouldDelete = !hasId || (!hasName && !hasAddress)
                    
                    if shouldDelete {
                        let leadName = hasName ? lead.name! : "No Name"
                        let leadAddress = hasAddress ? lead.address! : "No Address"
                        let leadId = lead.id?.uuidString ?? "No ID"
                        
                        if !hasId {
                            print("🗑️ Removing lead with nil ID: \(leadName)")
                        } else {
                            print("🗑️ Removing corrupted lead with no name/address: \(leadName) - \(leadAddress) (ID: \(leadId))")
                        }
                        
                        backgroundContext.delete(lead)
                        corruptedCount += 1
                    }
                }
                
                if corruptedCount > 0 {
                    try backgroundContext.save()
                    print("✅ Cleaned up \(corruptedCount) corrupted leads")
                } else {
                    print("✅ No corrupted leads found")
                }
            } catch {
                print("❌ Failed to clean up corrupted leads: \(error)")
            }
        }
    }
    
    // MARK: - Appointment Sync Methods
    
    private func syncAppointments(userId: String) async throws {
        print("🗓️ Syncing appointments...")
        
        // The AppointmentManager now handles timing and listener management internally
        await AppointmentManager.shared.syncAllAppointmentsToFirebase()
        
        print("✅ Appointments sync completed")
    }
}
