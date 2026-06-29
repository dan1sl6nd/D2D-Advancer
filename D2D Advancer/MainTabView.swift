import SwiftUI

struct MainTabView: View {
    @ObservedObject private var router = AppRouter.shared
    @ObservedObject private var locationManager = LocationManager.shared
    @ObservedObject private var userAccountManager = FirebaseUserAccountManager.shared
    @ObservedObject private var teamService = TeamFirebaseService.shared

    @FetchRequest(
        sortDescriptors: [],
        predicate: Lead.Status.activeFollowUpPredicate(dueBefore: Date())
    ) private var overdueLeads: FetchedResults<Lead>

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

    private var teamLeadBadgeCount: Int {
        min(teamSurfaceSummary?.badgeCount ?? 0, 99)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Content area
            Group {
                switch router.selectedTab {
                case 0:
                    MapView()
                case 1:
                    LeadsListView()
                case 2:
                    FollowUpView()
                case 3:
                    AppointmentsView()
                case 4:
                    MoreView()
                default:
                    MapView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(.easeInOut(duration: 0.2), value: router.selectedTab)

            // Obsidian tab bar
            HStack(spacing: 0) {
                TabBarButton(
                    title: "Map",
                    icon: "map",
                    selectedIcon: "map.fill",
                    isSelected: router.selectedTab == 0,
                    action: { router.selectedTab = 0 }
                )

                TabBarButton(
                    title: "Leads",
                    icon: "person.2",
                    selectedIcon: "person.2.fill",
                    isSelected: router.selectedTab == 1,
                    badgeCount: teamLeadBadgeCount,
                    action: { router.selectedTab = 1 }
                )

                TabBarButton(
                    title: "Follow Up",
                    icon: "bell",
                    selectedIcon: "bell.fill",
                    isSelected: router.selectedTab == 2,
                    badgeCount: overdueLeads.count,
                    action: { router.selectedTab = 2 }
                )

                TabBarButton(
                    title: "Appts",
                    icon: "calendar",
                    selectedIcon: "calendar",
                    isSelected: router.selectedTab == 3,
                    action: { router.selectedTab = 3 }
                )

                TabBarButton(
                    title: "More",
                    icon: "ellipsis.circle",
                    selectedIcon: "ellipsis.circle.fill",
                    isSelected: router.selectedTab == 4,
                    action: { router.selectedTab = 4 }
                )
            }
            .padding(.top, 8)
            .background(Color.obsidianBlack)
            .overlay(
                Rectangle()
                    .fill(Color.obsidianBorder)
                    .frame(height: 1),
                alignment: .top
            )
        }
        .background(Color.obsidianBlack)
        .customThemed()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("mainTabView")
        .onAppear {
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
            }
        }
        .onChange(of: userAccountManager.isLoggedIn) { _, _ in
            Task {
                await loadTeamWorkspaceIfNeeded()
            }
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
        .accessibilityIdentifier("tab_\(title.replacingOccurrences(of: " ", with: "_"))")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

#Preview {
    MainTabView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}
