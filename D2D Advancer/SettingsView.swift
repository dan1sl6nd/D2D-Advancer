import SwiftUI
import CoreData
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @ObservedObject private var preferences = AppPreferences.shared
    @ObservedObject private var userAccountManager = FirebaseUserAccountManager.shared
    @ObservedObject private var syncManager = UserDataSyncManager.shared
    @AppStorage("isDarkMode") private var darkModeEnabled = false
    @State private var showingOnboarding = false
    @State private var showingResetThemeConfirm = false
    
    private var syncStatusIcon: String {
        switch syncManager.syncStatus {
        case .idle:
            return "icloud.and.arrow.up"
        case .syncing:
            return "arrow.clockwise"
        case .completed:
            return "checkmark.icloud"
        case .failed(_):
            return "exclamationmark.icloud"
        }
    }
    
    private var syncStatusColor: Color {
        switch syncManager.syncStatus {
        case .idle:
            return .blue
        case .syncing:
            return .blue
        case .completed:
            return .green
        case .failed(_):
            return .red
        }
    }
    
    private var syncStatusText: String {
        switch syncManager.syncStatus {
        case .idle:
            if let lastSync = syncManager.lastSyncDate {
                return "Last synced: \(DateFormatter.localizedString(from: lastSync, dateStyle: .none, timeStyle: .short))"
            } else {
                return "Ready to sync"
            }
        case .syncing:
            return "Syncing..."
        case .completed:
            return "Sync completed"
        case .failed(let error):
            return "Sync failed: \(error)"
        }
    }
    
    var body: some View {
        NavigationView {
            List {
                // User Info Section
                Section("Account") {
                    if userAccountManager.isGuestMode {
                        GuestInfoRowView()

                        NavigationLink(destination: CreateAccountFromGuestView(userAccountManager: userAccountManager)) {
                            HStack {
                                Image(systemName: "person.crop.circle.badge.plus")
                                    .foregroundColor(.green)
                                    .frame(width: 20)
                                Text("Create Account")
                                    .foregroundColor(.green)
                                    .fontWeight(.semibold)
                                Spacer()
                            }
                        }
                    } else {
                        UserInfoRowView(userAccountManager: userAccountManager)

                        NavigationLink(destination: AccountManagementView(userAccountManager: userAccountManager)) {
                            HStack {
                                Image(systemName: "person.crop.circle.badge.gearshape")
                                    .foregroundColor(.blue)
                                    .frame(width: 20)
                                Text("Manage Account")
                                Spacer()
                            }
                        }
                    }
                }

                // Data Sync Section (only for logged-in users)
                if userAccountManager.isLoggedIn {
                    Section("Data Sync") {
                    HStack {
                        if syncManager.syncStatus == .syncing {
                            ProgressView()
                                .scaleEffect(0.8)
                                .foregroundColor(.blue)
                                .accessibilityLabel("Syncing in progress")
                        } else {
                            Image(systemName: syncStatusIcon)
                                .foregroundColor(syncStatusColor)
                                .frame(width: 20)
                                .accessibilityHidden(true) // Hide decorative icon
                        }
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Sync Data")
                                .font(.body)
                                .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                            Text(syncStatusText)
                                .font(.caption)
                                .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                                .foregroundColor(syncStatusColor)
                        }
                        
                        Spacer()
                        
                        if syncManager.syncStatus != .syncing {
                            Button("Sync") {
                                syncManager.syncWithServer()
                            }
                            .font(.caption)
                            .foregroundColor(.blue)
                            .accessibilityLabel("Sync data now")
                            .accessibilityHint("Synchronize local data with cloud storage")
                        }
                    }
                    .disabled(syncManager.syncStatus == .syncing)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Data synchronization")
                    .accessibilityValue(syncStatusText)
                    
                    Toggle("Auto Sync", isOn: $syncManager.isAutoSyncEnabled)
                        .accessibilityLabel("Auto sync")
                        .accessibilityHint("Automatically synchronize data when changes are made")
                }
                }

                // App Preferences Section
                Section("Preferences") {
                    HStack {
                        Image(systemName: "moon.fill")
                            .foregroundColor(.purple)
                            .frame(width: 20)
                        
                        Text("Dark Mode")
                        
                        Spacer()
                        
                        Toggle("", isOn: $darkModeEnabled)
                    }
                    
                    NavigationLink(destination: NotificationSettingsView()) {
                        HStack {
                            Image(systemName: "bell.fill")
                                .foregroundColor(.orange)
                                .frame(width: 20)
                            Text("Notifications")
                            Spacer()
                        }
                    }
                    NavigationLink(destination: ThemeSettingsView()) {
                        HStack {
                            Image(systemName: "paintbrush")
                                .foregroundColor(.purple)
                                .frame(width: 20)
                            Text("Theme")
                            Spacer()
                        }
                    }
                    NavigationLink(destination: CalendarSettingsView()) {
                        HStack {
                            Image(systemName: "calendar")
                                .foregroundColor(.red)
                                .frame(width: 20)
                            Text("Calendar")
                            Spacer()
                        }
                    }
                    NavigationLink(destination: AppPreferencesView()) {
                        HStack {
                            Image(systemName: "gearshape.2.fill")
                                .foregroundColor(.gray)
                                .frame(width: 20)
                            Text("App Preferences")
                            Spacer()
                        }
                    }
                    
                    NavigationLink(destination: AppointmentTypePresetsView()) {
                        HStack {
                            Image(systemName: "calendar.badge.plus")
                                .foregroundColor(.blue)
                                .frame(width: 20)
                            Text("Appointment Types")
                            Spacer()
                        }
                    }

                    Button(action: {
                        showingResetThemeConfirm = true
                    }) {
                        HStack {
                            Image(systemName: "arrow.counterclockwise.circle")
                                .foregroundColor(.red)
                                .frame(width: 20)
                            Text("Reset Theme")
                                .foregroundColor(.red)
                            Spacer()
                        }
                    }
                }
                
                // Help & Tutorial Section
                Section("Help & Tutorial") {
                    // Card-based button to match app style
                    Button(action: {
                        OnboardingManager.shared.startOnboarding()
                        showingOnboarding = true
                    }) {
                        MoreCardView(
                            icon: "questionmark.circle",
                            iconColor: .blue,
                            title: "Show Tutorial",
                            subtitle: "Walk through features and best practices",
                            showChevron: false
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
                    .accessibilityLabel("Show app tutorial")
                    .accessibilityHint("Restart the onboarding tutorial to learn about app features")
                    
                }
                
                // About Section
                Section("About") {
                    HStack {
                        Image(systemName: "info.circle")
                            .foregroundColor(.blue)
                            .frame(width: 20)
                        
                        Text("Version")
                        
                        Spacer()
                        
                        Text("1.0.0")
                            .foregroundColor(.secondary)
                    }
                }
                
                // Sign Out Section (only for logged-in users)
                if userAccountManager.isLoggedIn {
                    Section {
                        SignOutRowView(userAccountManager: userAccountManager)
                    }
                }
            }
            .navigationBarHidden(true)
            .sheet(isPresented: $showingOnboarding) {
                OnboardingView(isPresented: $showingOnboarding)
                    .interactiveDismissDisabled()
            }
        }
            .alert("Reset Theme", isPresented: $showingResetThemeConfirm) {
                Button("Cancel", role: .cancel) {}
                Button("Reset", role: .destructive) {
                    CustomizableThemeManager.shared.resetToDefault()
                }
            } message: {
                Text("This will restore all theme colors and styles to the default Professional preset.")
            }
    }
}

