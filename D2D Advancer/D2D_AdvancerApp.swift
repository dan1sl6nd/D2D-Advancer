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
        if launchArguments.contains("-resetMessageTemplatesForUITests") {
            UserDefaults.standard.removeObject(forKey: "custom_message_templates")
            print("🧪 Message templates reset for UI tests")
        }
        if launchArguments.contains("-resetAppointmentTypesForUITests") {
            UserDefaults.standard.removeObject(forKey: "custom_appointment_types")
            print("🧪 Appointment types reset for UI tests")
        }
        if launchArguments.contains("-resetSyncSettingsForUITests") {
            CloudSyncProvider.current = .icloud
            UserDefaults.standard.set(true, forKey: "auto_sync_enabled")
            UserDefaults.standard.set(UserDataSyncManager.SyncInterval.oneHour.rawValue, forKey: "sync_interval")
            print("🧪 Sync settings reset for UI tests")
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

        if shouldShowOnboardingForUITests {
            OnboardingManager.shared.resetOnboarding(hard: true)
            OnboardingManager.shared.startOnboarding()
        }

        persistenceController = PersistenceController.shared
        _firebaseService = StateObject(wrappedValue: FirebaseService.shared)
        _userAccountManager = StateObject(wrappedValue: FirebaseUserAccountManager.shared)
        _appleSignInManager = StateObject(wrappedValue: AppleSignInManager.shared)

        if isRunningUITests {
            UIView.setAnimationsEnabled(false)
            if launchArguments.contains("-openMoreTabForUITests") {
                AppRouter.shared.selectedTab = 4
            } else if launchArguments.contains("-openAppointmentsTabForUITests") {
                AppRouter.shared.selectedTab = 3
            } else if launchArguments.contains("-openFollowUpTabForUITests") {
                AppRouter.shared.selectedTab = 2
            } else if launchArguments.contains("-openLeadsTabForUITests") {
                AppRouter.shared.selectedTab = 1
            } else if launchArguments.contains("-openMapTabForUITests") {
                AppRouter.shared.selectedTab = 0
            }
        }
        print("🚀 D2D Advancer App Starting...")

        // Check for Apple Search Ads attribution
        AppleSearchAdsAttribution.shared.checkAttribution()

        // Only request notification authorization if onboarding is completed
        let onboardingCompleted = UserDefaults.standard.bool(forKey: "onboarding_completed")
        if onboardingCompleted && !isRunningUITests {
            print("📱 Onboarding completed - setting up notifications")
            requestNotificationAuthorization()
        } else {
            print("📱 Onboarding not completed yet - will request notification permission during onboarding")
            // Still set up categories so they're ready when permission is granted
            setupNotificationCategories()
        }

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

    private func requestNotificationAuthorization() {
        // Set up notification categories first
        setupNotificationCategories()
        
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
            DispatchQueue.main.async {
                if granted {
                    print("Notification authorization granted.")
                } else {
                    print("Notification authorization denied.")
                    if let error = error {
                        print("Notification authorization error: \(error.localizedDescription)")
                    }
                }
            }
        }
    }
    
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
