import Foundation
import SwiftUI
import FirebaseAuth
import Combine
import CoreData

enum SignOutWorkspaceCleanupPolicy {
    static func shouldClearLocalWorkspaceData(provider: CloudSyncProvider) -> Bool {
        provider == .firebase
    }
}

@MainActor
class FirebaseUserAccountManager: ObservableObject {
    static let shared = FirebaseUserAccountManager()
    
    @Published var authStatus: AuthStatus = .idle
    @Published var isLoggedIn: Bool = false
    @Published var currentUserEmail: String?
    @Published var currentUserDisplayName: String?
    @Published var shouldShowPasswordSavePrompt = false
    @Published var shouldShowEmailVerification = false
    @Published var securityBlockTimeRemaining: Int = 0
    @Published var isSecurityBlocked = false
    @Published var isGuestMode: Bool = UserDefaults.standard.bool(forKey: "isGuestMode")
    @Published var appleUserIdentifier: String?
    @Published var appleUserEmail: String?
    @Published var appleUserFullName: String?
    
    private var lastRefreshTime: Date?
    private let refreshCooldownSeconds: TimeInterval = 30 // Only refresh every 30 seconds
    
    private let firebaseService = FirebaseService.shared
    private let keychainService = KeychainService.shared
    private var securityBlockTimer: Timer?
    
    private var pendingEmail: String?
    private var pendingPassword: String?
    
    enum AuthStatus: Equatable {
        case idle
        case loading
        case success
        case failed(String)
    }
    
    private init() {
        // Listen to Firebase auth state changes
        firebaseService.$isAuthenticated
            .receive(on: DispatchQueue.main)
            .assign(to: &$isLoggedIn)
        
        firebaseService.$currentUser
            .receive(on: DispatchQueue.main)
            .map { $0?.email }
            .assign(to: &$currentUserEmail)
        
        firebaseService.$currentUser
            .receive(on: DispatchQueue.main)
            .map { $0?.displayName }
            .assign(to: &$currentUserDisplayName)
        
        // Listen for email verification status changes
        firebaseService.$currentUser
            .receive(on: DispatchQueue.main)
            .sink { [weak self] user in
                if let user = user, user.isEmailVerified {
                    // User's email is verified, dismiss any verification prompts
                    self?.shouldShowEmailVerification = false
                    print("✅ Email verification detected - dismissing prompt")
                }
            }
            .store(in: &cancellables)
    }
    
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Authentication Methods
    
    func signUp(email: String, password: String, displayName: String? = nil) {
        guard !email.isEmpty && !password.isEmpty else {
            authStatus = .failed("Email and password are required")
            return
        }
        
        guard isValidEmail(email) else {
            authStatus = .failed("Please enter a valid email address")
            return
        }
        
        guard password.count >= 6 else {
            authStatus = .failed("Password must be at least 6 characters")
            return
        }
        
        authStatus = .loading
        
        Task {
            do {
                try await firebaseService.signUp(email: email, password: password, displayName: displayName)
                
                await MainActor.run {
                    self.authStatus = .success
                    // Only show email verification prompt if email is not already verified
                    if let user = self.firebaseService.currentUser,
                       !user.isEmailVerified,
                       !FirebaseEmulatorConfiguration.isEnabled {
                        self.shouldShowEmailVerification = true
                        print("📧 Email verification prompt shown for: \(Utilities.redactedEmail(email))")
                    }
                    
                    print("✅ Account created successfully for: \(Utilities.redactedEmail(email))")
                    if let displayName = displayName {
                        print("✅ Display name set to: \(displayName)")
                    }
                }
                
                // Start comprehensive sync immediately after successful sign-up
                await performPostSignInSync()
                
            } catch {
                await MainActor.run {
                    self.authStatus = .failed(self.parseAuthError(error))
                    ErrorHandler.shared.handleFirebaseError(error, context: "Sign Up")
                }
            }
        }
    }
    