struct GuestInfoRowView: View {
    var body: some View {
        HStack {
            Image(systemName: "person.crop.circle.badge.questionmark")
                .foregroundColor(.green)
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text("Guest Account")
                    .font(.headline)
                    .foregroundColor(.green)
                Text("Data stored locally on this device")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
        .padding(.vertical, 2)
    }
}

struct UserInfoRowView: View {
    @ObservedObject var userAccountManager: FirebaseUserAccountManager

    var body: some View {
        HStack {
            Image(systemName: "person.circle.fill")
                .foregroundColor(.blue)
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 2) {
                if let user = userAccountManager.currentUser {
                    Text(userAccountManager.currentUserDisplayName ?? user.displayName ?? "User")
                        .font(.headline)
                    Text(user.email ?? "Unknown")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()
        }
        .padding(.vertical, 2)
    }
}

struct ExitGuestModeRowView: View {
    @ObservedObject var userAccountManager: FirebaseUserAccountManager
    @State private var showingExitConfirmation = false

    var body: some View {
        Button(action: {
            showingExitConfirmation = true
        }) {
            HStack {
                Image(systemName: "rectangle.portrait.and.arrow.right")
                    .foregroundColor(.orange)
                    .frame(width: 20, height: 20)

                Text("Exit Guest Mode")
                    .foregroundColor(.orange)

                Spacer()
            }
        }
        .padding(.vertical, 2)
        .alert("Exit Guest Mode?", isPresented: $showingExitConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Exit & Delete Data", role: .destructive) {
                userAccountManager.cancelGuestMode()
            }
        } message: {
            Text("All your guest data will be permanently deleted. Create an account first to save your data.")
        }
    }
}

struct CreateAccountFromGuestView: View {
    @ObservedObject var userAccountManager: FirebaseUserAccountManager
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var name = ""
    @State private var showingSuccess = false
    @Environment(\.presentationMode) var presentationMode

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                // Dynamic safe area spacer
                Rectangle()
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                Color(UIColor.systemBackground),
                                Color(UIColor.systemBackground).opacity(0.98)
                            ]),
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(height: max(geometry.safeAreaInsets.top + 10, 60))

                ScrollView {
                    LazyVStack(spacing: 16) {
                        // Header
                        VStack(spacing: 12) {
                            Circle()
                                .fill(Color.green.opacity(0.1))
                                .frame(width: 80, height: 80)
                                .overlay(
                                    Image(systemName: "person.crop.circle.badge.plus")
                                        .font(.system(size: 32))
                                        .foregroundColor(.green)
                                )

                            VStack(spacing: 6) {
                                Text("Create Your Account")
                                    .font(.title2)
                                    .fontWeight(.bold)

                                Text("Save your data and access it from any device")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                            }
                        }
                        .padding(.top, 16)
                        .padding(.horizontal, 16)

                        // Form Card
                        VStack(alignment: .leading, spacing: 16) {
                            HStack {
                                Image(systemName: "person.text.rectangle")
                                    .foregroundColor(.green)
                                    .font(.title2)

                                Text("Account Information")
                                    .font(.title3)
                                    .fontWeight(.bold)

                                Spacer()
                            }
                            .padding(.horizontal, 20)
                            .padding(.top, 20)

                            VStack(spacing: 16) {
                                accountTextField(title: "Full Name", text: $name, icon: "person.fill")
                                accountTextField(title: "Email", text: $email, icon: "envelope.fill", keyboardType: .emailAddress)
                                accountTextField(title: "Password", text: $password, icon: "lock.fill", isSecure: true)
                                accountTextField(title: "Confirm Password", text: $confirmPassword, icon: "checkmark.seal.fill", isSecure: true)
                            }
                            .padding(.horizontal, 20)
                            .padding(.bottom, 20)
                        }
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(
                                    LinearGradient(
                                        gradient: Gradient(colors: [
                                            Color(UIColor.tertiarySystemBackground),
                                            Color(UIColor.tertiarySystemBackground).opacity(0.8)
                                        ]),
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .shadow(color: Color.black.opacity(0.08), radius: 4, x: 0, y: 2)
                        )
                        .padding(.horizontal, 16)

                        // Create Account Button
                        Button(action: {
                            createAccount()
                        }) {
                            HStack(spacing: 8) {
                                if userAccountManager.authStatus == .loading {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                        .foregroundColor(.white)
                                    Text("Creating Account...")
                                } else {
                                    Image(systemName: "checkmark.circle.fill")
                                    Text("Create Account & Save Data")
                                }
                            }
                            .font(.headline)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(
                                        isFormValid ? LinearGradient(
                                            gradient: Gradient(colors: [Color.green, Color.green.opacity(0.8)]),
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ) : LinearGradient(
                                            gradient: Gradient(colors: [Color.gray, Color.gray]),
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .shadow(color: isFormValid ? Color.green.opacity(0.3) : Color.clear, radius: 4, x: 0, y: 2)
                            )
                        }
                        .disabled(!isFormValid || userAccountManager.authStatus == .loading)
                        .padding(.horizontal, 16)

                        // Error Card
                        if case let .failed(error) = userAccountManager.authStatus {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundColor(.red)
                                    Text("Error")
                                        .fontWeight(.semibold)
                                }
                                Text(error)
                                    .font(.subheadline)
                                    .foregroundColor(.red)
                            }
                            .padding()
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.red.opacity(0.1))
                            )
                            .padding(.horizontal, 16)
                        }

                        // Success Card
                        if case .success = userAccountManager.authStatus {
                            VStack(spacing: 16) {
                                HStack {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.green)
                                        .font(.title)
                                    Text("Account Created!")
                                        .font(.title3)
                                        .fontWeight(.semibold)
                                        .foregroundColor(.green)
                                }

                                Text("Your data has been successfully migrated to your new account.")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                            }
                            .padding()
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.green.opacity(0.1))
                            )
                            .padding(.horizontal, 16)
                        }
                    }
                    .padding(.vertical, 8)
                }
            }
            .navigationBarHidden(true)
            .navigationBarBackButtonHidden(true)
            .ignoresSafeArea(.all, edges: .top)
            .safeAreaInset(edge: .bottom) {
                // Back button
                Button(action: {
                    presentationMode.wrappedValue.dismiss()
                }) {
                    HStack {
                        Image(systemName: "chevron.left.circle.fill")
                            .font(.title3)
                        Text("Back to Settings")
                            .font(.headline)
                            .fontWeight(.semibold)
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(
                                LinearGradient(
                                    gradient: Gradient(colors: [Color.blue, Color.blue.opacity(0.8)]),
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .shadow(color: .blue.opacity(0.3), radius: 4, x: 0, y: 2)
                    )
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(
                    Rectangle()
                        .fill(Color(UIColor.systemBackground))
                        .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: -2)
                )
            }
        }
        .onAppear {
            userAccountManager.authStatus = .idle
        }
    }

    private func accountTextField(title: String, text: Binding<String>, icon: String, isSecure: Bool = false, keyboardType: UIKeyboardType = .default) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundColor(.green)
                    .frame(width: 18)

                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
            }

            Group {
                if isSecure {
                    SecureField(title, text: text)
                } else {
                    TextField(title, text: text)
                        .keyboardType(keyboardType)
                        .autocapitalization(keyboardType == .emailAddress ? .none : .words)
                }
            }
            .font(.body)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color(UIColor.systemBackground))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color(UIColor.separator).opacity(0.5), lineWidth: 1)
            )
        }
    }

    private func createAccount() {
        guard password == confirmPassword else {
            userAccountManager.authStatus = .failed("Passwords don't match")
            return
        }

        guard password.count >= 6 else {
            userAccountManager.authStatus = .failed("Password must be at least 6 characters")
            return
        }

        Task {
            do {
                try await userAccountManager.convertGuestToAccount(
                    email: email.trimmingCharacters(in: .whitespacesAndNewlines),
                    password: password,
                    displayName: name.trimmingCharacters(in: .whitespacesAndNewlines)
                )

                // Success - dismiss after a short delay
                try? await Task.sleep(nanoseconds: 1_500_000_000) // 1.5 seconds
                await MainActor.run {
                    presentationMode.wrappedValue.dismiss()
                }
            } catch {
                // Error already handled by the account manager
                print("Error creating account from guest mode: \(error)")
            }
        }
    }

    private var isFormValid: Bool {
        !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !password.isEmpty &&
        !confirmPassword.isEmpty &&
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        password.count >= 6
    }
}

