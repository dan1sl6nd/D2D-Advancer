import SwiftUI
import CoreData
import UniformTypeIdentifiers

enum SyncStatusSummaryPolicy {
    static func shortText(
        for status: UserDataSyncManager.SyncStatus,
        autoSyncEnabled: Bool,
        intervalShortName: String
    ) -> String {
        switch status {
        case .idle:
            return autoSyncEnabled ? intervalShortName : "Manual"
        case .syncing:
            return "Preparing..."
        case .uploading(let current, let total):
            return "Uploading \(current)/\(total)"
        case .downloading:
            return "Downloading..."
        case .completed:
            return "Done"
        case .failed(let message):
            return failedShortText(message)
        }
    }

    static func failedShortText(_ message: String) -> String {
        let normalized = message.lowercased()
        if normalized.contains("cloudkit container unavailable")
            || normalized.contains("not entitled")
            || normalized.contains("container unavailable") {
            return "iCloud unavailable"
        }

        if normalized.contains("offline") || normalized.contains("network") {
            return "Offline"
        }

        return "Failed"
    }
}

struct MoreView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.managedObjectContext) private var viewContext
    @ObservedObject private var preferences = AppPreferences.shared
    @ObservedObject private var userAccountManager = FirebaseUserAccountManager.shared
    @ObservedObject private var syncManager = UserDataSyncManager.shared
    @ObservedObject private var teamService = TeamFirebaseService.shared
    @State private var showingSyncSettings = false
    @State private var showingAuthentication = false
    @State private var exportFile: LeadExportFile?
    @State private var showingImportPicker = false
    @State private var importResult: LeadImportResult?
    @State private var importFailure: LeadImportFailure?
    @AppStorage("isDarkMode") private var darkModeEnabled = false
    @State private var showingCloudProviderSheet = false

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Lead.createdDate, ascending: false)],
        animation: .default
    ) private var allLeads: FetchedResults<Lead>

    private var isRunningUITests: Bool {
        ProcessInfo.processInfo.arguments.contains("-skipOnboardingForUITests")
    }

    private var shouldLoadTeamWorkspace: Bool {
        !isRunningUITests || FirebaseEmulatorConfiguration.isEnabled
    }

    private var teamSurfaceSummary: TeamWorkspaceSurfaceSummary? {
        TeamWorkspaceSurfaceSummary.make(
            team: teamService.activeTeam,
            currentMember: teamService.currentMember,
            members: teamService.teamMembers,
            leads: teamService.teamLeads,
            bookings: teamService.teamBookings,
            dutySessions: teamService.dutySessions,
            dutyLocationPoints: teamService.dutyLocationPoints,
            ownerNotifications: teamService.ownerNotifications
        )
    }

    private var roleContext: TeamRoleContext {
        TeamRoleContext(summary: teamSurfaceSummary)
    }
    
    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                let screenBackground = Color.obsidianBackground(for: colorScheme)

                VStack(spacing: 0) {
                    Rectangle()
                        .fill(screenBackground)
                        .frame(height: ObsidianLayout.safeAreaTop(geometry))
                    ObsidianHeaderView("More")

                    ScrollView {
                        LazyVStack(spacing: 16) {
                            accountHeroCard
                            todayActivityCard
                            workspaceSection
                            dataSyncSection
                            preferencesSection
                            accountSection
                            legalSupportSection
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                        .padding(.bottom, 24)
                    }
                    .background(screenBackground)
                }
                .navigationBarHidden(true)
                .ignoresSafeArea(.all, edges: .top)
                .background(screenBackground.ignoresSafeArea())
                .sheet(isPresented: $showingSyncSettings) {
                    SyncSettingsView()
                }
                .sheet(isPresented: $showingCloudProviderSheet) {
                    CloudProviderSheet()
                        .presentationDetents([.height(360)])
                }
                .sheet(isPresented: $showingAuthentication) {
                    AuthenticationSheetWrapper(isPresented: $showingAuthentication)
                }
                .sheet(item: $exportFile) { file in
                    ShareSheet(activityItems: [file.url])
                }
                .fileImporter(
                    isPresented: $showingImportPicker,
                    allowedContentTypes: [UTType.commaSeparatedText, UTType.plainText, UTType.text],
                    allowsMultipleSelection: false
                ) { result in
                    handleImportResult(result)
                }
                .alert(item: $importResult) { result in
                    let detail = result.errors.isEmpty
                        ? result.summary
                        : result.summary + "\n\n\(result.errors.count) issue(s). First: \(result.errors.first ?? "")"
                    return Alert(
                        title: Text("Import Complete"),
                        message: Text(detail),
                        dismissButton: .default(Text("OK"))
                    )
                }
                .alert(item: $importFailure) { failure in
                    Alert(
                        title: Text("Import Failed"),
                        message: Text(failure.message),
                        dismissButton: .default(Text("OK"))
                    )
                }
                .task {
                    await loadTeamWorkspaceIfNeeded()
                }
            }
        }
    }

    private var accountHeroCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                ObsidianIconTile(icon: accountHeroIcon, tint: accountHeroColor, size: 48, filled: true)

                VStack(alignment: .leading, spacing: 4) {
                    Text(accountHeadline)
                        .font(.obsidianHeadline)
                        .foregroundColor(Color.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)

                    Text(accountDetail)
                        .font(.obsidianFootnote)
                        .foregroundColor(Color.textSecondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }

            HStack(spacing: 8) {
                moreStatusPill(
                    icon: CloudSyncProvider.current.icon,
                    text: CloudSyncProvider.current == .off ? "Local only" : CloudSyncProvider.current.displayName,
                    color: cloudProviderColor
                )

                moreStatusPill(
                    icon: "mappin.and.ellipse",
                    text: "\(allLeads.count) leads",
                    color: Color.electricViolet
                )

                if let badgeCount = teamWorkspaceBadgeCount {
                    moreStatusPill(
                        icon: "bell.badge.fill",
                        text: "\(badgeCount) team",
                        color: Color.statusNotInterested
                    )
                }
            }
        }
        .padding(16)
        .background(Color.obsidianSurface)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.obsidianBorder.opacity(0.55), lineWidth: 0.5)
        )
    }

    private var workspaceSection: some View {
        MoreSectionGroup(
            title: roleContext.workspaceMenuTitle,
            icon: "square.grid.2x2.fill",
            subtitle: workspaceSectionSubtitle,
            accentColor: Color.electricViolet
        ) {
            NavigationLink(destination: OverviewContentView()) {
                MoreCardView(
                    icon: "chart.bar.fill",
                    iconColor: Color.electricViolet,
                    title: "Overview",
                    subtitle: "Statistics and performance metrics",
                    showChevron: true
                )
            }
            .buttonStyle(PlainButtonStyle())
            .accessibilityIdentifier("moreOverviewCard")

            moreDivider

            NavigationLink(destination: TeamWorkspaceView()) {
                MoreCardView(
                    icon: "person.3.fill",
                    iconColor: Color.electricViolet,
                    title: roleContext.workspaceMenuTitle,
                    subtitle: teamWorkspaceSubtitle,
                    showChevron: false,
                    trailingContent: {
                        HStack(spacing: 8) {
                            if let badgeCount = teamWorkspaceBadgeCount {
                                Text("\(badgeCount)")
                                    .font(.micro)
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 4)
                                    .background(Color.statusNotInterested)
                                    .clipShape(Capsule())
                            }

                            Image(systemName: "chevron.right")
                                .font(.obsidianFootnote)
                                .foregroundColor(Color.textSecondary)
                        }
                    }
                )
            }
            .buttonStyle(PlainButtonStyle())
            .accessibilityIdentifier("teamWorkspaceCard")

            moreDivider

            NavigationLink(destination: MessageTemplatesManagerView()) {
                MoreCardView(
                    icon: "text.bubble.fill",
                    iconColor: Color.electricViolet,
                    title: "Message Templates",
                    subtitle: "First-contact messages and replies",
                    showChevron: true
                )
            }
            .buttonStyle(PlainButtonStyle())
            .accessibilityIdentifier("moreMessageTemplatesCard")
        }
    }

    private var dataSyncSection: some View {
        MoreSectionGroup(
            title: "Data & Sync",
            icon: "externaldrive.connected.to.line.below.fill",
            subtitle: "Backups, imports, exports, and cloud controls.",
            accentColor: cloudProviderColor
        ) {
            Button {
                showingCloudProviderSheet = true
            } label: {
                MoreCardView(
                    icon: CloudSyncProvider.current.icon,
                    iconColor: cloudProviderColor,
                    title: "iCloud Sync",
                    subtitle: personalCloudSubtitle,
                    showChevron: true
                )
            }
            .buttonStyle(PlainButtonStyle())
            .accessibilityIdentifier("moreCloudStorageButton")

            if userAccountManager.hasActiveSession || CloudSyncProvider.current == .icloud {
                moreDivider

                Button {
                    if !syncManager.syncStatus.isBusy {
                        syncManager.syncWithServer()
                    }
                } label: {
                    MoreCardView(
                        icon: syncStatusIcon,
                        iconColor: syncStatusColor,
                        title: "Sync Data",
                        subtitle: syncStatusText,
                        trailingContent: {
                            if syncManager.syncStatus.isBusy {
                                ProgressView()
                                    .scaleEffect(0.8)
                            } else {
                                Image(systemName: "arrow.clockwise")
                                    .font(.obsidianFootnote)
                                    .foregroundColor(Color.electricViolet)
                            }
                        }
                    )
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(syncManager.syncStatus.isBusy)
                .accessibilityIdentifier("moreSyncDataButton")

                moreDivider

                Button {
                    showingSyncSettings = true
                } label: {
                    MoreCardView(
                        icon: "gearshape.fill",
                        iconColor: Color.electricViolet,
                        title: "Sync Settings",
                        subtitle: syncManager.isAutoSyncEnabled ? "Auto-sync \(syncManager.syncInterval.shortDisplayName)" : "Manual sync only",
                        showChevron: true
                    )
                }
                .buttonStyle(PlainButtonStyle())
                .accessibilityIdentifier("moreSyncSettingsButton")
            }

            moreDivider

            Button(action: exportLeadsToCSV) {
                MoreCardView(
                    icon: "square.and.arrow.up",
                    iconColor: allLeads.isEmpty ? Color.textMuted : Color.electricViolet,
                    title: "Export Leads",
                    subtitle: allLeads.isEmpty ? "No leads to export" : "\(allLeads.count) leads",
                    trailingContent: {
                        Image(systemName: "arrow.up.doc")
                            .font(.obsidianFootnote)
                            .foregroundColor(allLeads.isEmpty ? Color.textMuted : Color.electricViolet)
                    }
                )
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(allLeads.isEmpty)
            .accessibilityIdentifier("moreExportLeadsButton")

            moreDivider

            Button {
                showingImportPicker = true
            } label: {
                MoreCardView(
                    icon: "square.and.arrow.down",
                    iconColor: Color.electricViolet,
                    title: "Import Leads",
                    subtitle: "Load leads from a CSV file",
                    trailingContent: {
                        Image(systemName: "arrow.down.doc")
                            .font(.obsidianFootnote)
                            .foregroundColor(Color.electricViolet)
                    }
                )
            }
            .buttonStyle(PlainButtonStyle())
            .accessibilityIdentifier("moreImportLeadsButton")

            moreDivider

            NavigationLink(destination: AppleContactLeadImportView()) {
                MoreCardView(
                    icon: "person.crop.circle.badge.plus",
                    iconColor: Color.electricViolet,
                    title: "Apple Contacts",
                    subtitle: "Find Window or Gutter Cleaning leads",
                    showChevron: true
                )
            }
            .buttonStyle(PlainButtonStyle())
            .accessibilityIdentifier("moreAppleContactsImportCard")
        }
    }

    private var personalCloudSubtitle: String {
        switch CloudSyncProvider.current {
        case .firebase:
            return "Move legacy personal data to iCloud"
        case .icloud:
            return "On · Apple ID"
        case .off:
            return "Set up private iCloud sync"
        }
    }

    private var preferencesSection: some View {
        MoreSectionGroup(
            title: "Preferences",
            icon: "slider.horizontal.3",
            subtitle: "Notifications, calendar, defaults, and job labels.",
            accentColor: Color.statusNotHome
        ) {
            NavigationLink(destination: NotificationSettingsView()) {
                MoreCardView(
                    icon: "bell.fill",
                    iconColor: Color.statusNotHome,
                    title: "Notifications",
                    subtitle: "Sounds, reminders, and daily summary",
                    showChevron: true
                )
            }
            .buttonStyle(PlainButtonStyle())
            .accessibilityIdentifier("moreNotificationsCard")

            moreDivider

            NavigationLink(destination: CalendarSettingsView()) {
                MoreCardView(
                    icon: "calendar",
                    iconColor: Color.statusNotInterested,
                    title: "Calendar",
                    subtitle: "Apple Calendar sync and alerts",
                    showChevron: true
                )
            }
            .buttonStyle(PlainButtonStyle())
            .accessibilityIdentifier("moreCalendarSettingsCard")

            moreDivider

            NavigationLink(destination: AppPreferencesView()) {
                MoreCardView(
                    icon: "gearshape.2.fill",
                    iconColor: Color.textSecondary,
                    title: "App Preferences",
                    subtitle: "Default lead, follow-up, and map choices",
                    showChevron: true
                )
            }
            .buttonStyle(PlainButtonStyle())
            .accessibilityIdentifier("moreAppPreferencesCard")

            moreDivider

            NavigationLink(destination: AppointmentTypePresetsView()) {
                MoreCardView(
                    icon: "calendar.badge.plus",
                    iconColor: Color.electricViolet,
                    title: "Appointment Types",
                    subtitle: "Default and custom job labels",
                    showChevron: true
                )
            }
            .buttonStyle(PlainButtonStyle())
            .accessibilityIdentifier("moreAppointmentTypesCard")
        }
    }

    private var accountSection: some View {
        MoreSectionGroup(
            title: "Account & App",
            icon: "person.crop.circle.fill",
            subtitle: "Profile, appearance, and app info.",
            accentColor: accountHeroColor
        ) {
            accountManagementRow

            moreDivider

            MoreCardView(
                icon: "moon.fill",
                iconColor: Color.electricViolet,
                title: "Dark Mode",
                subtitle: darkModeEnabled ? "Enabled" : "Disabled",
                trailingContent: {
                    Toggle("Dark Mode", isOn: $darkModeEnabled)
                        .labelsHidden()
                        .accessibilityIdentifier("moreDarkModeToggle")
                        .accessibilityLabel("Dark Mode")
                        .accessibilityValue(darkModeEnabled ? "Enabled" : "Disabled")
                        .accessibilityHint("Toggles dark appearance for the app.")
                }
            )
            .accessibilityIdentifier("moreDarkModeCard")

            moreDivider

            MoreCardView(
                icon: "info.circle",
                iconColor: Color.electricViolet,
                title: "Version",
                subtitle: "D2D Advancer",
                trailingContent: {
                    Text(AppVersionDisplay.current)
                        .font(.obsidianFootnote)
                        .foregroundColor(Color.textSecondary)
                }
            )

            if userAccountManager.hasActiveSession {
                moreDivider
                SignOutCardView(userAccountManager: userAccountManager)
            }
        }
    }

    private var legalSupportSection: some View {
        MoreSectionGroup(
            title: "Legal & Support",
            icon: "questionmark.circle.fill",
            subtitle: "Policies, terms, and help.",
            accentColor: Color.statusInterested
        ) {
            if let privacyURL = URL(string: "https://dan1sl6nd.github.io/D2D-Advancer/PRIVACY_POLICY.html") {
                Link(destination: privacyURL) {
                    MoreCardView(
                        icon: "hand.raised.fill",
                        iconColor: Color.statusInterested,
                        title: "Privacy Policy",
                        subtitle: "How account, Team, and location data are handled",
                        showChevron: true
                    )
                }
                .buttonStyle(PlainButtonStyle())
                .accessibilityIdentifier("morePrivacyPolicyLink")
            }

            moreDivider

            if let termsURL = URL(string: "https://dan1sl6nd.github.io/D2D-Advancer/TERMS_OF_USE.html") {
                Link(destination: termsURL) {
                    MoreCardView(
                        icon: "doc.text.fill",
                        iconColor: Color.electricViolet,
                        title: "Terms of Use",
                        subtitle: "Subscription and service terms",
                        showChevron: true
                    )
                }
                .buttonStyle(PlainButtonStyle())
                .accessibilityIdentifier("moreTermsOfUseLink")
            }

            moreDivider

            if let supportURL = URL(string: "https://dan1sl6nd.github.io/D2D-Advancer/SUPPORT.html") {
                Link(destination: supportURL) {
                    MoreCardView(
                        icon: "lifepreserver.fill",
                        iconColor: Color.statusNotHome,
                        title: "Help & Support",
                        subtitle: "Troubleshooting and contact information",
                        showChevron: true
                    )
                }
                .buttonStyle(PlainButtonStyle())
                .accessibilityIdentifier("moreSupportLink")
            }
        }
    }

    @ViewBuilder
    private var accountManagementRow: some View {
        if userAccountManager.isLoggedIn {
            NavigationLink(destination: AccountManagementView(userAccountManager: userAccountManager)) {
                accountRow(showChevron: true)
            }
            .buttonStyle(PlainButtonStyle())
            .accessibilityIdentifier("moreAccountCard")
        } else if CloudSyncProvider.current == .firebase {
            Button {
                showingAuthentication = true
            } label: {
                accountRow(showChevron: true)
            }
            .buttonStyle(PlainButtonStyle())
            .accessibilityIdentifier("moreAccountCard")
        } else {
            Button {
                showingCloudProviderSheet = true
            } label: {
                accountRow(showChevron: true)
            }
            .buttonStyle(PlainButtonStyle())
            .accessibilityIdentifier("moreAccountCard")
        }
    }

    private func accountRow(showChevron: Bool) -> some View {
        MoreCardView(
            icon: accountHeroIcon,
            iconColor: accountHeroColor,
            title: accountHeadline,
            subtitle: accountDetail,
            showChevron: showChevron
        )
    }

    private var moreDivider: some View {
        Rectangle()
            .fill(Color.obsidianBorder.opacity(0.5))
            .frame(height: 0.5)
            .padding(.leading, 68)
    }

    private func moreStatusPill(icon: String, text: String, color: Color) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.micro)
            Text(text)
                .font(.micro)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .foregroundColor(color)
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(color.opacity(0.12))
        .clipShape(Capsule())
    }

    private var accountHeadline: String {
        if isICloudGuest {
            return "iCloud Sync"
        }
        if isLocalOnlyGuest {
            return "Local Data"
        }
        if let firebaseName = userAccountManager.currentUser?.displayName, !firebaseName.isEmpty {
            return firebaseName
        }
        if let appleName = userAccountManager.appleUserFullName, !appleName.isEmpty {
            return appleName
        }
        return isGuestAccount ? "Guest Account" : "Signed in"
    }

    private var accountDetail: String {
        if isICloudGuest {
            return "Using the Apple ID on this device"
        }
        if isLocalOnlyGuest {
            return "Stored only on this device"
        }
        if let firebaseEmail = userAccountManager.currentUser?.email, !firebaseEmail.isEmpty {
            return firebaseEmail
        }
        if let appleEmail = userAccountManager.appleUserEmail, !appleEmail.isEmpty {
            return appleEmail
        }
        if userAccountManager.isAppleAuthed && !userAccountManager.isLoggedIn {
            return "Signed in with Apple"
        }
        return isGuestAccount ? "Sign in to sync with Firebase" : "No email"
    }

    private var accountHeroIcon: String {
        if isICloudGuest {
            return "icloud.fill"
        }
        if isLocalOnlyGuest {
            return "iphone"
        }
        if userAccountManager.isAppleAuthed && !userAccountManager.isLoggedIn {
            return "applelogo"
        }
        return isGuestAccount ? "person.crop.circle.badge.questionmark" : "person.fill"
    }

    private var accountHeroColor: Color {
        if isICloudGuest {
            return Color.statusConverted
        }
        if isLocalOnlyGuest {
            return Color.textSecondary
        }
        return isGuestAccount ? Color.statusNotHome : Color.electricViolet
    }

    private var cloudProviderColor: Color {
        switch CloudSyncProvider.current {
        case .off:
            return Color.textSecondary
        case .firebase:
            return Color.electricViolet
        case .icloud:
            return Color.statusConverted
        }
    }

    private var isGuestAccount: Bool {
        !userAccountManager.hasActiveSession
    }

    private var isICloudGuest: Bool {
        isGuestAccount && CloudSyncProvider.current == .icloud
    }

    private var isLocalOnlyGuest: Bool {
        isGuestAccount && CloudSyncProvider.current == .off
    }

    private var teamWorkspaceSubtitle: String {
        guard let summary = teamSurfaceSummary else {
            return roleContext.workspaceMenuSubtitle
        }
        return "\(summary.headline) • \(summary.detailLine)"
    }

    private var workspaceSectionSubtitle: String {
        switch roleContext {
        case .owner:
            return "Team admin, reports, and customer messaging."
        case .salesRep:
            return "Assigned leads, replies, and customer messaging."
        case .technician:
            return "Assigned jobs, route status, and team access."
        case .solo:
            return "Reports, team setup, and customer messaging."
        }
    }

    private var teamWorkspaceBadgeCount: Int? {
        guard let count = teamSurfaceSummary?.badgeCount, count > 0 else { return nil }
        return min(count, 99)
    }

    private func loadTeamWorkspaceIfNeeded() async {
        guard shouldLoadTeamWorkspace else { return }
        await teamService.loadCurrentTeam(
            displayName: userAccountManager.currentUserDisplayName,
            email: userAccountManager.currentUserEmail
        )
    }

    // MARK: - Import Handling

    private func handleImportResult(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            do {
                let result = try LeadCSVService.importLeads(from: url, into: viewContext)
                if NotificationService.shouldRefreshNotificationsAfterLeadDataMutation(
                    inserted: result.created,
                    updated: result.updated
                ) {
                    NotificationService.shared.refreshAllNotifications()
                }
                self.importResult = result
            } catch {
                self.importFailure = LeadImportFailure(message: error.localizedDescription)
            }
        case .failure(let error):
            self.importFailure = LeadImportFailure(message: error.localizedDescription)
        }
    }
    
    // MARK: - Daily Activity

    private var todayActivityCard: some View {
        let startOfDay = Calendar.current.startOfDay(for: Date())
        let todayLeads = allLeads.filter { ($0.createdDate ?? .distantPast) >= startOfDay }
        let doorsKnocked = todayLeads.count
        let interested = todayLeads.filter { $0.status == "interested" }.count
        let notHome = todayLeads.filter { $0.status == "not_home" }.count
        let sold = todayLeads.filter { $0.status == "converted" }.count
        let followUpsDue = allLeads.filter {
            $0.leadStatus.allowsActiveFollowUp && $0.followUpDate != nil && ($0.followUpDate ?? .distantFuture) <= Date()
        }.count
        let followUpsTotal = allLeads.filter {
            $0.leadStatus.allowsActiveFollowUp && $0.followUpDate != nil
        }.count
        let statColumns = [
            GridItem(.flexible(), spacing: 10),
            GridItem(.flexible(), spacing: 10)
        ]

        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                ObsidianIconTile(icon: "flame.fill", tint: Color.electricViolet, size: 36)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Today's Activity")
                        .font(.obsidianTitle)
                        .foregroundColor(.textPrimary)

                    Text(Date().formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
                        .font(.obsidianFootnote)
                        .foregroundColor(.textSecondary)
                }

                Spacer()
            }

            LazyVGrid(columns: statColumns, spacing: 10) {
                activityStat(value: doorsKnocked, label: "Doors", color: .electricViolet)
                activityStat(value: interested, label: "Interested", color: .statusInterested)
                activityStat(value: notHome, label: "Not Home", color: .statusNotHome)
                activityStat(value: sold, label: "Sold", color: .statusConverted)
            }

            if followUpsTotal > 0 {
                HStack(spacing: 10) {
                    Image(systemName: "bell.badge")
                        .font(.obsidianFootnote)
                        .foregroundColor(.statusNotHome)

                    Text("\(followUpsDue) overdue")
                        .font(.obsidianFootnote)
                        .foregroundColor(.statusNotHome)

                    Spacer()

                    Text("\(followUpsTotal) total follow-ups")
                        .font(.obsidianFootnote)
                        .foregroundColor(.textSecondary)
                }
                .padding(12)
                .background(Color.obsidianElevated)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
        .padding(16)
        .background(Color.obsidianSurface)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.obsidianBorder.opacity(0.55), lineWidth: 0.5)
        )
    }

    private func activityStat(value: Int, label: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(value)")
                .font(.obsidianHeadline)
                .foregroundColor(color)

            Text(label)
                .font(.micro)
                .foregroundColor(.textMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.obsidianElevated)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.obsidianBorder.opacity(0.45), lineWidth: 0.5)
        )
    }

    private var syncStatusIcon: String {
        switch syncManager.syncStatus {
        case .idle:
            return "icloud.and.arrow.up"
        case .syncing, .downloading:
            return "arrow.clockwise"
        case .uploading:
            return "icloud.and.arrow.up.fill"
        case .completed:
            return "checkmark.icloud"
        case .failed:
            return "exclamationmark.icloud"
        }
    }

    private var syncStatusColor: Color {
        switch syncManager.syncStatus {
        case .idle:
            return Color.electricViolet
        case .syncing, .uploading, .downloading:
            return Color.electricViolet
        case .completed:
            return Color.statusInterested
        case .failed:
            return Color.statusNotInterested
        }
    }

    private var syncStatusText: String {
        SyncStatusSummaryPolicy.shortText(
            for: syncManager.syncStatus,
            autoSyncEnabled: syncManager.isAutoSyncEnabled,
            intervalShortName: syncManager.syncInterval.shortDisplayName
        )
    }

    // MARK: - CSV Export

    private func exportLeadsToCSV() {
        do {
            let url = try LeadCSVService.exportAllLeads(from: viewContext)
            exportFile = LeadExportFile(url: url)
        } catch {
            importFailure = LeadImportFailure(message: "Export failed: \(error.localizedDescription)")
        }
    }
}