    func signIn(email: String, password: String) {
        guard !email.isEmpty && !password.isEmpty else {
            authStatus = .failed("Email and password are required")
            return
        }
        
        guard isValidEmail(email) else {
            authStatus = .failed("Please enter a valid email address")
            return
        }
        
        authStatus = .loading
        
        Task {
            do {
                try await firebaseService.signIn(email: email, password: password)
                
                await MainActor.run {
                    self.authStatus = .success
                    self.pendingEmail = email
                    self.pendingPassword = password
                    
                    // Check if password should be saved to keychain
                    let hasCredentialsSaved = self.keychainService.hasCredentialsSaved(for: email)
                    let userDeclined = self.keychainService.hasUserDeclinedSaving(for: email)
                    
                    print("🔍 Keychain check for \(Utilities.redactedEmail(email)):")
                    print("   - Has credentials saved: \(hasCredentialsSaved)")
                    print("   - User previously declined: \(userDeclined)")
                    
                    // Only show prompt if:
                    // 1. Credentials are not already saved
                    // 2. User hasn't previously declined saving for this email
                    if !hasCredentialsSaved && !userDeclined {
                        self.shouldShowPasswordSavePrompt = true
                        print("   - Will show keychain prompt")
                    } else {
                        print("   - Will NOT show keychain prompt")
                    }
                    
                    print("✅ Signed in successfully: \(Utilities.redactedEmail(email))")
                }
                
                // Start comprehensive sync immediately after successful sign-in
                await performPostSignInSync()
                
            } catch {
                await MainActor.run {
                    self.authStatus = .failed(self.parseAuthError(error))
                    ErrorHandler.shared.handleFirebaseError(error, context: "Sign In")
                }
            }
        }
    }

