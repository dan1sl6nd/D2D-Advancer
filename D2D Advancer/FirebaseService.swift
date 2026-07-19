import Foundation
import FirebaseAuth
import FirebaseFirestore
import FirebaseCore
import UIKit
import CoreData

enum AccountAuthenticationMethod: Equatable, Sendable {
    case password
    case apple
    case unsupported

    static func resolve(providerIDs: [String], hasAppleIdentity: Bool = false) -> Self {
        let normalized = Set(providerIDs.map { $0.lowercased() })
        if normalized.contains("apple.com") || hasAppleIdentity {
            return .apple
        }
        if normalized.contains("password") {
            return .password
        }
        return .unsupported
    }
}

@MainActor
class FirebaseService: ObservableObject {
    static let shared: FirebaseService = {
        FirebaseBootstrap.configureIfNeeded()
        return FirebaseService()
    }()

    private let auth: Auth
    private let db: Firestore
    private var accountBackupService: CloudKitAccountBackupService? {
        CloudKitAccountBackupService.shared
    }
    private var authStateListenerHandle: AuthStateDidChangeListenerHandle?

    private let onboardingCompletedKey = "onboarding_completed"
    private let onboardingProfileKey = "onboarding_profile"
    private let premiumKey = "isPremiumUser"
    private let syncedPreferenceKeys: Set<String> = [
        "isDarkMode",
        "leadSortPreference",
        "leadSortAscending",
        "defaultLeadStatus",
        "defaultServiceCategoryID",
        "defaultFollowUpTime",
        "mapDefaultView",
        "defaultCheckInType",
        "targetIncomeMin",
        "targetIncomeMax",
        "targetHomeValueMin",
        "targetHomeValueMax",
        "preferredDensity",
        "preferHomeowners",
        "minimumOwnershipRate",
        "weightIncome",
        "weightDensity",
        "weightHomeValue",
        "weightConversion",
        "selectedProfile",
        "notification_settings",
        "calendar_integration_settings",
        "saved_search_presets",
        "custom_message_templates",
        "custom_appointment_types",
        "custom_service_categories",
        "sync_interval",
        "auto_sync_enabled"
    ]
    private let syncedPreferencePrefixes = ["customTheme_"]
    private let maxSyncedPreferencesPayloadBytes = 350_000
    
    @Published var currentUser: User?
    @Published var isAuthenticated = false

    var accountAuthenticationMethod: AccountAuthenticationMethod {
        AccountAuthenticationMethod.resolve(
            providerIDs: auth.currentUser?.providerData.map(\.providerID) ?? []
        )
    }
    
    private init() {
        FirebaseBootstrap.configureIfNeeded()
        auth = Auth.auth()
        db = Firestore.firestore()
        FirebaseEmulatorConfiguration.applyIfNeeded(auth: auth, firestore: db)
        
        // Listen for auth changes
        authStateListenerHandle = auth.addStateDidChangeListener { [weak self] _, user in
            DispatchQueue.main.async {
                self?.currentUser = user
                self?.isAuthenticated = user != nil
            }
        }
    }
    
    // MARK: - Authentication
    
    func signUp(email: String, password: String, displayName: String? = nil) async throws {
        let result = try await auth.createUser(withEmail: email, password: password)
        
        // Set display name if provided
        if let displayName = displayName, !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let changeRequest = result.user.createProfileChangeRequest()
            changeRequest.displayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
            try await changeRequest.commitChanges()
            print("✅ Display name set to: \(displayName)")
        }
        
        if FirebaseEmulatorConfiguration.isEnabled {
            print("🧪 Email verification skipped for Firebase emulator account")
        } else {
            try await result.user.sendEmailVerification()
        }

        // Mirror account metadata to both Firestore and CloudKit.
        await syncCurrentAccountProfileToClouds()
        