// Helper type for alert(item:)


struct OverviewContentView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @State private var statistics: LeadStatistics = LeadStatistics()
    @State private var isLoading = true
    @State private var statisticsErrorMessage: String?
    
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                if isLoading {
                    ObsidianStatusBanner(
                        icon: "arrow.clockwise",
                        title: "Loading statistics...",
                        message: "Checking your current lead and follow-up totals.",
                        tint: Color.electricViolet
                    )
                } else if let statisticsErrorMessage {
                    ObsidianStatusBanner(
                        icon: "exclamationmark.triangle.fill",
                        title: "Overview could not load",
                        message: statisticsErrorMessage,
                        tint: Color.statusNotHome
                    )
                } else {
                    overviewSection
                    statusBreakdownSection
                    activitySection
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 28)
        }
        .accessibilityIdentifier("overviewScreen")
        .obsidianScreenBackground()
        .obsidianPushedNavigation("Overview", backButtonAccessibilityIdentifier: "overviewBackButton")
        .refreshable {
            await loadStatistics()
        }
        .onAppear {
            Task {
                await loadStatistics()
            }
        }
    }
    
    @MainActor
    private func loadStatistics() async {
        isLoading = true

        let result: Result<LeadStatistics, Error> = await Task.detached { [weak viewContext = viewContext] in
            guard let context = viewContext else { return .success(LeadStatistics()) }

            do {
                let statistics = try await context.perform {
                    var stats = LeadStatistics()

                    // Active leads count - only leads where we received information
                    // Includes: notContacted, interested, converted
                    // Excludes: notHome (no info collected), notInterested (no info collected)
                    let activeLeadsRequest: NSFetchRequest<Lead> = Lead.fetchRequest(in: context)
                    activeLeadsRequest.predicate = NSPredicate(format: "status IN %@", [
                        Lead.Status.notContacted.rawValue,
                        Lead.Status.interested.rawValue,
                        Lead.Status.converted.rawValue
                    ])
                    stats.activeLeadsCount = try context.count(for: activeLeadsRequest)

                    // Status-specific counts
                    for status in Lead.Status.allCases {
                        let statusRequest: NSFetchRequest<Lead> = Lead.fetchRequest(in: context)
                        statusRequest.predicate = NSPredicate(format: "status == %@", status.rawValue)
                        let count = try context.count(for: statusRequest)
                        stats.statusCounts[status] = count

                        switch status {
                        case .converted:
                            stats.convertedCount = count
                        case .interested:
                            stats.interestedCount = count
                        case .notContacted:
                            stats.notContactedCount = count
                        default:
                            break
                        }
                    }

                    // Leads added today (exclude notHome and notInterested - no info collected)
                    let now = Date()
                    let today = Calendar.current.startOfDay(for: Date())
                    let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: today) ?? today.addingTimeInterval(86_400)
                    let todayRequest: NSFetchRequest<Lead> = Lead.fetchRequest(in: context)
                    todayRequest.predicate = NSPredicate(format: "createdDate >= %@ AND createdDate < %@ AND NOT (status IN %@)",
                        today as NSDate,
                        tomorrow as NSDate,
                        [Lead.Status.notHome.rawValue, Lead.Status.notInterested.rawValue])
                    stats.leadsAddedToday = try context.count(for: todayRequest)

                    // Leads updated this week (exclude notHome and notInterested - no info collected)
                    let weekAgo = Calendar.current.date(byAdding: .weekOfYear, value: -1, to: now) ?? now.addingTimeInterval(-604_800)
                    let weekRequest: NSFetchRequest<Lead> = Lead.fetchRequest(in: context)
                    weekRequest.predicate = NSPredicate(format: "updatedDate >= %@ AND NOT (status IN %@)",
                        weekAgo as NSDate,
                        [Lead.Status.notHome.rawValue, Lead.Status.notInterested.rawValue])
                    stats.leadsUpdatedThisWeek = try context.count(for: weekRequest)

                    // Follow-ups due this week
                    let weekFromNow = Calendar.current.date(byAdding: .weekOfYear, value: 1, to: now) ?? now.addingTimeInterval(604_800)
                    let followUpRequest: NSFetchRequest<Lead> = Lead.fetchRequest(in: context)
                    followUpRequest.predicate = Lead.Status.activeFollowUpPredicate(dueFrom: now, through: weekFromNow)
                    stats.followUpsDueThisWeek = try context.count(for: followUpRequest)

                    print("📊 Loaded statistics: \(stats.activeLeadsCount) active leads, \(stats.convertedCount) converted")
                    return stats
                }
                return .success(statistics)
            } catch {
                return .failure(error)
            }
        }.value

        switch result {
        case .success(let newStatistics):
            statistics = newStatistics
            statisticsErrorMessage = nil
        case .failure(let error):
            statisticsErrorMessage = "Your lead counts could not be read: \(error.localizedDescription)"
        }
        isLoading = false
    }
    
    private var overviewSection: some View {
        MoreSectionGroup(
            title: "Pipeline",
            icon: "chart.bar.fill",
            subtitle: "Active sales work by outcome.",
            accentColor: Color.electricViolet
        ) {
            VStack(spacing: 12) {
                StatCardView(
                    title: "Active Leads",
                    value: "\(statistics.activeLeadsCount)",
                    icon: "person.3.fill",
                    color: Color.electricViolet
                )

                StatCardView(
                    title: "Converted",
                    value: "\(statistics.convertedCount)",
                    icon: "checkmark.circle.fill",
                    color: Color.statusInterested
                )

                StatCardView(
                    title: "Interested",
                    value: "\(statistics.interestedCount)",
                    icon: "heart.fill",
                    color: Color.statusNotHome
                )
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 14)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Statistics overview")
    }
    
    private var statusBreakdownSection: some View {
        MoreSectionGroup(
            title: "Status Breakdown",
            icon: "slider.horizontal.3",
            subtitle: "Only statuses with useful customer information.",
            accentColor: Color.statusInterested
        ) {
            VStack(spacing: 12) {
                // Show only statuses where we have lead information.
                ForEach(Lead.Status.allCases.filter { $0 != .notHome && $0 != .notInterested }, id: \.self) { status in
                    StatusProgressCardView(
                        status: status,
                        count: statistics.statusCounts[status] ?? 0,
                        total: statistics.activeLeadsCount
                    )
                }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 14)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Status breakdown charts")
    }
    
    private var activitySection: some View {
        MoreSectionGroup(
            title: "Activity",
            icon: "clock.arrow.circlepath",
            subtitle: "Recent work that needs attention.",
            accentColor: Color.statusNotHome
        ) {
            VStack(spacing: 12) {
                RecentActivityCardView(
                    title: "Leads added today",
                    count: statistics.leadsAddedToday,
                    icon: "plus.circle.fill",
                    color: Color.electricViolet
                )

                RecentActivityCardView(
                    title: "Leads updated this week",
                    count: statistics.leadsUpdatedThisWeek,
                    icon: "pencil.circle.fill",
                    color: Color.statusNotHome
                )

                RecentActivityCardView(
                    title: "Follow ups due this week",
                    count: statistics.followUpsDueThisWeek,
                    icon: "clock.circle.fill",
                    color: Color.electricViolet
                )
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 14)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Recent activity summary")
    }
}

// MARK: - Card Components

struct MoreSectionGroup<Content: View>: View {
    let title: String
    let icon: String
    let subtitle: String?
    let accentColor: Color
    @ViewBuilder var content: Content

    init(
        title: String,
        icon: String,
        subtitle: String? = nil,
        accentColor: Color = .electricViolet,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.icon = icon
        self.subtitle = subtitle
        self.accentColor = accentColor
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                ObsidianIconTile(icon: icon, tint: accentColor, size: 36)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.obsidianTitle)
                        .foregroundColor(Color.textPrimary)

                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.obsidianFootnote)
                            .foregroundColor(Color.textSecondary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 8)

            VStack(spacing: 0) {
                content
            }
        }
        .background(Color.obsidianSurface)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.obsidianBorder.opacity(0.55), lineWidth: 0.5)
        )
    }
}

