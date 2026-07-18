//
//  D2D_AdvancerApp.swift
//  D2D Advancer
//
//  Created by Daniil Mukashev on 17/08/2025.
//

import SwiftUI
import UserNotifications
import FirebaseAuth
import FirebaseCore
import CoreData
import UIKit

@main
struct D2D_AdvancerApp: App {
    let persistenceController: PersistenceController
    @StateObject private var userAccountManager: FirebaseUserAccountManager
    @StateObject private var firebaseService: FirebaseService
    @StateObject private var appleSignInManager: AppleSignInManager
    @StateObject private var teamService: TeamFirebaseService
    @AppStorage("isDarkMode") private var isDarkMode = false
    init() {
        let launchArguments = ProcessInfo.processInfo.arguments
        let shouldSkipOnboardingForUITests = launchArguments.contains("-skipOnboardingForUITests")
        let shouldShowOnboardingForUITests = launchArguments.contains("-showOnboardingForUITests")
        let shouldResetOnboardingForUITests = launchArguments.contains("-resetOnboardingForUITests")
        let shouldCompleteOnboardingForLaunchTests = launchArguments.contains("-completeOnboardingForLaunchTests")
        let isRunningUITests = shouldSkipOnboardingForUITests || shouldShowOnboardingForUITests

        FirebaseBootstrap.configureIfNeeded()
        FirebaseEmulatorConfiguration.applyIfNeeded()

        if launchArguments.contains("-resetFirebaseAuthForUITests") {
            try? Auth.auth().signOut()
            UserDefaults.standard.removeObject(forKey: "isGuestMode")
            print("🧪 Firebase auth reset for UI tests")
        }
        #if DEBUG
        if launchArguments.contains("-resetTeamWorkspaceCacheForUITests") {
            TeamFirebaseService.resetCachedMembershipForUITests()
            print("🧪 Team workspace cache reset for UI tests")
        }
        #endif
        if launchArguments.contains("-resetMessageTemplatesForUITests") {
            UserDefaults.standard.removeObject(forKey: "custom_message_templates")
            print("🧪 Message templates reset for UI tests")
        }
        if launchArguments.contains("-resetAppointmentTypesForUITests") {
            UserDefaults.standard.removeObject(forKey: "custom_appointment_types")
            print("🧪 Appointment types reset for UI tests")
        }
        if launchArguments.contains("-resetUITestAppointments") {
            UserDefaults.standard.removeObject(forKey: "saved_appointments")
            UserDefaults.standard.removeObject(forKey: "deleted_appointment_ids")
            print("🧪 Appointments reset for UI tests")
        }
        if launchArguments.contains("-resetServiceCategoriesForUITests") {
            UserDefaults.standard.removeObject(forKey: "custom_service_categories")
            print("🧪 Service categories reset for UI tests")
        }
        if launchArguments.contains("-resetDefaultServiceForUITests") {
            UserDefaults.standard.removeObject(forKey: "defaultServiceCategoryID")
            print("🧪 Default service reset for UI tests")
        }
        if launchArguments.contains("-resetSyncSettingsForUITests") {
            CloudSyncProvider.current = .icloud
            UserDefaults.standard.set(true, forKey: "auto_sync_enabled")
            UserDefaults.standard.set(UserDataSyncManager.SyncInterval.oneHour.rawValue, forKey: "sync_interval")
            print("🧪 Sync settings reset for UI tests")
        }
        if launchArguments.contains("-resetSearchPresetsForUITests") {
            UserDefaults.standard.removeObject(forKey: "saved_search_presets")
            print("🧪 Search presets reset for UI tests")
        }
        if shouldResetOnboardingForUITests || shouldShowOnboardingForUITests {
            UserDefaults.standard.removeObject(forKey: "onboarding_completed")
            UserDefaults.standard.removeObject(forKey: "onboarding_profile")
            UserDefaults.standard.removeObject(forKey: "isPremiumUser")
            print("🧪 Onboarding reset for UI tests")
        }
        if shouldSkipOnboardingForUITests || shouldCompleteOnboardingForLaunchTests {
            UserDefaults.standard.set(true, forKey: "onboarding_completed")
        }
        if launchArguments.contains("-unlockPremiumForUITests") {
            UserDefaults.standard.set(true, forKey: "isPremiumUser")
        }
        if launchArguments.contains("-resetPremiumForUITests") {
            UserDefaults.standard.removeObject(forKey: "isPremiumUser")
            UserDefaults.standard.removeObject(forKey: "totalLeadCount")
        }
        if launchArguments.contains("-forceLightModeForUITests") {
            UserDefaults.standard.set(false, forKey: "isDarkMode")
        }
        if launchArguments.contains("-forceDarkModeForUITests") {
            UserDefaults.standard.set(true, forKey: "isDarkMode")
        }

        if shouldShowOnboardingForUITests {
            OnboardingManager.shared.resetOnboarding(hard: true)
            OnboardingManager.shared.startOnboarding()
        }

        persistenceController = PersistenceController.shared
        _firebaseService = StateObject(wrappedValue: FirebaseService.shared)
        _userAccountManager = StateObject(wrappedValue: FirebaseUserAccountManager.shared)
        _appleSignInManager = StateObject(wrappedValue: AppleSignInManager.shared)
        // Restore cached Team access before SwiftUI constructs MainTabView.
        _teamService = StateObject(wrappedValue: TeamFirebaseService.shared)

        #if DEBUG
        if isRunningUITests, launchArguments.contains("-resetUITestLeads") {
            Self.resetUITestLeadsWhenReady(using: persistenceController)
        }
        if launchArguments.contains("-seedMapPerformanceLeads") {
            Self.seedMapPerformanceLeadsWhenReady(using: persistenceController)
        }
        if launchArguments.contains("-seedAppStoreReviewData") {
            Self.seedAppStoreReviewDataWhenReady(using: persistenceController)
            Self.seedAppStoreReviewAppointments()
        }
        #endif

        if isRunningUITests {
            UIView.setAnimationsEnabled(false)
            if launchArguments.contains("-openTeamWorkspaceForUITests") {
                AppRouter.shared.openMore()
            } else if launchArguments.contains("-openMoreTabForUITests") {
                AppRouter.shared.openMore()
            } else if launchArguments.contains("-openAppointmentsTabForUITests") {
                AppRouter.shared.openAppointments()
            } else if launchArguments.contains("-openFollowUpTabForUITests") {
                AppRouter.shared.openFollowUps()
            } else if launchArguments.contains("-openLeadsTabForUITests") {
                AppRouter.shared.selectedTab = MainAppTab.leads.rawValue
            } else if launchArguments.contains("-openMapTabForUITests") {
                AppRouter.shared.selectedTab = MainAppTab.map.rawValue
            }
        }
        print("🚀 D2D Advancer App Starting...")

        // Check for Apple Search Ads attribution
        AppleSearchAdsAttribution.shared.checkAttribution()

        // Register actions at launch, but ask for notification access only after
        // the user schedules a follow-up or appointment.
        setupNotificationCategories()

        // Start monitoring connectivity to auto-recover listeners/sync
        if !isRunningUITests {
            NetworkMonitor.shared.start()
        }

        // Clean up duplicates on a background context once Core Data is ready.
        if !isRunningUITests {
            let persistence = persistenceController
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                guard persistence.hasPersistentStore else {
                    print("⏭️ Skipping duplicate cleanup: Core Data store not ready yet")
                    return
                }

                let cleanupContext = persistence.container.newBackgroundContext()
                cleanupContext.mergePolicy = NSMergePolicy.mergeByPropertyObjectTrump
                cleanupContext.perform {
                    do {
                        let sanitizedCount = try AppleContactLeadImportService.sanitizeImportedLeadNames(
                            in: cleanupContext
                        )
                        if cleanupContext.hasChanges {
                            try cleanupContext.save()
                        }
                        if sanitizedCount > 0 {
                            print("🧹 Sanitized \(sanitizedCount) Apple Contacts lead name(s)")
                        }
                    } catch {
                        print("⚠️ Apple Contacts lead-name cleanup failed: \(error.localizedDescription)")
                    }

                    Utilities.removeDuplicateLeads(from: cleanupContext)
                }
            }
        }

