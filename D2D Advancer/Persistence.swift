//
//  Persistence.swift
//  D2D Advancer
//
//  Created by Daniil Mukashev on 17/08/2025.
//

import CoreData

class PersistenceController {
    static let shared = PersistenceController()

    private static let managedObjectModel: NSManagedObjectModel = {
        guard let model = NSManagedObjectModel.mergedModel(from: [Bundle.main, Bundle(for: Lead.self)]) else {
            fatalError("Could not load D2D Advancer Core Data model")
        }
        return model
    }()

    @MainActor
    static let preview: PersistenceController = {
        let result = PersistenceController(inMemory: true)
        let viewContext = result.container.viewContext
        
        // Create sample leads for preview
        let sampleData = [
            ("John Doe", "555-0101", "not_contacted", 37.7749, -122.4194, 100.00),
            ("Jane Smith", "555-0102", "contacted", 37.7849, -122.4094, 250.00),
            ("Mike Johnson", "555-0103", "follow_up", 37.7649, -122.4294, 50.00),
            ("Sarah Wilson", "555-0104", "converted", 37.7549, -122.4394, 1200.00),
            ("David Brown", "555-0105", "not_interested", 37.7449, -122.4494, 0.00)
        ]
        
        for (name, phone, status, lat, lng, price) in sampleData {
            let newLead = Lead.create(in: viewContext)
            newLead.name = name
            newLead.phone = phone
            newLead.status = status
            newLead.latitude = lat
            newLead.longitude = lng
            newLead.price = price
            newLead.address = "\(Int.random(in: 100...999)) Sample St, San Francisco, CA"
            newLead.visitCount = Int16.random(in: 0...5)
        }
        
        do {
            try viewContext.save()
        } catch {
            let nsError = error as NSError
            print("❌ Preview save error: \(nsError), \(nsError.userInfo)")
            // Don't crash in preview mode - just log the error
        }
        return result
    }()

    let container: NSPersistentContainer
    private var didLoadPersistentStore = false
    
    var hasPersistentStore: Bool {
        didLoadPersistentStore && !container.persistentStoreCoordinator.persistentStores.isEmpty
    }