struct MoreCardView<TrailingContent: View>: View {
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String?
    let titleColor: Color
    let subtitleColor: Color
    let showChevron: Bool
    let trailingContent: (() -> TrailingContent)?
    
    init(
        icon: String,
        iconColor: Color,
        title: String,
        subtitle: String? = nil,
        titleColor: Color = Color.textPrimary,
        subtitleColor: Color = Color.textSecondary,
        showChevron: Bool = false,
        @ViewBuilder trailingContent: @escaping () -> TrailingContent
    ) {
        self.icon = icon
        self.iconColor = iconColor
        self.title = title
        self.subtitle = subtitle
        self.titleColor = titleColor
        self.subtitleColor = subtitleColor
        self.showChevron = showChevron
        self.trailingContent = trailingContent
    }
    
    init(
        icon: String,
        iconColor: Color,
        title: String,
        subtitle: String? = nil,
        titleColor: Color = Color.textPrimary,
        subtitleColor: Color = Color.textSecondary,
        showChevron: Bool = false
    ) where TrailingContent == EmptyView {
        self.icon = icon
        self.iconColor = iconColor
        self.title = title
        self.subtitle = subtitle
        self.titleColor = titleColor
        self.subtitleColor = subtitleColor
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
                        .foregroundColor(subtitleColor)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
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
        .padding(.vertical, 13)
        .contentShape(Rectangle())
    }
}

