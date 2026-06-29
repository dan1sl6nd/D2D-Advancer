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

    private var localLeadCount: Int? {
        let request: NSFetchRequest<Lead> = Lead.fetchRequest(in: viewContext)
        do {
            return try viewContext.count(for: request)
        } catch {
            return nil
        }
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
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 16) {
                    ObsidianScreenTitle(
                        title: "Settings",
                        subtitle: "Account, sync, notifications, and app defaults.",
                        icon: "gearshape.2.fill"
                    )
                    .padding(.bottom, 2)

                    accountSettingsSection
                    cloudSyncSettingsSection

                    if userAccountManager.isLoggedIn && selectedSyncProvider == .firebase {
                        firebaseSyncSection
                    }

                    preferencesSection
                    helpSection
                    aboutSection

                    if userAccountManager.hasActiveSession {
                        signOutSection
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 18)
                .padding(.bottom, 28)
            }
            .background(Color.obsidianBlack.ignoresSafeArea())
            .navigationTitle("Settings")
            .obsidianInlineNavigation()
            .sheet(isPresented: $showingOnboarding) {
                OnboardingView(isPresented: $showingOnboarding)
                    .interactiveDismissDisabled()
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
                    Text(LeadCountDisplay.firebaseToICloudMessage(for: localLeadCount))
                } else if selectedSyncProvider == .icloud {
                    Text(LeadCountDisplay.iCloudUploadMessage(for: localLeadCount))
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
                    Color.obsidianBlack.opacity(0.92)
                        .ignoresSafeArea()

                    VStack(spacing: 12) {
                        ProgressView()
                            .controlSize(.large)
                            .tint(.electricViolet)

                        Text("Syncing from Firebase before switching...")
                            .font(.obsidianFootnote)
                            .foregroundColor(.textSecondary)
                    }
                    .padding(22)
                    .background(Color.obsidianSurface)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(Color.obsidianBorder.opacity(0.55), lineWidth: 0.5)
                    )
                }
            }
            .onAppear {
                selectedSyncProvider = CloudSyncProvider.current
                if userAccountManager.isAuthenticated && !userAccountManager.hasRecentlyRefreshed {
                    userAccountManager.refreshUserState()
                }
            }
        }
    }

    @ViewBuilder
    private var accountSettingsSection: some View {
        MoreSectionGroup(
            title: "Account",
            icon: accountIcon,
            subtitle: accountSubtitle,
            accentColor: accountTint
        ) {
            MoreCardView(
                icon: accountIcon,
                iconColor: accountTint,
                title: accountTitle,
                subtitle: accountSubtitle
            )

            if userAccountManager.isLoggedIn {
                settingsDivider

                NavigationLink(destination: AccountManagementView(userAccountManager: userAccountManager)) {
                    MoreCardView(
                        icon: "person.crop.circle.badge.gearshape",
                        iconColor: Color.electricViolet,
                        title: "Manage Account",
                        subtitle: "Name, password, email verification, and account deletion",
                        showChevron: true
                    )
                }
                .buttonStyle(PlainButtonStyle())
            } else if !userAccountManager.isAppleAuthed && CloudSyncProvider.current == .firebase {
                settingsDivider

                NavigationLink(destination: AuthenticationView()) {
                    MoreCardView(
                        icon: "person.crop.circle.badge.plus",
                        iconColor: Color.statusInterested,
                        title: "Sign In or Create Account",
                        subtitle: "Use Firebase sync across devices",
                        showChevron: true
                    )
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
    }

    private var cloudSyncSettingsSection: some View {
        MoreSectionGroup(
            title: "Cloud Sync",
            icon: selectedSyncProvider.icon,
            subtitle: syncProviderSubtitle,
            accentColor: syncProviderTint
        ) {
            MoreCardView(
                icon: "cloud.fill",
                iconColor: syncProviderTint,
                title: "Cloud Storage",
                subtitle: selectedSyncProvider.displayName,
                trailingContent: {
                    Picker("Cloud storage provider", selection: $selectedSyncProvider) {
                        ForEach(CloudSyncProvider.allCases, id: \.self) { provider in
                            Label(provider.displayName, systemImage: provider.icon)
                                .tag(provider)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .onChange(of: selectedSyncProvider) { _, newValue in
                        if newValue != CloudSyncProvider.current {
                            showingSyncProviderRestart = true
                        }
                    }
                }
            )
        }
    }

    private var firebaseSyncSection: some View {
        MoreSectionGroup(
            title: "Firebase Sync",
            icon: syncStatusIcon,
            subtitle: syncStatusText,
            accentColor: syncStatusColor
        ) {
            MoreCardView(
                icon: syncStatusIcon,
                iconColor: syncStatusColor,
                title: "Sync Data",
                subtitle: syncStatusText,
                trailingContent: {
                    if syncManager.syncStatus == .syncing {
                        ProgressView()
                            .scaleEffect(0.8)
                            .tint(Color.electricViolet)
                    } else {
                        Button("Sync") {
                            syncManager.syncWithServer()
                        }
                        .font(.obsidianFootnote)
                        .fontWeight(.semibold)
                        .foregroundColor(Color.electricViolet)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(Color.electricViolet.opacity(0.12))
                        .clipShape(Capsule())
                    }
                }
            )
            .disabled(syncManager.syncStatus == .syncing)

            settingsDivider

            MoreCardView(
                icon: "arrow.triangle.2.circlepath",
                iconColor: Color.electricViolet,
                title: "Auto Sync",
                subtitle: "Automatically sync changes when Firebase is active",
                trailingContent: {
                    Toggle("Auto Sync", isOn: $syncManager.isAutoSyncEnabled)
                        .labelsHidden()
                        .toggleStyle(SwitchToggleStyle(tint: Color.electricViolet))
                        .accessibilityLabel("Auto Sync")
                        .accessibilityValue(syncManager.isAutoSyncEnabled ? "Enabled" : "Disabled")
                        .accessibilityHint("Toggles automatic data sync.")
                }
            )
        }
    }

    private var preferencesSection: some View {
        MoreSectionGroup(
            title: "Preferences",
            icon: "slider.horizontal.3",
            subtitle: "Customize how D2D Advancer behaves.",
            accentColor: Color.electricViolet
        ) {
            MoreCardView(
                icon: "moon.fill",
                iconColor: Color.electricViolet,
                title: "Dark Mode",
                subtitle: darkModeEnabled ? "Enabled" : "Disabled",
                trailingContent: {
                    Toggle("Dark Mode", isOn: $darkModeEnabled)
                        .labelsHidden()
                        .toggleStyle(SwitchToggleStyle(tint: Color.electricViolet))
                        .accessibilityLabel("Dark Mode")
                        .accessibilityValue(darkModeEnabled ? "Enabled" : "Disabled")
                        .accessibilityHint("Toggles dark appearance for the app.")
                }
            )

            settingsDivider
            settingsNavigationCard(title: "Notifications", subtitle: "Reminders and alerts", icon: "bell.fill", color: Color.statusNotHome) {
                NotificationSettingsView()
            }
            settingsDivider
            settingsNavigationCard(title: "Calendar", subtitle: "Calendar sync and appointment defaults", icon: "calendar", color: Color.statusNotInterested) {
                CalendarSettingsView()
            }
            settingsDivider
            settingsNavigationCard(title: "App Preferences", subtitle: "Default lead, follow-up, and map choices", icon: "gearshape.2.fill", color: Color.textSecondary) {
                AppPreferencesView()
            }
            settingsDivider
            settingsNavigationCard(title: "Appointment Types", subtitle: "Default and custom job types", icon: "calendar.badge.plus", color: Color.electricViolet) {
                AppointmentTypePresetsView()
            }
        }
    }

    private var helpSection: some View {
        MoreSectionGroup(
            title: "Help",
            icon: "questionmark.circle.fill",
            subtitle: "Restart onboarding whenever you need a refresher."
        ) {
            Button {
                OnboardingManager.shared.startOnboarding()
                showingOnboarding = true
            } label: {
                MoreCardView(
                    icon: "questionmark.circle",
                    iconColor: Color.electricViolet,
                    title: "Show Tutorial",
                    subtitle: "Walk through features and best practices"
                )
            }
            .buttonStyle(PlainButtonStyle())
            .accessibilityLabel("Show app tutorial")
            .accessibilityHint("Restart the onboarding tutorial to learn about app features")
        }
    }

    private var aboutSection: some View {
        MoreSectionGroup(
            title: "About",
            icon: "info.circle.fill",
            subtitle: "App version and release information."
        ) {
            MoreCardView(
                icon: "info.circle",
                iconColor: Color.electricViolet,
                title: "Version",
                subtitle: "1.0.0"
            )
        }
    }

    private var signOutSection: some View {
        MoreSectionGroup(
            title: "Session",
            icon: "rectangle.portrait.and.arrow.right",
            subtitle: "Sign out of the active account.",
            accentColor: Color.statusNotInterested
        ) {
            Button {
                userAccountManager.logout()
            } label: {
                MoreCardView(
                    icon: userAccountManager.authStatus == .loading ? "arrow.clockwise" : "rectangle.portrait.and.arrow.right",
                    iconColor: Color.statusNotInterested,
                    title: userAccountManager.authStatus == .loading ? "Syncing & Signing Out..." : "Sign Out",
                    subtitle: "Finish sync, then leave this account",
                    titleColor: Color.statusNotInterested
                )
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(userAccountManager.authStatus == .loading)
        }
    }

    private func settingsNavigationCard<Destination: View>(
        title: String,
        subtitle: String,
        icon: String,
        color: Color,
        @ViewBuilder destination: () -> Destination
    ) -> some View {
        NavigationLink(destination: destination()) {
            MoreCardView(
                icon: icon,
                iconColor: color,
                title: title,
                subtitle: subtitle,
                showChevron: true
            )
        }
        .buttonStyle(PlainButtonStyle())
    }

    private var settingsDivider: some View {
        Rectangle()
            .fill(Color.obsidianBorder.opacity(0.45))
            .frame(height: 0.5)
            .padding(.leading, 74)
    }

    private var accountTitle: String {
        if let firebaseUser = userAccountManager.currentUser {
            return userAccountManager.currentUserDisplayName ?? firebaseUser.displayName ?? "Signed In"
        }
        if userAccountManager.isAppleAuthed {
            let appleName = userAccountManager.appleUserFullName?.trimmingCharacters(in: .whitespacesAndNewlines)
            return appleName?.isEmpty == false ? (appleName ?? "Signed in with Apple") : "Signed in with Apple"
        }
        switch CloudSyncProvider.current {
        case .icloud: return "iCloud Sync"
        case .firebase: return "Guest Account"
        case .off: return "Local Data"
        }
    }

    private var accountSubtitle: String {
        if let firebaseEmail = userAccountManager.currentUser?.email, !firebaseEmail.isEmpty {
            return firebaseEmail
        }
        if let appleEmail = userAccountManager.appleUserEmail, !appleEmail.isEmpty {
            return appleEmail
        }
        if userAccountManager.isAppleAuthed {
            return "Apple ID connected"
        }
        switch CloudSyncProvider.current {
        case .icloud: return "Uses your device Apple ID automatically"
        case .firebase: return "Sign in to use Firebase sync"
        case .off: return "Stored on this device"
        }
    }

    private var accountIcon: String {
        if userAccountManager.isAppleAuthed && !userAccountManager.isLoggedIn {
            return "applelogo"
        }
        switch CloudSyncProvider.current {
        case .icloud: return "icloud.fill"
        case .firebase: return userAccountManager.isLoggedIn ? "person.circle.fill" : "person.crop.circle.badge.questionmark"
        case .off: return "iphone"
        }
    }

    private var accountTint: Color {
        if userAccountManager.isLoggedIn || userAccountManager.isAppleAuthed {
            return Color.electricViolet
        }
        switch CloudSyncProvider.current {
        case .icloud: return Color.statusConverted
        case .firebase: return Color.statusInterested
        case .off: return Color.textSecondary
        }
    }

    private var syncProviderSubtitle: String {
        switch selectedSyncProvider {
        case .off:
            return "Data is stored locally only. No cloud backup."
        case .firebase:
            return "Syncs via Firebase. Requires account sign-in. Works across devices."
        case .icloud:
            return "Syncs automatically via iCloud using your Apple ID."
        }
    }

    private var syncProviderTint: Color {
        switch selectedSyncProvider {
        case .off: return Color.textSecondary
        case .firebase: return Color.electricViolet
        case .icloud: return Color.statusConverted
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
                        .font(.obsidianCallout)
                        .foregroundColor(color)
                    Text(subtitle)
                        .font(.obsidianFootnote)
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
                        .font(.obsidianCallout)
                    Text(subtitle)
                        .font(.obsidianFootnote)
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
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                ObsidianScreenTitle(
                    title: "Create Account",
                    subtitle: "Save your guest data and sync it from any signed-in device.",
                    icon: "person.crop.circle.badge.plus"
                )

                ObsidianSectionCard(
                    title: "Account Information",
                    icon: "person.text.rectangle",
                    subtitle: "Use an email and password for Firebase sync.",
                    accentColor: Color.statusInterested
                ) {
                    VStack(spacing: 14) {
                        accountTextField(title: "Full Name", text: $name, icon: "person.fill")
                        accountTextField(title: "Email", text: $email, icon: "envelope.fill", keyboardType: .emailAddress)
                        accountTextField(title: "Password", text: $password, icon: "lock.fill", isSecure: true)
                        accountTextField(title: "Confirm Password", text: $confirmPassword, icon: "checkmark.seal.fill", isSecure: true)
                    }
                }

                if case let .failed(error) = userAccountManager.authStatus {
                    ObsidianStatusBanner(
                        icon: "exclamationmark.triangle.fill",
                        title: "Account creation failed",
                        message: error,
                        tint: Color.statusNotInterested
                    )
                }

                if case .success = userAccountManager.authStatus {
                    ObsidianStatusBanner(
                        icon: "checkmark.circle.fill",
                        title: "Account Created",
                        message: "Your guest data has been migrated to this account.",
                        tint: Color.statusInterested
                    )
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 18)
            .padding(.bottom, 28)
        }
        .background(Color.obsidianBlack.ignoresSafeArea())
        .navigationTitle("Create Account")
        .obsidianInlineNavigation()
        .safeAreaInset(edge: .bottom) {
            ObsidianBottomActionBar(
                isPrimaryDisabled: !isFormValid || userAccountManager.authStatus == .loading,
                primaryAction: createAccount,
                secondaryAction: { dismiss() },
                primaryLabel: {
                    if userAccountManager.authStatus == .loading {
                        Label("Creating...", systemImage: "arrow.clockwise")
                    } else {
                        Label("Create Account", systemImage: "checkmark.circle.fill")
                    }
                },
                secondaryLabel: {
                    Label("Cancel", systemImage: "xmark.circle.fill")
                }
            )
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
                    .font(.obsidianFootnote)
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
            .font(.obsidianCallout)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color.obsidianElevated)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
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
                    dismiss()
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
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                accountHero
                profileSection
                securitySection

                if FirebaseService.shared.currentUser?.isEmailVerified == false {
                    emailVerificationCard
                }

                if userAccountManager.authStatus != .idle {
                    statusCard
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 28)
        }
        .background(Color.obsidianBlack.ignoresSafeArea())
        .navigationTitle("Account")
        .obsidianInlineNavigation()
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

    private var accountHero: some View {
        HStack(alignment: .top, spacing: 14) {
            ObsidianIconTile(icon: "person.crop.circle.fill", tint: Color.electricViolet, size: 48, filled: true)

            VStack(alignment: .leading, spacing: 5) {
                Text(userAccountManager.currentUserDisplayName ?? userAccountManager.currentUser?.displayName ?? "Account")
                    .font(.obsidianHeadline)
                    .foregroundColor(Color.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)

                Text(userAccountManager.currentUser?.email ?? "Signed in")
                    .font(.obsidianFootnote)
                    .foregroundColor(Color.textSecondary)
                    .lineLimit(2)

                Text(FirebaseService.shared.currentUser?.isEmailVerified == true ? "Verified" : "Needs verification")
                    .font(.micro)
                    .foregroundColor(FirebaseService.shared.currentUser?.isEmailVerified == true ? Color.statusInterested : Color.statusNotHome)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background((FirebaseService.shared.currentUser?.isEmailVerified == true ? Color.statusInterested : Color.statusNotHome).opacity(0.12))
                    .clipShape(Capsule())
                    .padding(.top, 2)
            }

            Spacer(minLength: 0)
        }
        .padding(16)
        .background(Color.obsidianSurface)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.obsidianBorder.opacity(0.55), lineWidth: 0.5)
        )
    }

    private var profileSection: some View {
        MoreSectionGroup(
            title: "Profile",
            icon: "person.fill",
            subtitle: "Name and email shown on this account.",
            accentColor: Color.electricViolet
        ) {
            if editingName {
                editNameRow
            } else {
                MoreCardView(
                    icon: "person.fill",
                    iconColor: Color.electricViolet,
                    title: "Name",
                    subtitle: userAccountManager.currentUserDisplayName ?? userAccountManager.currentUser?.displayName ?? "Unknown",
                    trailingContent: {
                        Button("Edit") {
                            newName = userAccountManager.currentUserDisplayName ?? userAccountManager.currentUser?.displayName ?? ""
                            editingName = true
                        }
                        .font(.obsidianFootnote)
                        .fontWeight(.semibold)
                        .foregroundColor(Color.electricViolet)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(Color.electricViolet.opacity(0.12))
                        .clipShape(Capsule())
                    }
                )
            }

            Rectangle()
                .fill(Color.obsidianBorder.opacity(0.5))
                .frame(height: 0.5)
                .padding(.leading, 68)

            MoreCardView(
                icon: "envelope.fill",
                iconColor: Color.statusInterested,
                title: "Email",
                subtitle: userAccountManager.currentUser?.email ?? "Unknown",
                trailingContent: {
                    if FirebaseService.shared.currentUser?.isEmailVerified == true {
                        Text("Verified")
                            .font(.micro)
                            .foregroundColor(Color.statusInterested)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(Color.statusInterested.opacity(0.12))
                            .clipShape(Capsule())
                    } else {
                        Button("Verify") {
                            userAccountManager.resendVerificationEmail()
                        }
                        .font(.obsidianFootnote)
                        .fontWeight(.semibold)
                        .foregroundColor(Color.statusNotHome)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(Color.statusNotHome.opacity(0.12))
                        .clipShape(Capsule())
                    }
                }
            )
        }
    }

    private var editNameRow: some View {
        VStack(alignment: .leading, spacing: 12) {
            LeadFormTextField(
                title: "Display Name",
                placeholder: "Enter your full name",
                text: $newName,
                icon: "person.fill"
            )

            HStack(spacing: 10) {
                Button("Cancel") {
                    editingName = false
                    newName = userAccountManager.currentUserDisplayName ?? userAccountManager.currentUser?.displayName ?? ""
                }
                .frame(maxWidth: .infinity)
                .buttonStyle(ObsidianSecondaryButtonStyle())

                Button("Save") {
                    userAccountManager.updateUserName(newName: newName)
                    editingName = false
                }
                .frame(maxWidth: .infinity)
                .buttonStyle(ObsidianPrimaryButtonStyle())
                .disabled(newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .opacity(newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.55 : 1)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
    }

    private var securitySection: some View {
        MoreSectionGroup(
            title: "Security",
            icon: "lock.shield.fill",
            subtitle: "Password and account controls.",
            accentColor: Color.statusNotHome
        ) {
            Button {
                showingPasswordChange = true
            } label: {
                MoreCardView(
                    icon: "key.fill",
                    iconColor: Color.statusNotHome,
                    title: "Change Password",
                    subtitle: "Update your sign-in password",
                    showChevron: true
                )
            }
            .buttonStyle(PlainButtonStyle())

            Rectangle()
                .fill(Color.obsidianBorder.opacity(0.5))
                .frame(height: 0.5)
                .padding(.leading, 68)

            Button {
                showingDeletePasswordPrompt = true
            } label: {
                MoreCardView(
                    icon: "trash.fill",
                    iconColor: Color.statusNotInterested,
                    title: "Delete Account",
                    subtitle: "Permanently remove this account",
                    titleColor: Color.statusNotInterested,
                    subtitleColor: Color.statusNotInterested.opacity(0.72),
                    showChevron: true
                )
            }
            .buttonStyle(PlainButtonStyle())
        }
    }

    private var emailVerificationCard: some View {
        ObsidianSectionCard(
            title: "Email Not Verified",
            icon: "exclamationmark.triangle.fill",
            subtitle: "Check your inbox, then refresh your account status.",
            accentColor: Color.statusNotHome
        ) {
            VStack(spacing: 12) {
                Button {
                    userAccountManager.refreshUserState()
                } label: {
                    Label("Check Verification Status", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(ObsidianPrimaryButtonStyle())

                if case .failed(_) = userAccountManager.authStatus {
                    Button {
                        userAccountManager.resendVerificationEmail()
                    } label: {
                        Label("Resend Verification Email", systemImage: "envelope.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(ObsidianSecondaryButtonStyle())
                    .disabled(userAccountManager.authStatus == .loading)
                }
            }
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
            ObsidianSectionCard(
                title: "Error",
                icon: error.isSecurityOrRateLimitMessage ? "shield.checkerboard" : "exclamationmark.triangle.fill",
                subtitle: error,
                accentColor: error.isSecurityOrRateLimitMessage ? Color.statusNotHome : Color.statusNotInterested
            ) {
                if error.isSecurityOrRateLimitMessage {
                    Text("This is a temporary security measure. Your account is safe.")
                        .font(.obsidianFootnote)
                        .foregroundColor(Color.textSecondary)
                        .multilineTextAlignment(.leading)

                    if userAccountManager.isSecurityBlocked && userAccountManager.securityBlockTimeRemaining > 0 {
                        ObsidianStatusBanner(
                            icon: "clock",
                            title: "Try again in \(userAccountManager.formattedTimeRemaining)",
                            tint: Color.statusNotHome
                        )
                    }
                }
            }
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
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                sheetHeader

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        passwordFieldsSection
                        updateSection
                        passwordStatusSection
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 28)
                }
                .background(Color.obsidianBlack)
            }
            .background(Color.obsidianBlack)
            .navigationBarHidden(true)
        }
        .presentationBackground(Color.obsidianBlack)
        .onAppear {
            userAccountManager.authStatus = .idle
        }
    }

    private var sheetHeader: some View {
        HStack(alignment: .top, spacing: 12) {
            ObsidianIconTile(icon: "key.fill", tint: Color.statusNotHome, size: 42)

            VStack(alignment: .leading, spacing: 3) {
                Text("Change Password")
                    .font(.obsidianHeadline)
                    .foregroundColor(Color.textPrimary)

                Text("Use your current password to update account access.")
                    .font(.obsidianFootnote)
                    .foregroundColor(Color.textSecondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)

            ObsidianCompactIconButton(
                icon: "xmark",
                accessibilityLabel: "Close password change",
                accentColor: Color.textSecondary
            ) {
                dismiss()
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 18)
        .background(Color.obsidianBlack)
    }

    private var passwordFieldsSection: some View {
        ObsidianSectionCard(
            title: "Password Information",
            icon: "lock.fill",
            subtitle: "Enter your current password and choose a new one.",
            accentColor: Color.statusNotHome
        ) {
            VStack(spacing: 12) {
                passwordField(title: "Current Password", text: $currentPassword, icon: "lock.fill")
                passwordField(title: "New Password", text: $newPassword, icon: "lock.rotation")
                passwordField(title: "Confirm New Password", text: $confirmPassword, icon: "checkmark.seal.fill")
            }
        }
    }

    private var updateSection: some View {
        ObsidianSectionCard(
            title: "Update Password",
            icon: "arrow.triangle.2.circlepath",
            accentColor: Color.electricViolet
        ) {
            if userAccountManager.authStatus == .loading {
                ObsidianStatusBanner(
                    icon: "arrow.clockwise",
                    title: "Updating password...",
                    message: "Keep this screen open until the update finishes.",
                    tint: Color.electricViolet
                )
            } else {
                Button {
                    guard newPassword == confirmPassword else {
                        userAccountManager.authStatus = .failed("Passwords don't match")
                        return
                    }

                    userAccountManager.updatePassword(
                        currentPassword: currentPassword,
                        newPassword: newPassword
                    )
                } label: {
                    Label("Change Password", systemImage: "checkmark.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(ObsidianPrimaryButtonStyle())
                .disabled(!isFormValid || userAccountManager.authStatus == .loading)
                .opacity(isFormValid ? 1 : 0.55)
            }
        }
    }

    @ViewBuilder
    private var passwordStatusSection: some View {
        if case let .failed(error) = userAccountManager.authStatus {
            ObsidianSectionCard(
                title: "Error",
                icon: error.isSecurityOrRateLimitMessage ? "shield.checkerboard" : "exclamationmark.triangle.fill",
                subtitle: error,
                accentColor: error.isSecurityOrRateLimitMessage ? Color.statusNotHome : Color.statusNotInterested
            ) {
                if error.isSecurityOrRateLimitMessage {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("This is a temporary security measure. Your account is safe.")
                            .font(.obsidianFootnote)
                            .foregroundColor(Color.textSecondary)

                        if userAccountManager.isSecurityBlocked && userAccountManager.securityBlockTimeRemaining > 0 {
                            ObsidianStatusBanner(
                                icon: "clock",
                                title: "Try again in \(userAccountManager.formattedTimeRemaining)",
                                tint: Color.statusNotHome
                            )
                        }
                    }
                }
            }
        } else if case .success = userAccountManager.authStatus {
            ObsidianSectionCard(
                title: "Password Updated",
                icon: "checkmark.circle.fill",
                subtitle: "Your password has been successfully changed.",
                accentColor: Color.statusInterested
            ) {
                Button {
                    dismiss()
                } label: {
                    Label("Close", systemImage: "xmark.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(ObsidianPrimaryButtonStyle())
            }
        }
    }

    private func passwordField(title: String, text: Binding<String>, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundColor(Color.electricViolet)
                    .frame(width: 20)

                Text(title)
                    .font(.obsidianFootnote)
                    .foregroundColor(Color.textPrimary)
            }

            SecureField(title, text: text)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(Color.obsidianElevated)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.obsidianBorder.opacity(0.45), lineWidth: 0.5)
                )
                .foregroundColor(Color.textPrimary)
                .textContentType(.password)
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
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 16) {
                    ObsidianScreenTitle(
                        title: "App Preferences",
                        subtitle: "Default values for new leads, follow-ups, map, and backups.",
                        icon: "slider.horizontal.3"
                    )

                    MoreSectionGroup(
                        title: "Lead Defaults",
                        icon: "person.badge.plus",
                        subtitle: "Control how new leads appear by default."
                    ) {
                        PreferenceCardView(
                            icon: "person.badge.plus",
                            iconColor: Color.electricViolet,
                            title: "Default Lead Status",
                            subtitle: "Status assigned to new leads",
                            trailingContent: {
                                Picker("Default lead status", selection: $preferences.defaultLeadStatus) {
                                    Text("Not Contacted").tag("not_contacted")
                                    Text("Interested").tag("interested")
                                    Text("Not Interested").tag("not_interested")
                                    Text("Not Home").tag("not_home")
                                    Text("Converted").tag("converted")
                                }
                                .pickerStyle(.menu)
                                .labelsHidden()
                            }
                        )

                        preferencesDivider

                        PreferenceCardView(
                            icon: "arrow.up.arrow.down",
                            iconColor: Color.statusNotHome,
                            title: "Default Lead Sort",
                            subtitle: "How leads are sorted in lists",
                            trailingContent: {
                                Picker("Default lead sort", selection: $preferences.leadSortPreference) {
                                    Text("Date Updated").tag("date")
                                    Text("Name").tag("name")
                                    Text("Status").tag("status")
                                }
                                .pickerStyle(.menu)
                                .labelsHidden()
                            }
                        )
                    }

                    MoreSectionGroup(
                        title: "Follow-up Defaults",
                        icon: "clock.badge.checkmark",
                        subtitle: "Default reminders and check-in style.",
                        accentColor: Color.statusInterested
                    ) {
                        PreferenceCardView(
                            icon: "clock.badge.checkmark",
                            iconColor: Color.statusInterested,
                            title: "Default Follow-up Time",
                            subtitle: "Time interval for new follow-ups",
                            trailingContent: {
                                Picker("Default follow-up time", selection: $preferences.defaultFollowUpTime) {
                                    Text("1 Hour").tag("1_hour")
                                    Text("4 Hours").tag("4_hours")
                                    Text("1 Day").tag("1_day")
                                    Text("3 Days").tag("3_days")
                                    Text("1 Week").tag("1_week")
                                }
                                .pickerStyle(.menu)
                                .labelsHidden()
                            }
                        )

                        preferencesDivider

                        PreferenceCardView(
                            icon: "door.left.hand.open",
                            iconColor: Color.electricViolet,
                            title: "Default Check-in Type",
                            subtitle: "Method used for follow-up check-ins",
                            trailingContent: {
                                Picker("Default check-in type", selection: $preferences.defaultCheckInType) {
                                    Text("Door Knock").tag("door_knock")
                                    Text("Phone Call").tag("phone_call")
                                    Text("Text Message").tag("text_message")
                                    Text("Email").tag("email")
                                }
                                .pickerStyle(.menu)
                                .labelsHidden()
                            }
                        )
                    }

                    MoreSectionGroup(
                        title: "Map & Backup",
                        icon: "map",
                        subtitle: "Default map mode and backup frequency.",
                        accentColor: Color.dataCyan
                    ) {
                        PreferenceCardView(
                            icon: "map",
                            iconColor: .cyan,
                            title: "Default Map Type",
                            subtitle: "Map style when opening map view",
                            trailingContent: {
                                Picker("Default map type", selection: $preferences.mapDefaultView) {
                                    Text("Standard").tag("standard")
                                    Text("Satellite").tag("satellite")
                                    Text("Hybrid").tag("hybrid")
                                }
                                .pickerStyle(.menu)
                                .labelsHidden()
                            }
                        )

                        preferencesDivider

                        PreferenceCardView(
                            icon: "icloud.and.arrow.up",
                            iconColor: .indigo,
                            title: "Auto Backup Frequency",
                            subtitle: "How often data is automatically backed up",
                            trailingContent: {
                                Picker("Auto backup frequency", selection: $preferences.autoBackupFrequency) {
                                    Text("Daily").tag("daily")
                                    Text("Weekly").tag("weekly")
                                    Text("Monthly").tag("monthly")
                                    Text("Never").tag("never")
                                }
                                .pickerStyle(.menu)
                                .labelsHidden()
                            }
                        )
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 18)
                .padding(.bottom, 28)
            }
            .background(Color.obsidianBlack.ignoresSafeArea())
            .navigationTitle("App Preferences")
            .obsidianInlineNavigation()
        }
    }

    private var preferencesDivider: some View {
        Rectangle()
            .fill(Color.obsidianBorder.opacity(0.45))
            .frame(height: 0.5)
            .padding(.leading, 74)
    }
}

struct DeleteAccountView: View {
    @ObservedObject var userAccountManager: FirebaseUserAccountManager
    @State private var password = ""
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                deleteHeader

                ScrollView {
                    VStack(spacing: 16) {
                        ObsidianSectionCard(
                            title: "Permanent Action",
                            icon: "exclamationmark.triangle.fill",
                            subtitle: "This cannot be undone and permanently removes account data.",
                            accentColor: Color.statusNotInterested
                        ) {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Enter your current password to confirm deletion.")
                                    .font(.obsidianFootnote)
                                    .foregroundColor(Color.textSecondary)

                                SecureField("Current Password", text: $password)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 12)
                                    .background(Color.obsidianElevated)
                                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                                            .stroke(Color.obsidianBorder.opacity(0.45), lineWidth: 0.5)
                                    )
                                    .foregroundColor(Color.textPrimary)
                                    .textContentType(.password)
                            }
                        }

                        deleteActionSection
                        deleteStatusSection
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 28)
                }
                .background(Color.obsidianBlack)
            }
            .background(Color.obsidianBlack)
            .navigationBarHidden(true)
        }
        .presentationBackground(Color.obsidianBlack)
        .onAppear {
            userAccountManager.authStatus = .idle
        }
    }

    private var deleteHeader: some View {
        HStack(alignment: .top, spacing: 12) {
            ObsidianIconTile(icon: "trash.fill", tint: Color.statusNotInterested, size: 42)

            VStack(alignment: .leading, spacing: 3) {
                Text("Delete Account")
                    .font(.obsidianHeadline)
                    .foregroundColor(Color.textPrimary)

                Text("Confirm this only when you are sure.")
                    .font(.obsidianFootnote)
                    .foregroundColor(Color.textSecondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)

            ObsidianCompactIconButton(
                icon: "xmark",
                accessibilityLabel: "Close delete account",
                accentColor: Color.textSecondary
            ) {
                dismiss()
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 18)
        .background(Color.obsidianBlack)
    }

    private var deleteActionSection: some View {
        ObsidianSectionCard(
            title: "Confirm Deletion",
            icon: "lock.fill",
            accentColor: Color.statusNotInterested
        ) {
            if userAccountManager.authStatus == .loading {
                ObsidianStatusBanner(
                    icon: "arrow.clockwise",
                    title: "Deleting account...",
                    message: "Keep this screen open until deletion finishes.",
                    tint: Color.statusNotInterested
                )
            } else {
                Button {
                    userAccountManager.deleteAccount(currentPassword: password)
                } label: {
                    Label("Delete Account", systemImage: "trash.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(ObsidianDangerButtonStyle())
                .disabled(!isPasswordValid || userAccountManager.authStatus == .loading)
                .opacity(isPasswordValid ? 1 : 0.55)
            }
        }
    }

    @ViewBuilder
    private var deleteStatusSection: some View {
        if case let .failed(error) = userAccountManager.authStatus {
            ObsidianSectionCard(
                title: "Error",
                icon: error.isSecurityOrRateLimitMessage ? "shield.checkerboard" : "exclamationmark.triangle.fill",
                subtitle: error,
                accentColor: error.isSecurityOrRateLimitMessage ? Color.statusNotHome : Color.statusNotInterested
            ) {
                if error.isSecurityOrRateLimitMessage {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("This is a temporary security measure. Your account is safe.")
                            .font(.obsidianFootnote)
                            .foregroundColor(Color.textSecondary)

                        if userAccountManager.isSecurityBlocked && userAccountManager.securityBlockTimeRemaining > 0 {
                            ObsidianStatusBanner(
                                icon: "clock",
                                title: "Try again in \(userAccountManager.formattedTimeRemaining)",
                                tint: Color.statusNotHome
                            )
                        }
                    }
                }
            }
        } else if case .success = userAccountManager.authStatus {
            ObsidianSectionCard(
                title: "Account Deleted",
                icon: "checkmark.circle.fill",
                subtitle: "Your account and associated data have been permanently deleted.",
                accentColor: Color.statusInterested
            ) {
                Button {
                    dismiss()
                } label: {
                    Label("Close", systemImage: "xmark.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(ObsidianPrimaryButtonStyle())
            }
        }
    }
    
    private var isPasswordValid: Bool {
        !password.isEmpty
    }
}

private extension String {
    var isSecurityOrRateLimitMessage: Bool {
        let lowercasedMessage = lowercased()
        return lowercasedMessage.contains("security check")
            || lowercasedMessage.contains("blocked")
            || lowercasedMessage.contains("too many requests")
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
            ObsidianIconTile(icon: icon, tint: iconColor, size: 42)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.obsidianCallout)
                    .foregroundColor(titleColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)

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
        .padding(14)
        .background(Color.obsidianSurface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.obsidianBorder.opacity(0.55), lineWidth: 0.5)
        )
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
            ObsidianIconTile(icon: icon, tint: iconColor, size: 42)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.obsidianCallout)
                    .foregroundColor(Color.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)

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
        .padding(14)
        .background(Color.obsidianSurface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.obsidianBorder.opacity(0.55), lineWidth: 0.5)
        )
    }
}

#Preview {
    SettingsView()
}