struct SignOutRowView: View {
    @ObservedObject var userAccountManager: FirebaseUserAccountManager
    
    var body: some View {
        Button(action: {
            userAccountManager.logout()
        }) {
            HStack {
                if userAccountManager.authStatus == .loading {
                    ProgressView()
                        .frame(width: 20, height: 20)
                } else {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                        .foregroundColor(.red)
                        .frame(width: 20, height: 20)
                }
                
                Text(userAccountManager.authStatus == .loading ? "Syncing & Signing Out..." : "Sign Out")
                    .foregroundColor(.red)
                
                Spacer()
            }
        }
        .disabled(userAccountManager.authStatus == .loading)
        .padding(.vertical, 2)
        .onAppear {
            // Only refresh user state if user is authenticated and we haven't checked recently
            if userAccountManager.isAuthenticated && !userAccountManager.hasRecentlyRefreshed {
                userAccountManager.refreshUserState()
            }
        }
    }
}

struct AccountManagementView: View {
    @ObservedObject var userAccountManager: FirebaseUserAccountManager
    @State private var editingName = false
    @State private var newName = ""
    @State private var showingPasswordChange = false
    @State private var showingDeleteConfirmation = false
    @State private var showingDeletePasswordPrompt = false
    @Environment(\.presentationMode) var presentationMode
    
