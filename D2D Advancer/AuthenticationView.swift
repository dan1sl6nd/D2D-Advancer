import SwiftUI
import AuthenticationServices

struct AuthenticationView: View {
    @StateObject private var accountManager = FirebaseUserAccountManager.shared
    @StateObject private var appleSignInManager = AppleSignInManager.shared
    @Environment(\.dismiss) private var dismiss
    @State private var isLoginMode = true
    @State private var email = ""
    @State private var password = ""
    @State private var name = ""
    @State private var confirmPassword = ""
    @State private var showingForgotPassword = false
    @State private var showingPasswordReset = false
    @State private var resetEmail = ""
    
    var body: some View {
        ZStack {
            Color.obsidianBlack
                .ignoresSafeArea()

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 18) {
                    modernHeader
                    appleSignInSection
                    orDivider
                    modernAuthCard

                    if case let .failed(error) = accountManager.authStatus {
                        modernErrorCard(message: error)
                    }
                    if case let .failed(error) = appleSignInManager.authStatus {
                        modernErrorCard(message: "Apple Sign In: \(error)")
                    }

                    modernActionButtons
                    modernModeToggle
                    modernGuestModeCard
                }
                .padding(.horizontal, 20)
                .padding(.top, 24)
                .padding(.bottom, 32)
            }
        }
        .presentationBackground(Color.obsidianBlack)
        .navigationBarHidden(true)
        .onAppear {
            loadStoredCredentials()
        }
        .onChange(of: appleSignInManager.authStatus) { _, status in
            if case .success = status {
                dismiss()
            }
        }
        .sheet(isPresented: $showingForgotPassword) {
            ForgotPasswordSheet(
                email: $resetEmail,
                isPresented: $showingForgotPassword,
                accountManager: accountManager
            )
        }
    }
    
    // MARK: - Modern View Components

    private var modernHeader: some View {
        HStack(alignment: .top, spacing: 14) {
            ObsidianIconTile(icon: "person.crop.circle.badge.checkmark", tint: .electricViolet, size: 48)

            VStack(alignment: .leading, spacing: 5) {
                Text(isLoginMode ? "Sign In" : "Create Account")
                    .font(.displayMedium)
                    .foregroundColor(Color.textPrimary)

                Text("Use Apple for the simplest setup, or email if your team account already uses it.")
                    .font(.obsidianBody)
                    .foregroundColor(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            ObsidianCompactIconButton(
                icon: "xmark",
                accessibilityLabel: "Close sign in",
                accentColor: .textSecondary
            ) {
                dismiss()
            }
        }
    }

    private var modernAuthCard: some View {
        ObsidianSectionCard(
            title: isLoginMode ? "Email Sign In" : "Email Account",
            icon: isLoginMode ? "envelope.fill" : "person.badge.plus.fill",
            subtitle: isLoginMode ? "Use this only if your team account was created with email." : "Create a Firebase-backed account for team workspace access.",
            accentColor: .statusNotHome
        ) {
            VStack(spacing: 14) {
                if !isLoginMode {
                    modernTextField(
                        title: "Full Name",
                        text: $name,
                        icon: "person.fill",
                        placeholder: "Enter your full name"
                    )
                }

                modernTextField(
                    title: "Email",
                    text: $email,
                    icon: "envelope.fill",
                    placeholder: "your.email@example.com",
                    keyboardType: .emailAddress
                )
                .autocapitalization(.none)
                .textContentType(.emailAddress)

                modernTextField(
                    title: "Password",
                    text: $password,
                    icon: "lock.fill",
                    placeholder: "Enter your password",
                    isSecure: true
                )
                .textContentType(isLoginMode ? .password : .newPassword)

                if !isLoginMode {
                    modernTextField(
                        title: "Confirm Password",
                        text: $confirmPassword,
                        icon: "checkmark.seal.fill",
                        placeholder: "Confirm your password",
                        isSecure: true
                    )
                    .textContentType(.newPassword)
                }
            }
        }
    }

    private func modernErrorCard(message: String) -> some View {
        ObsidianStatusBanner(
            icon: "exclamationmark.triangle.fill",
            title: "Sign in problem",
            message: message,
            tint: .statusNotInterested
        )
    }

    private var appleSignInSection: some View {
        SignInWithAppleButton(
            isLoginMode ? .signIn : .signUp,
            onRequest: { request in
                appleSignInManager.configureRequest(request)
            },
            onCompletion: { result in
                appleSignInManager.handleAuthorizationCompletion(result)
            }
        )
        .signInWithAppleButtonStyle(.white)
        .frame(height: 56)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            Group {
                if case .loading = appleSignInManager.authStatus {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.black.opacity(0.25))
                        .overlay(ProgressView().tint(.white))
                }
            }
        )
    }

    private var orDivider: some View {
        HStack(spacing: 12) {
            Rectangle()
                .fill(Color.textSecondary.opacity(0.3))
                .frame(height: 0.5)
            Text("or")
                .font(.obsidianFootnote)
                .foregroundColor(Color.textSecondary)
            Rectangle()
                .fill(Color.textSecondary.opacity(0.3))
                .frame(height: 0.5)
        }
    }

    private var modernActionButtons: some View {
        VStack(spacing: 12) {
            Button(action: {
                handleAuthAction()
            }) {
                HStack(spacing: 8) {
                    if accountManager.authStatus == .loading {
                        ProgressView()
                            .scaleEffect(0.9)
                            .tint(.white)
                    } else {
                        Image(systemName: isLoginMode ? "arrow.right.circle.fill" : "checkmark.circle.fill")
                            .font(.title3)
                    }

                    Text(isLoginMode ? "Sign In" : "Create Account")
                        .font(.obsidianAction)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(ObsidianPrimaryButtonStyle())
            .disabled(accountManager.authStatus == .loading)
            .opacity(accountManager.authStatus == .loading ? 0.7 : 1)

            if isLoginMode {
                Button(action: {
                    showingForgotPassword = true
                }) {
                    Text("Forgot Password?")
                        .font(.obsidianBody)
                        .foregroundColor(Color.textSecondary)
                }
                .padding(.top, 4)
            }
        }
    }

    private var modernModeToggle: some View {
        Button(action: {
            toggleAuthMode()
        }) {
            HStack(spacing: 8) {
                Text(isLoginMode ? "Don't have an account?" : "Already have an account?")
                    .font(.obsidianBody)
                    .foregroundColor(Color.textSecondary)

                Text(isLoginMode ? "Sign Up" : "Sign In")
                    .font(.obsidianBody)
                    .foregroundColor(Color.electricViolet)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(ObsidianSecondaryButtonStyle())
    }

    private var modernGuestModeCard: some View {
        Button(action: {
            if accountManager.isGuestMode {
                dismiss()
            } else {
                accountManager.startGuestMode()
            }
        }) {
            MoreCardView(
                icon: "person.crop.circle.badge.questionmark",
                iconColor: .statusInterested,
                title: "Continue as Guest",
                subtitle: "Explore without creating an account.",
                showChevron: true
            )
        }
        .buttonStyle(PlainButtonStyle())
    }

    private func modernTextField(
        title: String,
        text: Binding<String>,
        icon: String,
        placeholder: String,
        isSecure: Bool = false,
        keyboardType: UIKeyboardType = .default
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.obsidianFootnote)
                    .foregroundColor(Color.electricViolet)

                Text(title)
                    .font(.obsidianFootnote)
                    .foregroundColor(Color.textPrimary)
            }

            Group {
                if isSecure {
                    SecureField(placeholder, text: text)
                } else {
                    TextField(placeholder, text: text)
                        .keyboardType(keyboardType)
                }
            }
            .font(.obsidianCallout)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.obsidianElevated)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.obsidianBorder.opacity(0.55), lineWidth: 0.5)
            )
        }
    }

    private func handleAuthAction() {
        // Clear any previous errors
        accountManager.authStatus = .idle
        
        // Validate inputs
        guard !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            accountManager.authStatus = .failed("Email is required")
            return
        }
        
        guard !password.isEmpty else {
            accountManager.authStatus = .failed("Password is required")
            return
        }
        
        if isLoginMode {
            accountManager.signIn(email: email.trimmingCharacters(in: .whitespacesAndNewlines), password: password)
        } else {
            guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                accountManager.authStatus = .failed("Name is required")
                return
            }
            
            guard password == confirmPassword else {
                accountManager.authStatus = .failed("Passwords don't match")
                return
            }
            
            accountManager.signUp(
                email: email.trimmingCharacters(in: .whitespacesAndNewlines), 
                password: password,
                displayName: name.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
    }
    
    private func toggleAuthMode() {
        isLoginMode.toggle()
        // Reset form and status
        email = ""
        password = ""
        name = ""
        confirmPassword = ""
        accountManager.authStatus = .idle
    }
    
    private func loadStoredCredentials() {
        // Load the last used email if available
        let storedEmails = KeychainService.shared.getAllStoredEmails()
        if let lastEmail = storedEmails.first, email.isEmpty {
            DispatchQueue.main.async {
                email = lastEmail
                // Auto-fill password if available
                if let storedPassword = KeychainService.shared.getStoredCredentials(for: lastEmail) {
                    password = storedPassword
                }
            }
        }
    }
    
    
}

