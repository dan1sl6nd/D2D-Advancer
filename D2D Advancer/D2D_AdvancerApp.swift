//
//  D2D_AdvancerApp.swift
//  D2D Advancer
//
//  Created by Daniil Mukashev on 17/08/2025.
//

import SwiftUI
import UserNotifications
import FirebaseCore

@main
struct D2D_AdvancerApp: App {
    let persistenceController = PersistenceController.shared
    @StateObject private var userAccountManager = FirebaseUserAccountManager.shared
    @StateObject private var firebaseService = FirebaseService.shared
    @AppStorage("isDarkMode") private var isDarkMode = false

    init() {
        FirebaseApp.configure()
        print("🚀 D2D Advancer App Starting...")

        // Only request notification authorization if onboarding is completed
        let onboardingCompleted = UserDefaults.standard.bool(forKey: "onboarding_completed")
        if onboardingCompleted {
            print("📱 Onboarding completed - setting up notifications")
            requestNotificationAuthorization()
        } else {
            print("📱 Onboarding not completed yet - will request notification permission during onboarding")
            // Still set up categories so they're ready when permission is granted
            setupNotificationCategories()
        }

        // Start monitoring connectivity to auto-recover listeners/sync
        NetworkMonitor.shared.start()

        // Clean up any duplicate leads from Core Data
        Utilities.removeDuplicateLeads(from: persistenceController.container.viewContext)

        // Auto-enable guest mode on first launch if not logged in
        Task { @MainActor in
            if !FirebaseUserAccountManager.shared.isLoggedIn && !FirebaseUserAccountManager.shared.isGuestMode {
                FirebaseUserAccountManager.shared.startGuestMode()
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
                                    .foregroundColor(.orange)
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
            // No paywall needed; monetization disabled
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
                        ErrorHandler.shared.handle(error, context: "Notification Authorization")
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