    var body: some View {
        GeometryReader { geometry in
                VStack(spacing: 0) {
                    // Dynamic safe area spacer that adapts to device
                    Rectangle()
                        .fill(
                            LinearGradient(
                                gradient: Gradient(colors: [
                                    Color(UIColor.systemBackground),
                                    Color(UIColor.systemBackground).opacity(0.98)
                                ]),
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(height: max(geometry.safeAreaInsets.top + 10, 60))
                    
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            // Name editing card
                            if editingName {
                                VStack(alignment: .leading, spacing: 16) {
                                    HStack(spacing: 16) {
                                        Circle()
                                            .fill(Color.blue)
                                            .frame(width: 48, height: 48)
                                            .overlay(
                                                Image(systemName: "person.fill")
                                                    .font(.system(size: 18, weight: .semibold))
                                                    .foregroundColor(.white)
                                            )
                                        
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text("Edit Name")
                                                .font(.system(size: 17, weight: .semibold, design: .rounded))
                                                .foregroundColor(.primary)
                                            
                                            Text("Update your display name")
                                                .font(.system(size: 14))
                                                .foregroundColor(.secondary)
                                        }
                                        
                                        Spacer()
                                    }
                                    
                                    VStack(spacing: 12) {
                                        TextField("Enter your full name", text: $newName)
                                            .font(.body)
                                            .padding(.horizontal, 16)
                                            .padding(.vertical, 12)
                                            .background(Color(UIColor.tertiarySystemBackground))
                                            .cornerRadius(12)
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 12)
                                                    .stroke(Color(UIColor.separator).opacity(0.5), lineWidth: 1)
                                            )
                                            .textContentType(.name)
                                            .autocapitalization(.words)
                                        
                                        HStack(spacing: 12) {
                                            Button("Cancel") {
                                                editingName = false
                                                newName = userAccountManager.currentUserDisplayName ?? userAccountManager.currentUser?.displayName ?? ""
                                            }
                                            .font(.headline)
                                            .fontWeight(.semibold)
                                            .foregroundColor(.primary)
                                            .frame(maxWidth: .infinity)
                                            .frame(height: 50)
                                            .background(Color(UIColor.tertiarySystemBackground))
                                            .cornerRadius(12)
                                            
                                            Button("Save") {
                                                userAccountManager.updateUserName(newName: newName)
                                                editingName = false
                                            }
                                            .font(.headline)
                                            .fontWeight(.semibold)
                                            .foregroundColor(.white)
                                            .frame(maxWidth: .infinity)
                                            .frame(height: 50)
                                            .background(newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.gray : Color.blue)
                                            .cornerRadius(12)
                                            .disabled(newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                                        }
                                    }
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 16)
                                .background(
                                    RoundedRectangle(cornerRadius: 16)
                                        .fill(
                                        LinearGradient(
                                            gradient: Gradient(colors: [
                                                Color(UIColor.tertiarySystemBackground),
                                                Color(UIColor.tertiarySystemBackground).opacity(0.8)
                                            ]),
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 16)
                                                .stroke(Color(UIColor.separator).opacity(0.3), lineWidth: 1)
                                        )
                                        .shadow(color: Color.black.opacity(0.08), radius: 4, x: 0, y: 2)
                                )
                                .padding(.horizontal, 16)
                                .padding(.vertical, 4)
                            } else {
                                AccountCardView(
                                    icon: "person.fill",
                                    iconColor: .blue,
                                    title: "Name",
                                    subtitle: userAccountManager.currentUserDisplayName ?? userAccountManager.currentUser?.displayName ?? "Unknown",
                                    trailingContent: {
                                        Button("Edit") {
                                            newName = userAccountManager.currentUserDisplayName ?? userAccountManager.currentUser?.displayName ?? ""
                                            editingName = true
                                        }
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 6)
                                        .background(Color.blue)
                                        .cornerRadius(16)
                                    }
                                )
                            }
                            
                            // Email card
                            AccountCardView(
                                icon: "envelope.fill",
                                iconColor: .green,
                                title: "Email",
                                subtitle: userAccountManager.currentUser?.email ?? "Unknown",
                                trailingContent: {
                                    if FirebaseService.shared.currentUser?.isEmailVerified == true {
                                        Text("Verified")
                                            .font(.caption)
                                            .fontWeight(.semibold)
                                            .foregroundColor(.white)
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 6)
                                            .background(Color.green)
                                            .cornerRadius(16)
                                    } else {
                                        Button("Verify") {
                                            userAccountManager.resendVerificationEmail()
                                        }
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 6)
                                        .background(Color.orange)
                                        .cornerRadius(16)
                                    }
                                }
                            )
                            
