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
    @State private var selectedSyncProvider = CloudSyncProvider.current
    @State private var showingSyncProviderRestart = false
    @State private var showRestartNeeded = false
    @State private var isMigrating = false

    private var leadsCount: Int {
        let request = Lead.fetchRequest()
        return (try? viewContext.count(for: request)) ?? 0
    }

    private func performProviderSwitch() {
        let oldProvider = CloudSyncProvider.current
        let newProvider = selectedSyncProvider

        // If switching FROM Firebase, do a final sync first
        if oldProvider == .firebase && userAccountManager.isLoggedIn {
            isMigrating = true
            syncManager.startSync()

            // Wait for sync to finish, then notify user
            Task {
                // Poll sync status
                for _ in 0..<60 { // max 30 seconds
                    try? await Task.sleep(nanoseconds: 500_000_000)
                    if !syncManager.syncStatus.isBusy { break }
                }

                await MainActor.run {
                    isMigrating = false
                    CloudSyncProvider.current = newProvider
                    showRestartNeeded = true
                }
            }
        } else {
            CloudSyncProvider.current = newProvider
            showRestartNeeded = true
        }
    }

    private var syncStatusIcon: String {
        switch syncManager.syncStatus {
        case .idle: return "icloud.and.arrow.up"
        case .syncing, .downloading: return "arrow.clockwise"
        case .uploading: return "icloud.and.arrow.up.fill"
        case .completed: return "checkmark.icloud"
        case .failed: return "exclamationmark.icloud"
        }
    }

    private var syncStatusColor: Color {
        switch syncManager.syncStatus {
        case .idle: return Color.electricViolet
        case .syncing, .uploading, .downloading: return Color.electricViolet
        case .completed: return Color.statusInterested
        case .failed: return Color.statusNotInterested
        }
    }

    private var syncStatusText: String {
        syncManager.syncStatus.displayText.isEmpty
            ? (syncManager.lastSyncDate.map { "Last synced: \(DateFormatter.localizedString(from: $0, dateStyle: .none, timeStyle: .short))" } ?? "Ready to sync")
            : syncManager.syncStatus.displayText
    }
    
    var body: some View {
        NavigationView {
            List {
                // User Info Section
                Section("Account") {
                    if userAccountManager.isLoggedIn {
                        UserInfoRowView(userAccountManager: userAccountManager)

                        NavigationLink(destination: AccountManagementView(userAccountManager: userAccountManager)) {
                            HStack {
                                Image(systemName: "person.crop.circle.badge.gearshape")
                                    .foregroundColor(Color.electricViolet)
                                    .frame(width: 20)
                                Text("Manage Account")
                                Spacer()
                            }
                        }
                    } else if userAccountManager.isAppleAuthed {
                        UserInfoRowView(userAccountManager: userAccountManager)
                    } else {
                        GuestInfoRowView()

                        if CloudSyncProvider.current == .firebase {
                            NavigationLink(destination: AuthenticationView()) {
                                HStack {
                                    Image(systemName: "person.crop.circle.badge.plus")
                                        .foregroundColor(Color.statusInterested)
                                        .frame(width: 20)
                                    Text("Sign In or Create Account")
                                        .foregroundColor(Color.statusInterested)
                                        .fontWeight(.semibold)
                                    Spacer()
                                }
                            }
                        }

                    }
                }

                // Cloud Storage Provider
                Section {
                    Picker(selection: $selectedSyncProvider) {
                        ForEach(CloudSyncProvider.allCases, id: \.self) { provider in
                            Label(provider.displayName, systemImage: provider.icon)
                                .tag(provider)
                        }
                    } label: {
                        Label("Cloud Storage", systemImage: "cloud.fill")
                    }
                    .onChange(of: selectedSyncProvider) { _, newValue in
                        if newValue != CloudSyncProvider.current {
                            showingSyncProviderRestart = true
                        }
                    }
                } header: {
                    Text("Cloud Sync")
                } footer: {
                    switch selectedSyncProvider {
                    case .off:
                        Text("Data is stored locally only. No cloud backup.")
                    case .firebase:
                        Text("Syncs via Firebase. Requires account sign-in. Works across devices.")
                    case .icloud:
                        Text("Syncs automatically via iCloud. Uses your Apple ID. No sign-in needed.")
                    }
                }
                .alert("Switch to \(selectedSyncProvider.displayName)?", isPresented: $showingSyncProviderRestart) {
                    Button("Switch") {
                        performProviderSwitch()
                    }
                    Button("Cancel", role: .cancel) {
                        selectedSyncProvider = CloudSyncProvider.current
                    }
                } message: {
                    if CloudSyncProvider.current == .firebase && selectedSyncProvider == .icloud {
                        Text("A final Firebase sync will run first to ensure all your data is up to date. All \(leadsCount) leads will be uploaded to iCloud automatically.")
                    } else if selectedSyncProvider == .icloud {
                        Text("Your local data (\(leadsCount) leads) will be automatically uploaded to iCloud.")
                    } else {
                        Text("Your local data will be preserved with the new sync provider.")
                    }
                }
                .alert("Restart Required", isPresented: $showRestartNeeded) {
                    Button("OK") { }
                } message: {
                    Text("Please close and reopen the app for the sync provider change to take full effect.")
                }
                .overlay {
                    if isMigrating {
                        VStack(spacing: 12) {
                            ProgressView()
                                .controlSize(.large)
                                .tint(.electricViolet)
                            Text("Syncing from Firebase before switching...")
                                .font(.obsidianFootnote)
                                .foregroundColor(.textSecondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.obsidianBlack.opacity(0.9))
                    }
                }

                // Data Sync Section (only for logged-in users)
                if userAccountManager.isLoggedIn && selectedSyncProvider == .firebase {
                    Section("Firebase Sync") {
                    HStack {
                        if syncManager.syncStatus == .syncing {
                            ProgressView()
                                .scaleEffect(0.8)
                                .foregroundColor(Color.electricViolet)
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
                            .foregroundColor(Color.electricViolet)
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
                            .foregroundColor(Color.electricViolet)
                            .frame(width: 20)
                        
                        Text("Dark Mode")
                        
                        Spacer()
                        
                        Toggle("", isOn: $darkModeEnabled)
                    }
                    
                    NavigationLink(destination: NotificationSettingsView()) {
                        HStack {
                            Image(systemName: "bell.fill")
                                .foregroundColor(Color.statusNotHome)
                                .frame(width: 20)
                            Text("Notifications")
                            Spacer()
                        }
                    }
                    NavigationLink(destination: CalendarSettingsView()) {
                        HStack {
                            Image(systemName: "calendar")
                                .foregroundColor(Color.statusNotInterested)
                                .frame(width: 20)
                            Text("Calendar")
                            Spacer()
                        }
                    }
                    NavigationLink(destination: AppPreferencesView()) {
                        HStack {
                            Image(systemName: "gearshape.2.fill")
                                .foregroundColor(Color.textSecondary)
                                .frame(width: 20)
                            Text("App Preferences")
                            Spacer()
                        }
                    }
                    
                    NavigationLink(destination: AppointmentTypePresetsView()) {
                        HStack {
                            Image(systemName: "calendar.badge.plus")
                                .foregroundColor(Color.electricViolet)
                                .frame(width: 20)
                            Text("Appointment Types")
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
                            iconColor: Color.electricViolet,
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
                            .foregroundColor(Color.electricViolet)
                            .frame(width: 20)

                        Text("Version")

                        Spacer()

                        Text("1.0.0")
                            .foregroundColor(Color.textSecondary)
                    }
                }
                
                // Sign Out Section (only for logged-in users)
                if userAccountManager.hasActiveSession {
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
    }
}

struct GuestInfoRowView: View {
    private var provider: CloudSyncProvider {
        CloudSyncProvider.current
    }

    private var icon: String {
        switch provider {
        case .icloud: return "icloud.fill"
        case .firebase: return "person.crop.circle.badge.questionmark"
        case .off: return "iphone"
        }
    }

    private var color: Color {
        switch provider {
        case .icloud: return Color.statusConverted
        case .firebase: return Color.statusInterested
        case .off: return Color.textSecondary
        }
    }

    private var title: String {
        switch provider {
        case .icloud: return "iCloud Sync"
        case .firebase: return "Guest Account"
        case .off: return "Local Data"
        }
    }

    private var subtitle: String {
        switch provider {
        case .icloud: return "Uses your device Apple ID automatically"
        case .firebase: return "Sign in to use Firebase sync"
        case .off: return "Stored on this device"
        }
    }

    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(color)
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                    .foregroundColor(color)
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(Color.textSecondary)
            }

            Spacer()
        }
        .padding(.vertical, 2)
    }
}

struct UserInfoRowView: View {
    @ObservedObject var userAccountManager: FirebaseUserAccountManager

    private var displayName: String {
        if let firebaseUser = userAccountManager.currentUser {
            return userAccountManager.currentUserDisplayName ?? firebaseUser.displayName ?? "User"
        }
        if let appleName = userAccountManager.appleUserFullName, !appleName.isEmpty {
            return appleName
        }
        return "Signed in with Apple"
    }

    private var subtitle: String {
        if let firebaseEmail = userAccountManager.currentUser?.email, !firebaseEmail.isEmpty {
            return firebaseEmail
        }
        if let appleEmail = userAccountManager.appleUserEmail, !appleEmail.isEmpty {
            return appleEmail
        }
        return "Apple ID connected"
    }

    private var icon: String {
        userAccountManager.isAppleAuthed && !userAccountManager.isLoggedIn ? "applelogo" : "person.circle.fill"
    }

    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(Color.electricViolet)
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(displayName)
                    .font(.headline)
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(Color.textSecondary)
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
                    .foregroundColor(Color.statusNotHome)
                    .frame(width: 20, height: 20)

                Text("Exit Guest Mode")
                    .foregroundColor(Color.statusNotHome)

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
                    .fill(Color.obsidianBlack)
                    .frame(height: max(geometry.safeAreaInsets.top + 10, 60))

                ScrollView {
                    LazyVStack(spacing: 16) {
                        // Header
                        VStack(spacing: 12) {
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .fill(Color.statusInterested.opacity(0.1))
                                .frame(width: 80, height: 80)
                                .overlay(
                                    Image(systemName: "person.crop.circle.badge.plus")
                                        .font(.system(size: 32))
                                        .foregroundColor(Color.statusInterested)
                                )

                            VStack(spacing: 6) {
                                Text("Create Your Account")
                                    .font(.title2)
                                    .fontWeight(.bold)

                                Text("Save your data and access it from any device")
                                    .font(.subheadline)
                                    .foregroundColor(Color.textSecondary)
                                    .multilineTextAlignment(.center)
                            }
                        }
                        .padding(.top, 16)
                        .padding(.horizontal, 16)

                        // Form Card
                        VStack(alignment: .leading, spacing: 16) {
                            HStack {
                                Image(systemName: "person.text.rectangle")
                                    .foregroundColor(Color.statusInterested)
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
                                            Color.obsidianSurface,
                                            Color.obsidianSurface.opacity(0.8)
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
                                            gradient: Gradient(colors: [Color.statusInterested, Color.statusInterested.opacity(0.8)]),
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ) : LinearGradient(
                                            gradient: Gradient(colors: [Color.textSecondary, Color.textSecondary]),
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .shadow(color: isFormValid ? Color.statusInterested.opacity(0.3) : Color.clear, radius: 4, x: 0, y: 2)
                            )
                        }
                        .disabled(!isFormValid || userAccountManager.authStatus == .loading)
                        .padding(.horizontal, 16)

                        // Error Card
                        if case let .failed(error) = userAccountManager.authStatus {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundColor(Color.statusNotInterested)
                                    Text("Error")
                                        .fontWeight(.semibold)
                                }
                                Text(error)
                                    .font(.subheadline)
                                    .foregroundColor(Color.statusNotInterested)
                            }
                            .padding()
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.statusNotInterested.opacity(0.1))
                            )
                            .padding(.horizontal, 16)
                        }

                        // Success Card
                        if case .success = userAccountManager.authStatus {
                            VStack(spacing: 16) {
                                HStack {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(Color.statusInterested)
                                        .font(.title)
                                    Text("Account Created!")
                                        .font(.title3)
                                        .fontWeight(.semibold)
                                        .foregroundColor(Color.statusInterested)
                                }

                                Text("Your data has been successfully migrated to your new account.")
                                    .font(.subheadline)
                                    .foregroundColor(Color.textSecondary)
                                    .multilineTextAlignment(.center)
                            }
                            .padding()
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.statusInterested.opacity(0.1))
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
                                    gradient: Gradient(colors: [Color.electricViolet, Color.electricViolet.opacity(0.8)]),
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .shadow(color: Color.electricViolet.opacity(0.3), radius: 4, x: 0, y: 2)
                    )
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(
                    Rectangle()
                        .fill(Color.obsidianBlack)
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
                    .foregroundColor(Color.statusInterested)
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
            .background(Color.obsidianBlack)
            .cornerRadius(16)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.obsidianBorder.opacity(0.5), lineWidth: 0.5)
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
                        .foregroundColor(Color.statusNotInterested)
                        .frame(width: 20, height: 20)
                }

                Text(userAccountManager.authStatus == .loading ? "Syncing & Signing Out..." : "Sign Out")
                    .foregroundColor(Color.statusNotInterested)
                
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
                        .fill(Color.obsidianBlack)
                        .frame(height: max(geometry.safeAreaInsets.top + 10, 60))

                    ScrollView {
                        LazyVStack(spacing: 12) {
                            // Name editing card
                            if editingName {
                                VStack(alignment: .leading, spacing: 16) {
                                    HStack(spacing: 16) {
                                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                                            .fill(Color.electricViolet)
                                            .frame(width: 48, height: 48)
                                            .overlay(
                                                Image(systemName: "person.fill")
                                                    .font(.obsidianAction)
                                                    .foregroundColor(.white)
                                            )

                                        VStack(alignment: .leading, spacing: 4) {
                                            Text("Edit Name")
                                                .font(.obsidianTitle)
                                                .foregroundColor(Color.textPrimary)

                                            Text("Update your display name")
                                                .font(.obsidianFootnote)
                                                .foregroundColor(Color.textSecondary)
                                        }
                                        
                                        Spacer()
                                    }
                                    
                                    VStack(spacing: 12) {
                                        TextField("Enter your full name", text: $newName)
                                            .font(.body)
                                            .padding(.horizontal, 16)
                                            .padding(.vertical, 12)
                                            .background(Color.obsidianSurface)
                                            .cornerRadius(16)
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 12)
                                                    .stroke(Color.obsidianBorder.opacity(0.5), lineWidth: 0.5)
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
                                            .foregroundColor(Color.textPrimary)
                                            .frame(maxWidth: .infinity)
                                            .frame(height: 50)
                                            .background(Color.obsidianSurface)
                                            .cornerRadius(16)

                                            Button("Save") {
                                                userAccountManager.updateUserName(newName: newName)
                                                editingName = false
                                            }
                                            .font(.headline)
                                            .fontWeight(.semibold)
                                            .foregroundColor(.white)
                                            .frame(maxWidth: .infinity)
                                            .frame(height: 50)
                                            .background(newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.textSecondary : Color.electricViolet)
                                            .cornerRadius(16)
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
                                                Color.obsidianSurface,
                                                Color.obsidianSurface.opacity(0.8)
                                            ]),
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 16)
                                                .stroke(Color.obsidianBorder.opacity(0.3), lineWidth: 0.5)
                                        )
                                        .shadow(color: Color.black.opacity(0.08), radius: 4, x: 0, y: 2)
                                )
                                .padding(.horizontal, 16)
                                .padding(.vertical, 4)
                            } else {
                                AccountCardView(
                                    icon: "person.fill",
                                    iconColor: Color.electricViolet,
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
                                        .background(Color.electricViolet)
                                        .cornerRadius(16)
                                    }
                                )
                            }

                            // Email card
                            AccountCardView(
                                icon: "envelope.fill",
                                iconColor: Color.statusInterested,
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
                                            .background(Color.statusInterested)
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
                                        .background(Color.statusNotHome)
                                        .cornerRadius(16)
                                    }
                                }
                            )
                            
                            // Email Verification Section (if not verified)
                            if FirebaseService.shared.currentUser?.isEmailVerified == false {
                                VStack(alignment: .leading, spacing: 12) {
                                    HStack {
                                        Image(systemName: "exclamationmark.triangle.fill")
                                            .foregroundColor(Color.statusNotHome)
                                        Text("Email not verified")
                                            .foregroundColor(Color.statusNotHome)
                                            .fontWeight(.semibold)
                                        Spacer()
                                    }
                                    
                                    Button("Check Verification Status") {
                                        userAccountManager.refreshUserState()
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(Color.statusInterested)
                                    .foregroundColor(.white)
                                    .cornerRadius(16)
                                    .fontWeight(.semibold)
                                    
                                    if case .failed(_) = userAccountManager.authStatus {
                                        Button("Resend Verification Email") {
                                            userAccountManager.resendVerificationEmail()
                                        }
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 12)
                                        .background(Color.electricViolet)
                                        .foregroundColor(.white)
                                        .cornerRadius(16)
                                        .fontWeight(.semibold)
                                        .disabled(userAccountManager.authStatus == .loading)
                                    }
                                    
                                    Text("Check your email first, then use the button above to refresh your verification status.")
                                        .font(.caption)
                                        .foregroundColor(Color.textSecondary)
                                        .multilineTextAlignment(.center)
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                                .background(
                                    RoundedRectangle(cornerRadius: 16)
                                        .fill(
                                        LinearGradient(
                                            gradient: Gradient(colors: [
                                                Color.obsidianSurface,
                                                Color.obsidianSurface.opacity(0.8)
                                            ]),
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 16)
                                                .stroke(Color.statusNotHome.opacity(0.3), lineWidth: 0.5)
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
                                    iconColor: Color.statusNotHome,
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
                                    iconColor: Color.statusNotInterested,
                                    title: "Delete Account",
                                    titleColor: Color.statusNotInterested
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
                                        gradient: Gradient(colors: [Color.electricViolet, Color.electricViolet.opacity(0.8)]),
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .shadow(color: Color.electricViolet.opacity(0.3), radius: 4, x: 0, y: 2)
                        )
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(
                        Rectangle()
                            .fill(Color.obsidianBlack)
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
                iconColor: Color.statusNotHome,
                title: "Updating...",
                subtitle: "Please wait"
            )
        case .success:
            AccountCardView(
                icon: "checkmark.circle.fill",
                iconColor: Color.statusInterested,
                title: "Update successful",
                subtitle: "Changes have been saved"
            )
        case let .failed(error):
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(error.lowercased().contains("security check") || error.lowercased().contains("blocked") || error.lowercased().contains("too many requests") ? Color.statusNotHome : Color.statusNotInterested)
                        .frame(width: 48, height: 48)
                        .overlay(
                            Image(systemName: error.lowercased().contains("security check") || error.lowercased().contains("blocked") || error.lowercased().contains("too many requests") ? "shield.checkerboard" : "exclamationmark.triangle.fill")
                                .font(.obsidianAction)
                                .foregroundColor(.white)
                        )

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Error")
                            .font(.obsidianTitle)
                            .foregroundColor(Color.textPrimary)

                        Text(error)
                            .font(.obsidianFootnote)
                            .foregroundColor(error.lowercased().contains("security check") || error.lowercased().contains("blocked") || error.lowercased().contains("too many requests") ? Color.statusNotHome : Color.statusNotInterested)
                            .lineLimit(nil)
                    }
                    
                    Spacer()
                }
                
                if error.lowercased().contains("security check") || error.lowercased().contains("blocked") || error.lowercased().contains("too many requests") {
                    Text("This is a temporary security measure. Your account is safe.")
                        .font(.caption)
                        .foregroundColor(Color.textSecondary)
                        .multilineTextAlignment(.leading)

                    if userAccountManager.isSecurityBlocked && userAccountManager.securityBlockTimeRemaining > 0 {
                        HStack {
                            Image(systemName: "clock")
                                .foregroundColor(Color.statusNotHome)
                                .font(.caption)

                            Text("Try again in: \(userAccountManager.formattedTimeRemaining)")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(Color.statusNotHome)
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
                                Color.obsidianSurface,
                                Color.obsidianSurface.opacity(0.8)
                            ]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.obsidianBorder, lineWidth: 0.5)
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
                                        .foregroundColor(Color.textSecondary)
                                }
                                .frame(maxWidth: .infinity)
                                .frame(height: 50)
                                .background(Color.obsidianSurface)
                                .cornerRadius(16)
                            } else {
                                Button("Change Password") {
                                    guard newPassword == confirmPassword else {
                                        userAccountManager.authStatus = .failed("Passwords don't match")
                                        return
                                    }
                                    
                                    userAccountManager.updatePassword(
                                        currentPassword: currentPassword,
                                        newPassword: newPassword
                                    )
                                }
                                .font(.headline)
                                .fontWeight(.semibold)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 50)
                                .background(isFormValid ? Color.electricViolet : Color.obsidianBorder.opacity(0.3))
                                .cornerRadius(16)
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
                                            .foregroundColor(Color.statusNotHome)
                                            .font(.title2)
                                    } else {
                                        Image(systemName: "exclamationmark.triangle.fill")
                                            .foregroundColor(Color.statusNotInterested)
                                            .font(.title2)
                                    }

                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(error)
                                            .foregroundColor(error.lowercased().contains("security check") || error.lowercased().contains("blocked") || error.lowercased().contains("too many requests") ? Color.statusNotHome : Color.statusNotInterested)
                                            .font(.subheadline)
                                            .fontWeight(.medium)
                                        
                                        if error.lowercased().contains("security check") || error.lowercased().contains("blocked") || error.lowercased().contains("too many requests") {
                                            Text("This is a temporary security measure. Your account is safe.")
                                                .font(.caption)
                                                .foregroundColor(Color.textSecondary)
                                        }
                                    }
                                    
                                    Spacer()
                                }
                                
                                if error.lowercased().contains("security check") || error.lowercased().contains("blocked") || error.lowercased().contains("too many requests") {
                                    if userAccountManager.isSecurityBlocked && userAccountManager.securityBlockTimeRemaining > 0 {
                                        HStack {
                                            Image(systemName: "clock")
                                                .foregroundColor(Color.statusNotHome)

                                            Text("Try again in: \(userAccountManager.formattedTimeRemaining)")
                                                .font(.subheadline)
                                                .fontWeight(.medium)
                                                .foregroundColor(Color.statusNotHome)

                                            Spacer()
                                        }
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 12)
                                        .background(Color.statusNotHome.opacity(0.1))
                                        .cornerRadius(16)
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
                                        .foregroundColor(Color.statusInterested)
                                        .font(.title2)

                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Password Updated")
                                            .font(.subheadline)
                                            .fontWeight(.medium)
                                            .foregroundColor(Color.statusInterested)

                                        Text("Your password has been successfully changed")
                                            .font(.caption)
                                            .foregroundColor(Color.textSecondary)
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
                                .background(Color.statusInterested)
                                .cornerRadius(16)
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
                                    gradient: Gradient(colors: [Color.electricViolet, Color.electricViolet.opacity(0.8)]),
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .shadow(color: Color.electricViolet.opacity(0.3), radius: 4, x: 0, y: 2)
                    )
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(
                    Rectangle()
                        .fill(Color.obsidianBlack)
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
                    .foregroundColor(Color.electricViolet)
                    .font(.title2)

                Text(title)
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(Color.textPrimary)

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
                            Color.obsidianSurface,
                            Color.obsidianSurface.opacity(0.8)
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
                    .foregroundColor(Color.electricViolet)
                    .frame(width: 20)

                Text(title)
                    .font(.headline)
                    .fontWeight(.semibold)
            }

            if isSecure {
                SecureField(title, text: text)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Color.obsidianSurface)
                    .cornerRadius(16)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.obsidianBorder.opacity(0.5), lineWidth: 0.5)
                    )
            } else {
                TextField(title, text: text)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Color.obsidianSurface)
                    .cornerRadius(16)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.obsidianBorder.opacity(0.5), lineWidth: 0.5)
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
                        .fill(Color.obsidianBlack)
                        .frame(height: max(geometry.safeAreaInsets.top + 10, 60))

                    ScrollView {
                        LazyVStack(spacing: 12) {
                            // Default Lead Status
                            PreferenceCardView(
                                icon: "person.badge.plus",
                                iconColor: Color.electricViolet,
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
                                iconColor: Color.statusNotHome,
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
                                iconColor: Color.statusInterested,
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
                                iconColor: Color.electricViolet,
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
                        .foregroundColor(Color.statusNotInterested)

                    Text("Delete Account")
                        .font(.largeTitle)
                        .fontWeight(.bold)

                    Text("This action cannot be undone and will permanently delete all your data.")
                        .font(.body)
                        .foregroundColor(Color.textSecondary)
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
                    .background(isPasswordValid ? Color.statusNotInterested : Color.textSecondary)
                    .foregroundColor(.white)
                    .cornerRadius(14)
                    .disabled(!isPasswordValid || userAccountManager.authStatus == .loading)
                    .padding(.horizontal)
                }
                
                if case let .failed(error) = userAccountManager.authStatus {
                    VStack(spacing: 4) {
                        HStack {
                            if error.lowercased().contains("security check") || error.lowercased().contains("blocked") || error.lowercased().contains("too many requests") {
                                Image(systemName: "shield.checkerboard")
                                    .foregroundColor(Color.statusNotHome)
                                    .font(.caption)
                            } else {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(Color.statusNotInterested)
                                    .font(.caption)
                            }

                            Text(error)
                                .foregroundColor(error.lowercased().contains("security check") || error.lowercased().contains("blocked") || error.lowercased().contains("too many requests") ? Color.statusNotHome : Color.statusNotInterested)
                                .font(.caption)
                                .multilineTextAlignment(.center)
                        }
                        
                        if error.lowercased().contains("security check") || error.lowercased().contains("blocked") || error.lowercased().contains("too many requests") {
                            Text("This is a temporary security measure. Your account is safe.")
                                .font(.caption2)
                                .foregroundColor(Color.textSecondary)
                                .multilineTextAlignment(.center)

                            // Show countdown timer if security block is active
                            if userAccountManager.isSecurityBlocked && userAccountManager.securityBlockTimeRemaining > 0 {
                                HStack {
                                    Image(systemName: "clock")
                                        .foregroundColor(Color.statusNotHome)
                                        .font(.caption2)

                                    Text("Try again in: \(userAccountManager.formattedTimeRemaining)")
                                        .font(.caption2)
                                        .fontWeight(.medium)
                                        .foregroundColor(Color.statusNotHome)
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
                                .foregroundColor(Color.statusInterested)
                            Text("Account deleted successfully")
                                .foregroundColor(Color.statusInterested)
                                .fontWeight(.semibold)
                        }
                        .padding()
                        
                        Text("Your account and all associated data have been permanently deleted.")
                            .font(.caption)
                            .multilineTextAlignment(.center)
                            .foregroundColor(Color.textSecondary)
                            .padding(.horizontal)
                        
                        Button("Close") {
                            presentationMode.wrappedValue.dismiss()
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.statusInterested)
                        .foregroundColor(.white)
                        .cornerRadius(14)
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
        titleColor: Color = Color.textPrimary,
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
        titleColor: Color = Color.textPrimary,
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
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(iconColor)
                .frame(width: 48, height: 48)
                .overlay(
                    Image(systemName: icon)
                        .font(.obsidianAction)
                        .foregroundColor(.white)
                )

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.obsidianTitle)
                    .foregroundColor(titleColor)

                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(.obsidianFootnote)
                        .foregroundColor(Color.textSecondary)
                        .lineLimit(2)
                }
            }

            Spacer()

            if let trailingContent = trailingContent {
                trailingContent()
            } else if showChevron {
                Image(systemName: "chevron.right")
                    .foregroundColor(Color.textSecondary)
                    .font(.obsidianFootnote)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(
                    LinearGradient(
                        gradient: Gradient(colors: [
                            Color.obsidianSurface,
                            Color.obsidianSurface.opacity(0.8)
                        ]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.obsidianBorder.opacity(0.3), lineWidth: 0.5)
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
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(iconColor)
                .frame(width: 48, height: 48)
                .overlay(
                    Image(systemName: icon)
                        .font(.obsidianAction)
                        .foregroundColor(.white)
                )

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.obsidianTitle)
                    .foregroundColor(Color.textPrimary)

                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(.obsidianFootnote)
                        .foregroundColor(Color.textSecondary)
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
                            Color.obsidianSurface,
                            Color.obsidianSurface.opacity(0.8)
                        ]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.obsidianBorder.opacity(0.3), lineWidth: 0.5)
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
