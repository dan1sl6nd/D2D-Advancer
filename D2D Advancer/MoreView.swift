import SwiftUI
import CoreData
import UniformTypeIdentifiers

struct MoreView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @ObservedObject private var preferences = AppPreferences.shared
    @ObservedObject private var userAccountManager = FirebaseUserAccountManager.shared
    @ObservedObject private var syncManager = UserDataSyncManager.shared
    @ObservedObject private var teamService = TeamFirebaseService.shared
    @State private var showingStatistics = false
    @State private var showingSettings = false
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
    
    var body: some View {
        NavigationView {
            GeometryReader { geometry in
                VStack(spacing: 0) {
                    Rectangle()
                        .fill(Color.obsidianBlack)
                        .frame(height: geometry.safeAreaInsets.top)
                    ObsidianHeaderView("More")

                    ScrollView {
                        LazyVStack(spacing: 12) {
                            // Daily Activity Summary
                            todayActivityCard

                            // Overview Card
                            NavigationLink(destination: OverviewContentView()) {
                                MoreCardView(
                                    icon: "chart.bar.fill",
                                    iconColor: Color.electricViolet,
                                    title: "Overview",
                                    subtitle: "View statistics and performance metrics",
                                    showChevron: true
                                )
                            }
                            .buttonStyle(PlainButtonStyle())

                            // Export Leads Card
                            Button(action: {
                                exportLeadsToCSV()
                            }) {
                                MoreCardView(
                                    icon: "square.and.arrow.up",
                                    iconColor: Color.electricViolet,
                                    title: "Export Leads",
                                    subtitle: "\(allLeads.count) leads",
                                    showChevron: false
                                )
                            }
                            .buttonStyle(PlainButtonStyle())
                            .disabled(allLeads.isEmpty)

                            // Import Leads Card
                            Button(action: {
                                showingImportPicker = true
                            }) {
                                MoreCardView(
                                    icon: "square.and.arrow.down",
                                    iconColor: Color.electricViolet,
                                    title: "Import Leads",
                                    subtitle: "Load leads from a CSV file",
                                    showChevron: false
                                )
                            }
                            .buttonStyle(PlainButtonStyle())

                            // Message Templates Card
                            NavigationLink(destination: MessageTemplatesManagerView()) {
                                MoreCardView(
                                    icon: "text.bubble.fill",
                                    iconColor: Color.electricViolet,
                                    title: "Message Templates",
                                    subtitle: "Create and edit first-contact messages",
                                    showChevron: true
                                )
                            }
                            .buttonStyle(PlainButtonStyle())

                            // Team Workspace Card
                            NavigationLink(destination: TeamWorkspaceView()) {
                                MoreCardView(
                                    icon: "person.3.fill",
                                    iconColor: Color.electricViolet,
                                    title: "Team Workspace",
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

                            // Cloud Storage Card
                            Button {
                                showingCloudProviderSheet = true
                            } label: {
                                MoreCardView(
                                    icon: CloudSyncProvider.current.icon,
                                    iconColor: CloudSyncProvider.current == .icloud ? Color.statusConverted : Color.electricViolet,
                                    title: "Cloud Storage",
                                    subtitle: CloudSyncProvider.current == .off ? "Off — local only" : CloudSyncProvider.current.displayName,
                                    trailingContent: {
                                        Image(systemName: "chevron.right")
                                            .font(.obsidianSmall)
                                            .foregroundColor(Color.textMuted)
                                    }
                                )
                            }
                            .buttonStyle(PlainButtonStyle())

                            // Data Management Card — visible for any active session (Firebase or Apple).
                            // In iCloud mode the action runs `performICloudSync`, which flushes
                            // pending Core Data saves and nudges NSUbiquitousKeyValueStore.
                            if userAccountManager.hasActiveSession || CloudSyncProvider.current == .icloud {
                                Button(action: {
                                    if !syncManager.syncStatus.isBusy {
                                        syncManager.syncWithServer()
                                    }
                                }) {
                                    MoreCardView(
                                        icon: syncStatusIcon,
                                        iconColor: syncStatusColor,
                                        title: "Sync Data",
                                        subtitle: syncStatusText,
                                        trailingContent: {
                                            HStack(spacing: 8) {
                                                if syncManager.syncStatus.isBusy {
                                                    ProgressView()
                                                        .scaleEffect(0.8)
                                                } else {
                                                    Image(systemName: "arrow.clockwise")
                                                        .font(.obsidianFootnote)
                                                        .foregroundColor(Color.electricViolet)
                                                }

                                                Button(action: {
                                                    showingSyncSettings = true
                                                }) {
                                                    Image(systemName: "gear")
                                                        .font(.obsidianFootnote)
                                                        .foregroundColor(Color.textSecondary)
                                                }
                                                .buttonStyle(PlainButtonStyle())
                                            }
                                        }
                                    )
                                }
                                .buttonStyle(PlainButtonStyle())
                                .disabled(syncManager.syncStatus.isBusy)
                            }
                            
                            // Account Info Card - tappable to manage account or login
                            if userAccountManager.isLoggedIn {
                                NavigationLink(destination: AccountManagementView(userAccountManager: userAccountManager)) {
                                    UserInfoCardView(userAccountManager: userAccountManager, showChevron: true)
                                }
                                .buttonStyle(PlainButtonStyle())
                            } else if userAccountManager.isAppleAuthed {
                                UserInfoCardView(userAccountManager: userAccountManager, showChevron: false)
                            } else if CloudSyncProvider.current == .firebase {
                                Button(action: {
                                    showingAuthentication = true
                                }) {
                                    UserInfoCardView(userAccountManager: userAccountManager, showChevron: true)
                                }
                                .buttonStyle(PlainButtonStyle())
                            } else {
                                UserInfoCardView(userAccountManager: userAccountManager, showChevron: false)
                            }

                            // Dark Mode Card
                            MoreCardView(
                                icon: "moon.fill",
                                iconColor: Color.electricViolet,
                                title: "Dark Mode",
                                subtitle: nil,
                                trailingContent: {
                                    Toggle("", isOn: $darkModeEnabled)
                                }
                            )

                            
                            // Version Card
                            MoreCardView(
                                icon: "info.circle",
                                iconColor: Color.electricViolet,
                                title: "Version",
                                subtitle: nil,
                                trailingContent: {
                                    Text("1.1")
                                        .font(.subheadline)
                                        .foregroundColor(Color.textSecondary)
                                }
                            )

                            // Sign Out Card (shown when signed in via any provider)
                            if userAccountManager.hasActiveSession {
                                SignOutCardView(userAccountManager: userAccountManager)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                    }
                }
                .navigationBarHidden(true)
                .ignoresSafeArea(.all, edges: .top)
                .sheet(isPresented: $showingSyncSettings) {
                    SyncSettingsView()
                }
                .sheet(isPresented: $showingCloudProviderSheet) {
                    CloudProviderSheet()
                        .presentationDetents([.medium])
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

    private var teamWorkspaceSubtitle: String {
        guard let summary = teamSurfaceSummary else {
            return "Create or manage your team workspace"
        }
        return "\(summary.headline) • \(summary.detailLine)"
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
                self.importResult = try LeadCSVService.importLeads(from: url, into: viewContext)
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

        return VStack(spacing: 12) {
            HStack {
                Image(systemName: "flame.fill")
                    .foregroundColor(.electricViolet)
                Text("Today's Activity")
                    .font(.obsidianCallout)
                    .foregroundColor(.textPrimary)
                Spacer()
                Text(Date().formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
                    .font(.obsidianSmall)
                    .foregroundColor(.textMuted)
            }

            HStack(spacing: 0) {
                activityStat(value: doorsKnocked, label: "Doors", color: .electricViolet)
                activityStat(value: interested, label: "Interested", color: .statusInterested)
                activityStat(value: notHome, label: "Not Home", color: .statusNotHome)
                activityStat(value: sold, label: "Sold", color: .statusConverted)
            }

            // Follow-up stats
            let followUpsDue = allLeads.filter { $0.followUpDate != nil && ($0.followUpDate ?? .distantFuture) <= Date() }.count
            let followUpsTotal = allLeads.filter { $0.followUpDate != nil }.count
            if followUpsTotal > 0 {
                Divider().padding(.vertical, 4)
                HStack {
                    Image(systemName: "bell.badge")
                        .font(.obsidianSmall)
                        .foregroundColor(.statusNotHome)
                    Text("\(followUpsDue) overdue")
                        .font(.obsidianSmall)
                        .foregroundColor(.statusNotHome)
                    Spacer()
                    Text("\(followUpsTotal) total follow-ups")
                        .font(.obsidianSmall)
                        .foregroundColor(.textMuted)
                }
            }
        }
        .padding(16)
        .background(Color.obsidianSurface)
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.obsidianBorder, lineWidth: 0.5)
        )
    }

    private func activityStat(value: Int, label: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text("\(value)")
                .font(.obsidianHeadline)
                .foregroundColor(color)
            Text(label)
                .font(.micro)
                .foregroundColor(.textMuted)
        }
        .frame(maxWidth: .infinity)
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
        switch syncManager.syncStatus {
        case .idle:
            if syncManager.isAutoSyncEnabled {
                return syncManager.syncInterval.shortDisplayName
            } else {
                return "Manual"
            }
        case .syncing:
            return "Preparing..."
        case .uploading(let current, let total):
            return "Uploading \(current)/\(total)"
        case .downloading:
            return "Downloading..."
        case .completed:
            return "Done"
        case .failed:
            return "Failed"
        }
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
    @Environment(\.dismiss) private var dismiss
    @State private var statistics: LeadStatistics = LeadStatistics()
    @State private var isLoading = true
    
    var body: some View {
        GeometryReader { geometry in
                VStack(spacing: 0) {
                    // Dynamic safe area spacer that adapts to device
                    Rectangle()
                        .fill(Color.obsidianBlack)
                        .frame(height: max(geometry.safeAreaInsets.top + 10, 60))

                    if isLoading {
                        VStack {
                            ProgressView()
                                .scaleEffect(1.2)
                            Text("Loading statistics...")
                                .font(.caption)
                                .foregroundColor(Color.textSecondary)
                                .padding(.top, 8)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 12) {
                                overviewSection
                                statusBreakdownSection
                                activitySection
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .refreshable {
                                await loadStatistics()
                            }
                        }
                    }
                }
                .navigationBarHidden(true)
                .navigationBarBackButtonHidden(true)
                .ignoresSafeArea(.all, edges: .top)
                .safeAreaInset(edge: .bottom) {
                    // Card-based back button at bottom
                    Button(action: {
                        dismiss()
                    }) {
                        HStack {
                            Image(systemName: "chevron.left.circle.fill")
                                .font(.title3)
                            Text("Back to More")
                                .font(.headline)
                                .fontWeight(.semibold)
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.electricViolet)
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
            Task {
                await loadStatistics()
            }
        }
    }
    
    @MainActor
    private func loadStatistics() async {
        isLoading = true
        
        let newStatistics = await Task.detached { [weak viewContext = viewContext] in
            guard let context = viewContext else { return LeadStatistics() }
            
            return await context.perform {
                var stats = LeadStatistics()

                // Active leads count - only leads where we received information
                // Includes: notContacted, interested, converted
                // Excludes: notHome (no info collected), notInterested (no info collected)
                let activeLeadsRequest: NSFetchRequest<Lead> = Lead.fetchRequest()
                activeLeadsRequest.predicate = NSPredicate(format: "status IN %@", [
                    Lead.Status.notContacted.rawValue,
                    Lead.Status.interested.rawValue,
                    Lead.Status.converted.rawValue
                ])
                stats.activeLeadsCount = (try? context.count(for: activeLeadsRequest)) ?? 0

                // Status-specific counts
                for status in Lead.Status.allCases {
                    let statusRequest: NSFetchRequest<Lead> = Lead.fetchRequest()
                    statusRequest.predicate = NSPredicate(format: "status == %@", status.rawValue)
                    let count = (try? context.count(for: statusRequest)) ?? 0
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
                let today = Calendar.current.startOfDay(for: Date())
                let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: today)!
                let todayRequest: NSFetchRequest<Lead> = Lead.fetchRequest()
                todayRequest.predicate = NSPredicate(format: "createdDate >= %@ AND createdDate < %@ AND NOT (status IN %@)",
                    today as NSDate,
                    tomorrow as NSDate,
                    [Lead.Status.notHome.rawValue, Lead.Status.notInterested.rawValue])
                stats.leadsAddedToday = (try? context.count(for: todayRequest)) ?? 0

                // Leads updated this week (exclude notHome and notInterested - no info collected)
                let weekAgo = Calendar.current.date(byAdding: .weekOfYear, value: -1, to: Date())!
                let weekRequest: NSFetchRequest<Lead> = Lead.fetchRequest()
                weekRequest.predicate = NSPredicate(format: "updatedDate >= %@ AND NOT (status IN %@)",
                    weekAgo as NSDate,
                    [Lead.Status.notHome.rawValue, Lead.Status.notInterested.rawValue])
                stats.leadsUpdatedThisWeek = (try? context.count(for: weekRequest)) ?? 0

                // Follow-ups due this week (exclude notHome and notInterested - no info collected)
                let weekFromNow = Calendar.current.date(byAdding: .weekOfYear, value: 1, to: Date())!
                let followUpRequest: NSFetchRequest<Lead> = Lead.fetchRequest()
                followUpRequest.predicate = NSPredicate(format: "followUpDate >= %@ AND followUpDate <= %@ AND NOT (status IN %@)",
                    Date() as NSDate,
                    weekFromNow as NSDate,
                    [Lead.Status.notHome.rawValue, Lead.Status.notInterested.rawValue])
                stats.followUpsDueThisWeek = (try? context.count(for: followUpRequest)) ?? 0
                
                print("📊 Loaded statistics: \(stats.activeLeadsCount) active leads, \(stats.convertedCount) converted")
                return stats
            }
        }.value
        
        statistics = newStatistics
        isLoading = false
    }
    
    private var overviewSection: some View {
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
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Statistics overview")
    }
    
    private var statusBreakdownSection: some View {
        VStack(spacing: 12) {
            // Show only statuses where we have lead information
            // Includes: notContacted, interested, converted
            // Excludes: notHome (no info), notInterested (no info)
            ForEach(Lead.Status.allCases.filter { $0 != .notHome && $0 != .notInterested }, id: \.self) { status in
                StatusProgressCardView(
                    status: status,
                    count: statistics.statusCounts[status] ?? 0,
                    total: statistics.activeLeadsCount
                )
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Status breakdown charts")
    }
    
    private var activitySection: some View {
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
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Recent activity summary")
    }
}

// MARK: - Card Components

struct MoreCardView<TrailingContent: View>: View {
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String?
    let showChevron: Bool
    let trailingContent: (() -> TrailingContent)?
    
    init(
        icon: String,
        iconColor: Color,
        title: String,
        subtitle: String? = nil,
        showChevron: Bool = false,
        @ViewBuilder trailingContent: @escaping () -> TrailingContent
    ) {
        self.icon = icon
        self.iconColor = iconColor
        self.title = title
        self.subtitle = subtitle
        self.showChevron = showChevron
        self.trailingContent = trailingContent
    }
    
    init(
        icon: String,
        iconColor: Color,
        title: String,
        subtitle: String? = nil,
        showChevron: Bool = false
    ) where TrailingContent == EmptyView {
        self.icon = icon
        self.iconColor = iconColor
        self.title = title
        self.subtitle = subtitle
        self.showChevron = showChevron
        self.trailingContent = nil
    }
    
    var body: some View {
        HStack(spacing: 16) {
            // Icon
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(iconColor)
                .frame(width: 40, height: 40)
                .overlay(
                    Image(systemName: icon)
                        .font(.obsidianAction)
                        .foregroundColor(.white)
                )

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.obsidianCallout)
                    .foregroundColor(Color.textPrimary)
                    .lineLimit(1)

                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(.obsidianFootnote)
                        .foregroundColor(Color.textSecondary)
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
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.obsidianSurface)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.obsidianBorder.opacity(0.3), lineWidth: 0.5)
                )
                .shadow(color: Color.black.opacity(0.08), radius: 4, x: 0, y: 2)
        )
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
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
            // User Avatar
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(avatarColor)
                .frame(width: 40, height: 40)
                .overlay(
                    Image(systemName: avatarIcon)
                        .font(.obsidianAction)
                        .foregroundColor(.white)
                )

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
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.obsidianSurface)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.obsidianBorder.opacity(0.3), lineWidth: 0.5)
                )
                .shadow(color: Color.black.opacity(0.08), radius: 4, x: 0, y: 2)
        )
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
    }
}

struct SignOutCardView: View {
    @ObservedObject var userAccountManager: FirebaseUserAccountManager
    @State private var showingSignOutAlert = false

    var body: some View {
        Button(action: {
            showingSignOutAlert = true
        }) {
            HStack(spacing: 16) {
                // Sign Out Icon
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.statusNotInterested)
                    .frame(width: 40, height: 40)
                    .overlay(
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                            .font(.obsidianAction)
                            .foregroundColor(.white)
                    )

                Text("Sign Out")
                    .font(.obsidianTitle)
                    .foregroundColor(Color.statusNotInterested)

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.obsidianSurface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.statusNotInterested.opacity(0.3), lineWidth: 0.5)
                    )
                    .shadow(color: Color.black.opacity(0.08), radius: 4, x: 0, y: 2)
            )
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
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
            // Icon
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(color)
                .frame(width: 40, height: 40)
                .overlay(
                    Image(systemName: icon)
                        .font(.obsidianAction)
                        .foregroundColor(.white)
                )

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
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.obsidianSurface)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.obsidianBorder.opacity(0.3), lineWidth: 0.5)
                )
                .shadow(color: Color.black.opacity(0.08), radius: 4, x: 0, y: 2)
        )
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
    }
}