                            // Email Verification Section (if not verified)
                            if FirebaseService.shared.currentUser?.isEmailVerified == false {
                                VStack(alignment: .leading, spacing: 12) {
                                    HStack {
                                        Image(systemName: "exclamationmark.triangle.fill")
                                            .foregroundColor(.orange)
                                        Text("Email not verified")
                                            .foregroundColor(.orange)
                                            .fontWeight(.semibold)
                                        Spacer()
                                    }
                                    
                                    Button("Check Verification Status") {
                                        userAccountManager.refreshUserState()
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(Color.green)
                                    .foregroundColor(.white)
                                    .cornerRadius(12)
                                    .fontWeight(.semibold)
                                    
                                    if case .failed(_) = userAccountManager.authStatus {
                                        Button("Resend Verification Email") {
                                            userAccountManager.resendVerificationEmail()
                                        }
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 12)
                                        .background(Color.blue)
                                        .foregroundColor(.white)
                                        .cornerRadius(12)
                                        .fontWeight(.semibold)
                                        .disabled(userAccountManager.authStatus == .loading)
                                    }
                                    
                                    Text("Check your email first, then use the button above to refresh your verification status.")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .multilineTextAlignment(.center)
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                                .background(
                                    RoundedRectangle(cornerRadius: 16)
                                        .fill(
                                        LinearGradient(
                                            gradient: Gradient(colors: [
                                                Color(UIColor.tertiarySystemBackground),
                                                Color(UIColor.tertiarySystemBackground).opacity(0.8)
                                            ]),
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 16)
                                                .stroke(Color.orange.opacity(0.3), lineWidth: 1)
                                        )
                                        .shadow(color: Color.black.opacity(0.08), radius: 4, x: 0, y: 2)
                                )
                                .padding(.horizontal, 16)
                                .padding(.vertical, 4)
                            }
                            
                            // Change Password Button
                            Button(action: {
                                showingPasswordChange = true
                            }) {
                                AccountCardView(
                                    icon: "key.fill",
                                    iconColor: .orange,
                                    title: "Change Password",
                                    showChevron: true
                                )
                            }
                            .buttonStyle(PlainButtonStyle())
                            
                            // Delete Account Button
                            Button(action: {
                                showingDeletePasswordPrompt = true
                            }) {
                                AccountCardView(
                                    icon: "trash.fill",
                                    iconColor: .red,
                                    title: "Delete Account",
                                    titleColor: .red
                                )
                            }
                            .buttonStyle(PlainButtonStyle())
                            
                            // Status Card
                            if userAccountManager.authStatus != .idle {
                                statusCard
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                    }
                }
                .navigationBarHidden(true)
                .navigationBarBackButtonHidden(true)
                .ignoresSafeArea(.all, edges: .top)
                .safeAreaInset(edge: .bottom) {
                    // Card-based back button at bottom
                    Button(action: {
                        presentationMode.wrappedValue.dismiss()
                    }) {
                        HStack {
                            Image(systemName: "chevron.left.circle.fill")
                                .font(.title3)
                            Text("Back to Settings")
                                .font(.headline)
                                .fontWeight(.semibold)
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(
                                    LinearGradient(
                                        gradient: Gradient(colors: [Color.blue, Color.blue.opacity(0.8)]),
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .shadow(color: .blue.opacity(0.3), radius: 4, x: 0, y: 2)
                        )
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(
                        Rectangle()
                            .fill(Color(UIColor.systemBackground))
                            .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: -2)
                    )
                }
        }
        .sheet(isPresented: $showingPasswordChange) {
            PasswordChangeView(userAccountManager: userAccountManager)
        }
        .sheet(isPresented: $showingDeletePasswordPrompt) {
            DeleteAccountView(userAccountManager: userAccountManager)
        }
        .onAppear {
            // Reset auth status when view appears
            userAccountManager.authStatus = .idle
        }
    }
    
    @ViewBuilder
    private var statusCard: some View {
        switch userAccountManager.authStatus {
        case .loading:
            AccountCardView(
                icon: "arrow.clockwise",
                iconColor: .orange,
                title: "Updating...",
                subtitle: "Please wait"
            )
        case .success:
            AccountCardView(
                icon: "checkmark.circle.fill",
                iconColor: .green,
                title: "Update successful",
                subtitle: "Changes have been saved"
            )
        case let .failed(error):
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Circle()
                        .fill(error.lowercased().contains("security check") || error.lowercased().contains("blocked") || error.lowercased().contains("too many requests") ? Color.orange : Color.red)
                        .frame(width: 48, height: 48)
                        .overlay(
                            Image(systemName: error.lowercased().contains("security check") || error.lowercased().contains("blocked") || error.lowercased().contains("too many requests") ? "shield.checkerboard" : "exclamationmark.triangle.fill")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(.white)
                        )
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Error")
                            .font(.system(size: 17, weight: .semibold, design: .rounded))
                            .foregroundColor(.primary)
                        
                        Text(error)
                            .font(.system(size: 14, weight: .regular, design: .rounded))
                            .foregroundColor(error.lowercased().contains("security check") || error.lowercased().contains("blocked") || error.lowercased().contains("too many requests") ? .orange : .red)
                            .lineLimit(nil)
                    }
                    
                    Spacer()
                }
                
                if error.lowercased().contains("security check") || error.lowercased().contains("blocked") || error.lowercased().contains("too many requests") {
                    Text("This is a temporary security measure. Your account is safe.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.leading)
                    
                    if userAccountManager.isSecurityBlocked && userAccountManager.securityBlockTimeRemaining > 0 {
                        HStack {
                            Image(systemName: "clock")
                                .foregroundColor(.orange)
                                .font(.caption)
                            
                            Text("Try again in: \(userAccountManager.formattedTimeRemaining)")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(.orange)
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                Color(UIColor.tertiarySystemBackground),
                                Color(UIColor.tertiarySystemBackground).opacity(0.8)
                            ]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color(UIColor.separator), lineWidth: 0.5)
                    )
            )
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
        case .idle:
            EmptyView()
        }
    }
}

struct PasswordChangeView: View {
    @ObservedObject var userAccountManager: FirebaseUserAccountManager
    @State private var currentPassword = ""
    @State private var newPassword = ""
    @State private var confirmPassword = ""
    @Environment(\.presentationMode) var presentationMode
    
