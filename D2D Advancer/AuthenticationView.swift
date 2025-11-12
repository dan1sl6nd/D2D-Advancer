import SwiftUI
import AuthenticationServices

struct AuthenticationView: View {
    @StateObject private var accountManager = FirebaseUserAccountManager.shared
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
        GeometryReader { geometry in
            ZStack {
                // Modern gradient background
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color.blue.opacity(0.05),
                        Color.purple.opacity(0.05),
                        Color(UIColor.systemBackground)
                    ]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 24) {
                        // Modern Header
                        modernHeader

                        // Main Authentication Card
                        modernAuthCard

                        // Error Display
                        if case let .failed(error) = accountManager.authStatus {
                            modernErrorCard(message: error)
                        }

                        // Action Buttons
                        modernActionButtons

                        // Mode Toggle
                        modernModeToggle

                        // Guest Mode Option
                        modernGuestModeCard

                        Spacer(minLength: 40)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, max(geometry.safeAreaInsets.top + 20, 60))
                    .padding(.bottom, 20)
                }
            }
            .navigationBarHidden(true)
            .onAppear {
                loadStoredCredentials()
            }
            .sheet(isPresented: $showingForgotPassword) {
                ForgotPasswordSheet(
                    email: $resetEmail,
                    isPresented: $showingForgotPassword,
                    accountManager: accountManager
                )
            }
        }
    }
    
    // MARK: - Modern View Components

    private var modernHeader: some View {
        VStack(spacing: 16) {
            // App Icon with glow effect
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [Color.blue, Color.purple]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 100, height: 100)
                    .shadow(color: Color.blue.opacity(0.3), radius: 20, x: 0, y: 10)

                Image(systemName: "house.fill")
                    .font(.system(size: 40, weight: .semibold))
                    .foregroundColor(.white)
            }

            VStack(spacing: 8) {
                Text("D2D Advancer")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)

                Text(isLoginMode ? "Welcome Back" : "Create Your Account")
                    .font(.system(size: 18, weight: .medium, design: .rounded))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 20)
    }

    private var modernAuthCard: some View {
        VStack(spacing: 20) {
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
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(Color(UIColor.secondarySystemGroupedBackground))
                .shadow(color: Color.black.opacity(0.08), radius: 20, x: 0, y: 10)
        )
    }

    private func modernErrorCard(message: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title3)
                .foregroundColor(.red)

            Text(message)
                .font(.subheadline)
                .foregroundColor(.red)
                .multilineTextAlignment(.leading)

            Spacer()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.red.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.red.opacity(0.3), lineWidth: 1)
                )
        )
    }

    private var modernActionButtons: some View {
        VStack(spacing: 12) {
            // Main action button
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
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(
                    accountManager.authStatus == .loading ?
                    LinearGradient(
                        gradient: Gradient(colors: [Color.gray, Color.gray.opacity(0.8)]),
                        startPoint: .leading,
                        endPoint: .trailing
                    ) :
                    LinearGradient(
                        gradient: Gradient(colors: [Color.blue, Color.purple]),
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .cornerRadius(16)
                .shadow(color: accountManager.authStatus == .loading ? Color.clear : Color.blue.opacity(0.3), radius: 15, x: 0, y: 8)
            }
            .disabled(accountManager.authStatus == .loading)

            // Forgot Password (Login mode only)
            if isLoginMode {
                Button(action: {
                    showingForgotPassword = true
                }) {
                    Text("Forgot Password?")
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundColor(.blue)
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
                    .font(.system(size: 15, weight: .regular, design: .rounded))
                    .foregroundColor(.secondary)

                Text(isLoginMode ? "Sign Up" : "Sign In")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundColor(.blue)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(UIColor.tertiarySystemGroupedBackground))
            )
        }
    }

    private var modernGuestModeCard: some View {
        Button(action: {
            // If already in guest mode, just dismiss the sheet
            if accountManager.isGuestMode {
                dismiss()
            } else {
                accountManager.startGuestMode()
            }
        }) {
            VStack(spacing: 8) {
                HStack(spacing: 10) {
                    Image(systemName: "person.crop.circle.badge.questionmark")
                        .font(.title2)
                        .foregroundColor(.green)

                    Text("Continue as Guest")
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .foregroundColor(.green)
                }

                Text("Explore the app without creating an account")
                    .font(.system(size: 13, weight: .regular, design: .rounded))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.green.opacity(0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.green.opacity(0.2), lineWidth: 1.5)
                    )
            )
        }
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
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.blue)

                Text(title)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundColor(.primary)
            }

            Group {
                if isSecure {
                    SecureField(placeholder, text: text)
                } else {
                    TextField(placeholder, text: text)
                        .keyboardType(keyboardType)
                }
            }
            .font(.system(size: 16, weight: .regular, design: .rounded))
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(UIColor.systemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color(UIColor.separator).opacity(0.3), lineWidth: 1)
            )
        }
    }

    // MARK: - Adaptive View Components (Legacy - keeping for reference)

    private var adaptiveHeaderSection: some View {
        VStack(spacing: isLoginMode ? 12 : 10) {
            // App Logo
            Circle()
                .fill(Color.blue.opacity(0.1))
                .frame(width: isLoginMode ? 85 : 78, height: isLoginMode ? 85 : 78)
                .overlay(
                    Image(systemName: "house.fill")
                        .font(.system(size: isLoginMode ? 35 : 32))
                        .foregroundColor(.blue)
                )
            
            VStack(spacing: isLoginMode ? 6 : 5) {
                Text("D2D Advancer")
                    .font(isLoginMode ? .title : .title2)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                
                Text(isLoginMode ? "Welcome Back" : "Create Account")
                    .font(isLoginMode ? .headline : .headline)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.top, isLoginMode ? 16 : 14)
    }
    
    private var adaptiveAuthFormCard: some View {
        adaptiveSectionCard(title: isLoginMode ? "Sign In" : "Create Account", icon: "person.circle.fill") {
            VStack(spacing: isLoginMode ? 14 : 12) {
                if !isLoginMode {
                    adaptiveTextField(title: "Full Name", text: $name, icon: "person.fill")
                }
                
                adaptiveTextField(title: "Email", text: $email, icon: "envelope.fill")
                    .keyboardType(.emailAddress)
                    .autocapitalization(.none)
                    .textContentType(.emailAddress)
                
                adaptiveTextField(title: "Password", text: $password, icon: "lock.fill", isSecure: true)
                    .textContentType(isLoginMode ? .password : .newPassword)
                
                if !isLoginMode {
                    adaptiveTextField(title: "Confirm Password", text: $confirmPassword, icon: "checkmark.seal.fill", isSecure: true)
                        .textContentType(.newPassword)
                }
            }
        }
    }
    
    private func adaptiveErrorCard(message: String) -> some View {
        adaptiveSectionCard(title: "Error", icon: "exclamationmark.triangle.fill", titleColor: .red) {
            HStack(spacing: 10) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.red)
                    .font(.subheadline)
                
                Text(message)
                    .font(.subheadline)
                    .foregroundColor(.red)
                    .multilineTextAlignment(.leading)
                
                Spacer()
            }
        }
    }
    
    private var adaptiveActionCard: some View {
        adaptiveSectionCard(title: "Action", icon: "arrow.right.circle.fill") {
            Button(action: {
                handleAuthAction()
            }) {
                HStack(spacing: 8) {
                    if accountManager.authStatus == .loading {
                        ProgressView()
                            .scaleEffect(0.8)
                            .foregroundColor(.white)
                    }
                    
                    Text(isLoginMode ? "Sign In" : "Create Account")
                        .fontWeight(.semibold)
                    
                    if accountManager.authStatus != .loading {
                        Image(systemName: "arrow.right")
                            .font(.subheadline)
                    }
                }
                .font(isLoginMode ? .headline : .headline)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: isLoginMode ? 48 : 45)
                .background(accountManager.authStatus == .loading ? Color.gray : Color.blue)
                .cornerRadius(12)
            }
            .disabled(accountManager.authStatus == .loading)
        }
    }
    
    private var adaptiveBottomActionsCard: some View {
        adaptiveSectionCard(title: isLoginMode ? "Need Help?" : "Switch Mode", icon: isLoginMode ? "questionmark.circle.fill" : "arrow.2.squarepath") {
            VStack(spacing: isLoginMode ? 12 : 10) {
                // Help button (only in login mode)
                if isLoginMode {
                    Button("Can't access your account?") {
                        showingForgotPassword = true
                    }
                    .font(.subheadline)
                    .foregroundColor(.blue)
                    .frame(maxWidth: .infinity)
                    .frame(height: 38)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(10)
                }

                // Toggle mode button
                Button(action: {
                    toggleAuthMode()
                }) {
                    VStack(spacing: isLoginMode ? 6 : 4) {
                        Text(isLoginMode ? "Don't have an account?" : "Already have an account?")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Text(isLoginMode ? "Sign Up" : "Sign In")
                            .font(isLoginMode ? .subheadline : .subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.blue)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: isLoginMode ? 44 : 40)
                    .background(Color(UIColor.tertiarySystemBackground))
                    .cornerRadius(10)
                }
            }
        }
    }

    private var adaptiveGuestModeCard: some View {
        adaptiveSectionCard(title: "Try Without Account", icon: "person.crop.circle.badge.questionmark") {
            Button(action: {
                // If already in guest mode, just dismiss the sheet
                if accountManager.isGuestMode {
                    dismiss()
                } else {
                    accountManager.startGuestMode()
                }
            }) {
                VStack(spacing: 8) {
                    HStack {
                        Image(systemName: "arrow.right.circle.fill")
                            .font(.headline)
                        Text("Continue as Guest")
                            .font(.headline)
                            .fontWeight(.semibold)
                    }

                    Text("Explore the app without creating an account")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .foregroundColor(.green)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color.green.opacity(0.1))
                .cornerRadius(12)
            }
        }
    }
    
    private func adaptiveSectionCard<Content: View>(title: String, icon: String, titleColor: Color = .blue, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: isLoginMode ? 12 : 10) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(titleColor)
                    .font(isLoginMode ? .headline : .headline)
                
                Text(title)
                    .font(isLoginMode ? .headline : .headline)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                
                Spacer()
            }
            .padding(.horizontal, isLoginMode ? 18 : 17)
            .padding(.top, isLoginMode ? 16 : 14)
            
            content()
                .padding(.horizontal, isLoginMode ? 18 : 17)
                .padding(.bottom, isLoginMode ? 16 : 14)
        }
        .background(
            RoundedRectangle(cornerRadius: isLoginMode ? 14 : 13)
                .fill(Color(UIColor.secondarySystemGroupedBackground))
                .shadow(color: .black.opacity(0.1), radius: 3, x: 0, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: isLoginMode ? 14 : 13)
                .stroke(Color(UIColor.separator), lineWidth: 0.5)
        )
    }
    
    private func adaptiveTextField(title: String, text: Binding<String>, icon: String, isSecure: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: isLoginMode ? 8 : 7) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundColor(.blue)
                    .frame(width: 18)
                    .font(.subheadline)
                
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
            }
            
            Group {
                if isSecure {
                    SecureField(title, text: text)
                } else {
                    TextField(title, text: text)
                }
            }
            .font(isLoginMode ? .body : .body)
            .padding(.horizontal, isLoginMode ? 14 : 13)
            .padding(.vertical, isLoginMode ? 12 : 11)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(UIColor.systemBackground))
                    .shadow(color: .black.opacity(0.05), radius: 1, x: 0, y: 1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color(UIColor.separator), lineWidth: 0.5)
            )
        }
    }
    
    // MARK: - Original Balanced Components (kept for reference)
    
    private var balancedHeaderSection: some View {
        VStack(spacing: 12) {
            // App Logo
            Circle()
                .fill(Color.blue.opacity(0.1))
                .frame(width: 85, height: 85)
                .overlay(
                    Image(systemName: "house.fill")
                        .font(.system(size: 35))
                        .foregroundColor(.blue)
                )
            
            VStack(spacing: 6) {
                Text("D2D Advancer")
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                
                Text(isLoginMode ? "Welcome Back" : "Create Account")
                    .font(.headline)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.top, 16)
    }
    
    private var balancedAuthFormCard: some View {
        balancedSectionCard(title: isLoginMode ? "Sign In" : "Create Account", icon: "person.circle.fill") {
            VStack(spacing: 14) {
                if !isLoginMode {
                    balancedTextField(title: "Full Name", text: $name, icon: "person.fill")
                }
                
                balancedTextField(title: "Email", text: $email, icon: "envelope.fill")
                    .keyboardType(.emailAddress)
                    .autocapitalization(.none)
                    .textContentType(.emailAddress)
                
                balancedTextField(title: "Password", text: $password, icon: "lock.fill", isSecure: true)
                    .textContentType(isLoginMode ? .password : .newPassword)
                
                if !isLoginMode {
                    balancedTextField(title: "Confirm Password", text: $confirmPassword, icon: "checkmark.seal.fill", isSecure: true)
                        .textContentType(.newPassword)
                }
            }
        }
    }
    
    private func balancedErrorCard(message: String) -> some View {
        balancedSectionCard(title: "Error", icon: "exclamationmark.triangle.fill", titleColor: .red) {
            HStack(spacing: 10) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.red)
                    .font(.subheadline)
                
                Text(message)
                    .font(.subheadline)
                    .foregroundColor(.red)
                    .multilineTextAlignment(.leading)
                
                Spacer()
            }
        }
    }
    
    private var balancedActionCard: some View {
        balancedSectionCard(title: "Action", icon: "arrow.right.circle.fill") {
            Button(action: {
                handleAuthAction()
            }) {
                HStack(spacing: 8) {
                    if accountManager.authStatus == .loading {
                        ProgressView()
                            .scaleEffect(0.8)
                            .foregroundColor(.white)
                    }
                    
                    Text(isLoginMode ? "Sign In" : "Create Account")
                        .fontWeight(.semibold)
                    
                    if accountManager.authStatus != .loading {
                        Image(systemName: "arrow.right")
                            .font(.subheadline)
                    }
                }
                .font(.headline)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(accountManager.authStatus == .loading ? Color.gray : Color.blue)
                .cornerRadius(12)
            }
            .disabled(accountManager.authStatus == .loading)
        }
    }
    
    private var balancedBottomActionsCard: some View {
        balancedSectionCard(title: isLoginMode ? "Need Help?" : "Switch Mode", icon: isLoginMode ? "questionmark.circle.fill" : "arrow.2.squarepath") {
            VStack(spacing: 12) {
                // Help button (only in login mode)
                if isLoginMode {
                    Button("Can't access your account?") {
                        showingForgotPassword = true
                    }
                    .font(.subheadline)
                    .foregroundColor(.blue)
                    .frame(maxWidth: .infinity)
                    .frame(height: 38)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(10)
                }
                
                // Toggle mode button
                Button(action: {
                    toggleAuthMode()
                }) {
                    VStack(spacing: 6) {
                        Text(isLoginMode ? "Don't have an account?" : "Already have an account?")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Text(isLoginMode ? "Sign Up" : "Sign In")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.blue)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(Color(UIColor.tertiarySystemBackground))
                    .cornerRadius(10)
                }
            }
        }
    }
    
    private func balancedSectionCard<Content: View>(title: String, icon: String, titleColor: Color = .blue, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(titleColor)
                    .font(.headline)
                
                Text(title)
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                
                Spacer()
            }
            .padding(.horizontal, 18)
            .padding(.top, 16)
            
            content()
                .padding(.horizontal, 18)
                .padding(.bottom, 16)
        }
        .background(Color(UIColor.tertiarySystemBackground))
        .cornerRadius(14)
    }
    
    private func balancedTextField(title: String, text: Binding<String>, icon: String, isSecure: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundColor(.blue)
                    .frame(width: 18)
                    .font(.subheadline)
                
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
            }
            
            Group {
                if isSecure {
                    SecureField(title, text: text)
                } else {
                    TextField(title, text: text)
                }
            }
            .font(.body)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color(UIColor.tertiarySystemBackground))
            .cornerRadius(8)
        }
    }
    
    private var headerSection: some View {
        VStack(spacing: 16) {
            // App Logo
            Circle()
                .fill(Color.blue.opacity(0.1))
                .frame(width: 100, height: 100)
                .overlay(
                    Image(systemName: "house.fill")
                        .font(.system(size: 40))
                        .foregroundColor(.blue)
                )
            
            VStack(spacing: 8) {
                Text("D2D Advancer")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                
                Text(isLoginMode ? "Welcome Back" : "Create Account")
                    .font(.title2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.top, 40)
    }
    
    private var authFormCard: some View {
        modernSectionCard(title: isLoginMode ? "Sign In" : "Create Account", icon: "person.circle.fill") {
            VStack(spacing: 16) {
                if !isLoginMode {
                    modernTextField(title: "Full Name", text: $name, icon: "person.fill")
                }
                
                modernTextField(title: "Email", text: $email, icon: "envelope.fill")
                    .keyboardType(.emailAddress)
                    .autocapitalization(.none)
                    .textContentType(.emailAddress)
                
                modernTextField(title: "Password", text: $password, icon: "lock.fill", isSecure: true)
                    .textContentType(isLoginMode ? .password : .newPassword)
                
                if !isLoginMode {
                    modernTextField(title: "Confirm Password", text: $confirmPassword, icon: "checkmark.seal.fill", isSecure: true)
                        .textContentType(.newPassword)
                }
            }
        }
    }
    
    private func errorCard(message: String) -> some View {
        modernSectionCard(title: "Error", icon: "exclamationmark.triangle.fill", titleColor: .red) {
            HStack {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.red)
                
                Text(message)
                    .font(.body)
                    .foregroundColor(.red)
                    .multilineTextAlignment(.leading)
                
                Spacer()
            }
        }
    }
    
    private var actionCard: some View {
        modernSectionCard(title: "Action", icon: "arrow.right.circle.fill") {
            Button(action: {
                handleAuthAction()
            }) {
                HStack(spacing: 8) {
                    if accountManager.authStatus == .loading {
                        ProgressView()
                            .scaleEffect(0.8)
                            .foregroundColor(.white)
                    }
                    
                    Text(isLoginMode ? "Sign In" : "Create Account")
                        .fontWeight(.semibold)
                    
                    if accountManager.authStatus != .loading {
                        Image(systemName: "arrow.right")
                            .font(.subheadline)
                    }
                }
                .font(.headline)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(accountManager.authStatus == .loading ? Color.gray : Color.blue)
                .cornerRadius(12)
            }
            .disabled(accountManager.authStatus == .loading)
        }
    }
    
    private var accountHelpCard: some View {
        modernSectionCard(title: "Need Help?", icon: "questionmark.circle.fill") {
            Button("Can't access your account?") {
                showingForgotPassword = true
            }
            .font(.body)
            .foregroundColor(.blue)
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background(Color.blue.opacity(0.1))
            .cornerRadius(12)
        }
    }
    
    private var toggleModeCard: some View {
        modernSectionCard(title: "Switch Mode", icon: "arrow.2.squarepath") {
            Button(action: {
                toggleAuthMode()
            }) {
                VStack(spacing: 8) {
                    Text(isLoginMode ? "Don't have an account?" : "Already have an account?")
                        .font(.body)
                        .foregroundColor(.secondary)
                    
                    Text(isLoginMode ? "Sign Up" : "Sign In")
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundColor(.blue)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 60)
                .background(Color(UIColor.tertiarySystemBackground))
                .cornerRadius(12)
            }
        }
    }
    
    private func modernSectionCard<Content: View>(title: String, icon: String, titleColor: Color = .blue, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(titleColor)
                    .font(.title2)
                
                Text(title)
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            
            content()
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
        }
        .background(Color(UIColor.tertiarySystemBackground))
        .cornerRadius(16)
    }
    
    private func modernTextField(title: String, text: Binding<String>, icon: String, isSecure: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(.blue)
                    .frame(width: 20)
                
                Text(title)
                    .font(.headline)
                    .fontWeight(.semibold)
            }
            
            Group {
                if isSecure {
                    SecureField(title, text: text)
                } else {
                    TextField(title, text: text)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(UIColor.tertiarySystemBackground))
            .cornerRadius(8)
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
        GeometryReader { geometry in
            ZStack {
                // Modern gradient background
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color.blue.opacity(0.05),
                        Color.purple.opacity(0.05),
                        Color(UIColor.systemBackground)
                    ]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 24) {
                        // Modern Header
                        modernPasswordResetHeader

                        // Email Input Card
                        modernEmailInputCard

                        // Error Display
                        if case let .failed(error) = accountManager.authStatus {
                            modernPasswordResetError(message: error)
                        }

                        // Action Button
                        if accountManager.authStatus == .loading {
                            modernLoadingCard
                        } else {
                            modernResetActionButton
                        }

                        // Success Display
                        if case .success = accountManager.authStatus {
                            modernSuccessCard
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, max(geometry.safeAreaInsets.top + 60, 80))
                    .padding(.bottom, 20)
                }
            }
            .overlay(alignment: .topTrailing) {
                Button(action: {
                    isPresented = false
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 30))
                        .foregroundColor(.secondary)
                        .padding(20)
                }
                .padding(.top, geometry.safeAreaInsets.top)
            }
        }
        .onAppear {
            accountManager.authStatus = .idle
            resetEmail = email
        }
    }

    private var modernPasswordResetHeader: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [Color.orange, Color.red]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 80, height: 80)
                    .shadow(color: Color.orange.opacity(0.3), radius: 15, x: 0, y: 8)

                Image(systemName: "key.fill")
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundColor(.white)
            }

            VStack(spacing: 8) {
                Text("Reset Password")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)

                Text("Enter your email to receive a password reset link")
                    .font(.system(size: 15, weight: .regular, design: .rounded))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
            }
        }
        .padding(.vertical, 20)
    }

    private var modernEmailInputCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "envelope.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.blue)

                Text("Email Address")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundColor(.primary)
            }

            TextField("your.email@example.com", text: $resetEmail)
                .keyboardType(.emailAddress)
                .autocapitalization(.none)
                .disableAutocorrection(true)
                .font(.system(size: 16, weight: .regular, design: .rounded))
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(UIColor.systemBackground))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color(UIColor.separator).opacity(0.3), lineWidth: 1)
                )
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(Color(UIColor.secondarySystemGroupedBackground))
                .shadow(color: Color.black.opacity(0.08), radius: 20, x: 0, y: 10)
        )
    }

    private func modernPasswordResetError(message: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title3)
                .foregroundColor(.red)

            Text(message)
                .font(.subheadline)
                .foregroundColor(.red)
                .multilineTextAlignment(.leading)

            Spacer()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.red.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.red.opacity(0.3), lineWidth: 1)
                )
        )
    }

    private var modernLoadingCard: some View {
        HStack(spacing: 12) {
            ProgressView()
                .scaleEffect(0.9)
                .tint(.blue)

            Text("Sending reset email...")
                .font(.system(size: 16, weight: .medium, design: .rounded))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(UIColor.tertiarySystemGroupedBackground))
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
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(
                isEmailValid ?
                LinearGradient(
                    gradient: Gradient(colors: [Color.orange, Color.red]),
                    startPoint: .leading,
                    endPoint: .trailing
                ) :
                LinearGradient(
                    gradient: Gradient(colors: [Color.gray, Color.gray.opacity(0.8)]),
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .cornerRadius(16)
            .shadow(color: isEmailValid ? Color.orange.opacity(0.3) : Color.clear, radius: 15, x: 0, y: 8)
        }
        .disabled(!isEmailValid)
    }

    private var modernSuccessCard: some View {
        VStack(spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title)
                    .foregroundColor(.green)

                Text("Email Sent!")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundColor(.green)
            }

            Text("Check your inbox for the password reset link. If you don't see it, check your spam folder.")
                .font(.system(size: 15, weight: .regular, design: .rounded))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)

            Button(action: {
                isPresented = false
            }) {
                Text("Done")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(
                        LinearGradient(
                            gradient: Gradient(colors: [Color.green, Color.green.opacity(0.8)]),
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .cornerRadius(14)
            }
            .padding(.top, 8)
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.green.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(Color.green.opacity(0.3), lineWidth: 1.5)
                )
        )
    }

    private var isEmailValid: Bool {
        let emailRegex = "^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}$"
        return NSPredicate(format: "SELF MATCHES %@", emailRegex).evaluate(with: resetEmail.trimmingCharacters(in: .whitespacesAndNewlines))
    }
    
    private var passwordResetHeader: some View {
        VStack(spacing: 16) {
            Circle()
                .fill(Color.blue.opacity(0.1))
                .frame(width: 80, height: 80)
                .overlay(
                    Image(systemName: "key.fill")
                        .font(.system(size: 32))
                        .foregroundColor(.blue)
                )
            
            VStack(spacing: 8) {
                Text("Reset Password")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                
                Text("Enter your email address and we'll send you a link to reset your password.")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.top, 20)
    }
    
    private var emailInputCard: some View {
        passwordResetSectionCard(title: "Email Address", icon: "envelope.fill") {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "envelope.fill")
                        .foregroundColor(.blue)
                        .frame(width: 20)
                    
                    Text("Email")
                        .font(.headline)
                        .fontWeight(.semibold)
                }
                
                TextField("Email", text: $resetEmail)
                    .keyboardType(.emailAddress)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(UIColor.systemBackground))
                            .shadow(color: .black.opacity(0.05), radius: 1, x: 0, y: 1)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color(UIColor.separator), lineWidth: 0.5)
                    )
            }
        }
    }
    
    private var loadingCard: some View {
        passwordResetSectionCard(title: "Sending", icon: "paperplane.fill") {
            HStack {
                ProgressView()
                    .scaleEffect(0.8)
                
                Text("Sending reset email...")
                    .font(.body)
                    .foregroundColor(.secondary)
                
                Spacer()
            }
            .padding(.vertical, 8)
        }
    }
    
    private var resetActionCard: some View {
        passwordResetSectionCard(title: "Send Reset", icon: "paperplane.circle.fill") {
            Button("Send Reset Email") {
                accountManager.resetPassword(email: resetEmail.trimmingCharacters(in: .whitespacesAndNewlines))
            }
            .font(.headline)
            .fontWeight(.semibold)
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(isEmailValid ? Color.blue : Color.gray)
            .cornerRadius(12)
            .disabled(!isEmailValid || accountManager.authStatus == .loading)
        }
    }
    
    private func passwordResetErrorCard(message: String) -> some View {
        passwordResetSectionCard(title: "Error", icon: "exclamationmark.triangle.fill", titleColor: .red) {
            HStack {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.red)
                
                Text(message)
                    .font(.body)
                    .foregroundColor(.red)
                    .multilineTextAlignment(.leading)
                
                Spacer()
            }
        }
    }
    
    private var successCard: some View {
        passwordResetSectionCard(title: "Success", icon: "checkmark.circle.fill", titleColor: .green) {
            VStack(spacing: 16) {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("Reset email sent!")
                        .foregroundColor(.green)
                        .fontWeight(.semibold)
                    Spacer()
                }
                
                Text("Check your email for a password reset link. If you don't see it, check your spam folder.")
                    .font(.body)
                    .multilineTextAlignment(.leading)
                    .foregroundColor(.secondary)
                
                Button("Done") {
                    isPresented = false
                }
                .font(.headline)
                .fontWeight(.semibold)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(Color.green)
                .cornerRadius(12)
            }
        }
    }
    
    private func passwordResetSectionCard<Content: View>(title: String, icon: String, titleColor: Color = .blue, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(titleColor)
                    .font(.title2)
                
                Text(title)
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            
            content()
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
        }
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(UIColor.secondarySystemGroupedBackground))
                .shadow(color: .black.opacity(0.1), radius: 3, x: 0, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color(UIColor.separator), lineWidth: 0.5)
        )
    }

}


struct AuthenticationView_Previews: PreviewProvider {
    static var previews: some View {
        AuthenticationView()
    }
}