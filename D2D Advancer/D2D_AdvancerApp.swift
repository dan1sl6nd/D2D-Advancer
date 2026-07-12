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
        if launchArguments.contains("-resetServiceCategoriesForUITests") {
            UserDefaults.standard.removeObject(forKey: "custom_service_categories")
            print("🧪 Service categories reset for UI tests")
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

        if isRunningUITests, launchArguments.contains("-resetUITestLeads") {
            Self.resetUITestLeadsWhenReady(using: persistenceController)
        }

        #if DEBUG
        if launchArguments.contains("-seedMapPerformanceLeads") {
            Self.seedMapPerformanceLeadsWhenReady(using: persistenceController)
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
                Utilities.removeDuplicateLeads(from: cleanupContext)
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
            ContentView()
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
        request.predicate = NSPredicate(format: "name BEGINSWITH %@", "UI ")

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

    #if DEBUG
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
                NSPredicate(format: "name BEGINSWITH %@", "UI Map Perf ")
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
