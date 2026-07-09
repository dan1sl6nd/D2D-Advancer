import SwiftUI
import CoreData

struct MainTabView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.managedObjectContext) private var viewContext
    @ObservedObject private var router = AppRouter.shared
    @ObservedObject private var locationManager = LocationManager.shared
    @ObservedObject private var userAccountManager = FirebaseUserAccountManager.shared
    @ObservedObject private var teamService = TeamFirebaseService.shared
    @State private var didApplyRoleDefaultTab = false
    @State private var shouldKeepMapAlive = false
    @State private var mapPrewarmTask: Task<Void, Never>?
    @State private var overdueLeadBadgeCount = 0
    @State private var overdueLeadBadgeTask: Task<Void, Never>?

    private var isRunningUITests: Bool {
        ProcessInfo.processInfo.arguments.contains("-skipOnboardingForUITests")
    }

    private var shouldLoadTeamWorkspace: Bool {
        !isRunningUITests || FirebaseEmulatorConfiguration.isEnabled
    }

    private var shouldOpenTeamWorkspaceForUITests: Bool {
        ProcessInfo.processInfo.arguments.contains("-openTeamWorkspaceForUITests")
    }

    private var teamSurfaceSummary: TeamWorkspaceSurfaceSummary? {
        TeamWorkspaceSurfaceSummary.makeShortcut(
            team: teamService.activeTeam,
            currentMember: teamService.currentMember,
            members: teamService.teamMembers,
            leads: teamService.teamLeads,
            bookings: teamService.teamBookings,
            dutySessions: teamService.dutySessions,
            ownerNotifications: teamService.ownerNotifications
        )
    }

    private var teamLeadBadgeCount: Int {
        min(teamSurfaceSummary?.badgeCount ?? 0, 99)
    }

    private var roleContext: TeamRoleContext {
        TeamRoleContext(summary: teamSurfaceSummary)
    }

    var body: some View {
        Group {
            if shouldOpenTeamWorkspaceForUITests {
                TeamWorkspaceView()
            } else {
                VStack(spacing: 0) {
                    // Content area
                    tabContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    // Obsidian tab bar
                    HStack(spacing: 0) {
                        TabBarButton(
                            title: roleContext.mapTabTitle,
                            icon: "map",
                            selectedIcon: "map.fill",
                            isSelected: router.selectedTab == 0,
                            accessibilityID: "tab_Map",
                            action: { router.selectedTab = 0 }
                        )

                        TabBarButton(
                            title: roleContext.leadsTabTitle,
                            icon: "person.2",
                            selectedIcon: "person.2.fill",
                            isSelected: router.selectedTab == 1,
                            badgeCount: teamLeadBadgeCount,
                            accessibilityID: "tab_Leads",
                            action: { router.selectedTab = 1 }
                        )

                        TabBarButton(
                            title: roleContext.followUpTabTitle,
                            icon: "bell",
                            selectedIcon: "bell.fill",
                            isSelected: router.selectedTab == 2,
                            badgeCount: overdueLeadBadgeCount,
                            accessibilityID: "tab_Follow_Up",
                            action: { router.selectedTab = 2 }
                        )

                        TabBarButton(
                            title: roleContext.scheduleTabTitle,
                            icon: "calendar",
                            selectedIcon: "calendar",
                            isSelected: router.selectedTab == 3,
                            accessibilityID: "tab_Appts",
                            action: { router.selectedTab = 3 }
                        )

                        TabBarButton(
                            title: roleContext.moreTabTitle,
                            icon: "ellipsis.circle",
                            selectedIcon: "ellipsis.circle.fill",
                            isSelected: router.selectedTab == 4,
                            accessibilityID: "tab_More",
                            action: { router.selectedTab = 4 }
                        )
                    }
                    .padding(.top, 8)
                    .background(Color.obsidianBackground(for: colorScheme))
                    .overlay(
                        Rectangle()
                            .fill(Color.obsidianBorder)
                            .frame(height: 1),
                        alignment: .top
                    )
                }
            }
        }
        .background(Color.obsidianBackground(for: colorScheme))
        .customThemed()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("mainTabView")
        .onAppear {
            scheduleOverdueLeadBadgeRefresh(after: 0)

            if router.selectedTab == 0 {
                shouldKeepMapAlive = true
            } else {
                scheduleMapPrewarmIfNeeded()
            }

            if isRunningUITests {
                print("🧪 MainTabView: Skipping startup side effects for UI tests")
                if shouldLoadTeamWorkspace {
                    Task {
                        await loadTeamWorkspaceIfNeeded()
                    }
                }
                return
            }

            // Initialize location services immediately when app launches
            print("📱 MainTabView: App launched, initializing location services")
            UserDataSyncManager.shared.activateAutoSyncTimerIfNeeded()
            initializeLocationServices()

            // Refresh daily notifications with fresh stats
            NotificationService.shared.scheduleDailySummaryNotification()

            // Clean up any duplicate appointments first
            AppointmentManager.shared.removeDuplicateAppointments()

            // Start Firebase appointment listener when main app loads
            AppointmentManager.shared.restartFirebaseSync()
            print("🗓️ MainTabView: Appointment sync startup check completed")

            Task {
                await loadTeamWorkspaceIfNeeded()
                applyDefaultTabForRoleIfNeeded()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSManagedObjectContextObjectsDidChange, object: viewContext)) { _ in
            scheduleOverdueLeadBadgeRefresh(after: 0.2)
        }
        .onChange(of: userAccountManager.isLoggedIn) { _, _ in
            Task {
                await loadTeamWorkspaceIfNeeded()
                applyDefaultTabForRoleIfNeeded(reset: true)
            }
        }
        .onChange(of: teamService.currentMember?.workType) { _, _ in
            applyDefaultTabForRoleIfNeeded()
        }
        .onChange(of: router.selectedTab) { _, newTab in
            if newTab == 0 {
                mapPrewarmTask?.cancel()
                mapPrewarmTask = nil
                shouldKeepMapAlive = true
            } else {
                scheduleMapPrewarmIfNeeded()
            }
        }
        .onDisappear {
            mapPrewarmTask?.cancel()
            mapPrewarmTask = nil
            overdueLeadBadgeTask?.cancel()
            overdueLeadBadgeTask = nil
        }
    }

    @ViewBuilder
    private var tabContent: some View {
        ZStack {
            if shouldKeepMapAlive || router.selectedTab == 0 {
                MapView(isVisible: router.selectedTab == 0)
                    .opacity(router.selectedTab == 0 ? 1 : 0)
                    .allowsHitTesting(router.selectedTab == 0)
                    .accessibilityHidden(router.selectedTab != 0)
                    .zIndex(router.selectedTab == 0 ? 1 : 0)
            }

            if router.selectedTab != 0 {
                nonMapTabContent
                    .zIndex(2)
            }
        }
    }

    @ViewBuilder
    private var nonMapTabContent: some View {
        switch router.selectedTab {
        case 1:
            LeadsListView()
        case 2:
            FollowUpView()
        case 3:
            AppointmentsView()
        case 4:
            MoreView()
        default:
            EmptyView()
        }
    }

    // MARK: - Location Services Initialization
    private func loadTeamWorkspaceIfNeeded() async {
        guard shouldLoadTeamWorkspace else { return }
        guard userAccountManager.isLoggedIn else { return }
        await teamService.loadCurrentTeam(
            displayName: userAccountManager.currentUserDisplayName,
            email: userAccountManager.currentUserEmail
        )
    }

    private func applyDefaultTabForRoleIfNeeded(reset: Bool = false) {
        guard !isRunningUITests else { return }
        if reset {
            didApplyRoleDefaultTab = false
        }
        guard !didApplyRoleDefaultTab else { return }
        guard router.selectedTab == 0 else {
            didApplyRoleDefaultTab = true
            return
        }

        let defaultTab = roleContext.defaultTabIndex
        if defaultTab != router.selectedTab {
            router.selectedTab = defaultTab
        }
        didApplyRoleDefaultTab = true
    }

    private func scheduleMapPrewarmIfNeeded() {
        guard !isRunningUITests else { return }
        guard !shouldKeepMapAlive else { return }
        guard mapPrewarmTask == nil else { return }

        mapPrewarmTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 700_000_000)
            guard !Task.isCancelled else { return }
            shouldKeepMapAlive = true
            mapPrewarmTask = nil
        }
    }

    private func scheduleOverdueLeadBadgeRefresh(after delay: TimeInterval = 0.05) {
        overdueLeadBadgeTask?.cancel()
        let context = viewContext

        overdueLeadBadgeTask = Task { @MainActor in
            if delay > 0 {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
            guard !Task.isCancelled else { return }

            let request: NSFetchRequest<Lead> = Lead.fetchRequest(in: context)
            request.predicate = Lead.Status.activeFollowUpPredicate(dueBefore: Date())
            request.includesPendingChanges = true
            request.includesSubentities = false

            do {
                let count = try context.count(for: request)
                guard !Task.isCancelled else { return }
                overdueLeadBadgeCount = min(count, 99)
            } catch {
                AppLog.warning("Tabs", "Could not refresh follow-up badge count: \(error.localizedDescription)")
            }

            overdueLeadBadgeTask = nil
        }
    }

    private func initializeLocationServices() {
        print("📍 MainTabView: Initializing location services for immediate map centering")
        locationManager.refreshAuthorizationStatusFromSystem(startIfAuthorized: false)

        // Check the live onboarding state before requesting permissions.
        let canRequestLocationOutsideOnboarding = OnboardingManager.shared.isCompleted && !OnboardingManager.shared.showOnboarding

        switch locationManager.authorizationStatus {
        case .notDetermined:
            if canRequestLocationOutsideOnboarding {
                print("📍 MainTabView: Onboarding completed - requesting location permission")
                locationManager.requestLocationPermission()
            } else {
                print("📍 MainTabView: Onboarding not completed - skipping location permission request (will be handled in onboarding)")
            }
        case .authorizedWhenInUse, .authorizedAlways:
            print("📍 MainTabView: Permission already granted, starting location updates")
            locationManager.startLaunchLocationCentering()
        case .denied, .restricted:
            print("📍 MainTabView: Location permission denied/restricted")
        @unknown default:
            break
        }
    }
}

struct TabBarButton: View {
    let title: String
    let icon: String
    let selectedIcon: String
    let isSelected: Bool
    var badgeCount: Int = 0
    let accessibilityID: String
    let action: () -> Void

    var body: some View {
        Button(action: {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        }) {
            VStack(spacing: 3) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: isSelected ? selectedIcon : icon)
                        .font(.obsidianAction)
                        .symbolRenderingMode(.hierarchical)
                    if badgeCount > 0 {
                        Text("\(badgeCount)")
                            .font(.nano)
                            .foregroundColor(.white)
                            .frame(minWidth: 14, minHeight: 14)
                            .background(Color.statusNotInterested)
                            .clipShape(Circle())
                            .offset(x: 8, y: -4)
                    }
                }
                Text(title)
                    .font(.nano)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .foregroundColor(isSelected ? Color.electricViolet : Color.textMuted)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(isSelected ? Color.electricViolet.opacity(0.15) : Color.clear)
                    .padding(.horizontal, 4)
            )
            .animation(.spring(response: 0.35, dampingFraction: 0.75), value: isSelected)
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityLabel(title)
        .accessibilityIdentifier(accessibilityID)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

#Preview {
    MainTabView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}