    init(inMemory: Bool = false) {
        container = NSPersistentContainer(name: "D2D_Advancer", managedObjectModel: Self.managedObjectModel)
        
        if inMemory {
            guard let description = container.persistentStoreDescriptions.first else {
                fatalError("No persistent store descriptions found in Core Data model")
            }
            description.url = URL(fileURLWithPath: "/dev/null")
        } else {
            // Configure local Core Data store options. CloudKit sync is handled
            // by dedicated backup services (not NSPersistentCloudKitContainer mirroring).
            guard let storeDescription = container.persistentStoreDescriptions.first else {
                fatalError("No persistent store descriptions found in Core Data model")
            }
            storeDescription.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
            storeDescription.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
            
            // Enable automatic lightweight migration
            storeDescription.setOption(true as NSNumber, forKey: NSMigratePersistentStoresAutomaticallyOption)
            storeDescription.setOption(true as NSNumber, forKey: NSInferMappingModelAutomaticallyOption)
        }
        
        container.loadPersistentStores(completionHandler: { [weak self] (storeDescription, error) in
            if let error = error as NSError? {
                self?.didLoadPersistentStore = false
                print("❌ Core Data error: \(error), \(error.userInfo)")
                
                // Attempt recovery by backing up and recreating store
                self?.handleCoreDataError(error: error)
                
                // Don't fatal error immediately - try recovery first
                print("⚠️ Attempting Core Data recovery...")
            } else {
                self?.didLoadPersistentStore = true
                print("✅ Persistent store loaded successfully: \(storeDescription)")
            }
        })
        
        container.viewContext.automaticallyMergesChangesFromParent = true
        
        let lastIntegrityCheck = UserDefaults.standard.object(
            forKey: StartupMaintenancePolicy.integrityCheckDateKey
        ) as? Date
        if StartupMaintenancePolicy.shouldRunIntegrityCheck(lastRunAt: lastIntegrityCheck) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) { [weak self] in
                guard let self else { return }
                guard self.performStartupDataCheck() else { return }
                UserDefaults.standard.set(
                    Date(),
                    forKey: StartupMaintenancePolicy.integrityCheckDateKey
                )
            }
        }
    }
    
    func save() {
        guard hasPersistentStore else {
            print("⚠️ Skipping Core Data save: persistent store is not loaded")
            return
        }
        
        let context = container.viewContext
        
        if context.hasChanges {
            do {
                try context.save()
                
                // Create automatic backup after successful save if follow-ups are involved
                checkAndBackupFollowUps()
                
            } catch {
                let nsError = error as NSError
                print("❌ Save failed: \(nsError), \(nsError.userInfo)")

                // Reset context to prevent corruption first
                context.rollback()

                // Try to recover follow-ups from backup after rollback
                restoreFollowUpsFromBackup()

                // Post notification to show error to user instead of crashing
                NotificationCenter.default.post(
                    name: NSNotification.Name("CoreDataSaveError"),
                    object: nil,
                    userInfo: ["error": nsError]
                )
            }
        }
    }
    
    private func checkAndBackupFollowUps() {
        guard hasPersistentStore else { return }
        
        let context = container.viewContext
        
        // Check if any follow-ups exist
        let followUpRequest: NSFetchRequest<Lead> = Lead.fetchRequest(in: context)
        followUpRequest.predicate = NSPredicate(format: "followUpDate != nil")
        
        do {
            let followUpCount = try context.count(for: followUpRequest)
            
            // Create backup if follow-ups exist and it's been more than 1 hour since last backup
            if followUpCount > 0 {
                let lastBackup = UserDefaults.standard.double(forKey: "LastBackupDate")
                let hourAgo = Date().timeIntervalSince1970 - 3600
                
                if lastBackup < hourAgo {
                    createDataBackup()
                }
            }
        } catch {
            print("❌ Error checking follow-ups: \(error)")
        }
    }
    
    func syncWithCloudKit() {
        // Core Data is local-only; this call currently just saves pending changes.
        save()
    }
    
    // MARK: - Data Protection & Recovery
    
    private func handleCoreDataError(error: NSError) {
        print("🔧 Handling Core Data error: \(error.localizedDescription)")
        
        // Create backup before attempting recovery
        createDataBackup()
        
        // Check if it's a migration error
        if error.domain == NSCocoaErrorDomain {
            switch error.code {
            case 134110: // Migration required
                print("📦 Core Data migration required")
                attemptDataMigration()
            case 134100: // Store incompatible
                print("🔄 Store incompatible, attempting to recreate")
                recreateDataStore()
            default:
                print("❓ Unknown Core Data error code: \(error.code)")
            }
        }
    }
    
    private func createDataBackup() {
        guard hasPersistentStore else {
            print("⚠️ Skipping backup: persistent store is not loaded")
            return
        }
        
        print("💾 Creating data backup...")
        
        let context = container.viewContext
        
        // Export follow-ups to UserDefaults as emergency backup
        let followUpRequest: NSFetchRequest<Lead> = Lead.fetchRequest(in: context)
        followUpRequest.predicate = NSPredicate(format: "followUpDate != nil")
        
        do {
            let leadsWithFollowUps = try context.fetch(followUpRequest)
            var backupData: [[String: Any]] = []
            
            for lead in leadsWithFollowUps {
                if let followUpDate = lead.followUpDate {
                    let backup: [String: Any] = [
                        "id": lead.id?.uuidString ?? UUID().uuidString,
                        "followUpDate": followUpDate.timeIntervalSince1970
                    ]
                    backupData.append(backup)
                }
            }
            
            let backupKey = "FollowUpBackup_\(Date().timeIntervalSince1970)"
            UserDefaults.standard.set(backupData, forKey: backupKey)
            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "LastBackupDate")
            pruneOldBackups(maxCount: 5)
            
            print("✅ Backup created with \(backupData.count) follow-ups")
            
        } catch {
            print("❌ Failed to create backup: \(error)")
        }
    }
    
    private func attemptDataMigration() {
        print("🔄 Attempting data migration...")
        // Migration is handled automatically by Core Data with the options we set
    }
    
    private func recreateDataStore() {
        print("🏗️ Recreating data store...")
        // This would be more complex in production - for now just log
        print("⚠️ Store recreation needed - data may be lost")
    }
    
    func restoreFollowUpsFromBackup() {
        guard hasPersistentStore else {
            print("⚠️ Skipping restore: persistent store is not loaded")
            return
        }
        
        print("🔧 Attempting to restore follow-ups from backup...")
        
        let keys = UserDefaults.standard.dictionaryRepresentation().keys
        let backupKeys = keys.filter { $0.hasPrefix("FollowUpBackup_") }
        
        guard let latestBackupKey = backupKeys.sorted().last,
              let backupData = UserDefaults.standard.array(forKey: latestBackupKey) as? [[String: Any]] else {
            print("❌ No backup data found")
            return
        }
        
        print("📂 Found backup with \(backupData.count) follow-ups")
        let context = container.viewContext
        var restoredCount = 0
        
        for backup in backupData {
            guard let idString = backup["id"] as? String,
                  let id = UUID(uuidString: idString),
                  let followUpTimestamp = backup["followUpDate"] as? TimeInterval else {
                continue
            }
            
            // Find existing lead
            let fetchRequest: NSFetchRequest<Lead> = Lead.fetchRequest(in: context)
            fetchRequest.predicate = NSPredicate(format: "id == %@", id as CVarArg)
            
            do {
                let existingLeads = try context.fetch(fetchRequest)
                if let existingLead = existingLeads.first,
                   existingLead.followUpDate == nil,
                   existingLead.leadStatus.allowsActiveFollowUp {
                    // Restore follow-up date only if it's missing
                    existingLead.followUpDate = Date(timeIntervalSince1970: followUpTimestamp)
                    restoredCount += 1
                    print("✅ Restored follow-up for: \(existingLead.displayName)")
                }
            } catch {
                print("❌ Error restoring lead \(idString): \(error)")
            }
        }
        
        if restoredCount > 0 {
            // Save directly to avoid recursive loop if called from save() error handler
            do {
                try context.save()
                print("✅ Successfully restored \(restoredCount) follow-ups")
                if NotificationService.shouldRefreshNotificationsAfterFollowUpRestore(restoredCount: restoredCount) {
                    Task { @MainActor in
                        NotificationService.shared.refreshAllNotifications()
                    }
                }
            } catch {
                print("❌ Failed to save restored follow-ups: \(error)")
                context.rollback()
            }
        }
    }
    
    @discardableResult
    private func performStartupDataCheck() -> Bool {
        guard hasPersistentStore else {
            print("⚠️ Skipping startup data check: persistent store is not loaded")
            return false
        }
        
        print("🔍 Performing startup data integrity check...")
        
        let context = container.viewContext
        guard normalizeLegacyStatuses(context) else { return false }
        
        // Check current follow-up count
        let followUpRequest: NSFetchRequest<Lead> = Lead.fetchRequest(in: context)
        followUpRequest.predicate = NSPredicate(format: "followUpDate != nil")
        
        do {
            let currentFollowUpCount = try context.count(for: followUpRequest)
            
            // Check if we have backup data
            let keys = UserDefaults.standard.dictionaryRepresentation().keys
            let backupKeys = keys.filter { $0.hasPrefix("FollowUpBackup_") }
            
            if let latestBackupKey = backupKeys.sorted().last,
               let backupData = UserDefaults.standard.array(forKey: latestBackupKey) as? [[String: Any]] {
                
                let backupFollowUpCount = backupData.count
                
                print("📊 Current follow-ups: \(currentFollowUpCount), Backup follow-ups: \(backupFollowUpCount)")
                
                // If we have significantly fewer follow-ups than backup, offer recovery
                if currentFollowUpCount == 0 && backupFollowUpCount > 0 {
                    print("⚠️ Follow-up data loss detected! Attempting automatic recovery...")
                    restoreFollowUpsFromBackup()
                } else if backupFollowUpCount > currentFollowUpCount + 3 {
                    print("⚠️ Potential follow-up data loss detected (backup has \(backupFollowUpCount - currentFollowUpCount) more)")
                    // Could trigger user notification here
                }
            } else {
                print("📝 No backup data found - creating initial backup if needed")
                if currentFollowUpCount > 0 {
                    createDataBackup()
                }
            }
            return true
        } catch {
            print("❌ Error during startup data check: \(error)")
            return false
        }
    }

    private func normalizeLegacyStatuses(_ context: NSManagedObjectContext) -> Bool {
        guard hasPersistentStore else { return false }
        
        // Map any legacy status strings (e.g., "sold", "closed") to current enum raw values
        let fetch: NSFetchRequest<Lead> = Lead.fetchRequest(in: context)
        fetch.predicate = NSPredicate(format: "status IN %@", ["sold", "closed", "close", "won"]) 
        do {
            let legacyLeads = try context.fetch(fetch)
            if !legacyLeads.isEmpty {
                for lead in legacyLeads {
                    lead.status = Lead.Status.converted.rawValue
                    lead.setFollowUpDate(nil, autoSave: false)
                }
                try context.save()
                print("✅ Normalized \(legacyLeads.count) legacy 'sold/closed' statuses to 'converted'")
            }
            return true
        } catch {
            print("❌ Failed normalizing legacy statuses: \(error)")
            return false
        }
    }

    private func pruneOldBackups(maxCount: Int) {
        let keys = UserDefaults.standard.dictionaryRepresentation().keys
            .filter { $0.hasPrefix("FollowUpBackup_") }
            .sorted()

        guard keys.count > maxCount else { return }

        let keysToDelete = keys.prefix(keys.count - maxCount)
        keysToDelete.forEach { UserDefaults.standard.removeObject(forKey: $0) }
    }
}
