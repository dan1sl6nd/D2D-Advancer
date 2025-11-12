import Foundation
import FirebaseAuth
import FirebaseFirestore
import FirebaseCore
import UIKit
import CoreData

class FirebaseService: ObservableObject {
    static let shared = FirebaseService()
    private let auth = Auth.auth()
    private let db = Firestore.firestore()
    private var authStateListenerHandle: AuthStateDidChangeListenerHandle?
    
    @Published var currentUser: User?
    @Published var isAuthenticated = false
    
    private init() {
        // Configure Firebase
        if FirebaseApp.app() == nil {
            FirebaseApp.configure()
        }
        
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
        
        // Send email verification
        try await result.user.sendEmailVerification()
        
        print("✅ User created successfully: \(result.user.uid)")
        print("📧 Verification email sent to: \(email)")
    }
    
    func signIn(email: String, password: String) async throws {
        let result = try await auth.signIn(withEmail: email, password: password)
        
        // Check if email is verified
        if !result.user.isEmailVerified {
            throw FirebaseError.emailNotVerified
        }
        
        print("✅ User signed in successfully: \(result.user.uid)")
    }
    
    func signOut() throws {
        try auth.signOut()
        print("✅ User signed out successfully")
    }
    
    func resetPassword(email: String) async throws {
        try await auth.sendPasswordReset(withEmail: email)
        print("📧 Password reset email sent to: \(email)")
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
        
        // Re-authenticate with current password before deletion
        let credential = EmailAuthProvider.credential(
            withEmail: user.email ?? "",
            password: currentPassword
        )
        
        try await user.reauthenticate(with: credential)
        
        // Delete the account
        try await user.delete()
        print("✅ Account deleted successfully")
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
            case .unknown(let message):
                return message
            }
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
        
        print("✅ User profile updated successfully")
    }
    
    
}