struct UserInfoCardView: View {
    @ObservedObject var userAccountManager: FirebaseUserAccountManager
    let showChevron: Bool

    init(userAccountManager: FirebaseUserAccountManager, showChevron: Bool = false) {
        self.userAccountManager = userAccountManager
        self.showChevron = showChevron
    }

    private var isGuest: Bool {
        !userAccountManager.hasActiveSession
    }

    private var isAppleOnly: Bool {
        userAccountManager.isAppleAuthed && !userAccountManager.isLoggedIn
    }

    private var isICloudGuest: Bool {
        isGuest && CloudSyncProvider.current == .icloud
    }

    private var isLocalOnlyGuest: Bool {
        isGuest && CloudSyncProvider.current == .off
    }

    private var displayName: String {
        if isICloudGuest {
            return "iCloud Sync"
        }
        if isLocalOnlyGuest {
            return "Local Data"
        }
        if let firebaseName = userAccountManager.currentUser?.displayName, !firebaseName.isEmpty {
            return firebaseName
        }
        if let appleName = userAccountManager.appleUserFullName, !appleName.isEmpty {
            return appleName
        }
        return isGuest ? "Guest Account" : "Signed in"
    }

    private var secondaryText: String {
        if isICloudGuest {
            return "Uses your device Apple ID automatically"
        }
        if isLocalOnlyGuest {
            return "Stored on this device"
        }
        if let firebaseEmail = userAccountManager.currentUser?.email, !firebaseEmail.isEmpty {
            return firebaseEmail
        }
        if let appleEmail = userAccountManager.appleUserEmail, !appleEmail.isEmpty {
            return appleEmail
        }
        if isAppleOnly {
            return "Signed in with Apple"
        }
        return isGuest ? "Tap to sign in or create account" : "No email"
    }