struct StatusProgressCardView: View {
    let status: Lead.Status
    let count: Int
    let total: Int
    
    private var percentage: Double {
        guard total > 0 else { return 0 }
        return Double(count) / Double(total)
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
            // Icon
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(statusColor)
                .frame(width: 40, height: 40)
                .overlay(
                    Image(systemName: statusIcon)
                        .font(.obsidianAction)
                        .foregroundColor(.white)
                )

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
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.obsidianSurface)
                            .frame(height: 6)

                        RoundedRectangle(cornerRadius: 4)
                            .fill(statusColor)
                            .frame(width: geometry.size.width * percentage, height: 6)
                    }
                }
                .frame(height: 6)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.obsidianSurface)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.obsidianBorder.opacity(0.3), lineWidth: 0.5)
                )
                .shadow(color: Color.black.opacity(0.08), radius: 4, x: 0, y: 2)
        )
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
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
            // Icon
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(color)
                .frame(width: 40, height: 40)
                .overlay(
                    Image(systemName: icon)
                        .font(.obsidianAction)
                        .foregroundColor(.white)
                )

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
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.obsidianSurface)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.obsidianBorder.opacity(0.3), lineWidth: 0.5)
                )
                .shadow(color: Color.black.opacity(0.08), radius: 4, x: 0, y: 2)
        )
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
    }
}