        Task<Void, Never> { @MainActor in
            if !isRunningUITests {
                AppleSignInManager.shared.verifyCredentialState()
            }

            let account = FirebaseUserAccountManager.shared
            #if DEBUG
            if await account.performTeamUITestAutoAuthIfNeeded() {
                return
            }
            #endif

            if !account.hasActiveSession && !account.isGuestMode {
                account.startGuestMode()
                print("👤 Auto-started guest mode for new user")
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            Group {
                #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("-openAppleContactImportForDeviceQA") {
                    NavigationStack {
                        AppleContactLeadImportView()
                    }
                } else {
                    ContentView()
                }
                #else
                ContentView()
                #endif
            }
            .environment(\.managedObjectContext, persistenceController.container.viewContext)
            .preferredColorScheme(isDarkMode ? .dark : .light)
            .customThemed()
            .alert("Save Password to Keychain", isPresented: $userAccountManager.shouldShowPasswordSavePrompt) {
                Button("Save to Keychain") {
                    userAccountManager.savePasswordFromPrompt()
                }
                Button("Never for This Account") {
                    userAccountManager.declinePasswordSave()
                }
                Button("Not Now", role: .cancel) {
                    userAccountManager.dismissPasswordSavePrompt()
                }
            } message: {
                Text("Save your password to iOS Keychain for secure autofill across all your devices? This will allow you to sign in quickly using Face ID, Touch ID, or your device passcode.")
            }
            .alert("Email Verification Required", isPresented: $userAccountManager.shouldShowEmailVerification) {
                switch userAccountManager.authStatus {
                case .loading:
                    // Show only dismiss button when loading
                    Button("Cancel", role: .cancel) {
                        userAccountManager.dismissEmailVerificationPrompt()
                    }
                case .success:
                    // Show only dismiss button when email was sent successfully
                    Button("OK") {
                        userAccountManager.dismissEmailVerificationPrompt()
                    }
                case .failed(_):
                    // Show retry and dismiss buttons when there's an error
                    Button("Try Again") {
                        userAccountManager.resendVerificationEmail()
                    }
                    Button("Remind Me Later", role: .cancel) {
                        userAccountManager.dismissEmailVerificationPrompt()
                    }
                case .idle:
                    // Show send and dismiss buttons for initial state
                    Button("Send Verification Email") {
                        userAccountManager.resendVerificationEmail()
                    }
                    Button("Remind Me Later", role: .cancel) {
                        userAccountManager.dismissEmailVerificationPrompt()
                    }
                }
            } message: {
                // Show different messages based on auth status
                switch userAccountManager.authStatus {
                case .loading:
                    Text("Sending verification email...")
                case .success:
                    Text("✅ Verification email sent! Check your inbox (including spam folder) and click the verification link.")
                case let .failed(error):
                    if error.lowercased().contains("security check") || error.lowercased().contains("blocked") || error.lowercased().contains("too many requests") {
                        VStack(spacing: 8) {
                            Text("🛡️ Security check triggered. This is a temporary protective measure.")
                            
                            // Show countdown timer if security block is active
                            if userAccountManager.isSecurityBlocked && userAccountManager.securityBlockTimeRemaining > 0 {
                                Text("⏰ Try again in: \(userAccountManager.formattedTimeRemaining)")
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .foregroundColor(Color.statusNotHome)
                            }
                        }
                    } else {
                        Text("❌ \(error)")
                    }
                case .idle:
                    Text("Please verify your email address to secure your account and access all features. Check your email for a verification link.")
                }
            }
            .errorAlert()
        }
    }

    #if DEBUG
    private static func resetUITestLeadsWhenReady(using persistenceController: PersistenceController, attemptsRemaining: Int = 20) {
        guard persistenceController.hasPersistentStore else {
            guard attemptsRemaining > 0 else {
                print("🧪 UI test lead reset skipped: Core Data store was not ready")
                return
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                resetUITestLeadsWhenReady(using: persistenceController, attemptsRemaining: attemptsRemaining - 1)
            }
            return
        }

        let context = persistenceController.container.viewContext
        let request = Lead.fetchRequest(in: context)
        request.predicate = uiTestLeadResetPredicate

        do {
            let testLeads = try context.fetch(request)
            testLeads.forEach(context.delete)
            if context.hasChanges {
                try context.save()
            }
            print("🧪 Reset \(testLeads.count) UI test lead(s)")
        } catch {
            context.rollback()
            print("🧪 UI test lead reset failed: \(error)")
        }
    }

    private static func seedMapPerformanceLeadsWhenReady(
        using persistenceController: PersistenceController,
        attemptsRemaining: Int = 40
    ) {
        guard persistenceController.hasPersistentStore else {
            guard attemptsRemaining > 0 else {
                print("Map performance fixture skipped: Core Data store was not ready")
                return
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                seedMapPerformanceLeadsWhenReady(
                    using: persistenceController,
                    attemptsRemaining: attemptsRemaining - 1
                )
            }
            return
        }

        let context = persistenceController.container.newBackgroundContext()
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        context.undoManager = nil

        context.perform {
            let request: NSFetchRequest<Lead> = Lead.fetchRequest()
            request.predicate = NSCompoundPredicate(orPredicateWithSubpredicates: [
                NSPredicate(format: "name BEGINSWITH %@", "Map Perf "),
                uiTestLeadResetPredicate
            ])
            request.fetchBatchSize = 500

            do {
                try context.fetch(request).forEach(context.delete)

                let now = Date()
                let centerLatitude = 37.7858
                let centerLongitude = -122.4064
                for index in 0..<2_000 {
                    let row = index / 50
                    let column = index % 50
                    let lead = Lead.create(in: context)
                    lead.id = UUID()
                    lead.name = "UI Map Perf \(index)"
                    lead.address = "\(1000 + index) Performance Test Way"
                    lead.latitude = centerLatitude + (Double(row - 20) * 0.00045)
                    lead.longitude = centerLongitude + (Double(column - 25) * 0.00045)
                    lead.createdDate = now.addingTimeInterval(TimeInterval(-index * 30))
                    lead.updatedDate = now.addingTimeInterval(TimeInterval(-index))
                    lead.priority = index.isMultiple(of: 17) ? 2 : 0
                    lead.estimatedValue = index.isMultiple(of: 23) ? Double(800 + index) : 0

                    switch index % 20 {
                    case 0:
                        lead.status = Lead.Status.converted.rawValue
                    case 1, 2:
                        lead.status = Lead.Status.interested.rawValue
                    case 3:
                        lead.status = Lead.Status.notHome.rawValue
                        lead.followUpDate = now.addingTimeInterval(-3_600)
                    default:
                        lead.status = Lead.Status.notContacted.rawValue
                    }
                }

                try context.save()
                print("Map performance fixture ready: 2000 leads")
            } catch {
                context.rollback()
                print("Map performance fixture failed: \(error.localizedDescription)")
            }
        }
    }

    private static var uiTestLeadResetPredicate: NSPredicate {
        NSCompoundPredicate(orPredicateWithSubpredicates: [
            NSPredicate(format: "name BEGINSWITH %@", "UI "),
            NSPredicate(format: "id IN %@", appStoreReviewLeadIds)
        ])
    }

    private static let appStoreReviewLeadIds: [UUID] = [
        UUID(uuidString: "A1000000-0000-4000-8000-000000000001")!,
        UUID(uuidString: "A1000000-0000-4000-8000-000000000002")!,
        UUID(uuidString: "A1000000-0000-4000-8000-000000000003")!,
        UUID(uuidString: "A1000000-0000-4000-8000-000000000004")!,
        UUID(uuidString: "A1000000-0000-4000-8000-000000000005")!,
        UUID(uuidString: "A1000000-0000-4000-8000-000000000006")!,
        UUID(uuidString: "A1000000-0000-4000-8000-000000000007")!,
        UUID(uuidString: "A1000000-0000-4000-8000-000000000008")!
    ]

    private static func seedAppStoreReviewDataWhenReady(
        using persistenceController: PersistenceController,
        attemptsRemaining: Int = 40
    ) {
        guard persistenceController.hasPersistentStore else {
            guard attemptsRemaining > 0 else {
                print("App Store review fixture skipped: Core Data store was not ready")
                return
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                seedAppStoreReviewDataWhenReady(
                    using: persistenceController,
                    attemptsRemaining: attemptsRemaining - 1
                )
            }
            return
        }

        struct DemoLead {
            let id: UUID
            let name: String
            let address: String
            let phone: String
            let email: String
            let latitude: Double
            let longitude: Double
            let status: Lead.Status
            let service: String
            let value: Double
            let priority: Int16
            let followUpOffset: TimeInterval?
            let notes: String
        }

        let leads = [
            DemoLead(
                id: UUID(uuidString: "A1000000-0000-4000-8000-000000000001")!,
                name: "Avery",
                address: "100 City Centre Dr, Mississauga, ON",
                phone: "(905) 555-0101",
                email: "avery@example.com",
                latitude: 43.5932,
                longitude: -79.6411,
                status: .converted,
                service: "Window Cleaning",
                value: 2_400,
                priority: 2,
                followUpOffset: nil,
                notes: "Sold package. Technician visit confirmed for tomorrow morning."
            ),
            DemoLead(
                id: UUID(uuidString: "A1000000-0000-4000-8000-000000000002")!,
                name: "Jordan",
                address: "201 City Centre Dr, Mississauga, ON",
                phone: "(905) 555-0102",
                email: "jordan@example.com",
                latitude: 43.5899,
                longitude: -79.6447,
                status: .interested,
                service: "Gutter Cleaning",
                value: 1_250,
                priority: 2,
                followUpOffset: 7_200,
                notes: "Interested in the spring service package. Follow up this afternoon."
            ),
            DemoLead(
                id: UUID(uuidString: "A1000000-0000-4000-8000-000000000003")!,
                name: "Morgan",
                address: "300 City Centre Dr, Mississauga, ON",
                phone: "(905) 555-0103",
                email: "morgan@example.com",
                latitude: 43.5878,
                longitude: -79.6423,
                status: .interested,
                service: "Exterior Cleaning",
                value: 980,
                priority: 1,
                followUpOffset: 86_400,
                notes: "Requested a written estimate and an afternoon arrival window."
            ),
            DemoLead(
                id: UUID(uuidString: "A1000000-0000-4000-8000-000000000004")!,
                name: "Taylor",
                address: "4141 Living Arts Dr, Mississauga, ON",
                phone: "(905) 555-0104",
                email: "taylor@example.com",
                latitude: 43.5908,
                longitude: -79.6475,
                status: .notHome,
                service: "Pressure Washing",
                value: 750,
                priority: 0,
                followUpOffset: -3_600,
                notes: "Customer was not home. Return after 5 PM."
            ),
            DemoLead(
                id: UUID(uuidString: "A1000000-0000-4000-8000-000000000005")!,
                name: "Casey",
                address: "1 City Centre Dr, Mississauga, ON",
                phone: "(905) 555-0105",
                email: "casey@example.com",
                latitude: 43.5964,
                longitude: -79.6381,
                status: .notContacted,
                service: "Window Cleaning",
                value: 0,
                priority: 0,
                followUpOffset: nil,
                notes: "New lead added from the map."
            ),
            DemoLead(
                id: UUID(uuidString: "A1000000-0000-4000-8000-000000000006")!,
                name: "Riley",
                address: "4100 Living Arts Dr, Mississauga, ON",
                phone: "(905) 555-0106",
                email: "riley@example.com",
                latitude: 43.5894,
                longitude: -79.6495,
                status: .converted,
                service: "Commercial Cleaning",
                value: 3_600,
                priority: 1,
                followUpOffset: nil,
                notes: "Annual service agreement signed."
            ),
            DemoLead(
                id: UUID(uuidString: "A1000000-0000-4000-8000-000000000007")!,
                name: "Sam",
                address: "200 City Centre Dr, Mississauga, ON",
                phone: "(905) 555-0107",
                email: "sam@example.com",
                latitude: 43.5910,
                longitude: -79.6390,
                status: .notHome,
                service: "Gutter Cleaning",
                value: 650,
                priority: 0,
                followUpOffset: 172_800,
                notes: "Leave a reminder for the weekend route."
            ),
            DemoLead(
                id: UUID(uuidString: "A1000000-0000-4000-8000-000000000008")!,
                name: "Jamie",
                address: "301 Burnhamthorpe Rd W, Mississauga, ON",
                phone: "(905) 555-0108",
                email: "jamie@example.com",
                latitude: 43.5864,
                longitude: -79.6460,
                status: .notContacted,
                service: "Exterior Cleaning",
                value: 0,
                priority: 0,
                followUpOffset: nil,
                notes: "Qualify during the next territory pass."
            )
        ]

        let context = persistenceController.container.newBackgroundContext()
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        context.undoManager = nil
        context.perform {
            let request: NSFetchRequest<Lead> = Lead.fetchRequest()
            request.predicate = NSPredicate(format: "source == %@", "App Store Demo")

            do {
                try context.fetch(request).forEach(context.delete)
                let now = Date()
                for (index, fixture) in leads.enumerated() {
                    let lead = Lead.create(in: context)
                    lead.id = fixture.id
                    lead.name = fixture.name
                    lead.address = fixture.address
                    lead.phone = fixture.phone
                    lead.email = fixture.email
                    lead.latitude = fixture.latitude
                    lead.longitude = fixture.longitude
                    lead.status = fixture.status.rawValue
                    lead.serviceCategory = fixture.service
                    lead.estimatedValue = fixture.value
                    lead.price = fixture.value
                    lead.priority = fixture.priority
                    lead.followUpDate = fixture.followUpOffset.map { now.addingTimeInterval($0) }
                    lead.notes = fixture.notes
                    lead.source = "App Store Demo"
                    lead.tags = "Sample"
                    lead.createdDate = now.addingTimeInterval(TimeInterval(-86_400 * (index + 1)))
                    lead.updatedDate = now.addingTimeInterval(TimeInterval(-900 * index))
                    lead.dateCreated = lead.createdDate
                    lead.dateModified = lead.updatedDate
                    lead.lastContactDate = index < 4 ? now.addingTimeInterval(-3_600) : nil
                    lead.visitCount = Int16(index < 4 ? 2 : 0)
                }

                try context.save()
                print("App Store review fixture ready: \(leads.count) leads")
            } catch {
                context.rollback()
                print("App Store review fixture failed: \(error.localizedDescription)")
            }
        }
    }

    private static func seedAppStoreReviewAppointments() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) ?? Date()
        func time(_ hour: Int, _ minute: Int = 0) -> Date {
            calendar.date(bySettingHour: hour, minute: minute, second: 0, of: tomorrow) ?? tomorrow
        }

        let appointments = [
            Appointment(
                id: UUID(uuidString: "B2000000-0000-4000-8000-000000000001")!,
                title: "Window Cleaning - Avery",
                notes: "Sold package. Bring exterior ladder and pure-water setup.",
                startDate: time(9, 30),
                endDate: time(11, 30),
                location: "100 City Centre Dr, Mississauga, ON",
                leadId: UUID(uuidString: "A1000000-0000-4000-8000-000000000001"),
                calendarEventId: nil,
                appointmentType: .installation,
                customAppointmentTypeId: nil,
                status: .confirmed
            ),
            Appointment(
                id: UUID(uuidString: "B2000000-0000-4000-8000-000000000002")!,
                title: "Gutter Estimate - Jordan",
                notes: "Review access points and confirm the final quote.",
                startDate: time(13),
                endDate: time(14),
                location: "201 City Centre Dr, Mississauga, ON",
                leadId: UUID(uuidString: "A1000000-0000-4000-8000-000000000002"),
                calendarEventId: nil,
                appointmentType: .consultation,
                customAppointmentTypeId: nil,
                status: .scheduled
            ),
            Appointment(
                id: UUID(uuidString: "B2000000-0000-4000-8000-000000000003")!,
                title: "Exterior Cleaning - Morgan",
                notes: "Customer requested an afternoon arrival window.",
                startDate: time(15, 30),
                endDate: time(17),
                location: "300 City Centre Dr, Mississauga, ON",
                leadId: UUID(uuidString: "A1000000-0000-4000-8000-000000000003"),
                calendarEventId: nil,
                appointmentType: .inspection,
                customAppointmentTypeId: nil,
                status: .scheduled
            )
        ]

        do {
            let data = try JSONEncoder().encode(appointments)
            UserDefaults.standard.set(data, forKey: "saved_appointments")
            UserDefaults.standard.removeObject(forKey: "deleted_appointment_ids")
            print("App Store review fixture ready: \(appointments.count) appointments")
        } catch {
            print("App Store appointment fixture failed: \(error.localizedDescription)")
        }
    }
    #endif

    private func setupNotificationCategories() {
        // Create actions for lead follow-up notifications
        let callAction = UNNotificationAction(
            identifier: "CALL_LEAD",
            title: "Call",
            options: [.foreground]
        )
        
        let messageAction = UNNotificationAction(
            identifier: "MESSAGE_LEAD",
            title: "Message",
            options: [.foreground]
        )
        
        let visitedAction = UNNotificationAction(
            identifier: "MARK_VISITED",
            title: "Mark as Visited",
            options: []
        )
        
        let snoozeAction = UNNotificationAction(
            identifier: "SNOOZE_FOLLOWUP",
            title: "Snooze (1 hour)",
            options: []
        )
        
        // Create appointment reminder actions
        let viewAction = UNNotificationAction(
            identifier: "VIEW_APPOINTMENT",
            title: "View",
            options: [.foreground]
        )

        let markCompleteAction = UNNotificationAction(
            identifier: "MARK_COMPLETE",
            title: "Mark Complete",
            options: []
        )

        // Create lead follow-up category
        let leadFollowUpCategory = UNNotificationCategory(
            identifier: "LEAD_FOLLOWUP",
            actions: [callAction, messageAction, visitedAction, snoozeAction],
            intentIdentifiers: [],
            options: []
        )

        // Create appointment reminder category
        let appointmentReminderCategory = UNNotificationCategory(
            identifier: "APPOINTMENT_REMINDER",
            actions: [viewAction, markCompleteAction],
            intentIdentifiers: [],
            options: []
        )

        // Create daily summary category
        let dailySummaryCategory = UNNotificationCategory(
            identifier: "DAILY_SUMMARY",
            actions: [],
            intentIdentifiers: [],
            options: []
        )

        // Register categories
        UNUserNotificationCenter.current().setNotificationCategories([
            leadFollowUpCategory,
            appointmentReminderCategory,
            dailySummaryCategory
        ])
        print("Notification categories registered successfully")
    }
    
    
}