    private var avatarIcon: String {
        if isICloudGuest {
            return "icloud.fill"
        }
        if isLocalOnlyGuest {
            return "iphone"
        }
        return isGuest ? "person.crop.circle.badge.questionmark" : (isAppleOnly ? "applelogo" : "person.fill")
    }

    private var avatarColor: Color {
        if isICloudGuest {
            return Color.statusConverted
        }
        if isLocalOnlyGuest {
            return Color.textSecondary
        }
        return isGuest ? Color.statusInterested : Color.electricViolet
    }

    var body: some View {
        HStack(spacing: 16) {
            ObsidianIconTile(icon: avatarIcon, tint: avatarColor, size: 42)

            VStack(alignment: .leading, spacing: 4) {
                Text(displayName)
                    .font(.obsidianTitle)
                    .foregroundColor(Color.textPrimary)

                Text(secondaryText)
                    .font(.obsidianFootnote)
                    .foregroundColor(isGuest ? avatarColor : Color.textSecondary)
                    .lineLimit(1)
            }

            Spacer()

            if showChevron {
                Image(systemName: "chevron.right")
                    .foregroundColor(Color.textSecondary)
                    .font(.obsidianFootnote)
            }
        }
        .padding(14)
        .background(Color.obsidianElevated)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.obsidianBorder.opacity(0.55), lineWidth: 0.5)
        )
        .shadow(color: Color.black.opacity(0.12), radius: 6, x: 0, y: 3)
    }
}

