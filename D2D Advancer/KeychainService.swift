import Foundation
import Security

class KeychainService {
    static let shared = KeychainService()
    
    private let service = "D2D-Advancer"
    private let server = "d2d-advancer.local" // Local identifier for better autofill compatibility
    
    private init() {}
    
    // MARK: - Password Storage and Retrieval
    
    func saveCredentials(email: String, password: String) -> Bool {
        let passwordData = password.data(using: .utf8)!
        
        // Use a simple, reliable keychain structure
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: email
        ]
        
        // Delete existing item first (ignore status - item might not exist)
        let deleteStatus = SecItemDelete(deleteQuery as CFDictionary)
        print("🗑️ Delete existing credential status: \(deleteStatus)")
        
        // Create new item with minimal attributes
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: email,
            kSecValueData as String: passwordData,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        
        // Add new item
        let status = SecItemAdd(addQuery as CFDictionary, nil)
        
        if status == errSecSuccess {
            print("✅ Credentials saved to iOS Keychain for: \(email)")
            // Mark that user has saved credentials for this email
            UserDefaults.standard.set(true, forKey: "keychain_saved_\(email)")
            return true
        } else {
            print("❌ Failed to save credentials to Keychain. Status: \(status)")
            switch status {
            case errSecDuplicateItem:
                print("   Error: Duplicate item still exists after delete attempt")
                // Try to update existing item instead
                return updateExistingCredentials(email: email, password: password)
            case errSecAuthFailed:
                print("   Error: Authentication failed")
            case errSecNoSuchAttr:
                print("   Error: No such attribute")
            case errSecParam:
                print("   Error: Invalid parameter")
            default:
                print("   Error: Unknown keychain error (\(status))")
            }
            return false
        }
    }
    
    func getStoredCredentials(for email: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: email,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var dataTypeRef: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &dataTypeRef)
        
        if status == errSecSuccess,
           let data = dataTypeRef as? Data,
           let password = String(data: data, encoding: .utf8) {
            return password
        }
        
        return nil
    }
    
    private func updateExistingCredentials(email: String, password: String) -> Bool {
        let passwordData = password.data(using: .utf8)!
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: email
        ]
        
        let attributesToUpdate: [String: Any] = [
            kSecValueData as String: passwordData
        ]
        
        let status = SecItemUpdate(query as CFDictionary, attributesToUpdate as CFDictionary)
        
        if status == errSecSuccess {
            print("✅ Updated existing credentials in iOS Keychain for: \(email)")
            UserDefaults.standard.set(true, forKey: "keychain_saved_\(email)")
            return true
        } else {
            print("❌ Failed to update existing credentials. Status: \(status)")
            return false
        }
    }
    
    func getAllStoredEmails() -> [String] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll
        ]
        
        var itemsRef: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &itemsRef)
        
        if status == errSecSuccess,
           let items = itemsRef as? [[String: Any]] {
            return items.compactMap { item in
                item[kSecAttrAccount as String] as? String
            }
        }
        
        return []
    }
    
    func deleteCredentials(for email: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: email
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        
        if status == errSecSuccess {
            print("✅ Credentials deleted from Keychain for: \(email)")
        } else {
            print("❌ Failed to delete credentials from Keychain: \(status)")
        }
    }
    
    func deleteAllCredentials() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        
        if status == errSecSuccess {
            print("✅ All credentials deleted from Keychain")
        } else {
            print("❌ Failed to delete all credentials from Keychain: \(status)")
        }
    }
    
    // MARK: - User Preference Tracking
    
    func hasCredentialsSaved(for email: String) -> Bool {
        // Check both UserDefaults flag AND actual keychain
        let flagExists = UserDefaults.standard.bool(forKey: "keychain_saved_\(email)")
        let keychainHasPassword = getStoredCredentials(for: email) != nil
        
        // If flag says we saved but keychain is empty, clear the flag
        if flagExists && !keychainHasPassword {
            UserDefaults.standard.removeObject(forKey: "keychain_saved_\(email)")
            return false
        }
        
        return keychainHasPassword
    }
    
    func markUserDeclinedSaving(for email: String) {
        UserDefaults.standard.set(true, forKey: "user_declined_save_\(email)")
    }
    
    func hasUserDeclinedSaving(for email: String) -> Bool {
        return UserDefaults.standard.bool(forKey: "user_declined_save_\(email)")
    }
    
    func clearUserPreference(for email: String) {
        UserDefaults.standard.removeObject(forKey: "keychain_saved_\(email)")
        UserDefaults.standard.removeObject(forKey: "user_declined_save_\(email)")
        print("🧹 Cleared keychain preferences for: \(email)")
    }
    
    func resetAllKeychainPreferences() {
        let userDefaults = UserDefaults.standard
        let allKeys = userDefaults.dictionaryRepresentation().keys
        
        // Remove all keychain-related preference keys
        let keychainKeys = allKeys.filter { 
            $0.hasPrefix("keychain_saved_") || $0.hasPrefix("user_declined_save_")
        }
        
        for key in keychainKeys {
            userDefaults.removeObject(forKey: key)
        }
        
        userDefaults.synchronize()
        print("🧹 Reset all keychain preferences")
    }
}