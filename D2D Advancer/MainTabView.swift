import SwiftUI
import CoreData
import UIKit

struct MainTabView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.managedObjectContext) private var viewContext
    @ObservedObject private var router = AppRouter.shared
    private let locationManager = LocationManager.shared
    @ObservedObject private var userAccountManager = FirebaseUserAccountManager.shared
    private let teamService = TeamFirebaseService.shared
    @State private var didApplyRoleDefaultTab = false
    @State private var shouldKeepMapAlive = false
    @State private var mapPrewarmTask: Task<Void, Never>?
    @State private var mapReleaseTask: Task<Void, Never>?
    @State private var overdueLeadBadgeCount = 0
    @State private var overdueLeadBadgeTask: Task<Void, Never>?
    @State private var teamLeadBadgeCount = 0
    @State private var roleContext: TeamRoleContext = .solo
    @State private var teamPresentationRefreshTask: Task<Void, Never>?

    private var isRunningUITests: Bool {
        ProcessInfo.processInfo.arguments.contains("-skipOnboardingForUITests")
    }

    private var shouldExerciseMapRuntimeEffects: Bool {
        ProcessInfo.processInfo.arguments.contains("-exerciseMapRuntimeEffectsForUITests")
    }

    private var shouldLoadTeamWorkspace: Bool {
        !isRunningUITests || FirebaseEmulatorConfiguration.isEnabled
    }

    private var shouldOpenTeamWorkspaceForUITests: Bool {
        ProcessInfo.processInfo.arguments.contains("-openTeamWorkspaceForUITests")
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
                            isSelected: router.selectedTab == MainAppTab.map.rawValue,
                            accessibilityID: "tab_Map",
                            action: { router.selectedTab = MainAppTab.map.rawValue }
                        )

                        TabBarButton(
                            title: roleContext.leadsTabTitle,
                            icon: "person.2",
                            selectedIcon: "person.2.fill",
                            isSelected: router.selectedTab == MainAppTab.leads.rawValue,
                            badgeCount: teamLeadBadgeCount,
                            accessibilityID: "tab_Leads",
                            action: { router.selectedTab = MainAppTab.leads.rawValue }
                        )

                        TabBarButton(
                            title: roleContext.workTabTitle,
                            icon: "briefcase",
                            selectedIcon: "briefcase.fill",
                            isSelected: router.selectedTab == MainAppTab.work.rawValue,
                            badgeCount: overdueLeadBadgeCount,
                            accessibilityID: "tab_Work",
                            action: { router.selectedTab = MainAppTab.work.rawValue }
                        )

                        TabBarButton(
                            title: roleContext.moreTabTitle,
                            icon: "ellipsis.circle",
                            selectedIcon: "ellipsis.circle.fill",
                            isSelected: router.selectedTab == MainAppTab.more.rawValue,
                            accessibilityID: "tab_More",
                            action: { router.selectedTab = MainAppTab.more.rawValue }
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.obsidianBackground(for: colorScheme).ignoresSafeArea())
        .customThemed()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("mainTabView")
        .onAppear {
            scheduleOverdueLeadBadgeRefresh(after: 0)
            refreshTeamPresentation()

            if router.selectedTab == MainAppTab.map.rawValue {
                shouldKeepMapAlive = true
            } else {
                scheduleMapPrewarmIfNeeded()
            }

            if isRunningUITests {
                print("🧪 MainTabView: Skipping startup side effects for UI tests")
                if shouldExerciseMapRuntimeEffects {
                    initializeLocationServices()
                }
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
        .onReceive(teamService.objectWillChange) { _ in
            scheduleTeamPresentationRefresh()
        }
        .onChange(of: router.selectedTab) { _, newTab in
            if newTab == MainAppTab.map.rawValue {
                mapPrewarmTask?.cancel()
                mapPrewarmTask = nil
                mapReleaseTask?.cancel()
                mapReleaseTask = nil
                shouldKeepMapAlive = true
            } else if shouldKeepMapAlive {
                scheduleMapReleaseIfNeeded()
            } else {
                scheduleMapPrewarmIfNeeded()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)) { _ in
            guard router.selectedTab != MainAppTab.map.rawValue else { return }
            mapPrewarmTask?.cancel()
            mapPrewarmTask = nil
            mapReleaseTask?.cancel()
            mapReleaseTask = nil
            shouldKeepMapAlive = false
        }
        .onDisappear {
            mapPrewarmTask?.cancel()
            mapPrewarmTask = nil
            mapReleaseTask?.cancel()
            mapReleaseTask = nil
            overdueLeadBadgeTask?.cancel()
            overdueLeadBadgeTask = nil
            teamPresentationRefreshTask?.cancel()
            teamPresentationRefreshTask = nil
        }
    }

    @ViewBuilder
    private var tabContent: some View {
        ZStack {
            if shouldKeepMapAlive || router.selectedTab == MainAppTab.map.rawValue {
                MapView(isVisible: router.selectedTab == MainAppTab.map.rawValue)
                    .opacity(router.selectedTab == MainAppTab.map.rawValue ? 1 : 0)
                    .allowsHitTesting(router.selectedTab == MainAppTab.map.rawValue)
                    .accessibilityHidden(router.selectedTab != MainAppTab.map.rawValue)
                    .zIndex(router.selectedTab == MainAppTab.map.rawValue ? 1 : 0)
            }

            if router.selectedTab != MainAppTab.map.rawValue {
                nonMapTabContent
                    .zIndex(2)
            }
        }
    }

    @ViewBuilder
    private var nonMapTabContent: some View {
        switch router.selectedTab {
        case MainAppTab.leads.rawValue:
            LeadsListView()
        case MainAppTab.work.rawValue:
            WorkView(roleContext: roleContext)
        case MainAppTab.more.rawValue:
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
        refreshTeamPresentation()
    }

    private func scheduleTeamPresentationRefresh(after delay: TimeInterval = 0.08) {
        teamPresentationRefreshTask?.cancel()
        teamPresentationRefreshTask = Task { @MainActor in
            if delay > 0 {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
            guard !Task.isCancelled else { return }
            refreshTeamPresentation()
            teamPresentationRefreshTask = nil
        }
    }

    private func refreshTeamPresentation() {
        let summary = TeamWorkspaceSurfaceSummary.makeShortcut(
            team: teamService.activeTeam,
            currentMember: teamService.currentMember,
            members: teamService.teamMembers,
            leads: teamService.teamLeads,
            bookings: teamService.teamBookings,
            dutySessions: teamService.dutySessions,
            ownerNotifications: teamService.ownerNotifications
        )
        let nextRoleContext = TeamRoleContext(summary: summary)
        let nextBadgeCount = min(summary?.badgeCount ?? 0, 99)

        if roleContext != nextRoleContext {
            roleContext = nextRoleContext
            applyDefaultTabForRoleIfNeeded()
        }
        if teamLeadBadgeCount != nextBadgeCount {
            teamLeadBadgeCount = nextBadgeCount
        }
    }

    private func applyDefaultTabForRoleIfNeeded(reset: Bool = false) {
        guard !isRunningUITests else { return }
        if reset {
            didApplyRoleDefaultTab = false
        }
        guard !didApplyRoleDefaultTab else { return }
        guard router.selectedTab == MainAppTab.map.rawValue else {
            didApplyRoleDefaultTab = true
            return
        }

        let defaultTab = roleContext.defaultTabIndex
        router.selectedWorkSection = roleContext.defaultWorkSection
        if defaultTab != router.selectedTab {
            router.selectedTab = defaultTab
        }
        didApplyRoleDefaultTab = true
    }

    private func scheduleMapPrewarmIfNeeded() {
        guard !isRunningUITests || shouldExerciseMapRuntimeEffects else { return }
        guard !shouldKeepMapAlive else { return }
        guard mapPrewarmTask == nil else { return }

        mapPrewarmTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard !Task.isCancelled,
                  router.selectedTab != MainAppTab.map.rawValue else { return }
            shouldKeepMapAlive = true
            mapPrewarmTask = nil
            scheduleMapReleaseIfNeeded()
        }
    }

    private func scheduleMapReleaseIfNeeded(after delay: TimeInterval = 45) {
        guard router.selectedTab != MainAppTab.map.rawValue else { return }
        mapReleaseTask?.cancel()
        mapReleaseTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled,
                  router.selectedTab != MainAppTab.map.rawValue else { return }
            shouldKeepMapAlive = false
            mapReleaseTask = nil
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
        .frame(maxWidth: .infinity, minHeight: 56)
        .contentShape(Rectangle())
        .accessibilityLabel(title)
        .accessibilityIdentifier(accessibilityID)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

#Preview {
    MainTabView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}
