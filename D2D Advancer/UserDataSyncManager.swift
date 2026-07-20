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

enum LeadDeletionTombstoneStore {
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

enum LeadCloudMergePolicy {
    static func shouldSkipRemoteLead(documentId: String, deletedIds: Set<UUID>) -> Bool {
        guard let id = UUID(uuidString: documentId) else { return false }
        return deletedIds.contains(id)
    }

    static func shouldApplyRemote(
        remoteModifiedDate: Date,
        localModifiedDate: Date
    ) -> Bool {
        remoteModifiedDate > localModifiedDate
    }
}

struct PersonalCloudMigrationSummary: Equatable {
    let firebaseLeadCount: Int
    let iCloudLeadCount: Int
    let appointmentCount: Int
}

struct PersonalSyncRequest: Equatable {
    let provider: CloudSyncProvider
    let includeAppointments: Bool
}

struct PersonalSyncExecutionGate {
    private(set) var activeRequest: PersonalSyncRequest?
    private(set) var pendingRequest: PersonalSyncRequest?

    var isActive: Bool {
        activeRequest != nil
    }

    mutating func request(_ request: PersonalSyncRequest) -> Bool {
        guard let activeRequest else {
            self.activeRequest = request
            return true
        }

        if activeRequest.provider != request.provider {
            pendingRequest = request
        } else {
            if pendingRequest?.provider != activeRequest.provider {
                pendingRequest = nil
            }
            if request.includeAppointments && !activeRequest.includeAppointments {
                pendingRequest = PersonalSyncRequest(
                    provider: request.provider,
                    includeAppointments: true
                )
            }
        }

        return false
    }

    mutating func finishActiveRequest() -> PersonalSyncRequest? {
        activeRequest = nil
        guard let pendingRequest else { return nil }
        self.pendingRequest = nil
        activeRequest = pendingRequest
        return pendingRequest
    }
}

enum PersonalCloudMigrationError: LocalizedError {
    case migrationAlreadyRunning
    case firebaseSignInRequired

    var errorDescription: String? {
        switch self {
        case .migrationAlreadyRunning:
            return "A cloud sync is already running. Wait for it to finish and try again."
        case .firebaseSignInRequired:
            return "Sign in with Apple again so the legacy Firebase data can be copied to iCloud."
        }
    }
}

@MainActor
class UserDataSyncManager: ObservableObject {
    static let shared = UserDataSyncManager()
    nonisolated static let privateCloudKitUserId = "icloudPrivateUser"
    nonisolated static let deletedLeadIdsKey = "deleted_lead_ids"
    
    @Published var syncStatus: SyncStatus = .idle
    @Published var lastSyncDate: Date?
    @Published var isAutoSyncEnabled = true  // Enabled by default
    @Published var syncInterval: SyncInterval = .oneHour  // Default to 1 hour
    
    private let db: Firestore
    private var cloudKitBackupService: CloudKitLeadBackupService? {
        CloudKitLeadBackupService.shared
    }
    private let firebaseService: FirebaseService
    private var syncTimer: Timer?
    private var hasActivatedAutoSyncTimer = false
    private var activeSyncTask: Task<Void, Never>?
    private var syncExecutionGate = PersonalSyncExecutionGate()
    
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
        FirebaseBootstrap.configureIfNeeded()
        db = Firestore.firestore()
        firebaseService = FirebaseService.shared
        loadSyncSettings()
    }
    
    enum SyncStatus: Equatable {
        case idle
        case syncing
        case uploading(Int, Int)
        case downloading
        case completed
        case failed(String)

        var isBusy: Bool {
            switch self {
            case .syncing, .uploading, .downloading:
                return true
            case .idle, .completed, .failed:
                return false
            }
        }

        var displayText: String {
            switch self {
            case .idle:
                return ""
            case .syncing:
                return "Preparing sync..."
            case .uploading(let current, let total):
                return "Uploading \(current)/\(total) leads..."
            case .downloading:
                return "Downloading..."
            case .completed:
                return "Sync complete"
            case .failed(let message):
                return "Sync failed: \(message)"
            }
        }
    }

    nonisolated static func shouldUseFirebaseLeadSync(
        provider: CloudSyncProvider,
        isAuthenticated: Bool
    ) -> Bool {
        shouldUseFirebasePersonalSync(provider: provider, isAuthenticated: isAuthenticated)
    }

    nonisolated static func shouldUseFirebasePersonalSync(
        provider: CloudSyncProvider,
        isAuthenticated: Bool
    ) -> Bool {
        provider == .firebase && isAuthenticated
    }

    nonisolated static func shouldDeleteLeadFromFirebase(
        provider: CloudSyncProvider,
        isAuthenticated: Bool
    ) -> Bool {
        shouldUseFirebaseLeadSync(provider: provider, isAuthenticated: isAuthenticated)
    }

    nonisolated static func cloudKitLeadBackupUserId(
        provider: CloudSyncProvider,
        isAuthenticated: Bool,
        currentUserId: String?
    ) -> String? {
        switch provider {
        case .firebase:
            guard isAuthenticated else { return nil }
            return currentUserId
        case .icloud:
            return privateCloudKitUserId
        case .off:
            return nil
        }
    }

    nonisolated static func shouldDeleteLeadFromCloud(
        provider: CloudSyncProvider,
        isAuthenticated: Bool
    ) -> Bool {
        provider == .icloud || shouldDeleteLeadFromFirebase(provider: provider, isAuthenticated: isAuthenticated)
    }