    #if DEBUG
    func performTeamUITestAutoAuthIfNeeded() async -> Bool {
        let environment = ProcessInfo.processInfo.environment
        let arguments = ProcessInfo.processInfo.arguments
        guard FirebaseEmulatorConfiguration.isEnabled,
              arguments.contains("-teamUITestAutoAuth"),
              let email = environment["D2D_TEAM_TEST_AUTH_EMAIL"]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !email.isEmpty,
              let password = environment["D2D_TEAM_TEST_AUTH_PASSWORD"],
              !password.isEmpty else {
            return false
        }

        let displayName = environment["D2D_TEAM_TEST_AUTH_DISPLAY_NAME"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let shouldCreateAccount = environment["D2D_TEAM_TEST_AUTH_CREATE"] == "1"

        authStatus = .loading
        do {
            try? firebaseService.signOut()

            if shouldCreateAccount {
                do {
                    try await firebaseService.signUp(email: email, password: password, displayName: displayName)
                } catch {
                    print("🧪 Team UI test auto-auth create fell back to sign-in: \(error.localizedDescription)")
                    try await firebaseService.signIn(email: email, password: password)
                }
            } else {
                try await firebaseService.signIn(email: email, password: password)
            }

            isGuestMode = false
            UserDefaults.standard.set(false, forKey: "isGuestMode")
            shouldShowPasswordSavePrompt = false
            shouldShowEmailVerification = false
            pendingEmail = nil
            pendingPassword = nil
            authStatus = .success
            print("🧪 Team UI test auto-authenticated: \(Utilities.redactedEmail(email))")
        } catch {
            authStatus = .failed(parseAuthError(error))
            print("❌ Team UI test auto-auth failed: \(error.localizedDescription)")
        }

        return true
    }
    #endif
    
    func signOut() {
        Task {
            do {
                let syncProvider = CloudSyncProvider.current
                let shouldClearLocalWorkspaceData = SignOutWorkspaceCleanupPolicy.shouldClearLocalWorkspaceData(provider: syncProvider)

                print("🚪 Starting sign-out process...")
                print("🚪 Sign-out workspace cleanup policy: provider=\(syncProvider.displayName), clearLocalWorkspaceData=\(shouldClearLocalWorkspaceData)")
                print("🗓️ Current appointments before sign-out: \(AppointmentManager.shared.appointments.count)")

                // Ensure local appointment changes are uploaded before clearing local data.
                await syncAppointmentsBeforeSignOut()

                // Stop listener after sign-out sync. Only Firebase-mode sign-out
                // clears local workspace data; iCloud/local-only data must remain
                // on this device.
                AppointmentManager.shared.stopFirebaseListener()
                if shouldClearLocalWorkspaceData {
                    AppointmentManager.shared.clearAppointmentsLocalOnly()
                    print("🗓️ Appointments after clearing: \(AppointmentManager.shared.appointments.count)")
                }

                // Then sync all other non-appointment data to Firebase/CloudKit.
                await performPreSignOutSync()
                
                // Clear session state after sync is complete. Preserve local
                // workspace data for iCloud/local-only modes.
                await clearAllLocalData(clearWorkspaceData: shouldClearLocalWorkspaceData)
                
                // Sign out from Firebase
                try firebaseService.signOut()
                
                await MainActor.run {
                    AppleSignInManager.shared.signOut()
                    self.authStatus = .idle
                    self.shouldShowPasswordSavePrompt = false
                    self.shouldShowEmailVerification = false
                    print("✅ Signed out successfully")
                }
            } catch {
                await MainActor.run {
                    self.authStatus = .failed("Failed to sign out: \(error.localizedDescription)")
                    ErrorHandler.shared.handleFirebaseError(error, context: "Sign Out")
                }
            }
        }
    }
    
    private func performPreSignOutSync() async {
        // Check if user is still authenticated before attempting sync
        guard firebaseService.isAuthenticated else {
            print("ℹ️ User already signed out, skipping pre-sign-out sync")
            return
        }
        
        print("🔄 Syncing data before sign-out...")
        
        await MainActor.run {
            self.authStatus = .loading
        }
        
        // Trigger a sync and wait for completion using polling
        let syncManager = UserDataSyncManager.shared
        
        // Wait for any ongoing sync to complete first
        while syncManager.syncStatus == .syncing {
            // Double-check auth during wait
            guard firebaseService.isAuthenticated else {
                print("ℹ️ User signed out during sync wait, aborting")
                return
            }
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
        }
        
        // Final auth check before starting sync
        guard firebaseService.isAuthenticated else {
            print("ℹ️ User signed out before sync start, aborting")
            return
        }
        
        // Start our pre-sign-out sync with timeout handling (exclude appointments to preserve Firebase data)
        syncManager.syncBeforeSignOut()
        
        // Poll for sync completion with shorter timeout to prevent hanging.
        // Important: startSync launches async work, so initial status can remain idle briefly.
        var attempts = 0
        let maxAttempts = 20 // 10 seconds timeout (reduced from 30)
        var hasObservedSyncing = false
        
        while attempts < maxAttempts {
            // Check if user is still authenticated during sync
            guard firebaseService.isAuthenticated else {
                print("ℹ️ User signed out during sync, aborting gracefully")
                // Stop the sync manager to prevent further errors
                syncManager.pauseSync()
                return
            }
            
            let status = syncManager.syncStatus
            
            switch status {
            case .completed:
                print("✅ Pre-sign-out sync completed successfully")
                return
            case .failed(let error):
                print("⚠️ Pre-sign-out sync failed: \(error)")
                // Don't retry on failure - just proceed with sign out
                return
            case .syncing, .uploading, .downloading:
                hasObservedSyncing = true
                try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
                attempts += 1
            case .idle:
                if hasObservedSyncing {
                    // If it went back to idle after syncing, proceed with sign-out.
                    print("ℹ️ Sync completed or stopped, proceeding with sign-out")
                    return
                }

                // Sync task may not have started yet; wait briefly before deciding.
                try? await Task.sleep(nanoseconds: 250_000_000) // 0.25 seconds
                attempts += 1
            }
        }
        
        print("⚠️ Pre-sign-out sync timed out after 10 seconds, proceeding with sign-out")
        // Stop the sync to prevent errors after sign-out
        syncManager.pauseSync()
    }
    
    func deleteAccount(currentPassword: String) {
        guard !currentPassword.isEmpty else {
            authStatus = .failed("Password is required to delete account")
            return
        }
        
        authStatus = .loading
        
        Task {
            do {
                try await firebaseService.deleteAccount(currentPassword: currentPassword)
                
                // Clear all local data after successful account deletion
                await self.clearAllLocalData()
                
                await MainActor.run {
                    self.authStatus = .success
                    print("✅ Account deleted successfully")
                }
                
            } catch {
                await MainActor.run {
                    self.authStatus = .failed(self.parseAuthError(error))
                    ErrorHandler.shared.handleFirebaseError(error, context: "Delete Account")
                }
            }
        }
    }
    
    func resetPassword(email: String) {
        guard !email.isEmpty else {
            authStatus = .failed("Email is required")
            return
        }
        
        guard isValidEmail(email) else {
            authStatus = .failed("Please enter a valid email address")
            return
        }
        
        authStatus = .loading
        
        Task {
            do {
                try await firebaseService.resetPassword(email: email)
                
                await MainActor.run {
                    self.authStatus = .success
                    print("📧 Password reset email sent to: \(Utilities.redactedEmail(email))")
                }
                
            } catch {
                await MainActor.run {
                    self.authStatus = .failed(self.parseAuthError(error))
                    ErrorHandler.shared.handleFirebaseError(error, context: "Password Reset")
                }
            }
        }
    }
    
    func resendVerificationEmail() {
        // Reset status before starting
        authStatus = .idle
        authStatus = .loading
        
        Task {
            do {
                try await firebaseService.resendEmailVerification()
                
                await MainActor.run {
                    self.authStatus = .success
                    print("✅ Verification email sent")
                }
                
            } catch {
                await MainActor.run {
                    self.authStatus = .failed(self.parseAuthError(error))
                    ErrorHandler.shared.handleFirebaseError(error, context: "Send Verification")
                }
            }
        }
    }
    
    func updatePassword(currentPassword: String, newPassword: String) {
        guard !currentPassword.isEmpty && !newPassword.isEmpty else {
            authStatus = .failed("Both passwords are required")
            return
        }
        
        guard newPassword.count >= 6 else {
            authStatus = .failed("New password must be at least 6 characters")
            return
        }
        
        authStatus = .loading
        
        Task {
            do {
                try await firebaseService.updatePassword(
                    currentPassword: currentPassword,
                    newPassword: newPassword
                )
                
                await MainActor.run {
                    self.authStatus = .success
                    
                    // Update keychain if password was saved
                    if let email = self.currentUserEmail {
                        if self.keychainService.hasCredentialsSaved(for: email) {
                            let _ = self.keychainService.saveCredentials(email: email, password: newPassword)
                        }
                    }
                    
                    print("✅ Password updated successfully")
                }
                
            } catch {
                await MainActor.run {
                    self.authStatus = .failed(self.parseAuthError(error))
                    print("❌ Password update error: \(error)")
                }
            }
        }
    }
    
    // MARK: - Keychain Methods
    
    func savePasswordFromPrompt() {
        guard let email = pendingEmail, let password = pendingPassword else { return }
        
        let _ = keychainService.saveCredentials(email: email, password: password)
        shouldShowPasswordSavePrompt = false
        
        // Clear pending credentials
        pendingEmail = nil
        pendingPassword = nil
        
        print("✅ Password saved to keychain for: \(Utilities.redactedEmail(email))")
    }
    
    func declinePasswordSave() {
        guard let email = pendingEmail else { return }
        
        keychainService.markUserDeclinedSaving(for: email)
        shouldShowPasswordSavePrompt = false
        
        // Clear pending credentials
        pendingEmail = nil
        pendingPassword = nil
        
        print("⏭️ Password save declined permanently for: \(Utilities.redactedEmail(email))")
        print("   User will not be prompted again for this account")
    }
    
    func dismissPasswordSavePrompt() {
        shouldShowPasswordSavePrompt = false
        
        // Clear pending credentials without marking as declined
        // This allows the prompt to appear again next time they sign in
        pendingEmail = nil
        pendingPassword = nil
        
        print("⏭️ Password save prompt dismissed (will ask again next time)")
    }
    
    func dismissEmailVerificationPrompt() {
        shouldShowEmailVerification = false
        print("⏭️ Email verification prompt dismissed")
    }
    
    func getSavedPassword(for email: String) -> String? {
        return keychainService.getStoredCredentials(for: email)
    }
    
    func hasPassword(for email: String) -> Bool {
        return keychainService.hasCredentialsSaved(for: email)
    }
    
    func resetKeychainPreferences() {
        keychainService.resetAllKeychainPreferences()
        print("🔄 All keychain save preferences have been reset")
    }
    
    func clearKeychainPreference(for email: String) {
        keychainService.clearUserPreference(for: email)
        print("🔄 Keychain preference cleared for: \(Utilities.redactedEmail(email))")
    }
    
    func debugKeychainPreferences() {
        let defaults = UserDefaults.standard
        let allKeys = defaults.dictionaryRepresentation().keys
        
        let keychainKeys = allKeys.filter { 
            $0.hasPrefix("keychain_saved_") || $0.hasPrefix("user_declined_save_")
        }
        
        print("🔍 Debug: Current keychain preferences:")
        if keychainKeys.isEmpty {
            print("   No keychain preferences found")
        } else {
            for key in keychainKeys.sorted() {
                let value = defaults.bool(forKey: key)
                print("   \(key): \(value)")
            }
        }
    }
    
    // MARK: - Guest Mode Methods

    func startGuestMode() {
        isGuestMode = true
        UserDefaults.standard.set(true, forKey: "isGuestMode")
        authStatus = .idle
        print("👤 Guest mode activated - user can explore app without account")
    }

    func convertGuestToAccount(email: String, password: String, displayName: String? = nil) async throws {
        guard isGuestMode else {
            throw FirebaseService.FirebaseError.unknown("Not in guest mode")
        }

        guard !email.isEmpty && !password.isEmpty else {
            throw FirebaseService.FirebaseError.unknown("Email and password are required")
        }

        guard isValidEmail(email) else {
            throw FirebaseService.FirebaseError.unknown("Please enter a valid email address")
        }

        guard password.count >= 6 else {
            throw FirebaseService.FirebaseError.unknown("Password must be at least 6 characters")
        }

        await MainActor.run {
            self.authStatus = .loading
        }

        do {
            // Create the Firebase account
            try await firebaseService.signUp(email: email, password: password, displayName: displayName)

            await MainActor.run {
                print("✅ Account created from guest mode for: \(Utilities.redactedEmail(email))")
            }

            // Migrate all local data to Firebase
            await migrateGuestDataToFirebase()

            // Exit guest mode
            await MainActor.run {
                self.isGuestMode = false
                UserDefaults.standard.set(false, forKey: "isGuestMode")
                self.authStatus = .success

                // Show email verification prompt if email is not verified
                if let user = self.firebaseService.currentUser,
                   !user.isEmailVerified,
                   !FirebaseEmulatorConfiguration.isEnabled {
                    self.shouldShowEmailVerification = true
                    print("📧 Email verification prompt shown for: \(Utilities.redactedEmail(email))")
                }

                print("✅ Guest data migrated successfully to account: \(Utilities.redactedEmail(email))")
            }

            // Start comprehensive sync after conversion
            await performPostSignInSync()

        } catch {
            await MainActor.run {
                self.authStatus = .failed(self.parseAuthError(error))
            }
            throw error
        }
    }

    private func migrateGuestDataToFirebase() async {
        print("🔄 Starting guest data migration to Firebase...")

        // Force a comprehensive sync to upload all local data
        let syncManager = UserDataSyncManager.shared
        syncManager.syncWithServer()

        // Wait for sync to complete
        var attempts = 0
        let maxAttempts = 60 // 30 seconds timeout
        var hasObservedSyncing = false

        while attempts < maxAttempts {
            let status = syncManager.syncStatus

            switch status {
            case .completed:
                print("✅ Guest data migration completed successfully")
                return
            case .failed(let error):
                print("⚠️ Guest data migration sync failed: \(error)")
                return
            case .syncing, .uploading, .downloading:
                hasObservedSyncing = true
                try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
                attempts += 1
            case .idle:
                if hasObservedSyncing {
                    print("ℹ️ Sync completed or stopped")
                    return
                }

                // Sync task may not have started yet; wait briefly.
                try? await Task.sleep(nanoseconds: 250_000_000) // 0.25 seconds
                attempts += 1
            }
        }

        print("⚠️ Guest data migration timed out after 30 seconds")
    }

    func cancelGuestMode() {
        isGuestMode = false
        UserDefaults.standard.set(false, forKey: "isGuestMode")
        authStatus = .idle
        print("❌ Guest mode cancelled - returning to login screen")
    }

    // MARK: - Sign in with Apple Bridge

    var isAppleAuthed: Bool {
        appleUserIdentifier != nil
    }

    var hasActiveSession: Bool {
        isLoggedIn || isAppleAuthed
    }

    func bridgeAppleSignIn(userIdentifier: String, email: String?, fullName: String?) {
        appleUserIdentifier = userIdentifier
        appleUserEmail = email
        appleUserFullName = fullName

        if isGuestMode {
            isGuestMode = false
            UserDefaults.standard.set(false, forKey: "isGuestMode")
            print("🍎 Exited guest mode via Apple Sign In")
        }
        authStatus = .success
        print("🍎 Apple Sign In bridged into account manager")
    }

    func clearAppleBridge() {
        appleUserIdentifier = nil
        appleUserEmail = nil
        appleUserFullName = nil
    }

    // MARK: - Helper Methods

    private func isValidEmail(_ email: String) -> Bool {
        let emailRegex = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,64}"
        let emailPredicate = NSPredicate(format:"SELF MATCHES %@", emailRegex)
        return emailPredicate.evaluate(with: email)
    }
    
