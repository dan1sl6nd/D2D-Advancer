//
//  Persistence.swift
//  D2D Advancer
//
//  Created by Daniil Mukashev on 17/08/2025.
//

import CoreData
import CloudKit

class PersistenceController {
    static let shared = PersistenceController()

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
            fatalError("Unresolved error \(nsError), \(nsError.userInfo)")
        }
        return result
    }()

    let container: NSPersistentCloudKitContainer

    private init(inMemory: Bool = false) {
        container = NSPersistentCloudKitContainer(name: "D2D_Advancer")
        
        if inMemory {
            container.persistentStoreDescriptions.first!.url = URL(fileURLWithPath: "/dev/null")
        } else {
            // Configure CloudKit options and data protection
            let storeDescription = container.persistentStoreDescriptions.first!
            storeDescription.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
            storeDescription.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
            
            // Enable automatic lightweight migration
            storeDescription.setOption(true as NSNumber, forKey: NSMigratePersistentStoresAutomaticallyOption)
            storeDescription.setOption(true as NSNumber, forKey: NSInferMappingModelAutomaticallyOption)
            
            // Add CloudKit configuration for better sync reliability
            storeDescription.cloudKitContainerOptions?.databaseScope = .private
        }
        
        container.loadPersistentStores(completionHandler: { [weak self] (storeDescription, error) in
            if let error = error as NSError? {
                print("❌ Core Data error: \(error), \(error.userInfo)")
                
                // Attempt recovery by backing up and recreating store
                self?.handleCoreDataError(error: error)
                
                // Don't fatal error immediately - try recovery first
                print("⚠️ Attempting Core Data recovery...")
            } else {
                print("✅ Persistent store loaded successfully: \(storeDescription)")
            }
        })
        
        container.viewContext.automaticallyMergesChangesFromParent = true
        
        // Set up CloudKit sync notifications
        NotificationCenter.default.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification,
            object: container,
            queue: .main
        ) { notification in
            print("CloudKit event: \(notification)")
        }
        
        // Check for data recovery on app launch
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.performStartupDataCheck()
        }
    }
    
    func save() {
        let context = container.viewContext
        
        if context.hasChanges {
            do {
                try context.save()
                
                // Create automatic backup after successful save if follow-ups are involved
                checkAndBackupFollowUps()
                
            } catch {
                let nsError = error as NSError
                print("❌ Save failed: \(nsError), \(nsError.userInfo)")
                
                // Try to recover from backup before failing
                restoreFollowUpsFromBackup()
                
                fatalError("Unresolved error \(nsError), \(nsError.userInfo)")
            }
        }
    }
    
    private func checkAndBackupFollowUps() {
        let context = container.viewContext
        
        // Check if any follow-ups exist
        let followUpRequest: NSFetchRequest<Lead> = Lead.fetchRequest()
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
        // CloudKit sync is automatic with NSPersistentCloudKitContainer
        // This method can be used to trigger explicit sync if needed
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
        print("💾 Creating data backup...")
        
        let context = container.viewContext
        
        // Export follow-ups to UserDefaults as emergency backup
        let followUpRequest: NSFetchRequest<Lead> = Lead.fetchRequest()
        followUpRequest.predicate = NSPredicate(format: "followUpDate != nil")
        
        do {
            let leadsWithFollowUps = try context.fetch(followUpRequest)
            var backupData: [[String: Any]] = []
            
            for lead in leadsWithFollowUps {
                if let followUpDate = lead.followUpDate {
                    let backup: [String: Any] = [
                        "id": lead.id?.uuidString ?? UUID().uuidString,
                        "name": lead.name ?? "",
                        "followUpDate": followUpDate.timeIntervalSince1970,
                        "notes": lead.notes ?? "",
                        "phone": lead.phone ?? "",
                        "address": lead.address ?? ""
                    ]
                    backupData.append(backup)
                }
            }
            
            UserDefaults.standard.set(backupData, forKey: "FollowUpBackup_\(Date().timeIntervalSince1970)")
            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "LastBackupDate")
            
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
            let fetchRequest: NSFetchRequest<Lead> = Lead.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "id == %@", id as CVarArg)
            
            do {
                let existingLeads = try context.fetch(fetchRequest)
                if let existingLead = existingLeads.first, existingLead.followUpDate == nil {
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
            save()
            print("✅ Successfully restored \(restoredCount) follow-ups")
        }
    }
    
    private func performStartupDataCheck() {
        print("🔍 Performing startup data integrity check...")
        
        let context = container.viewContext
        normalizeLegacyStatuses(context)
        
        // Check current follow-up count
        let followUpRequest: NSFetchRequest<Lead> = Lead.fetchRequest()
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
            
        } catch {
            print("❌ Error during startup data check: \(error)")
        }
    }

    private func normalizeLegacyStatuses(_ context: NSManagedObjectContext) {
        // Map any legacy status strings (e.g., "sold", "closed") to current enum raw values
        let fetch: NSFetchRequest<Lead> = Lead.fetchRequest()
        fetch.predicate = NSPredicate(format: "status IN %@", ["sold", "closed", "close", "won"]) 
        do {
            let legacyLeads = try context.fetch(fetch)
            if !legacyLeads.isEmpty {
                for lead in legacyLeads {
                    lead.status = Lead.Status.converted.rawValue
                    lead.updatedDate = Date()
                }
                try context.save()
                print("✅ Normalized \(legacyLeads.count) legacy 'sold/closed' statuses to 'converted'")
            }
        } catch {
            print("❌ Failed normalizing legacy statuses: \(error)")
        }
    }
}