    var body: some View {
        ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Password Fields Card
                    modernSectionCard(title: "Password Information", icon: "key.fill") {
                        VStack(spacing: 16) {
                            modernTextField(title: "Current Password", text: $currentPassword, icon: "lock.fill", isSecure: true)
                            
                            modernTextField(title: "New Password", text: $newPassword, icon: "lock.rotation", isSecure: true)
                            
                            modernTextField(title: "Confirm New Password", text: $confirmPassword, icon: "checkmark.seal.fill", isSecure: true)
                        }
                    }
                    
                    // Action Card
                    modernSectionCard(title: "Update Password", icon: "arrow.triangle.2.circlepath") {
                        VStack(spacing: 16) {
                            if userAccountManager.authStatus == .loading {
                                HStack {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                    Text("Updating password...")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                }
                                .frame(maxWidth: .infinity)
                                .frame(height: 50)
                                .background(Color(UIColor.tertiarySystemBackground))
                                .cornerRadius(12)
                            } else {
                                Button("Change Password") {
                                    guard newPassword == confirmPassword else {
                                        userAccountManager.authStatus = .failed("Passwords don't match")
                                        return
                                    }
                                    
                                    userAccountManager.changePassword(
                                        currentPassword: currentPassword,
                                        newPassword: newPassword
                                    )
                                }
                                .font(.headline)
                                .fontWeight(.semibold)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 50)
                                .background(isFormValid ? Color.blue : Color(UIColor.separator).opacity(0.3))
                                .cornerRadius(12)
                                .disabled(!isFormValid || userAccountManager.authStatus == .loading)
                            }
                        }
                    }
                    
                    // Error/Status Card
                    if case let .failed(error) = userAccountManager.authStatus {
                        modernSectionCard(title: "Error", icon: "exclamationmark.triangle.fill") {
                            VStack(spacing: 12) {
                                HStack {
                                    if error.lowercased().contains("security check") || error.lowercased().contains("blocked") || error.lowercased().contains("too many requests") {
                                        Image(systemName: "shield.checkerboard")
                                            .foregroundColor(.orange)
                                            .font(.title2)
                                    } else {
                                        Image(systemName: "exclamationmark.triangle.fill")
                                            .foregroundColor(.red)
                                            .font(.title2)
                                    }
                                    
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(error)
                                            .foregroundColor(error.lowercased().contains("security check") || error.lowercased().contains("blocked") || error.lowercased().contains("too many requests") ? .orange : .red)
                                            .font(.subheadline)
                                            .fontWeight(.medium)
                                        
                                        if error.lowercased().contains("security check") || error.lowercased().contains("blocked") || error.lowercased().contains("too many requests") {
                                            Text("This is a temporary security measure. Your account is safe.")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                    
                                    Spacer()
                                }
                                
                                if error.lowercased().contains("security check") || error.lowercased().contains("blocked") || error.lowercased().contains("too many requests") {
                                    if userAccountManager.isSecurityBlocked && userAccountManager.securityBlockTimeRemaining > 0 {
                                        HStack {
                                            Image(systemName: "clock")
                                                .foregroundColor(.orange)
                                            
                                            Text("Try again in: \(userAccountManager.formattedTimeRemaining)")
                                                .font(.subheadline)
                                                .fontWeight(.medium)
                                                .foregroundColor(.orange)
                                            
                                            Spacer()
                                        }
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 12)
                                        .background(Color.orange.opacity(0.1))
                                        .cornerRadius(8)
                                    }
                                }
                            }
                        }
                    }
                    
                    // Success Card
                    if case .success = userAccountManager.authStatus {
                        modernSectionCard(title: "Success", icon: "checkmark.circle.fill") {
                            VStack(spacing: 16) {
                                HStack {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.green)
                                        .font(.title2)
                                    
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Password Updated")
                                            .font(.subheadline)
                                            .fontWeight(.medium)
                                            .foregroundColor(.green)
                                        
                                        Text("Your password has been successfully changed")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    
                                    Spacer()
                                }
                                
                                Button("Close") {
                                    presentationMode.wrappedValue.dismiss()
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
                }
                .padding()
            }
            .navigationTitle("Change Password")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarHidden(true)
            .navigationBarBackButtonHidden(true)
            .safeAreaInset(edge: .bottom) {
                // Card-based back button
                Button(action: {
                    presentationMode.wrappedValue.dismiss()
                }) {
                    HStack {
                        Image(systemName: "chevron.left.circle.fill")
                            .font(.title3)
                        Text("Back to Account")
                            .font(.headline)
                            .fontWeight(.semibold)
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(
                                LinearGradient(
                                    gradient: Gradient(colors: [Color.blue, Color.blue.opacity(0.8)]),
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .shadow(color: .blue.opacity(0.3), radius: 4, x: 0, y: 2)
                    )
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(
                    Rectangle()
                        .fill(Color(UIColor.systemBackground))
                        .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: -2)
                )
            }
        .onAppear {
            userAccountManager.authStatus = .idle
        }
    }
    
    private func modernSectionCard<Content: View>(title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(.blue)
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
                .fill(
                    LinearGradient(
                        gradient: Gradient(colors: [
                            Color(UIColor.tertiarySystemBackground),
                            Color(UIColor.tertiarySystemBackground).opacity(0.8)
                        ]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .shadow(color: Color.black.opacity(0.08), radius: 4, x: 0, y: 2)
        )
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
            
            if isSecure {
                SecureField(title, text: text)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Color(UIColor.tertiarySystemBackground))
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color(UIColor.separator).opacity(0.5), lineWidth: 1)
                    )
            } else {
                TextField(title, text: text)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Color(UIColor.tertiarySystemBackground))
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color(UIColor.separator).opacity(0.5), lineWidth: 1)
                    )
            }
        }
    }
    
    private var isFormValid: Bool {
        !currentPassword.isEmpty && 
        !newPassword.isEmpty && 
        !confirmPassword.isEmpty && 
        newPassword.count >= 6
    }
}

