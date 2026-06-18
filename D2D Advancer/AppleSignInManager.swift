import Foundation
import SwiftUI
import AuthenticationServices
import CryptoKit

@MainActor
class AppleSignInManager: ObservableObject {
    static let shared = AppleSignInManager()

    @Published var isSignedIn: Bool = false
    @Published var userIdentifier: String?
    @Published var email: String?
    @Published var fullName: String?
    @Published var authStatus: AuthStatus = .idle

    private let keychainService = KeychainService.shared
    private var currentNonce: String?

    enum AuthStatus: Equatable {
        case idle
        case loading
        case success
        case failed(String)
    }

    private init() {
        loadStoredState()
    }

    // MARK: - State Loading

    private func loadStoredState() {
        guard let userID = keychainService.getAppleUserIdentifier() else {
            isSignedIn = false
            return
        }
        userIdentifier = userID
        email = keychainService.getAppleEmail(for: userID)
        fullName = keychainService.getAppleFullName(for: userID)
        isSignedIn = true
        print("🍎 Loaded Apple Sign In state from Keychain")

        // Defer the bridge by one runloop tick. AppleSignInManager.init() runs
        // synchronously during SwiftUI's @StateObject setup in D2D_AdvancerApp,
        // and mutating another ObservableObject's @Published properties from
        // inside that window triggers "Publishing changes from within view
        // updates" warnings. DispatchQueue.main.async defers to after the
        // current SwiftUI pass completes.
        let capturedEmail = email
        let capturedFullName = fullName
        DispatchQueue.main.async {
            FirebaseUserAccountManager.shared.bridgeAppleSignIn(
                userIdentifier: userID,
                email: capturedEmail,
                fullName: capturedFullName
            )
        }

        verifyCredentialState()
    }

    // MARK: - Credential Verification

    /// Call on app launch to detect if the user revoked Apple Sign In access in iOS Settings.
    /// When revoked, we sign them out locally so they re-authenticate on next app use.
    func verifyCredentialState() {
        guard let userID = userIdentifier else { return }
        let provider = ASAuthorizationAppleIDProvider()
        provider.getCredentialState(forUserID: userID) { [weak self] state, _ in
            Task { @MainActor in
                switch state {
                case .authorized:
                    print("✅ Apple ID credential still valid")
                case .revoked:
                    print("🚫 Apple ID credential revoked by user — signing out locally")
                    self?.signOut()
                case .notFound:
                    print("⚠️ Apple ID credential not found — signing out locally")
                    self?.signOut()
                case .transferred:
                    print("🔄 Apple ID credential transferred")
                @unknown default:
                    break
                }
            }
        }
    }

    // MARK: - Authorization Flow (SignInWithAppleButton)

    /// Configure the ASAuthorizationAppleIDRequest when the user taps the SIWA button.
    func configureRequest(_ request: ASAuthorizationAppleIDRequest) {
        request.requestedScopes = [.fullName, .email]
        let nonce = Self.randomNonce(length: 32)
        currentNonce = nonce
        request.nonce = Self.sha256(nonce)
        authStatus = .loading
    }

    /// Handle the result from the SIWA button's onCompletion closure.
    func handleAuthorizationCompletion(
        _ result: Result<ASAuthorization, Error>,
        requireFirebaseTeamSession: Bool = false
    ) {
        switch result {
        case .success(let authorization):
            handleSuccess(authorization, requireFirebaseTeamSession: requireFirebaseTeamSession)
        case .failure(let error):
            handleFailure(error)
        }
    }

    private func handleSuccess(_ authorization: ASAuthorization, requireFirebaseTeamSession: Bool) {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
            authStatus = .failed("Unexpected Apple ID credential type")
            return
        }

        let nonce = currentNonce
        let identityToken = credential.identityToken.flatMap { String(data: $0, encoding: .utf8) }
        let userID = credential.user
        let newEmail = credential.email
        let newFullName: String? = credential.fullName.flatMap { components in
            let formatter = PersonNameComponentsFormatter()
            let formatted = formatter.string(from: components)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return formatted.isEmpty ? nil : formatted
        }

        Task {
            let teamAuthError: String?
            if let identityToken, let nonce {
                do {
                    try await FirebaseService.shared.signInWithApple(
                        idToken: identityToken,
                        rawNonce: nonce,
                        fullName: credential.fullName
                    )
                    teamAuthError = nil
                } catch {
                    teamAuthError = error.localizedDescription
                }
            } else {
                teamAuthError = "Apple did not return the identity token needed for Team."
            }

            currentNonce = nil

            if requireFirebaseTeamSession, let teamAuthError {
                authStatus = .failed("Team sign-in could not connect. \(teamAuthError)")
                print("❌ Apple Sign In could not create Firebase Team session: \(teamAuthError)")
                return
            }

            if let teamAuthError {
                print("⚠️ Apple Sign In succeeded locally, but Firebase Team session was not created: \(teamAuthError)")
            }

            _ = keychainService.saveAppleUserIdentifier(
                userID,
                email: newEmail,
                fullName: newFullName
            )

            userIdentifier = userID
            email = newEmail ?? keychainService.getAppleEmail(for: userID)
            fullName = newFullName ?? keychainService.getAppleFullName(for: userID)
            isSignedIn = true
            authStatus = .success

            FirebaseUserAccountManager.shared.bridgeAppleSignIn(
                userIdentifier: userID,
                email: email,
                fullName: fullName
            )

            print("✅ Sign in with Apple succeeded (emailProvided=\(newEmail != nil), nameProvided=\(newFullName != nil), teamSession=\(teamAuthError == nil))")
        }
    }

    private func handleFailure(_ error: Error) {
        let nsError = error as NSError
        if nsError.code == ASAuthorizationError.canceled.rawValue {
            authStatus = .idle
            print("Apple Sign In cancelled")
            return
        }
        authStatus = .failed(error.localizedDescription)
        print("❌ Apple Sign In failed: \(error.localizedDescription)")
    }

    // MARK: - Sign Out

    func signOut() {
        userIdentifier = nil
        email = nil
        fullName = nil
        isSignedIn = false
        authStatus = .idle
        keychainService.clearAppleUserIdentifier()
        FirebaseUserAccountManager.shared.clearAppleBridge()
        print("👋 Signed out of Apple Sign In")
    }

    // MARK: - Nonce (used by Firebase Auth Apple credential exchange)

    private static func randomNonce(length: Int) -> String {
        let charset: [Character] = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        while result.count < length {
            var byte: UInt8 = 0
            let status = SecRandomCopyBytes(kSecRandomDefault, 1, &byte)
            guard status == errSecSuccess else { continue }
            if Int(byte) < charset.count {
                result.append(charset[Int(byte) % charset.count])
            }
        }
        return result
    }

    private static func sha256(_ input: String) -> String {
        let hashed = SHA256.hash(data: Data(input.utf8))
        return hashed.compactMap { String(format: "%02x", $0) }.joined()
    }
}