struct ForgotPasswordSheet: View {
    @Binding var email: String
    @Binding var isPresented: Bool
    @ObservedObject var accountManager: FirebaseUserAccountManager
    @State private var resetEmail = ""

    var body: some View {
        ZStack {
            Color.obsidianBlack
                .ignoresSafeArea()

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 18) {
                    modernPasswordResetHeader
                    modernEmailInputCard

                    if case let .failed(error) = accountManager.authStatus {
                        modernPasswordResetError(message: error)
                    }

                    if accountManager.authStatus == .loading {
                        modernLoadingCard
                    } else {
                        modernResetActionButton
                    }

                    if case .success = accountManager.authStatus {
                        modernSuccessCard
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 24)
                .padding(.bottom, 32)
            }
        }
        .presentationBackground(Color.obsidianBlack)
        .onAppear {
            accountManager.authStatus = .idle
            resetEmail = email
        }
    }

    private var modernPasswordResetHeader: some View {
        HStack(alignment: .top, spacing: 14) {
            ObsidianIconTile(icon: "key.fill", tint: .statusNotHome, size: 48)

            VStack(alignment: .leading, spacing: 5) {
                Text("Reset Password")
                    .font(.displayMedium)
                    .foregroundColor(Color.textPrimary)

                Text("Enter your email and we will send a reset link.")
                    .font(.obsidianBody)
                    .foregroundColor(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            ObsidianCompactIconButton(
                icon: "xmark",
                accessibilityLabel: "Close password reset",
                accentColor: .textSecondary
            ) {
                isPresented = false
            }
        }
    }

    private var modernEmailInputCard: some View {
        ObsidianSectionCard(
            title: "Email Address",
            icon: "envelope.fill",
            subtitle: "Use the email connected to your D2D Advancer account.",
            accentColor: .statusNotHome
        ) {
            TextField("your.email@example.com", text: $resetEmail)
                .keyboardType(.emailAddress)
                .autocapitalization(.none)
                .disableAutocorrection(true)
                .font(.obsidianCallout)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.obsidianElevated)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.obsidianBorder.opacity(0.55), lineWidth: 0.5)
                )
        }
    }

    private func modernPasswordResetError(message: String) -> some View {
        ObsidianStatusBanner(
            icon: "exclamationmark.triangle.fill",
            title: "Reset failed",
            message: message,
            tint: .statusNotInterested
        )
    }

    private var modernLoadingCard: some View {
        ObsidianStatusBanner(
            icon: "paperplane.fill",
            title: "Sending reset email...",
            message: "This usually takes a few seconds.",
            tint: .electricViolet
        )
    }

    private var modernResetActionButton: some View {
        Button(action: {
            accountManager.resetPassword(email: resetEmail.trimmingCharacters(in: .whitespacesAndNewlines))
        }) {
            HStack(spacing: 8) {
                Image(systemName: "paperplane.fill")
                    .font(.title3)

                Text("Send Reset Email")
                    .font(.obsidianAction)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(ObsidianPrimaryButtonStyle())
        .disabled(!isEmailValid)
        .opacity(isEmailValid ? 1 : 0.55)
    }

    private var modernSuccessCard: some View {
        ObsidianSectionCard(
            title: "Email Sent",
            icon: "checkmark.circle.fill",
            subtitle: "Check your inbox and spam folder.",
            accentColor: .statusInterested
        ) {
            Text("Check your inbox for the password reset link. If you don't see it, check your spam folder.")
                .font(.obsidianBody)
                .foregroundColor(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Button(action: {
                isPresented = false
            }) {
                Text("Done")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(ObsidianPrimaryButtonStyle())
            .padding(.top, 8)
        }
    }

    private var isEmailValid: Bool {
        let emailRegex = "^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}$"
        return NSPredicate(format: "SELF MATCHES %@", emailRegex).evaluate(with: resetEmail.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}


struct AuthenticationView_Previews: PreviewProvider {
    static var previews: some View {
        AuthenticationView()
    }
}