    private func parseAuthError(_ error: Error) -> String {
        if let authError = error as? AuthErrorCode {
            switch authError.code {
            case .emailAlreadyInUse:
                return "An account with this email already exists"
            case .invalidEmail:
                return "Please enter a valid email address"
            case .weakPassword:
                return "Password must be at least 6 characters"
            case .userNotFound:
                return "No account found with this email address"
            case .wrongPassword:
                return "Incorrect password"
            case .userDisabled:
                return "This account has been disabled"
            case .tooManyRequests:
                startSecurityBlockTimer()
                return "Too many requests. Please wait before trying again."
            case .networkError:
                return "Network error. Please check your connection"
            case .requiresRecentLogin:
                return "Please enter your current password to confirm this action"
            default:
                // Check for Firebase security blocks
                let errorMessage = error.localizedDescription.lowercased()
                if errorMessage.contains("blocked") || errorMessage.contains("unusual activity") {
                    startSecurityBlockTimer()
                    return "Security check triggered. Please wait before trying again."
                }
                return error.localizedDescription
            }
        }
        
        if let firebaseError = error as? FirebaseService.FirebaseError {
            return firebaseError.localizedDescription
        }
        
        return error.localizedDescription
    }
    
    // MARK: - Additional Methods
    
    var currentUser: FirebaseAuth.User? {
        return firebaseService.currentUser
    }
    