struct SignOutCardView: View {
    @ObservedObject var userAccountManager: FirebaseUserAccountManager
    @State private var showingSignOutAlert = false

    var body: some View {
        Button(action: {
            showingSignOutAlert = true
        }) {
            MoreCardView(
                icon: "rectangle.portrait.and.arrow.right",
                iconColor: Color.statusNotInterested,
                title: "Sign Out",
                subtitle: "End this device session",
                titleColor: Color.statusNotInterested,
                subtitleColor: Color.statusNotInterested.opacity(0.72),
                trailingContent: {
                    Image(systemName: "chevron.right")
                        .font(.obsidianFootnote)
                        .foregroundColor(Color.statusNotInterested.opacity(0.75))
                }
            )
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityIdentifier("signOutButton")
        .alert("Sign Out", isPresented: $showingSignOutAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Sign Out", role: .destructive) {
                userAccountManager.signOut()
            }
        } message: {
            Text("Are you sure you want to sign out? Your data will be safely stored and available when you sign back in.")
        }
    }
}

// MARK: - Overview Card Components

struct StatCardView: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        HStack(spacing: 16) {
            ObsidianIconTile(icon: icon, tint: color, size: 42)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.obsidianTitle)
                    .foregroundColor(Color.textPrimary)

                Text(value)
                    .font(.displayMedium)
                    .foregroundColor(color)
            }

            Spacer()
        }
        .padding(14)
        .background(Color.obsidianElevated)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.obsidianBorder.opacity(0.55), lineWidth: 0.5)
        )
        .shadow(color: Color.black.opacity(0.12), radius: 6, x: 0, y: 3)
    }
}

