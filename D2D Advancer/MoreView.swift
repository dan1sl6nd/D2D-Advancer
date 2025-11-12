import SwiftUI
import CoreData

struct MoreView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @ObservedObject private var preferences = AppPreferences.shared
    @ObservedObject private var userAccountManager = FirebaseUserAccountManager.shared
    @ObservedObject private var syncManager = UserDataSyncManager.shared
    @State private var showingStatistics = false
    @State private var showingSettings = false
    @State private var showingSyncSettings = false
    @State private var showingAuthentication = false
    @AppStorage("isDarkMode") private var darkModeEnabled = false
    
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
                            // Overview Card (monetization disabled)
                            NavigationLink(destination: OverviewContentView()) {
                                MoreCardView(
                                    icon: "chart.bar.fill",
                                    iconColor: .blue,
                                    title: "Overview",
                                    subtitle: "View statistics and performance metrics",
                                    showChevron: true
                                )
                            }
                            .buttonStyle(PlainButtonStyle())

                            // Data Management Card (only for logged-in users)
                            if userAccountManager.isLoggedIn {
                                MoreCardView(
                                    icon: syncStatusIcon,
                                    iconColor: syncStatusColor,
                                    title: "Sync Data",
                                    subtitle: syncStatusText,
                                    trailingContent: {
                                        HStack(spacing: 8) {
                                            Button(action: {
                                                showingSyncSettings = true
                                            }) {
                                                Image(systemName: "gear")
                                                    .font(.system(size: 14))
                                                    .foregroundColor(.blue)
                                                    .padding(8)
                                                    .background(Color.blue.opacity(0.1))
                                                    .clipShape(Circle())
                                            }

                                            if syncManager.syncStatus == .syncing {
                                                ProgressView()
                                                    .scaleEffect(0.8)
                                            } else {
                                                Button("Sync") {
                                                    syncManager.syncWithServer()
                                                }
                                                .font(.footnote)
                                                .fontWeight(.semibold)
                                                .foregroundColor(.white)
                                                .frame(minWidth: 45)
                                                .padding(.horizontal, 12)
                                                .padding(.vertical, 6)
                                                .background(Color.blue)
                                                .cornerRadius(14)
                                            }
                                        }
                                    }
                                )
                                .disabled(syncManager.syncStatus == .syncing)
                            }
                            
                            // Account Info Card - tappable to manage account or login
                            if userAccountManager.isLoggedIn {
                                NavigationLink(destination: AccountManagementView(userAccountManager: userAccountManager)) {
                                    UserInfoCardView(userAccountManager: userAccountManager, showChevron: true)
                                }
                                .buttonStyle(PlainButtonStyle())
                            } else {
                                Button(action: {
                                    showingAuthentication = true
                                }) {
                                    UserInfoCardView(userAccountManager: userAccountManager, showChevron: true)
                                }
                                .buttonStyle(PlainButtonStyle())
                            }

                            
                            
                            // Dark Mode Card
                            MoreCardView(
                                icon: "moon.fill",
                                iconColor: .purple,
                                title: "Dark Mode",
                                subtitle: nil,
                                trailingContent: {
                                    Toggle("", isOn: $darkModeEnabled)
                                }
                            )

                            // Import Leads removed per request
                            
                            // Version Card
                            MoreCardView(
                                icon: "info.circle",
                                iconColor: .blue,
                                title: "Version",
                                subtitle: nil,
                                trailingContent: {
                                    Text("1.1")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                }
                            )

                            // Sign Out Card (only for logged-in users)
                            if userAccountManager.isLoggedIn {
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
                .sheet(isPresented: $showingAuthentication) {
                    AuthenticationSheetWrapper(isPresented: $showingAuthentication)
                }
                // Import Leads sheet and alerts removed
            }
        }
    }
    
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
            if syncManager.isAutoSyncEnabled {
                return syncManager.syncInterval.shortDisplayName
            } else {
                return "Manual"
            }
        case .syncing:
            return "Syncing"
        case .completed:
            return "Done"
        case .failed(_):
            return "Failed"
        }
    }

    // MARK: - Pro Plan Helpers
    // Removed plan helpers; monetization disabled
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
                    
                    if isLoading {
                        VStack {
                            ProgressView()
                                .scaleEffect(1.2)
                            Text("Loading statistics...")
                                .font(.caption)
                                .foregroundColor(.secondary)
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
                color: .blue
            )
            
            StatCardView(
                title: "Converted",
                value: "\(statistics.convertedCount)",
                icon: "checkmark.circle.fill",
                color: .green
            )
            
            StatCardView(
                title: "Interested",
                value: "\(statistics.interestedCount)",
                icon: "heart.fill",
                color: .orange
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
                color: .blue
            )
            
            RecentActivityCardView(
                title: "Leads updated this week",
                count: statistics.leadsUpdatedThisWeek,
                icon: "pencil.circle.fill",
                color: .orange
            )
            
            RecentActivityCardView(
                title: "Follow ups due this week",
                count: statistics.followUpsDueThisWeek,
                icon: "clock.circle.fill",
                color: .purple
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
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                
                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(.system(size: 14, weight: .regular, design: .rounded))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
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

struct UserInfoCardView: View {
    @ObservedObject var userAccountManager: FirebaseUserAccountManager
    let showChevron: Bool

    init(userAccountManager: FirebaseUserAccountManager, showChevron: Bool = false) {
        self.userAccountManager = userAccountManager
        self.showChevron = showChevron
    }

    private var isGuest: Bool {
        !userAccountManager.isLoggedIn
    }

    var body: some View {
        HStack(spacing: 16) {
            // User Avatar
            Circle()
                .fill(isGuest ? Color.green : Color.blue)
                .frame(width: 48, height: 48)
                .overlay(
                    Image(systemName: isGuest ? "person.crop.circle.badge.questionmark" : "person.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.white)
                )

            VStack(alignment: .leading, spacing: 4) {
                Text(userAccountManager.currentUser?.displayName ?? "Anonymous User")
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundColor(.primary)

                Text(userAccountManager.currentUser?.email ?? (isGuest ? "Tap to sign in or create account" : "No email"))
                    .font(.system(size: 14, weight: .regular, design: .rounded))
                    .foregroundColor(isGuest ? .green : .secondary)
                    .lineLimit(1)
            }

            Spacer()

            if showChevron {
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

struct SignOutCardView: View {
    @ObservedObject var userAccountManager: FirebaseUserAccountManager
    @State private var showingSignOutAlert = false

    var body: some View {
        Button(action: {
            showingSignOutAlert = true
        }) {
            HStack(spacing: 16) {
                // Sign Out Icon
                Circle()
                    .fill(Color.red)
                    .frame(width: 48, height: 48)
                    .overlay(
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.white)
                    )

                Text("Sign Out")
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundColor(.red)

                Spacer()
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
                            .stroke(Color.red.opacity(0.3), lineWidth: 1)
                    )
                    .shadow(color: Color.black.opacity(0.08), radius: 4, x: 0, y: 2)
            )
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
        }
        .buttonStyle(PlainButtonStyle())
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
            Circle()
                .fill(color)
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
                
                Text(value)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundColor(color)
            }
            
            Spacer()
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
        case .notContacted: return .gray
        case .notHome: return .brown
        case .interested: return .orange
        case .converted: return .green
        case .notInterested: return .red
        }
    }
    
    var body: some View {
        HStack(spacing: 16) {
            // Icon
            Circle()
                .fill(statusColor)
                .frame(width: 48, height: 48)
                .overlay(
                    Image(systemName: statusIcon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.white)
                )
            
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(status.displayName)
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .foregroundColor(.primary)
                    
                    Spacer()
                    
                    Text("\(count)")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundColor(statusColor)
                }
                
                // Progress bar
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color(UIColor.tertiarySystemBackground))
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
            Circle()
                .fill(color)
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
                
                Text("\(count)")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundColor(color)
            }
            
            Spacer()
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
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 24)
                .background(Color(UIColor.systemBackground))
                
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
                                            .foregroundColor(.secondary)
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
            .background(Color(UIColor.systemBackground))
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
                        .foregroundColor(.primary)
                }
                
                Spacer()
                
                if syncManager.syncInterval == interval {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.blue)
                }
            }
            .padding(.vertical, 8)
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private func syncInfoRow(title: String, description: String, icon: String) -> some View {
        HStack {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(.blue)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                    .fontWeight(.medium)
                
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .padding(.vertical, 4)
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
        .background(Color(.systemGray6))
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

#Preview {
    MoreView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}