        print("✅ User created successfully: \(result.user.uid)")
        if !FirebaseEmulatorConfiguration.isEnabled {
            print("📧 Verification email sent to: \(Utilities.redactedEmail(email))")
        }
    }
    
    func signIn(email: String, password: String) async throws {
        let result = try await auth.signIn(withEmail: email, password: password)
        
        // Check if email is verified
        if !FirebaseEmulatorConfiguration.isEnabled && !result.user.isEmailVerified {
            throw FirebaseError.emailNotVerified
        }

        // Refresh mirrored profile metadata after sign-in.
        await syncCurrentAccountProfileToClouds()
        
        print("✅ User signed in successfully: \(result.user.uid)")
    }

    func signInWithApple(idToken: String, rawNonce: String, fullName: PersonNameComponents?) async throws {
        let credential = OAuthProvider.appleCredential(
            withIDToken: idToken,
            rawNonce: rawNonce,
            fullName: fullName
        )
        let result = try await auth.signIn(with: credential)

        let displayName = fullName.flatMap { components -> String? in
            let formatted = PersonNameComponentsFormatter()
                .string(from: components)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return formatted.isEmpty ? nil : formatted
        }

        if let displayName,
           result.user.displayName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
            let changeRequest = result.user.createProfileChangeRequest()
            changeRequest.displayName = displayName
            try await changeRequest.commitChanges()
        }

        await syncCurrentAccountProfileToClouds()

        print("✅ User signed in with Apple through Firebase Auth: \(result.user.uid)")
    }
    
    func signOut() throws {
        try auth.signOut()
        print("✅ User signed out successfully")
    }
    
    func resetPassword(email: String) async throws {
        try await auth.sendPasswordReset(withEmail: email)
        print("📧 Password reset email sent to: \(Utilities.redactedEmail(email))")
    }
    
    func updatePassword(currentPassword: String, newPassword: String) async throws {
        guard let user = auth.currentUser else {
            throw FirebaseError.notAuthenticated
        }
        
        // Re-authenticate with current password
        let credential = EmailAuthProvider.credential(
            withEmail: user.email ?? "",
            password: currentPassword
        )
        
        try await user.reauthenticate(with: credential)
        
        // Update to new password
        try await user.updatePassword(to: newPassword)
        
        print("✅ Password updated successfully")
    }
    
    func deleteAccount(currentPassword: String) async throws {
        guard let user = auth.currentUser else {
            throw FirebaseError.notAuthenticated
        }

        guard accountAuthenticationMethod == .password else {
            throw FirebaseError.unsupportedAuthenticationProvider
        }
        
        // Re-authenticate with current password before deletion
        let credential = EmailAuthProvider.credential(
            withEmail: user.email ?? "",
            password: currentPassword
        )
        
        try await user.reauthenticate(with: credential)
        
        try await deletePersonalFirebaseData(for: user.uid)
        await deleteCloudKitAccountBackupIfAvailable(for: user.uid)

        try await user.delete()
        AppLog.info("Account", "Password account deleted successfully")
    }

    func deleteAccount(with credentials: AppleAccountDeletionCredentials) async throws {
        guard let user = auth.currentUser else {
            throw FirebaseError.notAuthenticated
        }

        guard accountAuthenticationMethod == .apple else {
            throw FirebaseError.unsupportedAuthenticationProvider
        }

        let credential = OAuthProvider.appleCredential(
            withIDToken: credentials.idToken,
            rawNonce: credentials.rawNonce,
            fullName: nil
        )
        try await user.reauthenticate(with: credential)

        try await deletePersonalFirebaseData(for: user.uid)
        await deleteCloudKitAccountBackupIfAvailable(for: user.uid)
        try await auth.revokeToken(withAuthorizationCode: credentials.authorizationCode)
        try await user.delete()
        AppLog.info("Account", "Apple account revoked and deleted successfully")
    }
    
    func resendEmailVerification() async throws {
        guard let user = auth.currentUser else {
            throw FirebaseError.notAuthenticated
        }
        
        try await user.sendEmailVerification()
        print("📧 Verification email sent")
    }
    
    // MARK: - Error Handling
    
    enum FirebaseError: Error, LocalizedError {
        case notAuthenticated
        case emailNotVerified
        case invalidCredentials
        case networkError
        case unsupportedAuthenticationProvider
        case unknown(String)
        
        var errorDescription: String? {
            switch self {
            case .notAuthenticated:
                return "User not authenticated"
            case .emailNotVerified:
                return "Please verify your email address before signing in"
            case .invalidCredentials:
                return "Invalid email or password"
            case .networkError:
                return "Network error. Please check your connection"
            case .unsupportedAuthenticationProvider:
                return "This account must be confirmed with its original sign-in method."
            case .unknown(let message):
                return message
            }
        }
    }

    private func deletePersonalFirebaseData(for userId: String) async throws {
        let userReference = db.collection("users").document(userId)
        let subcollections = ["leads", "checkIns", "appointments", "teamProfile"]

        for name in subcollections {
            try await deleteAllDocuments(in: userReference.collection(name))
        }
        try await userReference.delete()
    }

    private func deleteAllDocuments(in collection: CollectionReference) async throws {
        while true {
            let snapshot = try await collection.limit(to: 400).getDocuments()
            guard !snapshot.documents.isEmpty else { return }

            let batch = db.batch()
            snapshot.documents.forEach { batch.deleteDocument($0.reference) }
            try await commit(batch)
        }
    }

    private func commit(_ batch: WriteBatch) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            batch.commit { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }

    private func deleteCloudKitAccountBackupIfAvailable(for userId: String) async {
        guard let accountBackupService else { return }
        do {
            try await accountBackupService.deleteProfile(for: userId)
        } catch {
            AppLog.warning("Account", "CloudKit account-profile cleanup was unavailable: \(error.localizedDescription)")
        }
    }
    
    // MARK: - User State Management
    
    func refreshUser() async throws {
        guard let user = auth.currentUser else {
            throw FirebaseError.notAuthenticated
        }
        
        try await user.reload()
        
        // Update the published properties on main actor
        await MainActor.run {
            self.currentUser = auth.currentUser
            self.isAuthenticated = auth.currentUser != nil
            print("🔄 User state refreshed - Email verified: \(auth.currentUser?.isEmailVerified ?? false)")
        }
    }
    
    // MARK: - User Profile Methods
    
    func updateUserProfile(displayName: String) async throws {
        guard let user = auth.currentUser else {
            throw FirebaseError.notAuthenticated
        }
        
        // Update Firebase Auth display name
        let changeRequest = user.createProfileChangeRequest()
        changeRequest.displayName = displayName
        try await changeRequest.commitChanges()

        await syncCurrentAccountProfileToClouds()
        
        print("✅ User profile updated successfully")
    }

    // MARK: - Account Profile Sync (Firebase + CloudKit)

    /// Writes account/profile metadata to both Firestore and CloudKit.
    /// Note: Authentication secrets are never persisted here.
    func syncCurrentAccountProfileToClouds() async {
        guard let user = auth.currentUser else { return }

        let payload = buildAccountPayload(from: user)

        do {
            try await db.collection("users")
                .document(user.uid)
                .setData(payload.firestoreData, merge: true)
            print("☁️ Account profile synced to Firestore")
        } catch {
            print("⚠️ Failed to sync account profile to Firestore: \(error.localizedDescription)")
        }

        if let accountBackupService {
            do {
                try await accountBackupService.uploadProfile(payload)
                print("☁️ Account profile synced to CloudKit backup")
            } catch {
                print("⚠️ Failed to sync account profile to CloudKit backup: \(error.localizedDescription)")
            }
        } else {
            print("⚠️ CloudKit account backup unavailable in this runtime")
        }
    }

    /// Restores local account-related flags/preferences from Firestore first,
    /// then CloudKit backup if Firestore is unavailable.
    func restoreAccountProfileFromClouds() async {
        guard let user = auth.currentUser else { return }

        var restoredFromFirestore = false
        do {
            let document = try await db.collection("users")
                .document(user.uid)
                .getDocument()
            if let data = document.data(), !data.isEmpty {
                applyAccountProfileData(data)
                restoredFromFirestore = true
                print("☁️ Restored account profile flags from Firestore")
            }
        } catch {
            print("⚠️ Failed to restore account profile from Firestore: \(error.localizedDescription)")
        }

        guard !restoredFromFirestore else { return }

        guard let accountBackupService else {
            print("⚠️ CloudKit account backup unavailable in this runtime")
            return
        }

        do {
            if let payload = try await accountBackupService.fetchProfile(for: user.uid) {
                applyAccountProfilePayload(payload)
                print("☁️ Restored account profile flags from CloudKit backup")
            }
        } catch {
            print("⚠️ Failed to restore account profile from CloudKit backup: \(error.localizedDescription)")
        }
    }

    private func buildAccountPayload(from user: User) -> AccountProfileSyncPayload {
        let defaults = UserDefaults.standard

        let onboardingProfileJSON = defaults.data(forKey: onboardingProfileKey)
            .flatMap { String(data: $0, encoding: .utf8) }
        let preferencesJSON = buildPreferencesJSON(from: defaults)

        return AccountProfileSyncPayload(
            userId: user.uid,
            email: user.email ?? "",
            displayName: user.displayName ?? "",
            isEmailVerified: user.isEmailVerified,
            isPremium: defaults.bool(forKey: premiumKey),
            onboardingCompleted: defaults.bool(forKey: onboardingCompletedKey),
            onboardingProfileJSON: onboardingProfileJSON,
            preferencesJSON: preferencesJSON,
            createdAt: user.metadata.creationDate ?? Date(),
            updatedAt: Date(),
            lastSignInAt: user.metadata.lastSignInDate
        )
    }

    private func applyAccountProfilePayload(_ payload: AccountProfileSyncPayload) {
        applyAccountProfileData(payload.firestoreData)
    }

    private func applyAccountProfileData(_ data: [String: Any]) {
        let defaults = UserDefaults.standard

        if parseBool(data["onboardingCompleted"]) == true {
            defaults.set(true, forKey: onboardingCompletedKey)
        }

        // Never force premium to false from backup metadata.
        if parseBool(data["isPremium"]) == true {
            defaults.set(true, forKey: premiumKey)
        }

        if let profileJSON = data["onboardingProfileJSON"] as? String,
           let profileData = profileJSON.data(using: .utf8) {
            defaults.set(profileData, forKey: onboardingProfileKey)
        }

        if let preferencesJSON = data["preferencesJSON"] as? String,
           !preferencesJSON.isEmpty {
            applySyncedPreferences(from: preferencesJSON, defaults: defaults)
        }

        defaults.synchronize()
        refreshPreferenceBackedManagers()
    }

    private func parseBool(_ value: Any?) -> Bool? {
        if let bool = value as? Bool {
            return bool
        }
        if let number = value as? NSNumber {
            return number.boolValue
        }
        if let string = value as? String {
            return NSString(string: string).boolValue
        }
        return nil
    }

    private func buildPreferencesJSON(from defaults: UserDefaults) -> String? {
        let prefixMatchedKeys = defaults.dictionaryRepresentation().keys.filter { key in
            syncedPreferencePrefixes.contains(where: key.hasPrefix)
        }

        let keysToSync = syncedPreferenceKeys.union(prefixMatchedKeys)
        guard !keysToSync.isEmpty else { return nil }

        var serialized: [String: SyncedPreferenceEntry] = [:]
        for key in keysToSync.sorted() {
            guard isSyncedPreferenceKey(key),
                  let rawValue = defaults.object(forKey: key),
                  let entry = makeSyncedPreferenceEntry(from: rawValue) else {
                continue
            }
            serialized[key] = entry
        }

        guard !serialized.isEmpty else { return nil }

        do {
            let encoded = try JSONEncoder().encode(serialized)
            guard encoded.count <= maxSyncedPreferencesPayloadBytes else {
                print("⚠️ Preferences snapshot too large (\(encoded.count) bytes). Skipping preferences sync.")
                return nil
            }
            return String(data: encoded, encoding: .utf8)
        } catch {
            print("⚠️ Failed to encode preferences snapshot: \(error.localizedDescription)")
            return nil
        }
    }

    private func applySyncedPreferences(from json: String, defaults: UserDefaults) {
        guard let jsonData = json.data(using: .utf8) else { return }

        do {
            let entries = try JSONDecoder().decode([String: SyncedPreferenceEntry].self, from: jsonData)
            for (key, entry) in entries where isSyncedPreferenceKey(key) {
                switch entry.type {
                case .bool:
                    if let value = entry.boolValue {
                        defaults.set(value, forKey: key)
                    }
                case .int:
                    if let value = entry.intValue {
                        defaults.set(value, forKey: key)
                    }
                case .double:
                    if let value = entry.doubleValue {
                        defaults.set(value, forKey: key)
                    }
                case .string:
                    if let value = entry.stringValue {
                        defaults.set(value, forKey: key)
                    }
                case .data:
                    if let encoded = entry.dataBase64,
                       let value = Data(base64Encoded: encoded) {
                        defaults.set(value, forKey: key)
                    }
                }
            }
        } catch {
            print("⚠️ Failed to decode synced preferences: \(error.localizedDescription)")
        }
    }

    private func makeSyncedPreferenceEntry(from value: Any) -> SyncedPreferenceEntry? {
        if let boolValue = value as? Bool {
            return SyncedPreferenceEntry(type: .bool, boolValue: boolValue)
        }

        if let stringValue = value as? String {
            return SyncedPreferenceEntry(type: .string, stringValue: stringValue)
        }

        if let dataValue = value as? Data {
            return SyncedPreferenceEntry(type: .data, dataBase64: dataValue.base64EncodedString())
        }

        if let intValue = value as? Int {
            return SyncedPreferenceEntry(type: .int, intValue: intValue)
        }

        if let doubleValue = value as? Double {
            return SyncedPreferenceEntry(type: .double, doubleValue: doubleValue)
        }

        if let floatValue = value as? Float {
            return SyncedPreferenceEntry(type: .double, doubleValue: Double(floatValue))
        }

        if let numberValue = value as? NSNumber {
            if CFGetTypeID(numberValue) == CFBooleanGetTypeID() {
                return SyncedPreferenceEntry(type: .bool, boolValue: numberValue.boolValue)
            }

            let doubleValue = numberValue.doubleValue
            let roundedValue = doubleValue.rounded(.towardZero)
            if abs(doubleValue - roundedValue) < 0.000_000_1,
               roundedValue <= Double(Int.max),
               roundedValue >= Double(Int.min) {
                return SyncedPreferenceEntry(type: .int, intValue: Int(roundedValue))
            }

            return SyncedPreferenceEntry(type: .double, doubleValue: doubleValue)
        }

        return nil
    }

    private func isSyncedPreferenceKey(_ key: String) -> Bool {
        if syncedPreferenceKeys.contains(key) {
            return true
        }

        return syncedPreferencePrefixes.contains(where: key.hasPrefix)
    }

    private func refreshPreferenceBackedManagers() {
        DispatchQueue.main.async {
            NotificationService.shared.reloadSettingsFromUserDefaults()
            CalendarService.shared.reloadSettingsFromUserDefaults()
            CustomizableThemeManager.shared.reloadThemeFromUserDefaults()
            UserDataSyncManager.shared.reloadSyncSettingsFromUserDefaults()
        }
    }
}

private struct SyncedPreferenceEntry: Codable {
    enum EntryType: String, Codable {
        case bool
        case int
        case double
        case string
        case data
    }

    let type: EntryType
    let boolValue: Bool?
    let intValue: Int?
    let doubleValue: Double?
    let stringValue: String?
    let dataBase64: String?

    init(
        type: EntryType,
        boolValue: Bool? = nil,
        intValue: Int? = nil,
        doubleValue: Double? = nil,
        stringValue: String? = nil,
        dataBase64: String? = nil
    ) {
        self.type = type
        self.boolValue = boolValue
        self.intValue = intValue
        self.doubleValue = doubleValue
        self.stringValue = stringValue
        self.dataBase64 = dataBase64
    }
}