struct StatusProgressCardView: View {
    let status: Lead.Status
    let count: Int
    let total: Int
    
    private var percentage: Double {
        guard total > 0 else { return 0 }
        return min(max(Double(count) / Double(total), 0), 1)
    }
    
    private var statusColor: Color {
        switch status {
        case .notContacted: return Color.textSecondary
        case .notHome: return .brown
        case .interested: return Color.statusNotHome
        case .converted: return Color.statusInterested
        case .notInterested: return Color.statusNotInterested
        }
    }
    
    var body: some View {
        HStack(spacing: 16) {
            ObsidianIconTile(icon: statusIcon, tint: statusColor, size: 42)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(status.displayName)
                        .font(.obsidianTitle)
                        .foregroundColor(Color.textPrimary)

                    Spacer()

                    Text("\(count)")
                        .font(.obsidianTitle)
                        .foregroundColor(statusColor)
                }

                // Progress bar
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(Color.obsidianElevated)
                            .frame(height: 6)

                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(statusColor)
                            .frame(
                                width: ObsidianLayout.finiteDimension(geometry.size.width) * CGFloat(percentage),
                                height: 6
                            )
                    }
                }
                .frame(height: 6)
            }
        }
        .padding(14)
        .background(Color.obsidianElevated)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.obsidianBorder.opacity(0.55), lineWidth: 0.5)
        )
        .shadow(color: Color.black.opacity(0.12), radius: 6, x: 0, y: 3)
    }

    private var statusIcon: String {
        switch status {
        case .notContacted: return "person.circle"
        case .notHome: return "house.fill"
        case .interested: return "heart.fill"
        case .converted: return "checkmark.circle.fill"
        case .notInterested: return "xmark.circle.fill"
        }
    }
}

struct RecentActivityCardView: View {
    let title: String
    let count: Int
    let icon: String
    let color: Color

    var body: some View {
        HStack(spacing: 16) {
            ObsidianIconTile(icon: icon, tint: color, size: 42)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.obsidianTitle)
                    .foregroundColor(Color.textPrimary)

                Text("\(count)")
                    .font(.obsidianSubheadline)
                    .foregroundColor(color)
            }

            Spacer()
        }
        .padding(14)
        .background(Color.obsidianSurface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.obsidianBorder.opacity(0.55), lineWidth: 0.5)
        )
        .shadow(color: Color.black.opacity(0.22), radius: 8, x: 0, y: 3)
    }
}

// MARK: - Cloud Provider Sheet

struct CloudProviderSheet: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext
    @State private var selectedProvider = CloudSyncProvider.current
    @State private var showingConfirmation = false
    @State private var isMigrating = false
    @State private var migrationOutcomeMessage: String?
    @State private var migrationDidSucceed = false
    @ObservedObject private var syncManager = UserDataSyncManager.shared

    private var localLeadCount: Int? {
        let request: NSFetchRequest<Lead> = Lead.fetchRequest(in: viewContext)
        do {
            return try viewContext.count(for: request)
        } catch {
            return nil
        }
    }

    private var availableProviders: [CloudSyncProvider] {
        PersonalCloudMigrationPolicy.availableProviders(current: CloudSyncProvider.current)
    }

    var body: some View {
        let screenBackground = Color.obsidianBackground(for: colorScheme)

        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                ObsidianIconTile(icon: "externaldrive.connected.to.line.below.fill", tint: Color.electricViolet, size: 42)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Personal iCloud Sync")
                        .font(.obsidianHeadline)
                        .foregroundColor(.textPrimary)
                        .accessibilityIdentifier("cloudProviderSheet")

                    Text("Personal leads and appointments sync with the Apple ID on this device.")
                        .font(.obsidianFootnote)
                        .foregroundColor(.textSecondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 0)

                ObsidianCompactIconButton(
                    icon: "xmark",
                    accessibilityLabel: "Close cloud storage",
                    accentColor: Color.textSecondary,
                    accessibilityIdentifier: "cloudProviderCloseButton"
                ) {
                    dismiss()
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 18)
            .background(screenBackground.ignoresSafeArea(edges: .top))

            // Provider options
            VStack(spacing: 0) {
                ForEach(availableProviders, id: \.self) { provider in
                    Button {
                        selectedProvider = provider
                        if provider != CloudSyncProvider.current {
                            showingConfirmation = true
                        }
                    } label: {
                        HStack(spacing: 14) {
                            ObsidianIconTile(
                                icon: provider.icon,
                                tint: providerColor(provider),
                                size: 40
                            )
                            VStack(alignment: .leading, spacing: 3) {
                                Text(provider.displayName)
                                    .font(.obsidianCallout)
                                    .foregroundColor(.textPrimary)
                                Text(providerSubtitle(provider))
                                    .font(.obsidianSmall)
                                    .foregroundColor(.textMuted)
                            }
                            Spacer()
                            if provider == CloudSyncProvider.current {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.obsidianSubheadline)
                                    .foregroundColor(providerColor(provider))
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                    }
                    .accessibilityIdentifier("cloudProviderOption_\(provider.rawValue)")
                    if provider != availableProviders.last {
                        Divider().padding(.leading, 70)
                    }
                }
            }
            .background(Color.obsidianSurface)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.obsidianBorder, lineWidth: 0.5)
            )
            .padding(.horizontal, 20)

            Spacer()
        }
        .background(screenBackground.ignoresSafeArea())
        .obsidianModalBackground()
        .overlay {
            if isMigrating {
                VStack(spacing: 12) {
                    ProgressView()
                        .controlSize(.large)
                        .tint(.electricViolet)
                    Text(CloudSyncProvider.current == .firebase
                        ? "Merging Firebase, local, and iCloud data..."
                        : "Uploading local data to iCloud...")
                        .font(.obsidianFootnote)
                        .foregroundColor(.textSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(screenBackground.opacity(0.9))
            }
        }
        .alert("Switch to \(selectedProvider.displayName)?", isPresented: $showingConfirmation) {
            Button("Switch") {
                performSwitch()
            }
            Button("Cancel", role: .cancel) {
                selectedProvider = CloudSyncProvider.current
            }
        } message: {
            Text(CloudSyncProvider.current == .firebase
                ? "\(LeadCountDisplay.firebaseToICloudMessage(for: localLeadCount)) Existing Firebase records will be retained as a legacy backup."
                : LeadCountDisplay.iCloudSyncMessage(for: localLeadCount))
        }
        .alert(
            migrationDidSucceed ? "iCloud Sync Ready" : "iCloud Migration Failed",
            isPresented: Binding(
                get: { migrationOutcomeMessage != nil },
                set: { if !$0 { migrationOutcomeMessage = nil } }
            )
        ) {
            Button("OK") { migrationOutcomeMessage = nil }
        } message: {
            Text(migrationOutcomeMessage ?? "")
        }
    }

    private func providerColor(_ provider: CloudSyncProvider) -> Color {
        switch provider {
        case .off: return .textMuted
        case .firebase: return .electricViolet
        case .icloud: return .statusConverted
        }
    }

    private func providerSubtitle(_ provider: CloudSyncProvider) -> String {
        switch provider {
        case .off: return "Legacy local-only mode"
        case .firebase: return "Legacy personal sync source"
        case .icloud: return "Private sync through your Apple ID"
        }
    }

    private func performSwitch() {
        guard selectedProvider == .icloud else {
            selectedProvider = CloudSyncProvider.current
            return
        }

        isMigrating = true
        migrationOutcomeMessage = nil

        Task {
            do {
                let summary = try await syncManager.migratePersonalDataToICloud()
                selectedProvider = .icloud
                migrationDidSucceed = true
                migrationOutcomeMessage = "Copied \(summary.iCloudLeadCount) leads and \(summary.appointmentCount) appointments to private iCloud sync. Firebase data was not deleted."
            } catch {
                selectedProvider = CloudSyncProvider.current
                migrationDidSucceed = false
                migrationOutcomeMessage = error.localizedDescription
            }
            isMigrating = false
        }
    }
}

