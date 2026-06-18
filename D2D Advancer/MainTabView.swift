import SwiftUI

struct MainTabView: View {
    @ObservedObject private var router = AppRouter.shared
    @ObservedObject private var locationManager = LocationManager.shared

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
                    action: { router.selectedTab = 1 }
                )

                TabBarButton(
                    title: "Follow Up",
                    icon: "bell",
                    selectedIcon: "bell.fill",
                    isSelected: router.selectedTab == 2,
                    action: { router.selectedTab = 2 }
                )

                TabBarButton(
                    title: "Appts",
                    icon: "calendar",
                    selectedIcon: "calendar.fill" ,
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
        .navigationViewStyle(StackNavigationViewStyle())
        .customThemed()
        .onAppear {
            // Initialize location services immediately when app launches
            print("📱 MainTabView: App launched, initializing location services")
            initializeLocationServices()

            // Clean up any duplicate appointments first
            AppointmentManager.shared.removeDuplicateAppointments()

            // Fix any cancelled appointments so they appear in the UI
            AppointmentManager.shared.fixCancelledAppointments()

            // Start Firebase appointment listener when main app loads
            AppointmentManager.shared.restartFirebaseSync()
            print("🗓️ MainTabView: Started Firebase listener for appointments on app launch")
        }
    }

    // MARK: - Location Services Initialization
    private func initializeLocationServices() {
        print("📍 MainTabView: Initializing location services for immediate map centering")

        // Check if onboarding is completed before requesting permissions
        let onboardingCompleted = UserDefaults.standard.bool(forKey: "onboarding_completed")

        switch locationManager.authorizationStatus {
        case .notDetermined:
            if onboardingCompleted {
                print("📍 MainTabView: Onboarding completed - requesting location permission")
                locationManager.requestLocationPermission()
            } else {
                print("📍 MainTabView: Onboarding not completed - skipping location permission request (will be handled in onboarding)")
            }
        case .authorizedWhenInUse, .authorizedAlways:
            print("📍 MainTabView: Permission already granted, starting location updates")
            locationManager.startLocationUpdates()

            // If we have a cached location, immediately center on it
            if locationManager.location != nil {
                print("📍 MainTabView: Found cached location, centering map immediately")
                locationManager.forceInitialLocationCenter()
            } else {
                print("📍 MainTabView: No cached location, requesting immediate update")
                locationManager.requestImmediateLocation()
            }
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
    let action: () -> Void

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: isSelected ? selectedIcon : icon)
                .font(.system(size: 20))
            Text(title)
                .font(.system(size: 11, weight: .medium))

            // Capsule underline for selected tab
            Capsule()
                .fill(Color.electricViolet)
                .frame(width: 20, height: 2)
                .opacity(isSelected ? 1 : 0)
        }
        .foregroundColor(isSelected ? Color.electricViolet : Color.textMuted)
        .frame(maxWidth: .infinity, minHeight: 64)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("tab_\(title.replacingOccurrences(of: " ", with: ""))")
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

#Preview {
    MainTabView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}