// MARK: - Cloud Provider Sheet

struct CloudProviderSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext
    @State private var selectedProvider = CloudSyncProvider.current
    @State private var showingConfirmation = false
    @State private var isMigrating = false
    @ObservedObject private var syncManager = UserDataSyncManager.shared
    @ObservedObject private var userAccountManager = FirebaseUserAccountManager.shared

    private var leadsCount: Int {
        let request = Lead.fetchRequest()
        return (try? viewContext.count(for: request)) ?? 0
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Cloud Storage")
                    .font(.obsidianSubheadline)
                    .foregroundColor(.textPrimary)
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.obsidianCaption)
                        .foregroundColor(.textSecondary)
                        .frame(width: 30, height: 30)
                        .background(Color.obsidianElevated)
                        .clipShape(Circle())
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 16)

            // Provider options
            VStack(spacing: 0) {
                ForEach(CloudSyncProvider.allCases, id: \.self) { provider in
                    Button {
                        selectedProvider = provider
                        if provider != CloudSyncProvider.current {
                            showingConfirmation = true
                        }
                    } label: {
                        HStack(spacing: 14) {
                            ZStack {
                                Circle()
                                    .fill(providerColor(provider).opacity(0.12))
                                    .frame(width: 40, height: 40)
                                Image(systemName: provider.icon)
                                    .font(.obsidianTitle)
                                    .foregroundColor(providerColor(provider))
                            }
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
                    if provider != CloudSyncProvider.allCases.last {
                        Divider().padding(.leading, 70)
                    }
                }
            }
            .background(Color.obsidianSurface)
            .cornerRadius(14)
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.obsidianBorder, lineWidth: 0.5)
            )
            .padding(.horizontal, 20)

            Spacer()
        }
        .background(Color.obsidianBlack)
        .presentationBackground(Color.obsidianBlack)
        .overlay {
            if isMigrating {
                VStack(spacing: 12) {
                    ProgressView()
                        .controlSize(.large)
                        .tint(.electricViolet)
                    Text("Syncing before switching...")
                        .font(.obsidianFootnote)
                        .foregroundColor(.textSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.obsidianBlack.opacity(0.9))
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
            if CloudSyncProvider.current == .firebase && selectedProvider == .icloud {
                Text("A final Firebase sync will run first. All \(leadsCount) leads will then sync automatically via iCloud. Firebase will be kept as a backup.")
            } else if selectedProvider == .icloud {
                Text("All \(leadsCount) leads will sync automatically via iCloud using your Apple ID.")
            } else if selectedProvider == .firebase {
                Text("Switching to Firebase. Requires account sign-in for cloud sync.")
            } else {
                Text("Cloud sync will be disabled. Data stays on this device only.")
            }
        }
        .alert("Restart Required", isPresented: $showRestartNeeded) {
            Button("OK") { }
        } message: {
            Text("Please close and reopen the app for the sync provider change to take full effect.")
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
        case .off: return "Local only, no backup"
        case .firebase: return "Cross-device, requires sign-in"
        case .icloud: return "Automatic, uses Apple ID"
        }
    }

    @State private var showRestartNeeded = false

    private func performSwitch() {
        let oldProvider = CloudSyncProvider.current
        let newProvider = selectedProvider

        if oldProvider == .firebase && userAccountManager.isLoggedIn {
            isMigrating = true
            syncManager.startSync()
            Task {
                for _ in 0..<60 {
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
}

struct SyncSettingsView: View {
    @ObservedObject private var syncManager = UserDataSyncManager.shared
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Header
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Sync Settings")
                                .font(.title)
                                .fontWeight(.bold)
                            
                            Text("Choose how often your data syncs automatically")
                                .font(.subheadline)
                                .foregroundColor(Color.textSecondary)
                        }
                        Spacer()
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 24)
                .background(Color.obsidianBlack)
                
                ScrollView {
                    VStack(spacing: 16) {
                        // Auto-sync toggle
                        modernSectionCard(title: "Automatic Sync", icon: "arrow.triangle.2.circlepath") {
                            VStack(spacing: 16) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Enable Auto-sync")
                                            .font(.body)
                                            .fontWeight(.medium)
                                        
                                        Text("Automatically sync your data at regular intervals")
                                            .font(.caption)
                                            .foregroundColor(Color.textSecondary)
                                    }
                                    
                                    Spacer()
                                    
                                    Toggle("", isOn: Binding(
                                        get: { syncManager.isAutoSyncEnabled },
                                        set: { newValue in
                                            syncManager.toggleAutoSync(newValue)
                                        }
                                    ))
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
                    .padding(.bottom, 40)
                }
            }
            .background(Color.obsidianBlack)
            .navigationBarHidden(true)
        }
        .presentationDetents([.height(600)])
    }
    
    private func syncIntervalRow(interval: UserDataSyncManager.SyncInterval) -> some View {
        Button(action: {
            syncManager.updateSyncInterval(interval)
        }) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(interval.displayName)
                        .font(.body)
                        .fontWeight(.medium)
                        .foregroundColor(Color.textPrimary)
                }

                Spacer()

                if syncManager.syncInterval == interval {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.obsidianSubheadline)
                        .foregroundColor(Color.electricViolet)
                }
            }
            .padding(.vertical, 8)
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private func syncInfoRow(title: String, description: String, icon: String) -> some View {
        HStack {
            Image(systemName: icon)
                .font(.obsidianCallout)
                .foregroundColor(Color.electricViolet)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                    .fontWeight(.medium)

                Text(description)
                    .font(.caption)
                    .foregroundColor(Color.textSecondary)
            }

            Spacer()
        }
        .padding(.vertical, 4)
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
        .background(Color.obsidianSurface)
        .cornerRadius(16)
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