struct AppPreferencesView: View {
    @ObservedObject private var preferences = AppPreferences.shared
    
    var body: some View {
        NavigationView {
            GeometryReader { geometry in
                VStack(spacing: 0) {
                    // Dynamic safe area spacer that adapts to device
                    Rectangle()
                        .fill(
                            LinearGradient(
                                gradient: Gradient(colors: [
                                    Color(UIColor.systemBackground),
                                    Color(UIColor.systemBackground).opacity(0.98)
                                ]),
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(height: max(geometry.safeAreaInsets.top + 10, 60))
                    
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            // Default Lead Status
                            PreferenceCardView(
                                icon: "person.badge.plus",
                                iconColor: .blue,
                                title: "Default Lead Status",
                                subtitle: "Status assigned to new leads",
                                trailingContent: {
                                    Picker("", selection: $preferences.defaultLeadStatus) {
                                        Text("Not Contacted").tag("not_contacted")
                                        Text("Interested").tag("interested")
                                        Text("Not Interested").tag("not_interested")
                                        Text("Not Home").tag("not_home")
                                        Text("Converted").tag("converted")
                                    }
                                    .pickerStyle(MenuPickerStyle())
                                }
                            )
                            
                            // Default Lead Sort
                            PreferenceCardView(
                                icon: "arrow.up.arrow.down",
                                iconColor: .orange,
                                title: "Default Lead Sort",
                                subtitle: "How leads are sorted in lists",
                                trailingContent: {
                                    Picker("", selection: $preferences.leadSortPreference) {
                                        Text("Date Updated").tag("date")
                                        Text("Name").tag("name")
                                        Text("Status").tag("status")
                                    }
                                    .pickerStyle(MenuPickerStyle())
                                }
                            )
                            
                            // Default Follow-up Time
                            PreferenceCardView(
                                icon: "clock.badge.checkmark",
                                iconColor: .green,
                                title: "Default Follow-up Time",
                                subtitle: "Time interval for new follow-ups",
                                trailingContent: {
                                    Picker("", selection: $preferences.defaultFollowUpTime) {
                                        Text("1 Hour").tag("1_hour")
                                        Text("4 Hours").tag("4_hours")
                                        Text("1 Day").tag("1_day")
                                        Text("3 Days").tag("3_days")
                                        Text("1 Week").tag("1_week")
                                    }
                                    .pickerStyle(MenuPickerStyle())
                                }
                            )
                            
                            // Default Check-in Type
                            PreferenceCardView(
                                icon: "door.left.hand.open",
                                iconColor: .purple,
                                title: "Default Check-in Type",
                                subtitle: "Method used for follow-up check-ins",
                                trailingContent: {
                                    Picker("", selection: $preferences.defaultCheckInType) {
                                        Text("Door Knock").tag("door_knock")
                                        Text("Phone Call").tag("phone_call")
                                        Text("Text Message").tag("text_message")
                                        Text("Email").tag("email")
                                    }
                                    .pickerStyle(MenuPickerStyle())
                                }
                            )
                            
                            // Default Map Type
                            PreferenceCardView(
                                icon: "map",
                                iconColor: .cyan,
                                title: "Default Map Type",
                                subtitle: "Map style when opening map view",
                                trailingContent: {
                                    Picker("", selection: $preferences.mapDefaultView) {
                                        Text("Standard").tag("standard")
                                        Text("Satellite").tag("satellite")
                                        Text("Hybrid").tag("hybrid")
                                    }
                                    .pickerStyle(MenuPickerStyle())
                                }
                            )
                            
                            // Auto Backup Frequency
                            PreferenceCardView(
                                icon: "icloud.and.arrow.up",
                                iconColor: .indigo,
                                title: "Auto Backup Frequency",
                                subtitle: "How often data is automatically backed up",
                                trailingContent: {
                                    Picker("", selection: $preferences.autoBackupFrequency) {
                                        Text("Daily").tag("daily")
                                        Text("Weekly").tag("weekly")
                                        Text("Monthly").tag("monthly")
                                        Text("Never").tag("never")
                                    }
                                    .pickerStyle(MenuPickerStyle())
                                }
                            )
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                    }
                }
                .navigationBarHidden(true)
                .ignoresSafeArea(.all, edges: .top)
            }
        }
    }
}

struct DeleteAccountView: View {
    @ObservedObject var userAccountManager: FirebaseUserAccountManager
    @State private var password = ""
    @Environment(\.presentationMode) var presentationMode
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 50))
                        .foregroundColor(.red)
                    
                    Text("Delete Account")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    
                    Text("This action cannot be undone and will permanently delete all your data.")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .padding(.bottom, 20)
                
                VStack(spacing: 16) {
                    Text("Enter your password to confirm account deletion:")
                        .font(.headline)
                        .multilineTextAlignment(.center)
                    
                    SecureField("Current Password", text: $password)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .textContentType(.password)
                }
                .padding(.horizontal)
                
                if userAccountManager.authStatus == .loading {
                    ProgressView("Deleting account...")
                        .padding()
                } else {
                    Button("Delete Account") {
                        userAccountManager.deleteAccount(currentPassword: password)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(isPasswordValid ? Color.red : Color.gray)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                    .disabled(!isPasswordValid || userAccountManager.authStatus == .loading)
                    .padding(.horizontal)
                }
                
                if case let .failed(error) = userAccountManager.authStatus {
                    VStack(spacing: 4) {
                        HStack {
                            if error.lowercased().contains("security check") || error.lowercased().contains("blocked") || error.lowercased().contains("too many requests") {
                                Image(systemName: "shield.checkerboard")
                                    .foregroundColor(.orange)
                                    .font(.caption)
                            } else {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.red)
                                    .font(.caption)
                            }
                            
                            Text(error)
                                .foregroundColor(error.lowercased().contains("security check") || error.lowercased().contains("blocked") || error.lowercased().contains("too many requests") ? .orange : .red)
                                .font(.caption)
                                .multilineTextAlignment(.center)
                        }
                        
                        if error.lowercased().contains("security check") || error.lowercased().contains("blocked") || error.lowercased().contains("too many requests") {
                            Text("This is a temporary security measure. Your account is safe.")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                            
                            // Show countdown timer if security block is active
                            if userAccountManager.isSecurityBlocked && userAccountManager.securityBlockTimeRemaining > 0 {
                                HStack {
                                    Image(systemName: "clock")
                                        .foregroundColor(.orange)
                                        .font(.caption2)
                                    
                                    Text("Try again in: \(userAccountManager.formattedTimeRemaining)")
                                        .font(.caption2)
                                        .fontWeight(.medium)
                                        .foregroundColor(.orange)
                                }
                                .padding(.top, 2)
                            }
                        }
                    }
                    .padding(.horizontal)
                }
                
                if case .success = userAccountManager.authStatus {
                    VStack(spacing: 16) {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("Account deleted successfully")
                                .foregroundColor(.green)
                                .fontWeight(.semibold)
                        }
                        .padding()
                        
                        Text("Your account and all associated data have been permanently deleted.")
                            .font(.caption)
                            .multilineTextAlignment(.center)
                            .foregroundColor(.secondary)
                            .padding(.horizontal)
                        
                        Button("Close") {
                            presentationMode.wrappedValue.dismiss()
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.green)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                        .padding(.horizontal)
                    }
                }
                
                Spacer()
            }
            .padding()
            .navigationTitle("Delete Account")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(
                trailing: Button("Cancel") {
                    presentationMode.wrappedValue.dismiss()
                }
            )
        }
        .onAppear {
            userAccountManager.authStatus = .idle
        }
    }
    
    private var isPasswordValid: Bool {
        !password.isEmpty
    }
}