struct SyncSettingsView: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var syncManager = UserDataSyncManager.shared
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        let screenBackground = Color.obsidianBackground(for: colorScheme)

        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 16) {
                        // Auto-sync toggle
                        modernSectionCard(title: "Automatic Sync", icon: "arrow.triangle.2.circlepath") {
                            VStack(spacing: 16) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Enable Auto-sync")
                                            .font(.obsidianCallout)
                                            .foregroundColor(Color.textPrimary)
                                        
                                        Text("Automatically sync your data at regular intervals")
                                            .font(.obsidianFootnote)
                                            .foregroundColor(Color.textSecondary)
                                    }
                                    
                                    Spacer()
                                    
                                    Toggle("Automatic Sync", isOn: Binding(
                                        get: { syncManager.isAutoSyncEnabled },
                                        set: { newValue in
                                            syncManager.toggleAutoSync(newValue)
                                        }
                                    ))
                                    .labelsHidden()
                                    .accessibilityIdentifier("syncSettingsAutoSyncToggle")
                                    .accessibilityLabel("Automatic Sync")
                                    .accessibilityValue(syncManager.isAutoSyncEnabled ? "Enabled" : "Disabled")
                                    .accessibilityHint("Toggles automatic data sync.")
                                }
                            }
                        }
                        
                        // Sync frequency options
                        if syncManager.isAutoSyncEnabled {
                            modernSectionCard(title: "Sync Frequency", icon: "clock") {
                                VStack(spacing: 12) {
                                    ForEach(UserDataSyncManager.SyncInterval.allCases, id: \.rawValue) { interval in
                                        syncIntervalRow(interval: interval)
                                    }
                                }
                            }
                        }
                        
                        // Manual sync info
                        modernSectionCard(title: "Additional Sync Events", icon: "info.circle") {
                            VStack(spacing: 12) {
                                syncInfoRow(title: "Manual Sync", description: "Tap the sync button anytime", icon: "hand.tap")
                                syncInfoRow(title: "Before Sign Out", description: "Data syncs automatically when signing out", icon: "arrow.right.square")
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 18)
                    .padding(.bottom, 24)
                }
                .accessibilityIdentifier("syncSettingsSheet")
            }
            .background(screenBackground.ignoresSafeArea())
            .obsidianPushedNavigation(
                "Sync Settings",
                backButtonAccessibilityIdentifier: "syncSettingsCloseButton",
                onBack: { dismiss() }
            )
        }
        .presentationDetents([.large])
        .obsidianModalBackground()
    }
    
    private func syncIntervalRow(interval: UserDataSyncManager.SyncInterval) -> some View {
        Button(action: {
            syncManager.updateSyncInterval(interval)
        }) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(interval.displayName)
                        .font(.obsidianCallout)
                        .foregroundColor(Color.textPrimary)
                }

                Spacer()

                if syncManager.syncInterval == interval {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.obsidianSubheadline)
                        .foregroundColor(Color.electricViolet)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityIdentifier("syncSettingsInterval_\(interval.rawValue)")
    }
    
    private func syncInfoRow(title: String, description: String, icon: String) -> some View {
        HStack {
            Image(systemName: icon)
                .font(.obsidianCallout)
                .foregroundColor(Color.electricViolet)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.obsidianCallout)
                    .foregroundColor(Color.textPrimary)

                Text(description)
                    .font(.obsidianFootnote)
                    .foregroundColor(Color.textSecondary)
            }

            Spacer()
        }
        .padding(.vertical, 4)
    }
    
    private func modernSectionCard<Content: View>(title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                ObsidianIconTile(icon: icon, tint: Color.electricViolet, size: 34)

                Text(title)
                    .font(.themeTitle)
                    .foregroundColor(Color.textPrimary)

                Spacer()
            }

            content()
        }
        .padding(16)
        .background(Color.obsidianSurface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.obsidianBorder.opacity(0.55), lineWidth: 0.5)
        )
    }
}

struct AuthenticationSheetWrapper: View {
    @Binding var isPresented: Bool
    @ObservedObject private var userAccountManager = FirebaseUserAccountManager.shared

    var body: some View {
        AuthenticationView()
            .onChange(of: userAccountManager.isLoggedIn) { _, newValue in
                if newValue {
                    // User successfully logged in, dismiss the sheet
                    isPresented = false
                }
            }
            .onChange(of: userAccountManager.isGuestMode) { _, newValue in
                if !newValue && !userAccountManager.isLoggedIn {
                    // User exited guest mode without logging in, keep sheet open
                } else if newValue {
                    // User clicked "Continue as Guest" from the auth sheet, dismiss
                    isPresented = false
                }
            }
    }
}

// MARK: - Share Sheet

struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

#Preview {
    MoreView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}