    func logout() {
        signOut()
    }
    
    func updateUserName(newName: String) {
        guard !newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            authStatus = .failed("Name cannot be empty")
            return
        }
        
        let trimmedName = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        authStatus = .loading
        
        Task {
            do {
                try await firebaseService.updateUserProfile(displayName: trimmedName)
                
                await MainActor.run {
                    self.authStatus = .success
                    // Refresh user state to get updated display name
                    Task {
                        try? await self.firebaseService.refreshUser()
                    }
                    print("✅ User name updated to: \(trimmedName)")
                }
                
            } catch {
                await MainActor.run {
                    self.authStatus = .failed(self.parseAuthError(error))
                    print("❌ User name update error: \(error)")
                }
            }
        }
    }
    
    func changePassword(currentPassword: String, newPassword: String) {
        authStatus = .loading
        
        guard let user = firebaseService.currentUser else {
            authStatus = .failed("No user signed in")
            return
        }
        
        // Re-authenticate the user first
        let credential = EmailAuthProvider.credential(withEmail: user.email ?? "", password: currentPassword)
        
        user.reauthenticate(with: credential) { [weak self] result, error in
            DispatchQueue.main.async {
                if let error = error {
                    self?.authStatus = .failed(self?.parseAuthError(error) ?? "Authentication failed")
                    return
                }
                
                // Update password
                user.updatePassword(to: newPassword) { updateError in
                    DispatchQueue.main.async {
                        if let updateError = updateError {
                            self?.authStatus = .failed(self?.parseAuthError(updateError) ?? "Failed to update password")
                        } else {
                            self?.authStatus = .success
                        }
                    }
                }
            }
        }
    }
    
    var isAuthenticated: Bool {
        firebaseService.isAuthenticated
    }
    
    var hasRecentlyRefreshed: Bool {
        guard let lastRefresh = lastRefreshTime else { return false }
        return Date().timeIntervalSince(lastRefresh) < refreshCooldownSeconds
    }
    
    func refreshUserState() {
        // Check if we've refreshed recently to avoid excessive API calls
        if hasRecentlyRefreshed {
            print("🔄 Skipping refresh - too recent (within \(refreshCooldownSeconds)s)")
            return
        }
        lastRefreshTime = Date()
        
        Task {
            do {
                try await firebaseService.refreshUser()
                
                await MainActor.run {
                    // Check if email verification prompt should be dismissed
                    if let user = self.firebaseService.currentUser, user.isEmailVerified {
                        if self.shouldShowEmailVerification {
                            self.shouldShowEmailVerification = false
                            print("✅ Email verified - dismissing verification prompt")
                        }
                    }
                }
                
                print("✅ User state refreshed successfully")
            } catch {
                print("❌ Failed to refresh user state: \(error)")
            }
        }
    }
    
    // MARK: - Security Block Timer Methods
    
    private func startSecurityBlockTimer() {
        // Start with 30 minutes (1800 seconds)
        securityBlockTimeRemaining = 1800
        isSecurityBlocked = true
        
        securityBlockTimer?.invalidate()
        securityBlockTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            
            DispatchQueue.main.async {
                if self.securityBlockTimeRemaining > 0 {
                    self.securityBlockTimeRemaining -= 1
                } else {
                    self.stopSecurityBlockTimer()
                }
            }
        }
        
        print("🕐 Security block timer started: 30 minutes")
    }
    
    private func stopSecurityBlockTimer() {
        securityBlockTimer?.invalidate()
        securityBlockTimer = nil
        securityBlockTimeRemaining = 0
        isSecurityBlocked = false
        
        print("✅ Security block timer completed")
    }
    
    private func formatTimeRemaining(_ seconds: Int) -> String {
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let remainingSeconds = seconds % 60
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, remainingSeconds)
        } else {
            return String(format: "%d:%02d", minutes, remainingSeconds)
        }
    }
    
    var formattedTimeRemaining: String {
        formatTimeRemaining(securityBlockTimeRemaining)
    }
    
    // MARK: - Data Cleanup Methods
    
    private func clearAllLocalData(clearWorkspaceData: Bool = true) async {
        print(clearWorkspaceData ? "🧹 Clearing all local app data..." : "🧹 Clearing account session state while preserving local workspace data...")
        
        if clearWorkspaceData {
            // Clear Core Data
            clearCoreData()

            // Clear UserDefaults
            clearUserDefaults()
        } else {
            clearSessionOnlyState()
        }
        
        // Clear Keychain
        clearKeychain()

        // Clear team workspace session state
        TeamFirebaseService.shared.clearTeamSessionForSignOut()

        // Clear any cache directories
        clearCacheDirectories()
        
        // Clear sync manager state
        UserDataSyncManager.shared.clearSyncState()
        
        // Clear location manager state
        LocationManager.shared.clearLocationState()
        
        print(clearWorkspaceData ? "✅ All local app data cleared (cloud data preserved)" : "✅ Account session state cleared (local workspace data preserved)")
    }

    private func clearSessionOnlyState() {
        print("🧹 Clearing account-only session flags...")
        shouldShowPasswordSavePrompt = false
        shouldShowEmailVerification = false
        pendingEmail = nil
        pendingPassword = nil
        isGuestMode = false
        UserDefaults.standard.set(false, forKey: "isGuestMode")
        print("✅ Account-only session flags cleared")
    }
    
    private func clearCoreData() {
        print("🗄️ Clearing Core Data...")

        let persistence = PersistenceController.shared
        guard persistence.hasPersistentStore else {
            print("⚠️ Skipping Core Data clear: persistent store is not loaded")
            return
        }

        let viewContext = persistence.container.viewContext
        let backgroundContext = persistence.container.newBackgroundContext()

        backgroundContext.performAndWait {
            deleteEntity(Lead.self, label: "leads", in: backgroundContext, mergeInto: viewContext)
            deleteEntity(FollowUpCheckIn.self, label: "follow-up check-ins", in: backgroundContext, mergeInto: viewContext)
            deleteEntity(Neighborhood.self, label: "neighborhoods", in: backgroundContext, mergeInto: viewContext)
            backgroundContext.reset()
        }

        viewContext.reset()
        print("✅ Core Data cleanup completed safely")
    }

    nonisolated private func deleteEntity<T: NSManagedObject>(
        _ entityType: T.Type,
        label: String,
        in context: NSManagedObjectContext,
        mergeInto viewContext: NSManagedObjectContext
    ) {
        let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: String(describing: entityType))
        let deleteRequest = NSBatchDeleteRequest(fetchRequest: fetchRequest)
        deleteRequest.resultType = .resultTypeObjectIDs

        do {
            let result = try context.execute(deleteRequest) as? NSBatchDeleteResult
            if let objectIDs = result?.result as? [NSManagedObjectID], !objectIDs.isEmpty {
                let changes: [AnyHashable: Any] = [NSDeletedObjectsKey: objectIDs]
                NSManagedObjectContext.mergeChanges(fromRemoteContextSave: changes, into: [viewContext])
            }
            print("✅ All \(label) deleted from Core Data")
        } catch {
            print("❌ Failed to delete \(label): \(error)")
        }
    }
    
    private func clearUserDefaults() {
        print("📝 Clearing UserDefaults...")
        
        let defaults = UserDefaults.standard
        
        // Get all current keys
        let allKeys = defaults.dictionaryRepresentation().keys
        
        // Keys to preserve (system-level preferences AND keychain preferences)
        let preservedKeys = Set([
            "AppleLanguages",
            "AppleLocale",
            "AppleKeyboards",
            "NSLanguages"
        ])
        
        // Also preserve keychain preference keys so users don't get prompted again
        let keychainKeys = Set(allKeys.filter { 
            $0.hasPrefix("keychain_saved_") || $0.hasPrefix("user_declined_save_")
        })
        
        let allPreservedKeys = preservedKeys.union(keychainKeys)
        
        // Remove all app-specific keys except preserved ones
        for key in allKeys {
            if !allPreservedKeys.contains(key) {
                defaults.removeObject(forKey: key)
            }
        }
        
        // Specifically clear backup data (but not keychain preferences)
        let backupKeys = allKeys.filter { $0.hasPrefix("FollowUpBackup_") }
        for backupKey in backupKeys {
            defaults.removeObject(forKey: backupKey)
        }
        
        defaults.synchronize()
        print("✅ UserDefaults cleared (keychain preferences preserved)")
        
        // Log preserved keychain preferences for debugging
        if !keychainKeys.isEmpty {
            print("🔐 Preserved keychain preferences: \(keychainKeys.count) entries")
        }
    }
    
    private func clearKeychain() {
        print("🔐 Clearing Keychain...")
        
        // Note: We're intentionally NOT clearing saved passwords from keychain
        // This preserves the user's choice to save passwords across sign-outs
        // If users want to remove saved passwords, they can do so through iOS Settings > Passwords
        
        print("✅ Keychain preserved (user passwords and preferences kept)")
    }
    
    private func clearCacheDirectories() {
        print("📂 Clearing cache directories...")
        
        let fileManager = FileManager.default
        
        // Clear cache directory
        if let cacheDirectory = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first {
            do {
                let cacheContents = try fileManager.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: nil)
                for url in cacheContents {
                    try fileManager.removeItem(at: url)
                }
                print("✅ Cache directory cleared")
            } catch {
                print("❌ Failed to clear cache directory: \(error)")
            }
        }
        
        // Clear temporary directory
        let tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
        do {
            let tempContents = try fileManager.contentsOfDirectory(at: tempDirectory, includingPropertiesForKeys: nil)
            for url in tempContents {
                try fileManager.removeItem(at: url)
            }
            print("✅ Temporary directory cleared")
        } catch {
            print("❌ Failed to clear temporary directory: \(error)")
        }
    }
    
    private func syncAppointmentsBeforeSignOut() async {
        // Check if user is still authenticated before attempting appointment sync
        guard firebaseService.isAuthenticated else {
            print("ℹ️ User not authenticated, skipping appointment sync")
            return
        }
        
        print("🗓️ Syncing appointments before sign-out...")
        
        // Sync all appointments to Firebase
        await AppointmentManager.shared.syncAllAppointmentsToFirebase()
        
        print("✅ Appointments synced to Firebase before sign-out")
    }
    
    private func performPostSignInSync() async {
        print("🔄 Starting comprehensive sync after sign-in...")

        // Restore account-level flags/preferences (onboarding/premium/profile) from cloud.
        await firebaseService.restoreAccountProfileFromClouds()
        // Then re-publish current local state to keep both clouds converged.
        await firebaseService.syncCurrentAccountProfileToClouds()
        
        // Start appointment Firebase sync first
        AppointmentManager.shared.restartFirebaseSync()
        
        // Start general data sync with server
        UserDataSyncManager.shared.syncWithServer()
        
        print("✅ Post-sign-in sync initiated")
    }
}