    nonisolated static func markLeadDeletedLocally(_ id: UUID, userDefaults: UserDefaults = .standard) {
        LeadDeletionTombstoneStore.markDeleted([id], in: userDefaults, key: deletedLeadIdsKey)
    }
    
    func startSync(includeAppointments: Bool = true) {
        let provider = CloudSyncProvider.current

        guard provider != .off else {
            DispatchQueue.main.async {
                if self.syncStatus == .syncing || self.lastSyncDate != nil {
                    self.syncStatus = .idle
                }
            }
            AppointmentManager.shared.stopFirebaseListener()
            print("⏭️ Cloud sync skipped: \(provider.displayName) sync mode active")
            return
        }

        if provider == .firebase && !firebaseService.isAuthenticated {
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

        if provider == .firebase && firebaseService.currentUser == nil {
            DispatchQueue.main.async {
                // Only show failed if we were actively trying to sync
                if self.syncStatus == .syncing {
                    self.syncStatus = .failed("No current user available")
                }
            }
            print("❌ Sync failed: No current user")
            return
        }

        let request = PersonalSyncRequest(
            provider: provider,
            includeAppointments: includeAppointments
        )
        guard syncExecutionGate.request(request) else {
            print("♻️ Personal cloud sync request coalesced with the active run")
            return
        }

        launchSync(request)
    }

    private func launchSync(_ request: PersonalSyncRequest) {
        switch request.provider {
        case .icloud:
            AppointmentManager.shared.stopFirebaseListener()
            print("☁️ Starting iCloud lead sync")
        case .firebase:
            print("🔄 Starting sync for user: \(firebaseService.currentUser?.uid ?? "unknown")")
        case .off:
            syncExecutionGate = PersonalSyncExecutionGate()
            return
        }

        activeSyncTask = Task { [weak self] in
            guard let self else { return }

            switch request.provider {
            case .icloud:
                await self.performCloudKitOnlySync(includeAppointments: request.includeAppointments)
            case .firebase:
                await self.performSync(includeAppointments: request.includeAppointments)
            case .off:
                break
            }

            self.finishSyncExecution()
        }
    }

    private func finishSyncExecution() {
        activeSyncTask = nil
        guard let pendingRequest = syncExecutionGate.finishActiveRequest() else { return }
        launchSync(pendingRequest)
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
        
        // Load auto-sync enabled state (default to true for new users)
        if UserDefaults.standard.object(forKey: "auto_sync_enabled") != nil {
            isAutoSyncEnabled = UserDefaults.standard.bool(forKey: "auto_sync_enabled")
        } else {
            isAutoSyncEnabled = true
        }
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

    func reloadSyncSettingsFromUserDefaults() {
        loadSyncSettings()
        restartSyncTimer()
    }

    func activateAutoSyncTimerIfNeeded() {
        guard !hasActivatedAutoSyncTimer else { return }
        hasActivatedAutoSyncTimer = true
        startSyncTimer()
    }
    
    func toggleAutoSync(_ enabled: Bool) {
        isAutoSyncEnabled = enabled
        saveSyncSettings()
        
        if enabled {
            hasActivatedAutoSyncTimer = true
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
            Task { @MainActor in
                self?.performScheduledSync()
            }
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
        let provider = CloudSyncProvider.current

        guard provider != .off else {
            print("⏰ Skipping scheduled sync - cloud sync is off")
            return
        }

        if provider == .firebase {
            guard firebaseService.isAuthenticated else {
                print("⏰ Skipping scheduled sync - user not authenticated")
                return
            }
        }

        print("⏰ Performing scheduled \(provider.displayName) sync (\(syncInterval.displayName))...")
        startSync()
    }
    
    func syncBeforeSignOut() {
        guard firebaseService.isAuthenticated else {
            print("🚪 Skipping sign-out sync - user not authenticated")
            return
        }
        
        print("🚪 Performing sync before sign out...")
        startSync(includeAppointments: false)
    }
    
    func syncWithServer() {
        // Start appointment Firebase listener for complete sync
        AppointmentManager.shared.restartFirebaseSync()
        
        // Start general data sync (including appointments)
        startSync()
    }

    func migratePersonalDataToICloud() async throws -> PersonalCloudMigrationSummary {
        guard !syncStatus.isBusy, !syncExecutionGate.isActive else {
            throw PersonalCloudMigrationError.migrationAlreadyRunning
        }

        let sourceProvider = CloudSyncProvider.current
        var firebaseLeadCount = 0

        syncStatus = .syncing

        do {
            await cleanupCorruptedLeads()

            if PersonalCloudMigrationPolicy.needsFirebaseMerge(current: sourceProvider) {
                guard firebaseService.isAuthenticated,
                      let userId = firebaseService.currentUser?.uid else {
                    throw PersonalCloudMigrationError.firebaseSignInRequired
                }

                PersonalCloudMigrationStateStore.setPhase(.firebaseMerge)

                // Download first so a newer local record is never overwritten by
                // an older copy uploaded from this device.
                let downloadSummary = try await downloadLeadsFromFirestore(userId: userId)
                firebaseLeadCount = downloadSummary.remoteCount

                let mergedFirebasePayloads = try await fetchLeadSyncPayloads()
                try await uploadLeadsToFirestore(userId: userId, payloads: mergedFirebasePayloads)

                let appointmentSnapshot = try await db.collection("users")
                    .document(userId)
                    .collection("appointments")
                    .getDocuments()
                let remoteAppointments = appointmentSnapshot.documents.compactMap { document in
                    try? document.data(as: Appointment.self)
                }
                AppointmentManager.shared.mergeAppointmentsForMigration(
                    remoteAppointments,
                    preferIncoming: true
                )
                await AppointmentManager.shared.syncAllAppointmentsToFirebase()
            }

            PersonalCloudMigrationStateStore.setPhase(.iCloudUpload)

            // Merge any prior private iCloud backup before writing the union.
            _ = try await restoreLeadsFromCloudKitBackup(userId: Self.privateCloudKitUserId)
            let iCloudPayloads = try await fetchLeadSyncPayloads()
            let uploadedLeadCount = try await uploadLeadsToCloudKitBackupStrict(
                userId: Self.privateCloudKitUserId,
                payloads: iCloudPayloads
            )
            let appointmentCount = try await AppointmentManager.shared.migrateAppointmentsToPrivateICloud()

            // The provider flag is the final commit point. Firebase records are
            // intentionally retained as a non-authoritative legacy backup.
            PersonalCloudMigrationStateStore.setPhase(.completed)
            CloudSyncProvider.current = .icloud
            AppointmentManager.shared.restartFirebaseSync()
            syncStatus = .completed
            lastSyncDate = Date()

            return PersonalCloudMigrationSummary(
                firebaseLeadCount: firebaseLeadCount,
                iCloudLeadCount: uploadedLeadCount,
                appointmentCount: appointmentCount
            )
        } catch {
            syncStatus = .failed(error.localizedDescription)
            throw error
        }
    }

    private func performCloudKitOnlySync(includeAppointments: Bool = true) async {
        await MainActor.run {
            syncStatus = .syncing
        }
        AppLog.event(.cloudSync, .syncStarted)

        do {
            print("☁️ Starting iCloud background sync operations...")
            await cleanupCorruptedLeads()

            let userId = Self.privateCloudKitUserId
            let restoredCount = try await restoreLeadsFromCloudKitBackup(userId: userId)
            if restoredCount > 0 {
                print("☁️ Restored \(restoredCount) leads from CloudKit backup before upload")
            }

            let leadPayloads = try await fetchLeadSyncPayloads()
            let uploadedCount = try await uploadLeadsToCloudKitBackupStrict(userId: userId, payloads: leadPayloads)
            print("☁️ iCloud lead backup upload completed: \(uploadedCount) leads")

            if includeAppointments {
                await AppointmentManager.shared.syncAllAppointmentsToFirebase()
            } else {
                print("🗓️ Skipping appointment sync as requested")
            }

            await MainActor.run {
                syncStatus = .completed
                lastSyncDate = Date()
            }
            AppLog.event(.cloudSync, .syncCompleted)
            print("✅ iCloud data sync completed successfully")
        } catch {
            await MainActor.run {
                print("⚠️ iCloud data sync failed: \(error.localizedDescription)")
                syncStatus = .failed(error.localizedDescription)
            }
            AppLog.warning("Sync", "iCloud data sync failed: \(error.localizedDescription)")
        }
    }
    
    private func performSync(includeAppointments: Bool = true) async {
        // Update status on main thread
        await MainActor.run {
            syncStatus = .syncing
        }
        AppLog.event(.cloudSync, .syncStarted)
        
        let retryOperation = RetryableOperation(maxRetries: 3, retryDelay: 2.0)
        
        do {
            try await retryOperation.execute(
                operation: { [self] in
                    // Check authentication before each operation
                    guard firebaseService.isAuthenticated, let userId = firebaseService.currentUser?.uid else {
                        throw SyncError.notAuthenticated
                    }

                    // Keep account/profile preferences mirrored alongside lead data sync.
                    await self.firebaseService.syncCurrentAccountProfileToClouds()
                    
                    // Perform sync operations on background thread
                    print("🔄 Starting background sync operations...")
                    
                    // Clean up any corrupted leads first
                    await self.cleanupCorruptedLeads()
                    
                    // Check auth again before upload
                    guard firebaseService.isAuthenticated else {
                        throw SyncError.notAuthenticated
                    }

                    let leadPayloads = try await self.fetchLeadSyncPayloads()

                    // Keep a CloudKit mirror as a second independent backup channel.
                    await self.uploadLeadsToCloudKitBackup(userId: userId, payloads: leadPayloads)

                    try await self.uploadLeadsToFirestore(userId: userId, payloads: leadPayloads)
                    
                    // Check auth again before download
                    guard firebaseService.isAuthenticated else {
                        throw SyncError.notAuthenticated
                    }
                    
                    // Download leads from Firebase (background operation)
                    do {
                        let downloadSummary = try await self.downloadLeadsFromFirestore(userId: userId)
                        if downloadSummary.remoteCount == 0 {
                            _ = await self.restoreLeadsFromCloudKitBackupIfPossible(userId: userId, reason: "Firestore lead collection was empty")
                        }
                    } catch {
                        print("⚠️ Firebase lead download failed: \(error.localizedDescription)")
                        let restoredCount = await self.restoreLeadsFromCloudKitBackupIfPossible(
                            userId: userId,
                            reason: "Firebase lead download failed"
                        )
                        if restoredCount == 0 {
                            throw error
                        }
                    }
                    
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
            AppLog.event(.cloudSync, .syncCompleted)
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
                    AppLog.warning("Sync", "Personal data sync failed: \(error.localizedDescription)")
                }
            }
        }
    }
    
    private func fetchLeadSyncPayloads() async throws -> [LeadSyncPayload] {
        let container = PersistenceController.shared.container
        let backgroundContext = container.newBackgroundContext()

        return try await backgroundContext.perform {
            let fetchRequest: NSFetchRequest<Lead> = Lead.fetchRequest(in: backgroundContext)
            let leads = try backgroundContext.fetch(fetchRequest)

            var payloads: [LeadSyncPayload] = []
            var generatedMissingIds = 0
            var generatedMissingCheckInIds = 0

            for lead in leads {
                let leadId: UUID
                if let existingId = lead.id {
                    leadId = existingId
                } else {
                    let generatedId = UUID()
                    lead.id = generatedId
                    leadId = generatedId
                    generatedMissingIds += 1
                }

                let createdDate = lead.createdDate ?? lead.dateCreated ?? Date()
                let updatedDate = lead.updatedDate ?? lead.dateModified ?? createdDate

                // Keep legacy/modern date fields aligned to prevent drift.
                lead.createdDate = createdDate
                lead.dateCreated = createdDate
                lead.updatedDate = updatedDate
                lead.dateModified = updatedDate

                let checkInObjects = (lead.checkIns?.allObjects as? [FollowUpCheckIn] ?? [])
                    .sorted { ($0.checkInDate ?? Date.distantPast) < ($1.checkInDate ?? Date.distantPast) }

                var checkInPayloads: [LeadCheckInSyncPayload] = []
                checkInPayloads.reserveCapacity(checkInObjects.count)

                for checkIn in checkInObjects {
                    let checkInId: UUID
                    if let existingCheckInId = checkIn.id {
                        checkInId = existingCheckInId
                    } else {
                        let generatedCheckInId = UUID()
                        checkIn.id = generatedCheckInId
                        checkInId = generatedCheckInId
                        generatedMissingCheckInIds += 1
                    }

                    let checkInDate = checkIn.checkInDate ?? updatedDate
                    if checkIn.checkInDate == nil {
                        checkIn.checkInDate = checkInDate
                    }

                    let normalizedCheckInType = UserDataSyncManager.normalizedCheckInType(checkIn.checkInType)
                    if checkIn.checkInType != normalizedCheckInType {
                        checkIn.checkInType = normalizedCheckInType
                    }

                    checkInPayloads.append(
                        LeadCheckInSyncPayload(
                            id: checkInId,
                            checkInDate: checkInDate,
                            checkInType: normalizedCheckInType,
                            outcome: UserDataSyncManager.optionalTrimmedString(checkIn.outcome),
                            notes: UserDataSyncManager.optionalTrimmedString(checkIn.notes),
                            scheduledNextFollowUp: checkIn.scheduledNextFollowUp
                        )
                    )
                }

                payloads.append(
                    LeadSyncPayload(
                        id: leadId,
                        name: lead.name ?? "",
                        address: lead.address ?? "",
                        phone: lead.phone ?? "",
                        email: lead.email ?? "",
                        latitude: lead.latitude,
                        longitude: lead.longitude,
                        status: UserDataSyncManager.normalizeLeadStatus(lead.status ?? Lead.Status.notContacted.rawValue),
                        notes: lead.notes ?? "",
                        createdDate: createdDate,
                        updatedDate: updatedDate,
                        priority: lead.priority,
                        source: lead.source ?? "",
                        estimatedValue: lead.estimatedValue,
                        price: lead.price,
                        tags: lead.tags ?? "",
                        visitCount: lead.visitCount,
                        serviceCategory: UserDataSyncManager.optionalTrimmedString(lead.serviceCategory),
                        neighborhoodId: UserDataSyncManager.optionalTrimmedString(lead.neighborhoodId),
                        lastContactDate: lead.lastContactDate,
                        followUpDate: lead.followUpDate,
                        checkIns: checkInPayloads
                    )
                )
            }

            if generatedMissingIds > 0 || generatedMissingCheckInIds > 0 || backgroundContext.hasChanges {
                try backgroundContext.save()
            }

            if generatedMissingIds > 0 {
                print("🔧 Assigned IDs to \(generatedMissingIds) leads before cloud sync")
            }
            if generatedMissingCheckInIds > 0 {
                print("🔧 Assigned IDs to \(generatedMissingCheckInIds) follow-up check-ins before cloud sync")
            }

            return payloads
        }
    }

    private func uploadLeadsToCloudKitBackup(userId: String, payloads: [LeadSyncPayload]) async {
        do {
            let uploadedCount = try await uploadLeadsToCloudKitBackupStrict(userId: userId, payloads: payloads)
            print("☁️ CloudKit backup upload completed: \(uploadedCount) leads")
        } catch {
            print("⚠️ CloudKit backup upload skipped: \(error.localizedDescription)")
        }
    }

    private func uploadLeadsToCloudKitBackupStrict(userId: String, payloads: [LeadSyncPayload]) async throws -> Int {
        guard let cloudKitBackupService else {
            throw CloudKitLeadBackupError.containerUnavailable(CloudKitLeadBackupService.containerIdentifier)
        }

        return try await cloudKitBackupService.uploadLeads(payloads, for: userId)
    }

    private func uploadLeadsToFirestore(userId: String, payloads: [LeadSyncPayload]) async throws {
        print("📤 Uploading leads to Firebase...")

        let namedLeadCount = payloads.filter { !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count
        let unnamedLeadCount = payloads.count - namedLeadCount

        print("📤 Syncing \(payloads.count) leads: \(namedLeadCount) contacts, \(unnamedLeadCount) visited houses")

        for payload in payloads {
            try await db.collection("users")
                .document(userId)
                .collection("leads")
                .document(payload.id.uuidString)
                .setData(payload.firestoreData, merge: true)
        }

        let duplicateIds = Dictionary(grouping: payloads.map(\.id), by: { $0 })
            .filter { $1.count > 1 }
        if !duplicateIds.isEmpty {
            print("⚠️ Found duplicate IDs in sync payload: \(duplicateIds.keys)")
        }

        print("📤 Upload completed: \(payloads.count) leads")
    }
    
    func deleteLeadFromCloud(leadId: String) async throws {
        let provider = CloudSyncProvider.current
        let firebaseUserId = firebaseService.currentUser?.uid ?? Auth.auth().currentUser?.uid
        let firestoreUserId = Self.shouldDeleteLeadFromFirebase(
            provider: provider,
            isAuthenticated: firebaseService.isAuthenticated
        ) ? firebaseUserId : nil
        let cloudKitUserId = Self.cloudKitLeadBackupUserId(
            provider: provider,
            isAuthenticated: firebaseService.isAuthenticated,
            currentUserId: firebaseUserId
        )

        if provider == .firebase && firestoreUserId == nil {
            throw SyncError.notAuthenticated
        }

        if let firestoreUserId {
            print("🗑️ Deleting lead \(leadId) from Firebase...")
            try await db.collection("users")
                .document(firestoreUserId)
                .collection("leads")
                .document(leadId)
                .delete()
            print("✅ Lead \(leadId) deleted from Firebase")
        }

        guard let leadUUID = UUID(uuidString: leadId), let cloudKitUserId else {
            return
        }

        do {
            guard let cloudKitBackupService else {
                throw CloudKitLeadBackupError.containerUnavailable(CloudKitLeadBackupService.containerIdentifier)
            }

            try await cloudKitBackupService.deleteLead(leadUUID, for: cloudKitUserId)
            print("☁️ Lead \(leadId) deleted from CloudKit backup")
        } catch {
            if provider == .icloud {
                throw error
            }
            print("⚠️ Failed to delete lead from CloudKit backup: \(error.localizedDescription)")
        }
    }

    func deleteLeadFromFirebase(leadId: String) async throws {
        try await deleteLeadFromCloud(leadId: leadId)
    }
    
    func clearSyncState() {
        print("🔄 Clearing sync manager state...")
        
        // Stop sync timer
        stopSyncTimer()
        
        DispatchQueue.main.async {
            self.syncStatus = .idle
            self.lastSyncDate = nil
            // Preserve user's auto-sync preference
        }
        
        print("✅ Sync manager state cleared")
    }
    
    deinit {
        syncTimer?.invalidate()
        syncTimer = nil
    }
    
    private struct LeadDownloadSummary {
        let remoteCount: Int
        let downloaded: Int
        let updated: Int
        let skipped: Int
    }

    private func downloadLeadsFromFirestore(userId: String) async throws -> LeadDownloadSummary {
        print("📥 Downloading leads from Firebase...")

        let snapshot = try await db.collection("users")
            .document(userId)
            .collection("leads")
            .getDocuments()

        // Clean up any existing leads with nil IDs before processing new data
        await cleanupCorruptedLeads()

        let container = PersistenceController.shared.container
        let backgroundContext = container.newBackgroundContext()
        let deletedLeadIds = Self.locallyDeletedLeadIds()

        let summary = try await backgroundContext.perform {
            var downloadedCount = 0
            var updatedCount = 0
            var skippedCount = 0

            for document in snapshot.documents {
                let mergeOutcome = try UserDataSyncManager.mergeLeadDocumentData(
                    document.data(),
                    documentId: document.documentID,
                    deletedLeadIds: deletedLeadIds,
                    in: backgroundContext
                )

                switch mergeOutcome {
                case .inserted:
                    downloadedCount += 1
                case .updated:
                    updatedCount += 1
                case .skipped:
                    skippedCount += 1
                }
            }

            if backgroundContext.hasChanges {
                try backgroundContext.save()
            }

            return LeadDownloadSummary(
                remoteCount: snapshot.documents.count,
                downloaded: downloadedCount,
                updated: updatedCount,
                skipped: skippedCount
            )
        }

        print("📥 Download completed: \(summary.downloaded) new leads, \(summary.updated) updated leads, \(summary.skipped) skipped")
        await refreshNotificationsAfterLeadDataMutationIfNeeded(
            inserted: summary.downloaded,
            updated: summary.updated
        )
        return summary
    }

    private func restoreLeadsFromCloudKitBackupIfPossible(userId: String, reason: String) async -> Int {
        do {
            let restoredCount = try await restoreLeadsFromCloudKitBackup(userId: userId)
            if restoredCount > 0 {
                print("☁️ Restored \(restoredCount) leads from CloudKit backup (\(reason))")
            } else {
                print("☁️ CloudKit backup had no leads to restore (\(reason))")
            }
            return restoredCount
        } catch {
            print("⚠️ CloudKit restore unavailable (\(reason)): \(error.localizedDescription)")
            return 0
        }
    }

    private func restoreLeadsFromCloudKitBackup(userId: String) async throws -> Int {
        guard let cloudKitBackupService else {
            throw CloudKitLeadBackupError.containerUnavailable(CloudKitLeadBackupService.containerIdentifier)
        }

        let backupPayloads = try await cloudKitBackupService.fetchLeads(for: userId)
        guard !backupPayloads.isEmpty else {
            return 0
        }

        let container = PersistenceController.shared.container
        let backgroundContext = container.newBackgroundContext()
        let deletedLeadIds = Self.locallyDeletedLeadIds()

        let restoredCount = try await backgroundContext.perform {
            var mergedCount = 0

            for payload in backupPayloads {
                let mergeOutcome = try UserDataSyncManager.mergeLeadDocumentData(
                    payload.syncDictionary,
                    documentId: payload.id.uuidString,
                    deletedLeadIds: deletedLeadIds,
                    in: backgroundContext
                )

                if case .skipped = mergeOutcome {
                    continue
                }
                mergedCount += 1
            }

            if backgroundContext.hasChanges {
                try backgroundContext.save()
            }

            return mergedCount
        }

        await refreshNotificationsAfterLeadDataMutationIfNeeded(
            inserted: restoredCount,
            updated: 0
        )
        return restoredCount
    }

    private func refreshNotificationsAfterLeadDataMutationIfNeeded(inserted: Int, updated: Int) async {
        guard NotificationService.shouldRefreshNotificationsAfterLeadDataMutation(
            inserted: inserted,
            updated: updated
        ) else { return }

        await MainActor.run {
            NotificationService.shared.refreshAllNotifications()
        }
    }

    private enum LeadMergeOutcome {
        case inserted
        case updated
        case skipped
    }

    nonisolated private static func mergeLeadDocumentData(
        _ data: [String: Any],
        documentId: String,
        deletedLeadIds: Set<UUID>,
        in context: NSManagedObjectContext
    ) throws -> LeadMergeOutcome {
        guard let documentUUID = UUID(uuidString: documentId) else {
            return .skipped
        }
        guard !LeadCloudMergePolicy.shouldSkipRemoteLead(
            documentId: documentId,
            deletedIds: deletedLeadIds
        ) else {
            return .skipped
        }

        let fetchRequest: NSFetchRequest<Lead> = Lead.fetchRequest(in: context)
        fetchRequest.predicate = NSPredicate(format: "id == %@", documentUUID as CVarArg)

        let existingLeads = try context.fetch(fetchRequest)
        let remoteModifiedDate = UserDataSyncManager.parseDateValue(data["updatedDate"])
            ?? UserDataSyncManager.parseDateValue(data["dateModified"])
            ?? UserDataSyncManager.parseDateValue(data["createdDate"])
            ?? UserDataSyncManager.parseDateValue(data["dateCreated"])
            ?? Date.distantPast

        if let existingLead = existingLeads.first {
            let localModifiedDate = existingLead.updatedDate ?? existingLead.dateModified ?? Date.distantPast

            if !LeadCloudMergePolicy.shouldApplyRemote(
                remoteModifiedDate: remoteModifiedDate,
                localModifiedDate: localModifiedDate
            ) {
                return .skipped
            }

            applyLeadDocumentData(data, to: existingLead)
            return .updated
        }

        let lead = Lead.create(in: context)
        lead.id = documentUUID
        applyLeadDocumentData(data, to: lead)
        return .inserted
    }

    nonisolated private static func locallyDeletedLeadIds(userDefaults: UserDefaults = .standard) -> Set<UUID> {
        LeadDeletionTombstoneStore.loadDeletedIds(from: userDefaults, key: deletedLeadIdsKey)
    }

    nonisolated private static func applyLeadDocumentData(_ data: [String: Any], to lead: Lead) {
        lead.name = UserDataSyncManager.optionalStringValue(data["name"])
        lead.address = UserDataSyncManager.optionalStringValue(data["address"])
        lead.phone = UserDataSyncManager.optionalStringValue(data["phone"])
        lead.email = UserDataSyncManager.optionalStringValue(data["email"])
        lead.latitude = UserDataSyncManager.parseDoubleValue(data["latitude"]) ?? 0.0
        lead.longitude = UserDataSyncManager.parseDoubleValue(data["longitude"]) ?? 0.0

        if let rawStatus = UserDataSyncManager.optionalStringValue(data["status"]) {
            lead.status = UserDataSyncManager.normalizeLeadStatus(rawStatus)
        } else {
            lead.status = Lead.Status.notContacted.rawValue
        }

        lead.notes = UserDataSyncManager.optionalStringValue(data["notes"])

        let createdDate = UserDataSyncManager.parseDateValue(data["createdDate"])
            ?? UserDataSyncManager.parseDateValue(data["dateCreated"])
            ?? lead.createdDate
            ?? lead.dateCreated
            ?? Date()
        let updatedDate = UserDataSyncManager.parseDateValue(data["updatedDate"])
            ?? UserDataSyncManager.parseDateValue(data["dateModified"])
            ?? lead.updatedDate
            ?? lead.dateModified
            ?? createdDate

        // Keep both date fields in sync for compatibility.
        lead.createdDate = createdDate
        lead.dateCreated = createdDate
        lead.updatedDate = updatedDate
        lead.dateModified = updatedDate

        lead.lastContactDate = UserDataSyncManager.parseDateValue(data["lastContactDate"])

        let mergedFollowUpDate = UserDataSyncManager.resolvedFollowUpDateForMerge(
            data,
            existingDate: lead.followUpDate
        )
        lead.followUpDate = lead.leadStatus.resolvedFollowUpDate(mergedFollowUpDate)

        lead.priority = UserDataSyncManager.parseInt16Value(data["priority"]) ?? 0
        lead.source = UserDataSyncManager.optionalStringValue(data["source"])
        lead.estimatedValue = UserDataSyncManager.parseDoubleValue(data["estimatedValue"]) ?? 0.0
        lead.price = UserDataSyncManager.parseDoubleValue(data["price"]) ?? 0.0
        lead.tags = UserDataSyncManager.optionalStringValue(data["tags"])
        lead.visitCount = UserDataSyncManager.parseInt16Value(data["visitCount"]) ?? 0
        lead.serviceCategory = UserDataSyncManager.optionalStringValue(data["serviceCategory"])
        lead.neighborhoodId = UserDataSyncManager.optionalStringValue(data["neighborhoodId"])

        // Check-ins are mirrored as nested payloads under each lead.
        // The schema flag avoids treating legacy payloads as authoritative empty arrays.
        let checkInsSchemaVersion = UserDataSyncManager.parseInt16Value(data["checkInsSchemaVersion"]) ?? 0
        if checkInsSchemaVersion > 0 {
            UserDataSyncManager.applyCheckInData(data["checkIns"], to: lead)
        }
    }

    nonisolated private static func applyCheckInData(_ value: Any?, to lead: Lead) {
        guard let normalizedCheckIns = parseCheckInArray(value) else {
            return
        }

        guard let context = lead.managedObjectContext else {
            return
        }

        let existingCheckIns = lead.checkIns?.allObjects as? [FollowUpCheckIn] ?? []
        var existingById: [UUID: FollowUpCheckIn] = [:]
        for checkIn in existingCheckIns {
            if let id = checkIn.id {
                existingById[id] = checkIn
            }
        }

        var seenIds = Set<UUID>()

        for payload in normalizedCheckIns {
            let checkIn = existingById[payload.id] ?? FollowUpCheckIn(context: context)
            checkIn.id = payload.id
            checkIn.lead = lead
            checkIn.checkInDate = payload.checkInDate
            checkIn.checkInType = normalizedCheckInType(payload.checkInType)
            checkIn.outcome = payload.outcome
            checkIn.notes = payload.notes
            checkIn.scheduledNextFollowUp = payload.scheduledNextFollowUp
            seenIds.insert(payload.id)
        }

        // The remote payload is authoritative for check-ins once present.
        for (checkInId, localCheckIn) in existingById where !seenIds.contains(checkInId) {
            context.delete(localCheckIn)
        }
    }

    nonisolated static func parseCheckInArray(_ value: Any?) -> [LeadCheckInSyncPayload]? {
        guard let value else { return nil }

        if let checkInMaps = value as? [[String: Any]] {
            return parseCheckInDictionaries(checkInMaps)
        }

        if let checkInValues = value as? [Any] {
            var maps: [[String: Any]] = []
            maps.reserveCapacity(checkInValues.count)

            for item in checkInValues {
                guard let itemMap = item as? [String: Any] else { return nil }
                maps.append(itemMap)
            }

            return parseCheckInDictionaries(maps)
        }

        if let jsonString = value as? String,
           let jsonData = jsonString.data(using: .utf8),
           let jsonObject = try? JSONSerialization.jsonObject(with: jsonData),
           let jsonArray = jsonObject as? [[String: Any]] {
            return parseCheckInDictionaries(jsonArray)
        }

        return nil
    }

    nonisolated static func resolvedFollowUpDateForMerge(
        _ data: [String: Any],
        existingDate: Date?
    ) -> Date? {
        guard data.keys.contains("followUpDate") else {
            // Legacy remote documents did not always include follow-up data. Keep
            // the local reminder unless the remote payload explicitly provides or
            // clears the field.
            return existingDate
        }

        return parseDateValue(data["followUpDate"])
    }

    nonisolated private static func parseCheckInDictionaries(_ dictionaries: [[String: Any]]) -> [LeadCheckInSyncPayload]? {
        var parsed: [LeadCheckInSyncPayload] = []
        parsed.reserveCapacity(dictionaries.count)

        for dictionary in dictionaries {
            guard let payload = parseCheckInDictionary(dictionary) else {
                return nil
            }
            parsed.append(payload)
        }

        return parsed
    }

    nonisolated private static func parseCheckInDictionary(_ dictionary: [String: Any]) -> LeadCheckInSyncPayload? {
        guard let rawId = optionalStringValue(dictionary["id"]) ?? optionalStringValue(dictionary["checkInId"]),
              let checkInId = UUID(uuidString: rawId) else {
            return nil
        }

        let checkInDate = parseDateValue(dictionary["checkInDate"]) ?? Date()
        let checkInType = normalizedCheckInType(optionalStringValue(dictionary["checkInType"]))
        let outcome = optionalStringValue(dictionary["outcome"])
        let notes = optionalStringValue(dictionary["notes"])
        let scheduledNextFollowUp = parseDateValue(dictionary["scheduledNextFollowUp"])

        return LeadCheckInSyncPayload(
            id: checkInId,
            checkInDate: checkInDate,
            checkInType: checkInType,
            outcome: outcome,
            notes: notes,
            scheduledNextFollowUp: scheduledNextFollowUp
        )
    }

    nonisolated private static func parseDateValue(_ value: Any?) -> Date? {
        if let date = value as? Date {
            return date
        }
        if let timestamp = value as? Timestamp {
            return timestamp.dateValue()
        }
        if let interval = value as? TimeInterval {
            return Date(timeIntervalSince1970: interval)
        }
        if let number = value as? NSNumber {
            return Date(timeIntervalSince1970: number.doubleValue)
        }
        if let string = value as? String {
            if let interval = TimeInterval(string) {
                return Date(timeIntervalSince1970: interval)
            }
            if let isoDate = iso8601DateFormatter.date(from: string) {
                return isoDate
            }
            if let isoDate = iso8601DateFormatterNoFractional.date(from: string) {
                return isoDate
            }
        }
        return nil
    }

    nonisolated private static func parseDoubleValue(_ value: Any?) -> Double? {
        if let double = value as? Double {
            return double
        }
        if let float = value as? Float {
            return Double(float)
        }
        if let int = value as? Int {
            return Double(int)
        }
        if let int64 = value as? Int64 {
            return Double(int64)
        }
        if let number = value as? NSNumber {
            return number.doubleValue
        }
        if let string = value as? String {
            return Double(string)
        }
        return nil
    }

    nonisolated private static func parseInt16Value(_ value: Any?) -> Int16? {
        if let int16 = value as? Int16 {
            return int16
        }
        if let int = value as? Int {
            return Int16(clamping: int)
        }
        if let int64 = value as? Int64 {
            return Int16(clamping: Int(int64))
        }
        if let double = value as? Double {
            return Int16(clamping: Int(double))
        }
        if let number = value as? NSNumber {
            return Int16(clamping: number.intValue)
        }
        if let string = value as? String, let int = Int(string) {
            return Int16(clamping: int)
        }
        return nil
    }

    nonisolated private static func optionalStringValue(_ value: Any?) -> String? {
        if let string = value as? String {
            return optionalTrimmedString(string)
        }
        if let number = value as? NSNumber {
            return optionalTrimmedString(number.stringValue)
        }
        return nil
    }

    nonisolated private static func optionalTrimmedString(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    nonisolated private static func normalizedCheckInType(_ value: String?) -> String {
        let normalized = optionalTrimmedString(value)?.lowercased() ?? FollowUpCheckIn.CheckInType.doorKnock.rawValue

        switch normalized {
        case "door_knock", "doorknock", "door":
            return FollowUpCheckIn.CheckInType.doorKnock.rawValue
        case "phone_call", "phonecall", "call":
            return FollowUpCheckIn.CheckInType.phoneCall.rawValue
        case "sms_message", "sms", "text":
            return FollowUpCheckIn.CheckInType.smsMessage.rawValue
        case "email", "mail":
            return FollowUpCheckIn.CheckInType.email.rawValue
        case "virtual_meeting", "virtual", "zoom", "meeting_virtual":
            return FollowUpCheckIn.CheckInType.virtualMeeting.rawValue
        case "in_person_meeting", "inperson", "meeting":
            return FollowUpCheckIn.CheckInType.inPersonMeeting.rawValue
        default:
            return FollowUpCheckIn.CheckInType.doorKnock.rawValue
        }
    }

    nonisolated(unsafe) private static let iso8601DateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    nonisolated(unsafe) private static let iso8601DateFormatterNoFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    // Normalize remote status strings to current app values
    nonisolated private static func normalizeLeadStatus(_ status: String) -> String {
        Lead.Status.normalizedRawValueOrDefault(from: status)
    }
    
    private func cleanupCorruptedLeads() async {
        print("🧹 Cleaning up corrupted leads...")
        
        let container = PersistenceController.shared.container
        let backgroundContext = container.newBackgroundContext()
        
        await backgroundContext.perform {
            let fetchRequest: NSFetchRequest<Lead> = Lead.fetchRequest(in: backgroundContext)
            
            do {
                let allLeads = try backgroundContext.fetch(fetchRequest)
                var corruptedCount = 0
                
                for lead in allLeads {
                    let trimmedName = lead.name?.trimmingCharacters(in: .whitespacesAndNewlines)
                    let trimmedAddress = lead.address?.trimmingCharacters(in: .whitespacesAndNewlines)
                    let hasName = trimmedName?.isEmpty == false
                    let hasAddress = trimmedAddress?.isEmpty == false
                    let hasId = lead.id != nil
                    
                    // Remove leads that are truly corrupted:
                    // 1. No ID (database corruption)
                    // 2. No name, address, or usable map coordinate.
                    let shouldDelete = UserDataSyncManager.shouldDeleteCorruptedLead(
                        hasId: hasId,
                        name: lead.name,
                        address: lead.address,
                        latitude: lead.latitude,
                        longitude: lead.longitude
                    )
                    
                    if shouldDelete {
                        let leadName = hasName ? (trimmedName ?? "No Name") : "No Name"
                        let leadAddress = hasAddress ? (trimmedAddress ?? "No Address") : "No Address"
                        let leadId = lead.id?.uuidString ?? "No ID"
                        
                        if !hasId {
                            print("🗑️ Removing lead with nil ID: \(Utilities.redactedText(leadName))")
                        } else {
                            let redactedName = Utilities.redactedText(leadName)
                            let redactedAddress = Utilities.redactedText(leadAddress)
                            print("🗑️ Removing corrupted lead with no name/address: \(redactedName) - \(redactedAddress) (ID: \(leadId))")
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

    nonisolated static func shouldDeleteCorruptedLead(
        hasId: Bool,
        name: String?,
        address: String?,
        latitude: Double,
        longitude: Double
    ) -> Bool {
        guard hasId else { return true }

        let hasName = optionalTrimmedString(name) != nil
        let hasAddress = optionalTrimmedString(address) != nil
        let hasCoordinate = isUsableLeadCoordinate(latitude: latitude, longitude: longitude)

        return !hasName && !hasAddress && !hasCoordinate
    }

    nonisolated private static func isUsableLeadCoordinate(latitude: Double, longitude: Double) -> Bool {
        guard latitude.isFinite, longitude.isFinite else { return false }
        guard (-90...90).contains(latitude), (-180...180).contains(longitude) else { return false }

        // Core Data's default zero coordinate is not a real saved doorstep.
        return latitude != 0 || longitude != 0
    }
    
    // MARK: - Appointment Sync Methods
    
    private func syncAppointments(userId: String) async throws {
        print("🗓️ Syncing appointments...")
        
        // The AppointmentManager now handles timing and listener management internally
        await AppointmentManager.shared.syncAllAppointmentsToFirebase()
        
        print("✅ Appointments sync completed")
    }
}