// MARK: - Settings Card Components

struct AccountCardView<TrailingContent: View>: View {
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String?
    let titleColor: Color
    let showChevron: Bool
    let trailingContent: (() -> TrailingContent)?
    
    init(
        icon: String,
        iconColor: Color,
        title: String,
        subtitle: String? = nil,
        titleColor: Color = .primary,
        showChevron: Bool = false,
        @ViewBuilder trailingContent: @escaping () -> TrailingContent
    ) {
        self.icon = icon
        self.iconColor = iconColor
        self.title = title
        self.subtitle = subtitle
        self.titleColor = titleColor
        self.showChevron = showChevron
        self.trailingContent = trailingContent
    }
    
    init(
        icon: String,
        iconColor: Color,
        title: String,
        subtitle: String? = nil,
        titleColor: Color = .primary,
        showChevron: Bool = false
    ) where TrailingContent == EmptyView {
        self.icon = icon
        self.iconColor = iconColor
        self.title = title
        self.subtitle = subtitle
        self.titleColor = titleColor
        self.showChevron = showChevron
        self.trailingContent = nil
    }
    
    var body: some View {
        HStack(spacing: 16) {
            // Icon
            Circle()
                .fill(iconColor)
                .frame(width: 48, height: 48)
                .overlay(
                    Image(systemName: icon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.white)
                )
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundColor(titleColor)
                
                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(.system(size: 14, weight: .regular, design: .rounded))
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
            }
            
            Spacer()
            
            if let trailingContent = trailingContent {
                trailingContent()
            } else if showChevron {
                Image(systemName: "chevron.right")
                    .foregroundColor(.secondary)
                    .font(.system(size: 14, weight: .medium))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(
                    LinearGradient(
                        gradient: Gradient(colors: [
                            Color(UIColor.tertiarySystemBackground),
                            Color(UIColor.tertiarySystemBackground).opacity(0.8)
                        ]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color(UIColor.separator).opacity(0.3), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.08), radius: 4, x: 0, y: 2)
        )
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
    }
}

struct PreferenceCardView<TrailingContent: View>: View {
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String?
    let trailingContent: () -> TrailingContent
    
    init(
        icon: String,
        iconColor: Color,
        title: String,
        subtitle: String? = nil,
        @ViewBuilder trailingContent: @escaping () -> TrailingContent
    ) {
        self.icon = icon
        self.iconColor = iconColor
        self.title = title
        self.subtitle = subtitle
        self.trailingContent = trailingContent
    }
    
    var body: some View {
        HStack(spacing: 16) {
            // Icon
            Circle()
                .fill(iconColor)
                .frame(width: 48, height: 48)
                .overlay(
                    Image(systemName: icon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.white)
                )
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundColor(.primary)
                
                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(.system(size: 14, weight: .regular, design: .rounded))
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
            }
            
            Spacer()
            
            trailingContent()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(
                    LinearGradient(
                        gradient: Gradient(colors: [
                            Color(UIColor.tertiarySystemBackground),
                            Color(UIColor.tertiarySystemBackground).opacity(0.8)
                        ]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color(UIColor.separator).opacity(0.3), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.08), radius: 4, x: 0, y: 2)
        )
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
    }
}

#Preview {
    SettingsView()
}
