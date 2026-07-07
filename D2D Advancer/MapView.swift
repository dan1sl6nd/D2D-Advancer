import SwiftUI
import MapKit
import CoreData
import UIKit

enum MapWorkflowMode: String, CaseIterable, Identifiable {
    case all
    case hot
    case due
    case today
    case sold
    case next

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "All"
        case .hot: return "Hot"
        case .due: return "Due"
        case .today: return "Today"
        case .sold: return "Sold"
        case .next: return "Next"
        }
    }

    var icon: String {
        switch self {
        case .all: return "map"
        case .hot: return "flame.fill"
        case .due: return "calendar.badge.clock"
        case .today: return "sun.max.fill"
        case .sold: return "checkmark.seal.fill"
        case .next: return "sparkles"
        }
    }

    var color: Color {
        switch self {
        case .all: return Color.electricViolet
        case .hot: return Color.statusInterested
        case .due: return Color.statusNotHome
        case .today: return Color.electricViolet
        case .sold: return Color.statusConverted
        case .next: return Color.statusInterested
        }
    }

    func includes(_ lead: Lead, now: Date = Date()) -> Bool {
        switch self {
        case .all:
            return true
        case .hot:
            return LeadMapWorkflowPolicy.isHotLead(lead, now: now)
        case .due:
            return LeadWorkflowScorer.isFollowUpDue(lead, now: now)
        case .today:
            return Calendar.current.isDate(lead.createdDate ?? .distantPast, inSameDayAs: now)
        case .sold:
            return lead.leadStatus == .converted
        case .next:
            return lead.leadStatus != .notInterested && lead.leadStatus != .converted
        }
    }
}

enum MapAddressSource {
    case mapSearchAddress
    case streetAddress
    case preferredAddress
    case coordinateFallback

    var debugLabel: String {
        switch self {
        case .mapSearchAddress:
            return "map search address"
        case .streetAddress:
            return "street address"
        case .preferredAddress:
            return "preferred address"
        case .coordinateFallback:
            return "coordinate fallback"
        }
    }
}

enum MapQuickLeadAddressPolicy {
    static func acceptedAddress(_ address: String, source: MapAddressSource) -> String? {
        guard source != .coordinateFallback else { return nil }
        return AddLeadAddressPolicy.cleanedAddress(address)
    }
}

enum MapAddressResolutionPolicy {
    static func resolvedCoordinate(
        pressedCoordinate: CLLocationCoordinate2D,
        candidateCoordinate: CLLocationCoordinate2D?,
        source: MapAddressSource
    ) -> CLLocationCoordinate2D {
        switch source {
        case .mapSearchAddress, .streetAddress:
            return candidateCoordinate ?? pressedCoordinate
        case .preferredAddress, .coordinateFallback:
            return pressedCoordinate
        }
    }
}

enum MapQuickActionLeadPolicy {
    static func usableAddress(_ address: String) -> String? {
        AddLeadAddressPolicy.cleanedAddress(address)
    }

    static func canCreateLead(address: String) -> Bool {
        usableAddress(address) != nil
    }
}

struct MapQuickActionLeadSeed {
    let coordinate: CLLocationCoordinate2D
    let address: String?
}

enum MapQuickActionLeadSeedPolicy {
    static func seed(
        resolvedCoordinate: CLLocationCoordinate2D,
        resolvedAddress: String,
        source: MapAddressSource
    ) -> MapQuickActionLeadSeed {
        MapQuickActionLeadSeed(
            coordinate: resolvedCoordinate,
            address: MapQuickLeadAddressPolicy.acceptedAddress(resolvedAddress, source: source)
        )
    }
}

enum MapLongPressLeadSeedPolicy {
    static func seed(
        pressedCoordinate: CLLocationCoordinate2D,
        confirmedAddress: String
    ) -> AddLeadLocationSeed {
        AddLeadLocationSeed(
            coordinate: pressedCoordinate,
            address: confirmedAddress
        )
    }
}

struct MapQuickLeadUndoDeletionPlan: Equatable {
    let localDeletedId: UUID?
    let cloudLeadId: String?
}

enum MapQuickLeadUndoPolicy {
    static func deletionPlan(
        leadId: UUID?,
        provider: CloudSyncProvider,
        isAuthenticated: Bool
    ) -> MapQuickLeadUndoDeletionPlan {
        let cloudLeadId: String?
        if let leadId,
           UserDataSyncManager.shouldDeleteLeadFromCloud(
            provider: provider,
            isAuthenticated: isAuthenticated
           ) {
            cloudLeadId = leadId.uuidString
        } else {
            cloudLeadId = nil
        }

        return MapQuickLeadUndoDeletionPlan(
            localDeletedId: leadId,
            cloudLeadId: cloudLeadId
        )
    }
}

private struct MapAddressResolution {
    let coordinate: CLLocationCoordinate2D
    let address: String
    let source: MapAddressSource
}

private struct MapAddressCandidate {
    let address: String
    let coordinate: CLLocationCoordinate2D
    let hasStreetNumber: Bool
    let distanceFromPress: CLLocationDistance
    let score: Double
    let source: MapAddressSource
    let confidenceRadius: CLLocationDistance

    var isConfident: Bool {
        hasStreetNumber && distanceFromPress <= confidenceRadius
    }
}

private enum MapStyleChoice: String, CaseIterable, Identifiable {
    case standard
    case satellite
    case hybrid

    var id: String { rawValue }

    var title: String {
        switch self {
        case .standard: return "Standard"
        case .satellite: return "Satellite"
        case .hybrid: return "Hybrid"
        }
    }

    var icon: String {
        switch self {
        case .standard: return "map"
        case .satellite: return "globe.americas.fill"
        case .hybrid: return "map.fill"
        }
    }

    var mapType: MKMapType {
        switch self {
        case .standard: return .standard
        case .satellite: return .satellite
        case .hybrid: return .hybrid
        }
    }

    static func choice(for mapType: MKMapType) -> MapStyleChoice {
        switch mapType {
        case .satellite, .satelliteFlyover:
            return .satellite
        case .hybrid, .hybridFlyover:
            return .hybrid
        default:
            return .standard
        }
    }
}

enum MapLaunchCenteringPolicy {
    private static let foregroundRecenteringDistance: CLLocationDistance = 150

    static func isMapCenteredOnUser(
        region: MKCoordinateRegion,
        location: CLLocation?,
        distanceThreshold: CLLocationDistance = foregroundRecenteringDistance
    ) -> Bool {
        guard let location,
              LocationManager.isUsableForInitialMapCenter(location) else {
            return false
        }

        let mapCenter = CLLocation(
            latitude: region.center.latitude,
            longitude: region.center.longitude
        )
        let allowedDistance = max(distanceThreshold, location.horizontalAccuracy * 1.5)
        return mapCenter.distance(from: location) <= allowedDistance
    }

    static func hasUsableLaunchLocationTarget(
        region: MKCoordinateRegion,
        location: CLLocation?
    ) -> Bool {
        isMapCenteredOnUser(region: region, location: location)
    }

    static func shouldPrepareOnForeground(
        isAuthorized: Bool,
        didCenterMapOnLaunch: Bool,
        isLaunchCenteringActive _: Bool,
        hasUsableLocation: Bool,
        mapIsCenteredOnUser: Bool
    ) -> Bool {
        guard isAuthorized else { return false }
        return !didCenterMapOnLaunch
            || !hasUsableLocation
            || !mapIsCenteredOnUser
    }

    static func shouldApplyLaunchCenteringRequest(
        visibleMapCenteredConfirmed: Bool,
        isLaunchCenteringActive _: Bool
    ) -> Bool {
        !visibleMapCenteredConfirmed
    }
}

struct MapView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject private var locationManager = LocationManager.shared
    @ObservedObject private var onboardingManager = OnboardingManager.shared
    @ObservedObject private var preferences = AppPreferences.shared
    @ObservedObject private var firebaseService = FirebaseService.shared
    @ObservedObject private var teamService = TeamFirebaseService.shared
    @ObservedObject private var syncManager = UserDataSyncManager.shared
    @ObservedObject private var userAccountManager = FirebaseUserAccountManager.shared
    @State private var selectedLead: Lead?
    @State private var showingAddLead = false
    @State private var addLeadCoordinate: CLLocationCoordinate2D?
    @State private var addLeadInitialAddress: String?
    @State private var addLeadPresentationID = UUID()
    @State private var isPreparingCurrentLocationLead = false
    @State private var mapType: MKMapType = AppPreferences.shared.mapDefaultViewType
    @State private var mapRotation: Double = 0.0
    @State private var mapPitch: Double = 0.0
    @State private var is3DModeEnabled = false
    @State private var leadToChangeStatus: Lead?
    @State private var triggerMapAnimation = false
    @ObservedObject private var paywallManager = PaywallManager.shared
    @State private var toastLead: Lead?
    @State private var toastMessage: String = ""
    @State private var toastToken = UUID()
    @State private var showToast = false
    @State private var showingLookAround = false
    @State private var showingRoutePlanner = false
    @State private var showingMapTools = false
    @State private var lookAroundCoordinate = CLLocationCoordinate2D(latitude: 0, longitude: 0)
    @State private var longPressCoordinate: CLLocationCoordinate2D?
    @State private var longPressAddress: String?
    @State private var activeDialog: MapDialog?
    @State private var isSearching = false
    @State private var searchPin: SearchPin?
    @State private var pendingSearchPinActions: SearchPin?
    @State private var showingSearchPinActions = false
    @State private var matchingLeadsForPin: [Lead] = []
    @State private var selectedLeadCluster: LeadClusterSelection?
    @State private var showingInterestedForm = false
    @State private var interestedFormCoordinate: CLLocationCoordinate2D?
    @State private var showingComeBackPicker = false
    @State private var comeBackCoordinate: CLLocationCoordinate2D?
    @State private var didCenterMapOnLaunch = false
    @State private var didRequestLaunchLocationCenter = false
    @State private var didConfirmVisibleMapCenteredOnLaunch = false
    @State private var launchCenteringResetToken = 0
    @State private var showingTeamFieldMap = false
    @State private var selectedTeamRepUserId: String?
    @State private var selectedMapMode: MapWorkflowMode = .all

    private var isRunningUITests: Bool {
        ProcessInfo.processInfo.arguments.contains("-skipOnboardingForUITests")
    }

    private var shouldLoadTeamWorkspace: Bool {
        !isRunningUITests || FirebaseEmulatorConfiguration.isEnabled
    }

    enum MapDialog: Identifiable {
        case statusChange
        case longPressMenu
        var id: Int { hashValue }
    }

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Lead.updatedDate, ascending: false)],
        animation: .default
    )
    private var leads: FetchedResults<Lead>

    private var interestedCount: Int {
        leads.filter { $0.status == "interested" }.count
    }

    private var notHomeCount: Int {
        leads.filter { $0.status == "not_home" }.count
    }

    private var notInterestedCount: Int {
        leads.filter { $0.status == "not_interested" }.count
    }

    private var soldCount: Int {
        leads.filter { $0.status == "converted" }.count
    }

    private var todayCount: Int {
        let startOfDay = Calendar.current.startOfDay(for: Date())
        return leads.filter { ($0.createdDate ?? .distantPast) >= startOfDay }.count
    }

    private var allLeads: [Lead] {
        Array(leads)
    }

    private var visibleMapLeads: [Lead] {
        MapLeadVisibilityPolicy.visibleLeads(
            from: allLeads,
            mode: selectedMapMode
        )
    }

    private var nextBestLead: Lead? {
        LeadWorkflowScorer.nextBestLead(
            from: allLeads,
            near: locationManager.location?.coordinate ?? locationManager.region.center
        )
    }

    private var workflowStatusText: String? {
        switch teamService.syncWriteState {
        case .pending, .failed:
            return teamService.syncWriteState.displayText
        case .idle:
            break
        }

        if syncManager.syncStatus.isBusy {
            return syncManager.syncStatus.displayText
        }

        if selectedMapMode != .all {
            return "\(visibleMapLeads.count) \(selectedMapMode.title.lowercased()) leads"
        }

        return nil
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
        ZStack {
                mapView
                overlayControls
                toastOverlay

                // Show location permission status
                if !isRunningUITests && LocationManager.shouldShowPermissionPrompt(
                    for: locationManager.authorizationStatus,
                    hasKnownLocation: locationManager.location != nil,
                    isOnboardingPresented: onboardingManager.showOnboarding
                ) {
                    VStack {
                        Spacer()
                        statusIndicator
                    }
                }
            }
            .navigationBarHidden(true)
            .ignoresSafeArea(.all, edges: .top)
            .onAppear {
                if !isRunningUITests {
                    prepareLaunchMapCentering()
                }
            }
            .sheet(item: $selectedLead) { lead in
                LeadDetailView(lead: lead)
            }
            .sheet(item: $selectedLeadCluster) { selection in
                LeadClusterSheet(
                    selection: selection,
                    onViewLead: { lead in
                        selectedLead = lead
                    },
                    onFocusLead: { lead in
                        focusLead(lead, openDetail: false)
                    }
                )
                .presentationDetents([.medium, .large])
            }
            .sheet(
                isPresented: $showingAddLead,
                onDismiss: {
                    addLeadCoordinate = nil
                    addLeadInitialAddress = nil
                }
            ) {
                AddLeadView(
                    coordinate: addLeadCoordinate ?? locationManager.region.center,
                    initialAddress: addLeadInitialAddress
                )
                .id(addLeadPresentationID)
            }
            .sheet(item: $activeDialog) { dialog in
                switch dialog {
                case .statusChange:
	                    StatusChangeSheet(
	                        lead: leadToChangeStatus,
	                        onSelect: { status in
	                            if let lead = leadToChangeStatus {
	                                updateLeadStatusFromMap(lead, status: status)
	                            }
	                            activeDialog = nil
	                            leadToChangeStatus = nil
	                        },
                        onCancel: {
                            activeDialog = nil
                            leadToChangeStatus = nil
                        }
                    )
                    .presentationDetents([.medium])
                case .longPressMenu:
                    LongPressMenuSheet(
                        coordinate: longPressCoordinate,
                        address: $longPressAddress,
                        onAddLead: { resolvedAddress in
                            guard paywallManager.gateAction() else { return }
                            let coordinate = longPressCoordinate
                            activeDialog = nil
                            longPressAddress = resolvedAddress
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                                guard let coordinate else { return }
                                let seed = MapLongPressLeadSeedPolicy.seed(
                                    pressedCoordinate: coordinate,
                                    confirmedAddress: resolvedAddress
                                )
                                presentAddLead(
                                    coordinate: seed.coordinate,
                                    initialAddress: seed.address
                                )
                            }
                        },
                        onStreetView: {
                            if let coordinate = longPressCoordinate {
                                lookAroundCoordinate = coordinate
                            }
                            activeDialog = nil
                            // Delay Look Around sheet until long press sheet finishes dismissing
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                                showingLookAround = true
                            }
                        },
                        onNavigate: {
                            let coordinate = longPressCoordinate
                            let name = longPressAddress
                            activeDialog = nil
                            // Delay the launch until the sheet finishes dismissing to
                            // prevent Maps from opening behind a still-animating modal.
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                                guard let coordinate = coordinate else { return }
                                let placemark = MKPlacemark(coordinate: coordinate)
                                let mapItem = MKMapItem(placemark: placemark)
                                mapItem.name = name ?? "Dropped Pin"
                                mapItem.openInMaps(launchOptions: [
                                    MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving
                                ])
                            }
                        },
                        onCancel: { activeDialog = nil }
                    )
                    .presentationDetents([.large])
                }
            }
            .sheet(isPresented: $showingLookAround) {
                LookAroundSheet(
                    coordinate: $lookAroundCoordinate,
                    title: "Street View"
                )
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showingRoutePlanner) {
                RoutePlannerSheet(region: locationManager.region)
            }
            .sheet(isPresented: $showingMapTools) {
                MapToolsSheet(
                    selectedMode: selectedMapMode,
                    selectedStyle: MapStyleChoice.choice(for: mapType),
                    is3DModeEnabled: is3DModeEnabled,
                    workflowStatusText: workflowStatusText,
                    teamSummary: teamSurfaceSummary,
                    onSelectMode: setMapMode,
                    onSelectMapStyle: { choice in
                        setMapType(choice.mapType)
                    },
                    onToggle3D: toggle3DMode,
                    onOpenRoutePlanner: {
                        showingRoutePlanner = true
                    },
                    onOpenTeamMap: openTeamFieldMap
                )
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
            .sheet(
                isPresented: $isSearching,
                onDismiss: {
                    guard let pin = pendingSearchPinActions else { return }
                    pendingSearchPinActions = nil
                    DispatchQueue.main.async {
                        presentSearchPinActions(for: pin, haptic: false)
                    }
                }
            ) {
                MapSearchSheet { coordinate, title in
                    let pin = SearchPin(coordinate: coordinate, title: title)
                    searchPin = pin
                    pendingSearchPinActions = pin
                    let newRegion = MKCoordinateRegion(
                        center: coordinate,
                        span: MKCoordinateSpan(latitudeDelta: 0.005, longitudeDelta: 0.005)
                    )
                    triggerMapAnimation = true
                    locationManager.region = newRegion
                }
            }
            .sheet(isPresented: $showingSearchPinActions) {
                SearchPinActionsSheet(
                    pin: searchPin ?? SearchPin(coordinate: CLLocationCoordinate2D(), title: ""),
                    matchingLeads: matchingLeadsForPin,
                    onViewLead: { lead in
                        showingSearchPinActions = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                            selectedLead = lead
                        }
                    },
                    onAddLead: {
                        guard let pin = searchPin else { return }
                        showingSearchPinActions = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                            presentAddLeadFromSelectedPin(
                                coordinate: pin.coordinate,
                                preferredAddress: pin.title
                            )
                        }
                    }
                )
                .presentationDetents([.medium])
            }
            .sheet(isPresented: $showingInterestedForm) {
                InterestedQuickForm(
                    coordinate: interestedFormCoordinate ?? locationManager.region.center,
                    resolveLeadSeed: resolveQuickActionLeadSeed
                ) {
                    showingInterestedForm = false
                }
                .presentationDetents([.large])
            }
            .sheet(isPresented: $showingComeBackPicker) {
                ComeBackLaterSheet(
                    coordinate: comeBackCoordinate ?? locationManager.region.center,
                    resolveLeadSeed: resolveQuickActionLeadSeed,
                    onDone: { showingComeBackPicker = false }
                )
                .presentationDetents([.large])
            }
            .sheet(isPresented: $showingTeamFieldMap) {
                if let summary = teamSurfaceSummary {
                    TeamFieldMapSheet(
                        summary: summary,
                        selectedRepUserId: $selectedTeamRepUserId
                    )
                }
            }
            .task {
                await loadTeamWorkspaceUntilAvailable()
            }
            .onChange(of: userAccountManager.isLoggedIn) { _, _ in
                Task {
                    await loadTeamWorkspaceUntilAvailable()
                }
            }
            .onChange(of: firebaseService.currentUser?.uid) { _, _ in
                Task {
                    await loadTeamWorkspaceUntilAvailable()
                }
            }
    }

    private var mapView: some View {
        AdvancedMapView(
            region: $locationManager.region,
            mapType: $mapType,
            rotation: $mapRotation,
            pitch: $mapPitch,
            animateNextUpdate: $triggerMapAnimation,
            is3DModeEnabled: $is3DModeEnabled,
            launchCenteringResetToken: launchCenteringResetToken,
            launchLocationCenterRevision: locationManager.initialMapCenterRevision,
            leads: visibleMapLeads,
            searchPin: $searchPin,
            showsUserLocation: !isRunningUITests && LocationManager.isAuthorized(locationManager.authorizationStatus),
            shouldFollowUserLocationOnLaunch: !isRunningUITests
                && locationManager.shouldUseUserLocation
                && !didConfirmVisibleMapCenteredOnLaunch,
            needsLaunchLocationCenteringConfirmation: !isRunningUITests
                && LocationManager.isAuthorized(locationManager.authorizationStatus)
                && !didConfirmVisibleMapCenteredOnLaunch,
            hasLaunchLocationCandidate: MapLaunchCenteringPolicy.hasUsableLaunchLocationTarget(
                region: locationManager.region,
                location: locationManager.location
            ),
            onLaunchCenteringConfirmed: {
                didCenterMapOnLaunch = true
                didRequestLaunchLocationCenter = true
                didConfirmVisibleMapCenteredOnLaunch = true
            },
            onLeadTap: { lead in
                selectedLead = lead
            },
            onLeadClusterTap: { leads, coordinate in
                selectedLeadCluster = LeadClusterSelection(leads: leads, coordinate: coordinate)
            },
            onSearchPinTap: { pin in
                handleSearchPinTap(pin)
            },
            onLongPress: { coordinate, lead in
                handleLongPress(coordinate: coordinate, lead: lead)
            }
        )
        .onChangeCompat(of: onboardingManager.showOnboarding) { isPresented in
            if !isPresented && !isRunningUITests {
                prepareLaunchMapCentering()
            }
        }
        .onChange(of: locationManager.authorizationStatus) { _, newStatus in
            guard !isRunningUITests else { return }
            if newStatus == .authorizedWhenInUse || newStatus == .authorizedAlways {
                prepareLaunchMapCentering()
            }
        }
        .onReceive(locationManager.$location) { location in
            guard !isRunningUITests, location != nil else { return }
            centerMapOnLaunchIfPossible()
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard !isRunningUITests, newPhase == .active else { return }
            refreshLaunchMapCenteringAfterForeground()
        }
    }
    private var overlayControls: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 10) {
                        statSummaryPill
                        urgentTeamMapShortcut
                    }

                    Spacer()

                    mapControlsGroup
                }
                .padding(.horizontal, 16)
                .padding(.top, overlayTopPadding(for: geometry))

                Spacer()

                // Bottom: floating action bar
                floatingActionBar
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
            }
            .ignoresSafeArea()
        }
    }

    private func overlayTopPadding(for geometry: GeometryProxy) -> CGFloat {
        // The map root ignores the top safe area, so GeometryProxy can report
        // zero here. Clamp to keep controls out of the status bar and tappable.
        ObsidianLayout.safeAreaTop(geometry, minimum: 56) + 4
    }

    private var statusIndicator: some View {
        VStack(spacing: 8) {
            if locationManager.authorizationStatus == .denied || locationManager.authorizationStatus == .restricted {
                deniedLocationView
            } else if locationManager.authorizationStatus == .notDetermined {
                requestingLocationView
            } else if locationManager.location != nil {
                activeLocationView
            }
        }
    }
    
    private var deniedLocationView: some View {
        VStack(spacing: 16) {
            Image(systemName: "location.slash")
                .font(.displayMedium)
                .foregroundColor(Color.statusNotInterested)

            VStack(spacing: 6) {
                Text("Location Access Denied")
                    .font(.obsidianTitle)
                    .foregroundColor(Color.textPrimary)

                Text("Enable location in Settings to use map features.")
                    .font(.obsidianBody)
                    .multilineTextAlignment(.center)
                    .foregroundColor(Color.textSecondary)
            }

            Button("Open Settings") {
                if let settingsUrl = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(settingsUrl)
                }
            }
            .buttonStyle(ObsidianPrimaryButtonStyle())
        }
        .padding(24)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .padding(24)
    }

    private var requestingLocationView: some View {
        VStack(spacing: 16) {
            Image(systemName: "location.badge.questionmark")
                .font(.displayMedium)
                .foregroundColor(Color.electricViolet)

            VStack(spacing: 6) {
                Text("Location Permission Required")
                    .font(.obsidianTitle)
                    .foregroundColor(Color.textPrimary)

                Text("D2D Advancer needs location access to show your position on the map.")
                    .font(.obsidianBody)
                    .multilineTextAlignment(.center)
                    .foregroundColor(Color.textSecondary)
            }

            Button("Grant Location Access") {
                locationManager.requestLocationPermission()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    locationManager.refreshAuthorizationStatusFromSystem()
                    if locationManager.authorizationStatus == .notDetermined {
                        locationManager.requestLocationPermission()
                    }
                }
            }
            .buttonStyle(ObsidianPrimaryButtonStyle())
        }
        .padding(24)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .padding(24)
    }

    private var activeLocationView: some View {
        EmptyView()
    }
    
    private func setupLocationServices() {
        locationManager.refreshAuthorizationStatusFromSystem(startIfAuthorized: false)

        let canRequestLocationOutsideOnboarding = OnboardingManager.shared.isCompleted && !OnboardingManager.shared.showOnboarding

        switch locationManager.authorizationStatus {
        case .notDetermined:
            if canRequestLocationOutsideOnboarding {
                locationManager.requestLocationPermission()
            }
        case .authorizedWhenInUse, .authorizedAlways:
            locationManager.startLaunchLocationCentering()
        case .denied, .restricted:
            break
        @unknown default:
            break
        }
    }
    
    private func handleLongPress(coordinate: CLLocationCoordinate2D?, lead: Lead?) {
        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
        impactFeedback.impactOccurred()

        if let lead = lead {
            guard paywallManager.gateAction() else { return }
            leadToChangeStatus = lead
            activeDialog = .statusChange
        } else if let coordinate = coordinate {
            longPressCoordinate = coordinate
            longPressAddress = nil
            activeDialog = .longPressMenu

            resolveLeadAddress(from: coordinate) { resolution in
                DispatchQueue.main.async {
                    guard longPressCoordinate?.isEqual(to: coordinate, tolerance: 0.000001) == true else { return }
                    longPressAddress = resolution.source == .coordinateFallback ? nil : resolution.address
                    AppLog.debug("Map", "Long press resolved \(resolution.source.debugLabel): \(Utilities.redactedText(resolution.address))")
                }
            }
        }
    }

    private func handleSearchPinTap(_ pin: SearchPin) {
        presentSearchPinActions(for: pin, haptic: true)
    }

    private func presentSearchPinActions(for pin: SearchPin, haptic: Bool) {
        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
        if haptic {
            impactFeedback.impactOccurred()
        }

        // Find leads near this coordinate or matching the address
        let threshold = 0.0005 // ~50 meters
        let nearbyLeads = leads.filter { lead in
            let latDiff = abs(lead.latitude - pin.coordinate.latitude)
            let lonDiff = abs(lead.longitude - pin.coordinate.longitude)
            if latDiff < threshold && lonDiff < threshold { return true }
            // Also match by address text
            if let addr = lead.address?.lowercased(), !addr.isEmpty {
                let pinAddr = pin.title.lowercased()
                if addr.contains(pinAddr) || pinAddr.contains(addr) { return true }
            }
            return false
        }

        matchingLeadsForPin = Array(nearbyLeads)

        guard searchPin == pin else { return }
        showingSearchPinActions = true
    }

    // MARK: - HUD Components

    private var mapControlsGroup: some View {
        VStack(spacing: 10) {
            mapControlButton(icon: "magnifyingglass", color: .textPrimary) {
                isSearching = true
            }
            .accessibilityIdentifier("searchButton")
            mapControlButton(icon: "location.fill", color: .textPrimary) {
                centerOnUserLocationWithAnimation()
            }
            .accessibilityIdentifier("centerOnUserButton")
            mapControlButton(icon: mapStyleIcon, color: .electricViolet) {
                cycleMapType()
            }
            .accessibilityLabel("Change map style")
            .accessibilityValue(mapStyleTitle)
            .accessibilityIdentifier("mapStyleButton")
            mapControlButton(icon: "cube.fill", color: is3DModeEnabled ? .statusInterested : .textPrimary) {
                toggle3DMode()
            }
            .accessibilityLabel(is3DModeEnabled ? "Turn off 3D map" : "Turn on 3D map")
            .accessibilityIdentifier("threeDMapButton")
            mapControlButton(icon: "slider.horizontal.3", color: selectedMapMode == .all ? .electricViolet : selectedMapMode.color) {
                showingMapTools = true
            }
            .accessibilityLabel("Open map tools")
            .accessibilityIdentifier("mapToolsButton")
        }
    }

    private var mapStyleIcon: String {
        MapStyleChoice.choice(for: mapType).icon
    }

    private var mapStyleTitle: String {
        MapStyleChoice.choice(for: mapType).title
    }

    @ViewBuilder
    private var urgentTeamMapShortcut: some View {
        if let summary = teamSurfaceSummary {
            TeamMapShortcutPill(summary: summary) {
                openTeamFieldMap()
            }
        }
    }

    private func openTeamFieldMap() {
        Task {
            await loadTeamWorkspaceUntilAvailable()
            if teamSurfaceSummary != nil {
                showingTeamFieldMap = true
            }
        }
    }

    private func loadTeamWorkspaceIfNeeded() async {
        guard shouldLoadTeamWorkspace else { return }
        guard firebaseService.currentUser != nil else { return }
        await teamService.loadCurrentTeam(
            displayName: userAccountManager.currentUserDisplayName,
            email: userAccountManager.currentUserEmail
        )
    }

    private func loadTeamWorkspaceUntilAvailable() async {
        guard shouldLoadTeamWorkspace else { return }

        for attempt in 0..<8 {
            await loadTeamWorkspaceIfNeeded()

            let hasAuthenticatedIdentity = firebaseService.currentUser != nil
            if hasAuthenticatedIdentity && teamService.activeTeam != nil && teamService.currentMember != nil {
                return
            }

            let delay: UInt64 = attempt < 2 ? 300_000_000 : 800_000_000
            try? await Task.sleep(nanoseconds: delay)
        }
    }

    @ViewBuilder
    private func mapControlButton(icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.obsidianBody)
                .foregroundColor(color)
                .frame(width: 42, height: 42)
                .background(.ultraThinMaterial)
                .clipShape(Circle())
                .shadow(color: .black.opacity(0.15), radius: 6, x: 0, y: 2)
        }
    }

    private var floatingActionBar: some View {
        HStack(spacing: 8) {
            // Quick status buttons
            quickActionButton(icon: "house.slash", label: "Away", color: .statusNotHome) {
                guard paywallManager.gateAction() else { return }
                createQuickLead(status: .notHome)
            }
            quickActionButton(icon: "clock.arrow.circlepath", label: "Later", color: .statusNotHome) {
                guard paywallManager.gateAction() else { return }
                comeBackCoordinate = locationManager.location?.coordinate ?? locationManager.region.center
                showingComeBackPicker = true
            }
            quickActionButton(icon: "hand.raised", label: "Pass", color: .statusNotInterested) {
                guard paywallManager.gateAction() else { return }
                createQuickLead(status: .notInterested)
            }
            quickActionButton(icon: "star", label: "Interest", color: .statusInterested) {
                guard paywallManager.gateAction() else { return }
                interestedFormCoordinate = locationManager.location?.coordinate ?? locationManager.region.center
                showingInterestedForm = true
            }

            // Primary add button — stands out
            Button {
                guard paywallManager.gateAction() else { return }
                prepareCurrentLocationLead()
            } label: {
                ZStack {
                    if isPreparingCurrentLocationLead {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Image(systemName: "plus")
                            .font(.obsidianAction)
                            .foregroundColor(.white)
                    }
                }
                .frame(width: 50, height: 50)
                .background(
                    LinearGradient(
                        colors: [.electricViolet, .electricVioletDeep],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .clipShape(Circle())
                .shadow(color: .electricViolet.opacity(0.3), radius: 8, x: 0, y: 3)
            }
            .disabled(isPreparingCurrentLocationLead)
            .accessibilityLabel("Add lead")
            .accessibilityIdentifier("addLeadButton")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
        .shadow(color: .black.opacity(0.15), radius: 12, x: 0, y: 4)
    }

    @ViewBuilder
    private func quickActionButton(
        icon: String,
        label: String,
        color: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: icon)
                    .font(.obsidianFootnote)
                Text(label)
                    .font(.nano)
                    .lineLimit(1)
            }
            .foregroundColor(color)
            .frame(width: 48, height: 44)
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityLabel(label)
        .accessibilityIdentifier("quickAction_\(label.lowercased())")
    }

    static func currentLocationAddLeadSeed(
        coordinate: CLLocationCoordinate2D,
        resolvedAddress: String?
    ) -> AddLeadLocationSeed {
        AddLeadLocationSeed(coordinate: coordinate, address: resolvedAddress)
    }

    private func presentAddLead(
        coordinate: CLLocationCoordinate2D,
        initialAddress: String?,
        after delay: TimeInterval = 0
    ) {
        let show = {
            addLeadCoordinate = coordinate
            addLeadInitialAddress = initialAddress?.trimmingCharacters(in: .whitespacesAndNewlines)
            addLeadPresentationID = UUID()
            showingAddLead = true
        }

        if delay > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: show)
        } else {
            show()
        }
    }

    private func presentAddLeadFromSelectedPin(
        coordinate: CLLocationCoordinate2D,
        preferredAddress: String?
    ) {
        resolveLeadAddress(from: coordinate, preferredAddress: preferredAddress) { resolution in
            DispatchQueue.main.async {
                AppLog.debug("Map", "Search pin resolved \(resolution.source.debugLabel): \(Utilities.redactedText(resolution.address))")

                presentAddLead(
                    coordinate: resolution.coordinate,
                    initialAddress: resolution.address
                )
            }
        }
    }

    private func resolveQuickActionLeadSeed(
        from coordinate: CLLocationCoordinate2D,
        completion: @escaping (MapQuickActionLeadSeed) -> Void
    ) {
        resolveLeadAddress(from: coordinate) { resolution in
            let seed = MapQuickActionLeadSeedPolicy.seed(
                resolvedCoordinate: resolution.coordinate,
                resolvedAddress: resolution.address,
                source: resolution.source
            )

            DispatchQueue.main.async {
                completion(seed)
            }
        }
    }

    private func normalizedAddress(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func coordinateFallbackAddress(for coordinate: CLLocationCoordinate2D) -> String {
        String(format: "Dropped pin at %.5f, %.5f", coordinate.latitude, coordinate.longitude)
    }

    private func prepareCurrentLocationLead() {
        guard !isPreparingCurrentLocationLead else { return }

        if locationManager.location == nil {
            locationManager.requestImmediateLocation()
        }

        let coordinate = locationManager.location?.coordinate ?? locationManager.region.center
        isPreparingCurrentLocationLead = true
        addLeadCoordinate = coordinate
        addLeadInitialAddress = nil

        if isRunningUITests {
            isPreparingCurrentLocationLead = false
            presentAddLead(
                coordinate: coordinate,
                initialAddress: nil
            )
            return
        }

        locationManager.reverseGeocode(coordinate: coordinate) { address in
            DispatchQueue.main.async {
                let seed = Self.currentLocationAddLeadSeed(
                    coordinate: coordinate,
                    resolvedAddress: address
                )

                addLeadCoordinate = seed.coordinate
                addLeadInitialAddress = seed.address
                isPreparingCurrentLocationLead = false
                presentAddLead(
                    coordinate: seed.coordinate,
                    initialAddress: seed.address
                )
            }
        }
    }

    private var statSummaryPill: some View {
        HStack(spacing: 7) {
            Image(systemName: selectedMapMode == .all ? "chart.bar.fill" : selectedMapMode.icon)
                .font(.obsidianSmall)
                .foregroundColor(selectedMapMode == .all ? .electricViolet : selectedMapMode.color)

            Text(mapSummaryText)
                .font(.obsidianFootnote)
                .foregroundColor(Color.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
        .shadow(color: .black.opacity(0.12), radius: 6, x: 0, y: 2)
        .accessibilityLabel(mapSummaryText)
    }

    private var mapSummaryText: String {
        if selectedMapMode == .all {
            return "\(NumberFormatter.localizedString(from: NSNumber(value: allLeads.count), number: .decimal)) leads"
        }
        return "\(NumberFormatter.localizedString(from: NSNumber(value: visibleMapLeads.count), number: .decimal)) \(selectedMapMode.title.lowercased())"
    }

    private var toastOverlay: some View {
        VStack {
            if showToast {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.obsidianCallout)
                        .foregroundColor(.statusInterested)

                    Text(toastMessage)
                        .font(.obsidianFootnote)
                        .foregroundColor(Color.textPrimary)
                        .lineLimit(1)
                        .accessibilityIdentifier("quickLeadToastMessage")

                    Spacer()

                    Button {
                        undoQuickLead()
                    } label: {
                        Text("Undo")
                            .font(.obsidianFootnote)
                            .fontWeight(.semibold)
                            .foregroundColor(Color.electricViolet)
                            .frame(minWidth: 64, minHeight: 44)
                            .padding(.horizontal, 2)
                    }
                    .buttonStyle(.plain)
                    .background(Color.electricViolet.opacity(0.12))
                    .clipShape(Capsule())
                    .contentShape(Capsule())
                    .accessibilityLabel("Undo quick lead")
                    .accessibilityHint("Deletes the quick lead you just created.")
                    .accessibilityIdentifier("quickLeadUndoButton")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(.ultraThinMaterial)
                .clipShape(Capsule())
                .shadow(color: .black.opacity(0.15), radius: 10, x: 0, y: 3)
                .transition(.move(edge: .top).combined(with: .opacity))
                .padding(.horizontal, 20)
                .padding(.top, 60)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("quickLeadToast")

                Spacer()
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: showToast)
    }

    private func showQuickLeadToast(status: Lead.Status, address: String, lead: Lead) {
        let token = UUID()
        toastToken = token
        toastLead = lead
        toastMessage = "\(status.displayName) — \(address)"
        withAnimation {
            showToast = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 15) {
            guard toastToken == token else { return }
            withAnimation {
                showToast = false
            }
            toastLead = nil
        }
    }

    private func undoQuickLead() {
        if let lead = toastLead {
            let deletionPlan = MapQuickLeadUndoPolicy.deletionPlan(
                leadId: lead.id,
                provider: CloudSyncProvider.current,
                isAuthenticated: FirebaseService.shared.isAuthenticated
            )

            if let localDeletedId = deletionPlan.localDeletedId {
                NotificationService.shared.cancelFollowUpNotification(for: localDeletedId)
            }

            viewContext.delete(lead)
            do {
                try viewContext.save()
                if let localDeletedId = deletionPlan.localDeletedId {
                    UserDataSyncManager.markLeadDeletedLocally(localDeletedId)
                }

                if let cloudLeadId = deletionPlan.cloudLeadId {
                    Task {
                        do {
                            try await UserDataSyncManager.shared.deleteLeadFromCloud(leadId: cloudLeadId)
                        } catch {
                            AppLog.warning("Map", "Quick lead undo removed the local lead, but cloud cleanup will retry later for \(cloudLeadId): \(error.localizedDescription)")
                        }
                    }
                }
            } catch {
                viewContext.rollback()
                ErrorHandler.shared.handle(error, context: "Undo Quick Lead")
            }
        }
        withAnimation {
            showToast = false
        }
        toastToken = UUID()
        toastLead = nil
    }

    private func cycleMapType() {
        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
        impactFeedback.impactOccurred()

        switch MapStyleChoice.choice(for: mapType) {
        case .standard:
            mapType = .satellite
        case .satellite:
            mapType = .hybrid
        case .hybrid:
            mapType = .standard
        }
    }

    private func setMapType(_ type: MKMapType) {
        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
        impactFeedback.impactOccurred()
        mapType = type
    }

    private func toggle3DMode() {
        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
        impactFeedback.impactOccurred()

        is3DModeEnabled.toggle()
        mapPitch = is3DModeEnabled ? max(mapPitch, 45) : 0
    }
    
    private func centerOnUserLocationWithAnimation() {
        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
        impactFeedback.impactOccurred()
        
        guard let userLocation = locationManager.location else {
            // If no location available, request it first
            locationManager.requestImmediateLocation()
            return
        }
        
        let newRegion = MKCoordinateRegion(
            center: userLocation.coordinate,
            span: LocationManager.initialMapCenterSpan(for: userLocation)
        )
        
        // First set the animation trigger to true
        triggerMapAnimation = true
        
        // Then update the region - the AdvancedMapView will animate to it
        locationManager.region = newRegion
    }

    private func centerMapOnLaunchIfPossible() {
        guard LocationManager.isAuthorized(locationManager.authorizationStatus) else { return }

        guard let userLocation = locationManager.location,
              LocationManager.isUsableForInitialMapCenter(userLocation) else {
            if !didRequestLaunchLocationCenter {
                didRequestLaunchLocationCenter = true
                locationManager.resetLocationRequestRetries()
                locationManager.startLaunchLocationCentering()
            }
            return
        }

        guard MapLaunchCenteringPolicy.shouldApplyLaunchCenteringRequest(
            visibleMapCenteredConfirmed: didConfirmVisibleMapCenteredOnLaunch,
            isLaunchCenteringActive: locationManager.shouldUseUserLocation
        ) else { return }

        didRequestLaunchLocationCenter = true
        triggerMapAnimation = false

        if locationManager.hasInitialLocation,
           locationManager.region.center.isEqual(to: userLocation.coordinate, tolerance: 0.0001) {
            return
        }

        locationManager.applyLaunchMapCenter(userLocation)
    }

    private func prepareLaunchMapCentering() {
        if LocationManager.isAuthorized(locationManager.authorizationStatus) {
            let currentLocation = locationManager.location
            let hasUsableLocation = currentLocation.map {
                LocationManager.isUsableForInitialMapCenter($0)
            } ?? false
            let mapIsCenteredOnUser = MapLaunchCenteringPolicy.isMapCenteredOnUser(
                region: locationManager.region,
                location: currentLocation
            )

            guard MapLaunchCenteringPolicy.shouldPrepareOnForeground(
                isAuthorized: true,
                didCenterMapOnLaunch: didConfirmVisibleMapCenteredOnLaunch,
                isLaunchCenteringActive: locationManager.shouldUseUserLocation,
                hasUsableLocation: hasUsableLocation,
                mapIsCenteredOnUser: mapIsCenteredOnUser
            ) else {
                locationManager.startLocationUpdates()
                locationManager.requestImmediateLocation()
                return
            }
        }

        didCenterMapOnLaunch = false
        didRequestLaunchLocationCenter = false
        didConfirmVisibleMapCenteredOnLaunch = false
        launchCenteringResetToken += 1
        setupLocationServices()
        centerMapOnLaunchIfPossible()
    }

    private func refreshLaunchMapCenteringAfterForeground() {
        locationManager.refreshAuthorizationStatusFromSystem(startIfAuthorized: false)

        let currentLocation = locationManager.location
        let hasUsableLocation = currentLocation.map {
            LocationManager.isUsableForInitialMapCenter($0)
        } ?? false
        let mapIsCenteredOnUser = MapLaunchCenteringPolicy.isMapCenteredOnUser(
            region: locationManager.region,
            location: currentLocation
        )

        guard MapLaunchCenteringPolicy.shouldPrepareOnForeground(
            isAuthorized: LocationManager.isAuthorized(locationManager.authorizationStatus),
            didCenterMapOnLaunch: didCenterMapOnLaunch,
            isLaunchCenteringActive: locationManager.shouldUseUserLocation,
            hasUsableLocation: hasUsableLocation,
            mapIsCenteredOnUser: mapIsCenteredOnUser
        ) else {
            locationManager.startLocationUpdates()
            locationManager.requestImmediateLocation()
            return
        }

        prepareLaunchMapCentering()
    }

    private func setMapMode(_ mode: MapWorkflowMode) {
        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
        impactFeedback.impactOccurred()
        selectedMapMode = mode

        if mode == .next {
            focusNextBestLead(openDetail: false)
        }
    }

    private func focusNextBestLead(openDetail: Bool) {
        guard let lead = nextBestLead else {
            toastMessage = "No open leads need attention"
            withAnimation {
                showToast = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                withAnimation {
                    showToast = false
                }
            }
            return
        }
        focusLead(lead, openDetail: openDetail)
    }

    private func focusLead(_ lead: Lead, openDetail: Bool) {
        let newRegion = MKCoordinateRegion(
            center: lead.coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.0045, longitudeDelta: 0.0045)
        )
        triggerMapAnimation = true
        locationManager.region = newRegion

        if openDetail {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                selectedLead = lead
            }
        }
    }

    private func createQuickLead(status: Lead.Status) {
        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
        impactFeedback.impactOccurred()

        let coordinate = locationManager.location?.coordinate ?? locationManager.region.center
        createQuickLeadAt(coordinate: coordinate, status: status)
    }

    private func createQuickLeadAt(coordinate: CLLocationCoordinate2D, status: Lead.Status) {
        // Save any pending changes from other views before creating a new lead
        if viewContext.hasChanges {
            do {
                try viewContext.save()
            } catch {
                viewContext.rollback()
                ErrorHandler.shared.handle(error, context: "Prepare Quick Lead")
                return
            }
        }

        // Quick leads should only use a confident address. Coordinate fallback
        // text is useful for display, but it is not a real lead address.
        resolveLeadAddress(from: coordinate) { resolution in
            DispatchQueue.main.async {
                let seed = MapQuickActionLeadSeedPolicy.seed(
                    resolvedCoordinate: resolution.coordinate,
                    resolvedAddress: resolution.address,
                    source: resolution.source
                )

                guard let addressString = seed.address else {
                    // Show user feedback that address couldn't be resolved
                    let impactFeedback = UIImpactFeedbackGenerator(style: .heavy)
                    impactFeedback.impactOccurred()
                    AppLog.error("Map", "Failed to create quick lead: No address found")
                    return
                }

                // Create the lead at the pressed coordinate with the resolved address.
                let newLead = Lead.create(in: viewContext)
                newLead.applyLeadStatus(status, autoSave: false)
                newLead.latitude = seed.coordinate.latitude
                newLead.longitude = seed.coordinate.longitude
                newLead.name = nil
                newLead.address = addressString

                // Auto-set follow-up for Not Home leads to tomorrow at 9 AM
                if status == .notHome {
                    let calendar = Calendar.current
                    if let tomorrow = calendar.date(byAdding: .day, value: 1, to: Date()),
                       let morning = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow) {
                        newLead.setFollowUpDate(morning, autoSave: false)
                    }
                }

                do {
                    try viewContext.save()
                    AppLog.info("Map", "Quick lead created: \(status.displayName) at \(Utilities.redactedText(addressString))")
                    UserDataSyncManager.shared.syncWithServer()
                    // Schedule notification for Not Home follow-ups
                    if status == .notHome {
                        NotificationService.shared.scheduleFollowUpNotification(for: newLead)
                    }
                    showQuickLeadToast(status: status, address: addressString, lead: newLead)
                } catch {
                    AppLog.error("Map", "Error creating quick lead: \(error.localizedDescription)")
                    ErrorHandler.shared.handle(error, context: "Create Quick Lead")
                }
            }
        }
    }
    
    private func resolveLeadAddress(
        from coordinate: CLLocationCoordinate2D,
        preferredAddress: String? = nil,
        completion: @escaping (MapAddressResolution) -> Void
    ) {
        let preferred = normalizedAddress(preferredAddress)
        let originalLocation = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)

        func finish(with candidate: MapAddressCandidate?) {
            if let candidate, candidate.isConfident {
                completion(
                    MapAddressResolution(
                        coordinate: MapAddressResolutionPolicy.resolvedCoordinate(
                            pressedCoordinate: coordinate,
                            candidateCoordinate: candidate.coordinate,
                            source: candidate.source
                        ),
                        address: candidate.address,
                        source: candidate.source
                    )
                )
                return
            }

            if let preferred {
                completion(
                    MapAddressResolution(
                        coordinate: coordinate,
                        address: preferred,
                        source: .preferredAddress
                    )
                )
                return
            }

            completion(
                MapAddressResolution(
                    coordinate: coordinate,
                    address: Self.coordinateFallbackAddress(for: coordinate),
                    source: .coordinateFallback
                )
            )
        }

        findMapSearchAddressCandidate(from: coordinate, originalLocation: originalLocation) { mapSearchCandidate in
            if let mapSearchCandidate, mapSearchCandidate.isConfident {
                finish(with: mapSearchCandidate)
                return
            }

            reverseGeocodeExactAddress(from: coordinate, originalLocation: originalLocation) { exactCandidate in
                if let exactCandidate, exactCandidate.isConfident {
                    finish(with: exactCandidate)
                    return
                }

                finish(with: mapSearchCandidate ?? exactCandidate)
            }
        }
    }

    private func findMapSearchAddressCandidate(
        from coordinate: CLLocationCoordinate2D,
        originalLocation: CLLocation,
        completion: @escaping (MapAddressCandidate?) -> Void
    ) {
        let coordinateQuery = String(format: "%.6f, %.6f", coordinate.latitude, coordinate.longitude)
        let queries = [coordinateQuery, "address"]
        var bestCandidate: MapAddressCandidate?

        func runSearch(at index: Int) {
            guard index < queries.count else {
                completion(bestCandidate)
                return
            }

            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = queries[index]
            request.region = MKCoordinateRegion(
                center: coordinate,
                latitudinalMeters: 90,
                longitudinalMeters: 90
            )
            request.resultTypes = [.address]

            MKLocalSearch(request: request).start { response, _ in
                let candidates = (response?.mapItems ?? []).compactMap {
                    Self.mapAddressCandidate(
                        from: $0.placemark,
                        originalLocation: originalLocation,
                        source: .mapSearchAddress,
                        confidenceRadius: 35
                    )
                }

                if let strongest = candidates.max(by: { $0.score < $1.score }),
                   strongest.score > (bestCandidate?.score ?? .leastNormalMagnitude) {
                    bestCandidate = strongest
                }

                if bestCandidate?.isConfident == true {
                    completion(bestCandidate)
                } else {
                    runSearch(at: index + 1)
                }
            }
        }

        runSearch(at: 0)
    }

    private func reverseGeocodeExactAddress(
        from coordinate: CLLocationCoordinate2D,
        originalLocation: CLLocation,
        completion: @escaping (MapAddressCandidate?) -> Void
    ) {
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)

        CLGeocoder().reverseGeocodeLocation(location, preferredLocale: Locale.current) { placemarks, _ in
            let candidates = (placemarks ?? []).compactMap {
                Self.mapAddressCandidate(
                    from: $0,
                    originalLocation: originalLocation,
                    source: .streetAddress,
                    confidenceRadius: 25
                )
            }
            completion(candidates.max(by: { $0.score < $1.score }))
        }
    }

    private static func mapAddressCandidate(
        from placemark: CLPlacemark,
        originalLocation: CLLocation,
        source: MapAddressSource,
        confidenceRadius: CLLocationDistance
    ) -> MapAddressCandidate? {
        let streetNumber = placemark.subThoroughfare?.trimmingCharacters(in: .whitespacesAndNewlines)
        let streetName = placemark.thoroughfare?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let streetName, !streetName.isEmpty else { return nil }

        var addressComponents: [String] = []
        let hasStreetNumber = streetNumber?.isEmpty == false
        if let streetNumber, !streetNumber.isEmpty {
            addressComponents.append("\(streetNumber) \(streetName)")
        } else {
            addressComponents.append(streetName)
        }

        if let city = placemark.locality, !city.isEmpty {
            addressComponents.append(city)
        }
        if let state = placemark.administrativeArea, !state.isEmpty {
            addressComponents.append(state)
        }
        if let postalCode = placemark.postalCode, !postalCode.isEmpty {
            addressComponents.append(postalCode)
        }

        let coordinate = placemark.location?.coordinate ?? originalLocation.coordinate
        let placemarkLocation = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let distanceFromPress = originalLocation.distance(from: placemarkLocation)

        var score: Double = 0
        score += source == .mapSearchAddress ? 160 : 0
        score += hasStreetNumber ? 1_000 : 120
        score += placemark.postalCode?.isEmpty == false ? 160 : 0
        score += placemark.locality?.isEmpty == false ? 80 : 0
        score -= min(distanceFromPress, 100) * 4

	        return MapAddressCandidate(
	            address: addressComponents.joined(separator: ", "),
	            coordinate: coordinate,
	            hasStreetNumber: hasStreetNumber,
	            distanceFromPress: distanceFromPress,
	            score: score,
	            source: source,
	            confidenceRadius: confidenceRadius
	        )
	    }

    private func updateLeadStatusFromMap(_ lead: Lead, status: Lead.Status) {
        lead.applyLeadStatus(status, autoSave: false)

	        do {
	            try viewContext.save()
	            UserDataSyncManager.shared.syncWithServer()
	        } catch {
	            viewContext.rollback()
	            ErrorHandler.shared.handle(error, context: "Update Map Lead Status")
	        }
	    }

	}

// MARK: - Interested Quick Form

struct InterestedQuickForm: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.managedObjectContext) private var viewContext

    let coordinate: CLLocationCoordinate2D
    let resolveLeadSeed: (CLLocationCoordinate2D, @escaping (MapQuickActionLeadSeed) -> Void) -> Void
    let onDismiss: () -> Void

    @State private var name = ""
    @State private var phone = ""
    @State private var note = ""
    @State private var address = ""
    @State private var resolvedCoordinate: CLLocationCoordinate2D
    @State private var isSaving = false
    @State private var showingMessageConfirmation = false
    @State private var createdLead: Lead?

    init(
        coordinate: CLLocationCoordinate2D,
        resolveLeadSeed: @escaping (CLLocationCoordinate2D, @escaping (MapQuickActionLeadSeed) -> Void) -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.coordinate = coordinate
        self.resolveLeadSeed = resolveLeadSeed
        self.onDismiss = onDismiss
        _resolvedCoordinate = State(initialValue: coordinate)
    }

    private var usableAddress: String? {
        MapQuickActionLeadPolicy.usableAddress(address)
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView(showsIndicators: false) {
                VStack(spacing: 14) {
                    locationCard
                    customerSection
                    noteSection
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
            }

            saveButton
                .padding(.horizontal, 20)
                .padding(.top, 10)
                .padding(.bottom, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.obsidianBackground(for: colorScheme))
        .presentationBackground(Color.obsidianBackground(for: colorScheme))
        .sheet(isPresented: $showingMessageConfirmation) {
            if let lead = createdLead {
                FirstMessageConfirmationView(lead: lead) {
                    onDismiss()
                }
            }
        }
        .onAppear {
            resolveLocation()
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            ObsidianIconTile(icon: "star.fill", tint: Color.statusInterested, size: 42)

            VStack(alignment: .leading, spacing: 3) {
                Text("Interested Lead")
                    .font(.obsidianTitle)
                    .foregroundColor(Color.textPrimary)
                    .lineLimit(1)
                    .accessibilityIdentifier("interestedQuickFormSheet")

                Text("Capture the customer while the conversation is fresh.")
                    .font(.obsidianFootnote)
                    .foregroundColor(Color.textSecondary)
                    .lineLimit(2)
            }

            Spacer()

            ObsidianCompactIconButton(
                icon: "xmark",
                accessibilityLabel: "Close interested lead form",
                accentColor: Color.textSecondary
            ) {
                onDismiss()
            }
            .accessibilityIdentifier("interestedQuickFormCloseButton")
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 14)
    }

    private var locationCard: some View {
        HStack(spacing: 12) {
            ObsidianIconTile(icon: "mappin.circle.fill", tint: Color.electricViolet, size: 38)

            VStack(alignment: .leading, spacing: 3) {
                Text("Lead location")
                    .font(.obsidianCaption)
                    .foregroundColor(Color.textSecondary)

                Text(usableAddress ?? "Finding nearest address...")
                    .font(.obsidianCallout)
                    .foregroundColor(Color.textPrimary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.82)
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .background(Color.obsidianElevated)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.obsidianBorder.opacity(0.7), lineWidth: 0.7)
        )
    }

    private var customerSection: some View {
        quickCaptureSection(title: "Customer", icon: "person.crop.circle") {
            inputRow(
                title: "Name",
                icon: "person.fill",
                placeholder: "Customer name",
                text: $name
            )

            inputRow(
                title: "Phone",
                icon: "phone.fill",
                placeholder: "Phone number",
                text: $phone,
                keyboard: .phonePad
            )
            .onChange(of: phone) { _, newValue in
                phone = Utilities.formatPhoneNumber(newValue)
            }
        }
    }

    private var noteSection: some View {
        quickCaptureSection(title: "Conversation", icon: "text.bubble.fill") {
            inputRow(
                title: "Note",
                icon: "note.text",
                placeholder: "What did they ask for?",
                text: $note
            )
        }
    }

    private var saveButton: some View {
        Button(action: saveInterestedLead) {
            HStack {
                if isSaving {
                    ProgressView()
                        .tint(.white)
                } else {
                    Image(systemName: "checkmark.circle.fill")
                    Text("Save Interested Lead")
                        .fontWeight(.semibold)
                }
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                LinearGradient(
                    colors: [Color.electricViolet, Color.electricVioletDeep],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(color: Color.electricViolet.opacity(0.25), radius: 10, x: 0, y: 4)
            .accessibilityIdentifier("saveInterestedLeadButton")
        }
        .disabled(isSaving || usableAddress == nil)
        .opacity(usableAddress == nil ? 0.55 : 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Save Interested Lead")
        .accessibilityHint(usableAddress == nil ? "Wait for the address to finish loading before saving." : "Saves this interested lead.")
        .accessibilityIdentifier("saveInterestedLeadButton")
    }

    @ViewBuilder
    private func quickCaptureSection<Content: View>(
        title: String,
        icon: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.obsidianCallout)
                    .foregroundColor(Color.textPrimary)
                    .frame(width: 28, height: 28)

                Text(title)
                    .font(.obsidianHeadline)
                    .foregroundColor(Color.textPrimary)

                Spacer()
            }

            VStack(spacing: 10) {
                content()
            }
        }
        .padding(16)
        .background(Color.obsidianSurface)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.obsidianBorder.opacity(0.7), lineWidth: 0.7)
        )
    }

    private func inputRow(
        title: String,
        icon: String,
        placeholder: String,
        text: Binding<String>,
        keyboard: UIKeyboardType = .default
    ) -> some View {
        HStack(spacing: 12) {
            ObsidianIconTile(icon: icon, tint: Color.electricViolet, size: 34)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.obsidianCaption)
                    .foregroundColor(Color.textSecondary)

                TextField(placeholder, text: text)
                    .font(.obsidianCallout)
                    .foregroundColor(Color.textPrimary)
                    .keyboardType(keyboard)
                    .textInputAutocapitalization(title == "Name" ? .words : .sentences)
                    .accessibilityIdentifier("interestedQuickForm\(title.replacingOccurrences(of: " ", with: ""))Field")
            }
        }
        .padding(12)
        .background(Color.obsidianElevated)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.obsidianBorder.opacity(0.55), lineWidth: 0.7)
        )
    }

    private func resolveLocation() {
        resolveLeadSeed(coordinate) { seed in
            resolvedCoordinate = seed.coordinate
            address = seed.address ?? ""
        }
    }

    private func saveInterestedLead() {
        guard let effectiveAddress = usableAddress else { return }

        isSaving = true

        // Save pending changes first
        if viewContext.hasChanges {
            do {
                try viewContext.save()
            } catch {
                isSaving = false
                viewContext.rollback()
                ErrorHandler.shared.handle(error, context: "Prepare Interested Lead")
                return
            }
        }

        let newLead = Lead.create(in: viewContext)
        newLead.applyLeadStatus(.interested, autoSave: false)
        newLead.latitude = resolvedCoordinate.latitude
        newLead.longitude = resolvedCoordinate.longitude
        newLead.name = name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : name.trimmingCharacters(in: .whitespacesAndNewlines)
        newLead.phone = phone.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : phone.trimmingCharacters(in: .whitespacesAndNewlines)
        newLead.notes = note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : note.trimmingCharacters(in: .whitespacesAndNewlines)
        newLead.address = effectiveAddress

        do {
            try viewContext.save()
            UserDataSyncManager.shared.syncWithServer()
            isSaving = false

            // Show message confirmation if phone was provided
            if !phone.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                createdLead = newLead
                showingMessageConfirmation = true
            } else {
                onDismiss()
            }
        } catch {
            isSaving = false
            AppLog.error("Map", "Error saving interested lead: \(error.localizedDescription)")
            ErrorHandler.shared.handle(error, context: "Save Interested Lead")
        }
    }

}

// MARK: - Map Search Completer

class MapSearchCompleter: NSObject, ObservableObject, MKLocalSearchCompleterDelegate {
    @Published var results: [MKLocalSearchCompletion] = []
    private let completer = MKLocalSearchCompleter()

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest]
    }

    func search(query: String) {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else {
            results = []
            return
        }
        completer.queryFragment = query
    }

    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        DispatchQueue.main.async {
            self.results = completer.results
        }
    }

    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        AppLog.warning("Map", "Search completer error: \(error.localizedDescription)")
    }
}

// MARK: - Map Search Sheet

struct SearchPin: Equatable {
    let coordinate: CLLocationCoordinate2D
    let title: String

    static func == (lhs: SearchPin, rhs: SearchPin) -> Bool {
        lhs.title == rhs.title &&
        lhs.coordinate.latitude == rhs.coordinate.latitude &&
        lhs.coordinate.longitude == rhs.coordinate.longitude
    }
}

struct MapSearchSheet: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @StateObject private var completer = MapSearchCompleter()
    @State private var searchText = ""
    @FocusState private var isSearchFocused: Bool
    let onSelect: (CLLocationCoordinate2D, String) -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Search Address")
                    .font(.obsidianSubheadline)
                    .foregroundColor(.textPrimary)
                    .accessibilityIdentifier("mapSearchSheet")
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.obsidianCaption)
                        .foregroundColor(.textSecondary)
                        .frame(width: 30, height: 30)
                        .background(Color.obsidianElevated)
                        .clipShape(Circle())
                }
                .accessibilityLabel("Close search")
                .accessibilityIdentifier("mapSearchCloseButton")
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 12)

            // Search field
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.textMuted)
                    .font(.obsidianBody)
                TextField("Type an address...", text: $searchText)
                    .font(.obsidianCallout)
                    .foregroundColor(.textPrimary)
                    .focused($isSearchFocused)
                    .accessibilityIdentifier("mapSearchField")
                    .onChange(of: searchText) { _, newValue in
                        completer.search(query: newValue)
                    }
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                        completer.results = []
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.textMuted)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color.obsidianSurface)
            .cornerRadius(14)
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(isSearchFocused ? Color.electricViolet.opacity(0.5) : Color.obsidianBorder, lineWidth: 1)
            )
            .padding(.horizontal, 20)

            // Results
            if completer.results.isEmpty && !searchText.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "mappin.slash")
                        .font(.displayLarge)
                        .foregroundColor(.textMuted)
                    Text("No results found")
                        .font(.obsidianBody)
                        .foregroundColor(.textSecondary)
                    Spacer()
                }
            } else if completer.results.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "map")
                        .font(.displayLarge)
                        .foregroundColor(.textMuted)
                    Text("Search for a street address, city, or place")
                        .font(.obsidianFootnote)
                        .foregroundColor(.textMuted)
                    Spacer()
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(completer.results.prefix(8).enumerated()), id: \.offset) { index, result in
                            Button { resolveAndSelect(result) } label: {
                                HStack(spacing: 14) {
                                    ZStack {
                                        Circle()
                                            .fill(Color.electricViolet.opacity(0.12))
                                            .frame(width: 38, height: 38)
                                        Image(systemName: "mappin")
                                            .font(.obsidianFootnote)
                                            .foregroundColor(.electricViolet)
                                    }
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(result.title)
                                            .font(.obsidianBody)
                                            .foregroundColor(.textPrimary)
                                            .lineLimit(1)
                                        if !result.subtitle.isEmpty {
                                            Text(result.subtitle)
                                                .font(.obsidianCaption)
                                                .foregroundColor(.textMuted)
                                                .lineLimit(1)
                                        }
                                    }
                                    Spacer()
                                    Image(systemName: "arrow.up.left")
                                        .font(.obsidianSmall)
                                        .foregroundColor(.textMuted)
                                }
                                .padding(.horizontal, 20)
                                .padding(.vertical, 12)
                            }
                            .accessibilityIdentifier("mapSearchResult_\(index)")
                            if index < min(completer.results.count, 8) - 1 {
                                Divider()
                                    .padding(.leading, 72)
                            }
                        }
                    }
                    .padding(.top, 8)
                }
            }
        }
        .background(Color.obsidianBackground(for: colorScheme))
        .presentationBackground(Color.obsidianBackground(for: colorScheme))
        .onAppear { isSearchFocused = true }
    }

    private func resolveAndSelect(_ result: MKLocalSearchCompletion) {
        let request = MKLocalSearch.Request(completion: result)
        let search = MKLocalSearch(request: request)
        search.start { response, _ in
            guard let item = response?.mapItems.first else { return }
            let title = [result.title, result.subtitle].filter { !$0.isEmpty }.joined(separator: ", ")
            dismiss()
            onSelect(item.placemark.coordinate, title)
        }
    }
}

// MARK: - Long Press Menu Sheet

// MARK: - Come Back Later Sheet

struct ComeBackLaterSheet: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.managedObjectContext) private var viewContext
    let coordinate: CLLocationCoordinate2D
    let resolveLeadSeed: (CLLocationCoordinate2D, @escaping (MapQuickActionLeadSeed) -> Void) -> Void
    let onDone: () -> Void
    @State private var selectedTime = Calendar.current.date(byAdding: .hour, value: 2, to: Date()) ?? Date()
    @State private var address = ""
    @State private var resolvedCoordinate: CLLocationCoordinate2D

    init(
        coordinate: CLLocationCoordinate2D,
        resolveLeadSeed: @escaping (CLLocationCoordinate2D, @escaping (MapQuickActionLeadSeed) -> Void) -> Void,
        onDone: @escaping () -> Void
    ) {
        self.coordinate = coordinate
        self.resolveLeadSeed = resolveLeadSeed
        self.onDone = onDone
        _resolvedCoordinate = State(initialValue: coordinate)
    }

    private var usableAddress: String? {
        MapQuickActionLeadPolicy.usableAddress(address)
    }

    private let quickTimes: [(title: String, subtitle: String, hours: Int, icon: String)] = [
        ("1 Hour", "Soon", 1, "clock.fill"),
        ("2 Hours", "Same day", 2, "clock.badge.checkmark.fill"),
        ("4 Hours", "Later today", 4, "sun.max.fill"),
        ("Tomorrow", "9:00 AM", 24, "calendar.badge.clock")
    ]

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView(showsIndicators: false) {
                VStack(spacing: 14) {
                    locationCard
                    quickTimeSection
                    customTimeSection
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
        }
        .background(Color.obsidianBackground(for: colorScheme))
        .presentationBackground(Color.obsidianBackground(for: colorScheme))
        .onAppear {
            resolveLocation()
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            ObsidianIconTile(icon: "clock.arrow.circlepath", tint: Color.statusNotHome, size: 42)

            VStack(alignment: .leading, spacing: 3) {
                Text("Come Back Later")
                    .font(.obsidianTitle)
                    .foregroundColor(Color.textPrimary)
                    .lineLimit(1)
                    .accessibilityIdentifier("comeBackLaterSheet")

                Text("Create a follow-up lead at this location.")
                    .font(.obsidianFootnote)
                    .foregroundColor(Color.textSecondary)
                    .lineLimit(2)
            }

            Spacer()

            ObsidianCompactIconButton(
                icon: "xmark",
                accessibilityLabel: "Close come back later",
                accentColor: Color.textSecondary
            ) {
                onDone()
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 14)
    }

    private var locationCard: some View {
        HStack(spacing: 12) {
            ObsidianIconTile(icon: "mappin.circle.fill", tint: Color.electricViolet, size: 38)

            VStack(alignment: .leading, spacing: 3) {
                Text("Location")
                    .font(.obsidianCaption)
                    .foregroundColor(Color.textSecondary)

                Text(usableAddress ?? "Finding nearest address...")
                    .font(.obsidianCallout)
                    .foregroundColor(Color.textPrimary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.82)
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .background(Color.obsidianElevated)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.obsidianBorder.opacity(0.7), lineWidth: 0.7)
        )
    }

    private var quickTimeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "bolt.fill")
                    .font(.obsidianCallout)
                    .foregroundColor(Color.statusNotHome)
                    .frame(width: 28, height: 28)

                Text("Quick follow-up")
                    .font(.obsidianHeadline)
                    .foregroundColor(Color.textPrimary)

                Spacer()
            }

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 10),
                    GridItem(.flexible(), spacing: 10)
                ],
                spacing: 10
            ) {
                ForEach(quickTimes, id: \.hours) { option in
                    quickTimeButton(option)
                }
            }
        }
        .padding(16)
        .background(Color.obsidianSurface)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.obsidianBorder.opacity(0.7), lineWidth: 0.7)
        )
    }

    private var customTimeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "calendar")
                    .font(.obsidianCallout)
                    .foregroundColor(Color.electricViolet)
                    .frame(width: 28, height: 28)

                Text("Pick exact time")
                    .font(.obsidianHeadline)
                    .foregroundColor(Color.textPrimary)

                Spacer()
            }

            HStack(spacing: 12) {
                ObsidianIconTile(icon: "clock.fill", tint: Color.electricViolet, size: 34)

                DatePicker(
                    "Come back at",
                    selection: $selectedTime,
                    in: Date()...,
                    displayedComponents: [.date, .hourAndMinute]
                )
                .font(.obsidianCallout)
                .foregroundColor(Color.textPrimary)
                .labelsHidden()
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(12)
            .background(Color.obsidianElevated)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.obsidianBorder.opacity(0.55), lineWidth: 0.7)
            )

            Button {
                createComeBackLead(followUpDate: selectedTime)
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill")
                    Text("Save Follow-Up")
                        .fontWeight(.semibold)
                }
                .font(.obsidianCallout)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(
                    LinearGradient(
                        colors: [Color.electricViolet, Color.electricVioletDeep],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(usableAddress == nil)
            .opacity(usableAddress == nil ? 0.55 : 1)
            .accessibilityIdentifier("saveCustomComeBackLeadButton")
        }
        .padding(16)
        .background(Color.obsidianSurface)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.obsidianBorder.opacity(0.7), lineWidth: 0.7)
        )
    }

    private func quickTimeButton(_ option: (title: String, subtitle: String, hours: Int, icon: String)) -> some View {
        Button {
            createComeBackLead(hoursFromNow: option.hours)
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    ObsidianIconTile(icon: option.icon, tint: Color.statusNotHome, size: 34)
                    Spacer()
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(option.title)
                        .font(.obsidianCallout)
                        .foregroundColor(Color.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)

                    Text(option.subtitle)
                        .font(.obsidianCaption)
                        .foregroundColor(Color.textSecondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 94, alignment: .leading)
            .padding(12)
            .background(Color.obsidianElevated)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.obsidianBorder.opacity(0.55), lineWidth: 0.7)
            )
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(usableAddress == nil)
        .opacity(usableAddress == nil ? 0.55 : 1)
        .accessibilityIdentifier("comeBackQuickTime_\(option.hours)")
    }

    private func createComeBackLead(hoursFromNow: Int) {
        let calendar = Calendar.current
        let followUpDate: Date
        if hoursFromNow >= 24 {
            // Tomorrow at 9 AM
            if let tomorrow = calendar.date(byAdding: .day, value: 1, to: Date()),
               let morning = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow) {
                followUpDate = morning
            } else { return }
        } else {
            guard let date = calendar.date(byAdding: .hour, value: hoursFromNow, to: Date()) else { return }
            followUpDate = date
        }

        createComeBackLead(followUpDate: followUpDate)
    }

    private func createComeBackLead(followUpDate: Date) {
        guard let effectiveAddress = usableAddress else { return }

        let newLead = Lead.create(in: viewContext)
        newLead.applyLeadStatus(.notHome, followUpDate: followUpDate, shouldReplaceFollowUpDate: true, autoSave: false)
        newLead.latitude = resolvedCoordinate.latitude
        newLead.longitude = resolvedCoordinate.longitude
        newLead.address = effectiveAddress
        newLead.name = nil

        do {
            try viewContext.save()
            UserDataSyncManager.shared.syncWithServer()
            NotificationService.shared.scheduleFollowUpNotification(for: newLead)
            let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
            impactFeedback.impactOccurred()
        } catch {
            AppLog.error("Map", "Error creating come-back lead: \(error.localizedDescription)")
        }
        onDone()
    }

    private func resolveLocation() {
        resolveLeadSeed(coordinate) { seed in
            resolvedCoordinate = seed.coordinate
            address = seed.address ?? ""
        }
    }
}

struct LongPressMenuSheet: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    let coordinate: CLLocationCoordinate2D?
    @Binding var address: String?
    let onAddLead: (String) -> Void
    let onStreetView: () -> Void
    let onNavigate: () -> Void
    let onCancel: () -> Void
    @State private var confirmedAddress = ""
    @State private var didEditConfirmedAddress = false
    @State private var isApplyingResolvedAddress = false

    private var trimmedConfirmedAddress: String {
        confirmedAddress.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canAddLead: Bool {
        !trimmedConfirmedAddress.isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView(showsIndicators: false) {
                VStack(spacing: 14) {
                    selectedLocationCard
                    actionSection
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
        }
        .background(Color.obsidianBackground(for: colorScheme))
        .presentationBackground(Color.obsidianBackground(for: colorScheme))
        .presentationDragIndicator(.visible)
        .onAppear {
            if confirmedAddress.isEmpty {
                applyResolvedAddress(address)
            }
        }
        .onChange(of: address) { _, newValue in
            guard !didEditConfirmedAddress else { return }
            applyResolvedAddress(newValue)
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            ObsidianIconTile(icon: "mappin.and.ellipse", tint: Color.electricViolet, size: 42)

            VStack(alignment: .leading, spacing: 3) {
                Text("Dropped Pin")
                    .font(.obsidianTitle)
                    .foregroundColor(Color.textPrimary)
                    .accessibilityIdentifier("longPressMenuSheet")

                Text(address == nil ? "Finding the nearest address..." : "Using the closest address to this pin.")
                    .font(.obsidianFootnote)
                    .foregroundColor(Color.textSecondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)

            ObsidianCompactIconButton(
                icon: "xmark",
                accessibilityLabel: "Close pin actions",
                accentColor: Color.textSecondary
            ) {
                dismiss()
                onCancel()
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 14)
    }

    private var selectedLocationCard: some View {
        ObsidianSectionCard(
            title: "Selected Location",
            icon: "mappin.circle.fill",
            subtitle: coordinateText,
            accentColor: Color.statusConverted
        ) {
            HStack(alignment: .top, spacing: 12) {
                ObsidianIconTile(
                    icon: address == nil ? "arrow.triangle.2.circlepath" : "checkmark.seal.fill",
                    tint: address == nil ? Color.statusNotHome : Color.statusInterested,
                    size: 36
                )

                VStack(alignment: .leading, spacing: 3) {
                    if let address = address {
                        Text(address)
                            .font(.obsidianCallout)
                            .foregroundColor(Color.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                            .contextMenu {
                                Button {
                                    copyAddress(address)
                                } label: {
                                    Label("Copy Address", systemImage: "doc.on.doc")
                                }
                            }
                            .accessibilityHint("Long press to copy address")
                    } else {
                        Text("Finding nearest address...")
                            .font(.obsidianCallout)
                            .foregroundColor(Color.textSecondary)

                        Text("Lead creation unlocks when a real address is found.")
                            .font(.micro)
                            .foregroundColor(Color.textMuted)
                    }

                    if let coordinate {
                        Text(String(format: "%.5f, %.5f", coordinate.latitude, coordinate.longitude))
                            .font(.micro)
                            .foregroundColor(Color.textMuted)
                            .padding(.top, 2)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(12)
            .background(Color.obsidianElevated)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.obsidianBorder.opacity(0.45), lineWidth: 0.5)
            )

            VStack(alignment: .leading, spacing: 7) {
                Label("Lead address", systemImage: "house.fill")
                    .font(.obsidianFootnote)
                    .foregroundColor(Color.textSecondary)

                TextField("Nearest address", text: $confirmedAddress)
                    .font(.obsidianCallout)
                    .foregroundColor(Color.textPrimary)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled(false)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(Color.obsidianElevated)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(
                                trimmedConfirmedAddress.isEmpty ? Color.statusNotHome.opacity(0.65) : Color.obsidianBorder.opacity(0.45),
                                lineWidth: 0.7
                            )
                    )
                    .onChange(of: confirmedAddress) { _, _ in
                        guard !isApplyingResolvedAddress else { return }
                        didEditConfirmedAddress = true
                    }
                    .accessibilityIdentifier("longPressConfirmedAddressField")

                Text("The closest resolved address is used automatically. Edit it only if the map result is wrong.")
                    .font(.micro)
                    .foregroundColor(Color.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var actionSection: some View {
        ObsidianSectionCard(
            title: "Actions",
            icon: "bolt.fill",
            subtitle: "Use this pin for your next field step."
        ) {
            VStack(spacing: 10) {
                pinActionButton(
                    title: "Add Lead Here",
                    subtitle: canAddLead ? "Open lead creation with this address" : "Waiting for nearest address",
                    icon: "plus.circle.fill",
                    tint: Color.electricViolet,
                    isDisabled: !canAddLead,
                    accessibilityIdentifier: "longPressAddLeadButton"
                ) {
                    guard canAddLead else { return }
                    dismiss()
                    onAddLead(trimmedConfirmedAddress)
                }

                pinActionButton(
                    title: "Street View",
                    subtitle: "Preview the house or street before you walk up",
                    icon: "binoculars.fill",
                    tint: Color.statusInterested,
                    accessibilityIdentifier: "longPressStreetViewButton"
                ) {
                    dismiss()
                    onStreetView()
                }

                pinActionButton(
                    title: "Navigate",
                    subtitle: "Open driving directions in Maps",
                    icon: "location.north.line.fill",
                    tint: Color.statusNotHome,
                    accessibilityIdentifier: "longPressNavigateButton"
                ) {
                    dismiss()
                    onNavigate()
                }
            }
        }
    }

    private func copyAddress(_ address: String) {
        UIPasteboard.general.string = address
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        UIAccessibility.post(notification: .announcement, argument: "Address copied")
    }

    private var coordinateText: String? {
        guard let coordinate else { return nil }
        return String(format: "Pin %.5f, %.5f", coordinate.latitude, coordinate.longitude)
    }

    private func applyResolvedAddress(_ value: String?) {
        let cleaned = Self.cleanSuggestedAddress(value) ?? ""
        isApplyingResolvedAddress = true
        confirmedAddress = cleaned
        DispatchQueue.main.async {
            isApplyingResolvedAddress = false
        }
    }

    private static func cleanSuggestedAddress(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else { return nil }
        guard !trimmed.localizedCaseInsensitiveContains("Dropped pin at") else { return nil }
        return trimmed
    }

    private func pinActionButton(
        title: String,
        subtitle: String,
        icon: String,
        tint: Color,
        isDisabled: Bool = false,
        accessibilityIdentifier: String? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ObsidianIconTile(icon: icon, tint: isDisabled ? Color.textMuted : tint, size: 40)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.obsidianCallout)
                        .foregroundColor(isDisabled ? Color.textMuted : Color.textPrimary)

                    Text(subtitle)
                        .font(.obsidianFootnote)
                        .foregroundColor(Color.textSecondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.micro)
                    .foregroundColor(Color.textMuted)
            }
            .padding(12)
            .background(Color.obsidianElevated)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.obsidianBorder.opacity(0.45), lineWidth: 0.5)
            )
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.55 : 1)
        .accessibilityIdentifier(accessibilityIdentifier ?? title)
    }
}

// MARK: - Search Pin Actions Sheet

struct SearchPinActionsSheet: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    let pin: SearchPin
    let matchingLeads: [Lead]
    let onViewLead: (Lead) -> Void
    let onAddLead: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Search Result")
                    .font(.obsidianSubheadline)
                    .foregroundColor(.textPrimary)
                    .accessibilityIdentifier("searchPinActionsTitle")
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.obsidianCaption)
                        .foregroundColor(.textSecondary)
                        .frame(width: 30, height: 30)
                        .background(Color.obsidianElevated)
                        .clipShape(Circle())
                }
                .accessibilityLabel("Close pin actions")
                .accessibilityIdentifier("searchPinActionsCloseButton")
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 16)

            // Address card
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(Color.statusConverted.opacity(0.12))
                        .frame(width: 42, height: 42)
                    Image(systemName: "mappin.circle.fill")
                        .font(.obsidianSubheadline)
                        .foregroundColor(.statusConverted)
                }
                Text(pin.title)
                    .font(.obsidianFootnote)
                    .foregroundColor(.textPrimary)
                    .lineLimit(2)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(Color.obsidianSurface)
            .cornerRadius(14)
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.obsidianBorder, lineWidth: 0.5)
            )
            .padding(.horizontal, 20)

            // Matching leads section
            if !matchingLeads.isEmpty {
                HStack {
                    Text("LEADS AT THIS ADDRESS")
                        .font(.micro)
                        .foregroundColor(.textMuted)
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 8)

                VStack(spacing: 0) {
                    ForEach(matchingLeads, id: \.id) { lead in
                        Button { onViewLead(lead) } label: {
                            HStack(spacing: 12) {
                                Circle()
                                    .fill(lead.leadStatus.swiftUIColor)
                                    .frame(width: 10, height: 10)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(lead.displayName)
                                        .font(.obsidianBody)
                                        .foregroundColor(.textPrimary)
                                    Text(lead.leadStatus.displayName)
                                        .font(.obsidianSmall)
                                        .foregroundColor(.textSecondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.obsidianSmall)
                                    .foregroundColor(.textMuted)
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 12)
                        }
                        if lead.id != matchingLeads.last?.id {
                            Divider().padding(.leading, 42)
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
            } else {
                HStack(spacing: 10) {
                    Image(systemName: "person.slash")
                        .foregroundColor(.textMuted)
                    Text("No leads found at this address")
                        .font(.obsidianFootnote)
                        .foregroundColor(.textSecondary)
                }
                .padding(.top, 20)
            }

            Spacer()

            // Add lead button
            Button { onAddLead() } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus")
                        .font(.obsidianFootnote)
                    Text("Add New Lead Here")
                        .font(.obsidianCallout)
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    LinearGradient(
                        colors: [.electricViolet, .electricVioletDeep],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .cornerRadius(14)
                .shadow(color: .electricViolet.opacity(0.3), radius: 8, x: 0, y: 3)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
            .accessibilityIdentifier("searchPinAddLeadButton")
        }
        .background(Color.obsidianBackground(for: colorScheme))
        .presentationBackground(Color.obsidianBackground(for: colorScheme))
    }
}

struct LeadClusterSelection: Identifiable {
    let id = UUID()
    let leads: [Lead]
    let coordinate: CLLocationCoordinate2D

    var summary: LeadClusterSummary {
        LeadClusterSummary(leads: leads)
    }

    var sortedLeads: [Lead] {
        summary.sortedLeads
    }
}

enum LeadMapWorkflowPolicy {
    static func isHotLead(_ lead: Lead, now: Date = Date()) -> Bool {
        guard lead.leadStatus.allowsActiveFollowUp else { return false }
        return lead.priority > 0
            || lead.leadStatus == .interested
            || isFollowUpDue(lead, now: now)
            || max(lead.price, lead.estimatedValue) > 0
    }

    static func isFollowUpDue(_ lead: Lead, now: Date = Date(), calendar: Calendar = .current) -> Bool {
        guard lead.leadStatus.allowsActiveFollowUp else { return false }
        guard let followUpDate = lead.followUpDate else { return false }
        let dueCutoff = calendar.date(byAdding: .hour, value: 12, to: now) ?? now
        return followUpDate <= dueCutoff
    }
}

private enum LeadWorkflowScorer {
    static func nextBestLead(from leads: [Lead], near coordinate: CLLocationCoordinate2D) -> Lead? {
        leads
            .filter { $0.leadStatus != .converted && $0.leadStatus != .notInterested }
            .sorted { lhs, rhs in
                score(lhs, near: coordinate) > score(rhs, near: coordinate)
            }
            .first
    }

    static func isFollowUpDue(_ lead: Lead, now: Date = Date()) -> Bool {
        LeadMapWorkflowPolicy.isFollowUpDue(lead, now: now)
    }

    static func score(_ lead: Lead, near coordinate: CLLocationCoordinate2D, now: Date = Date()) -> Double {
        var score = 0.0
        if lead.priority > 0 { score += 700 }
        if isFollowUpDue(lead, now: now) { score += 520 }

        switch lead.leadStatus {
        case .interested:
            score += 430
        case .notHome:
            score += 210
        case .notContacted:
            score += 160
        case .converted:
            score += 80
        case .notInterested:
            score -= 500
        }

        score += min(180, max(lead.price, lead.estimatedValue) / 10)

        if let updatedDate = lead.updatedDate {
            let hours = max(0, now.timeIntervalSince(updatedDate) / 3600)
            score += max(0, 90 - hours)
        }

        let distance = CLLocation(latitude: lead.latitude, longitude: lead.longitude)
            .distance(from: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude))
        score -= min(220, distance / 35)
        return score
    }
}

enum MapLeadVisibilityPolicy {
    static func visibleLeads(
        from leads: [Lead],
        mode: MapWorkflowMode,
        now: Date = Date()
    ) -> [Lead] {
        LeadClusterSummary.sortedLeads(
            leads.filter { mode.includes($0, now: now) },
            now: now
        )
    }
}

private struct MapToolsSheet: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss

    let selectedMode: MapWorkflowMode
    let selectedStyle: MapStyleChoice
    let is3DModeEnabled: Bool
    let workflowStatusText: String?
    let teamSummary: TeamWorkspaceSurfaceSummary?
    let onSelectMode: (MapWorkflowMode) -> Void
    let onSelectMapStyle: (MapStyleChoice) -> Void
    let onToggle3D: () -> Void
    let onOpenRoutePlanner: () -> Void
    let onOpenTeamMap: () -> Void

    private var optionColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 96), spacing: 10)]
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let workflowStatusText {
                        statusCard(workflowStatusText)
                    }

                    MapToolSection(title: "View") {
                        LazyVGrid(columns: optionColumns, spacing: 10) {
                            ForEach(MapWorkflowMode.allCases) { mode in
                                MapToolOptionButton(
                                    title: mode.title,
                                    icon: mode.icon,
                                    color: mode.color,
                                    isSelected: selectedMode == mode,
                                    accessibilityIdentifier: "mapWorkflowMode_\(mode.rawValue)"
                                ) {
                                    dismissThen {
                                        onSelectMode(mode)
                                    }
                                }
                            }
                        }
                    }

                    MapToolSection(title: "Map Style") {
                        LazyVGrid(columns: optionColumns, spacing: 10) {
                            ForEach(MapStyleChoice.allCases) { style in
                                MapToolOptionButton(
                                    title: style.title,
                                    icon: style.icon,
                                    color: Color.electricViolet,
                                    isSelected: selectedStyle == style,
                                    accessibilityIdentifier: "mapStyle_\(style.rawValue)"
                                ) {
                                    onSelectMapStyle(style)
                                }
                            }

                            MapToolOptionButton(
                                title: "3D",
                                icon: "cube.fill",
                                color: Color.statusInterested,
                                isSelected: is3DModeEnabled,
                                accessibilityIdentifier: "threeDMapButton",
                                action: onToggle3D
                            )
                        }
                    }

                    MapToolSection(title: "Actions") {
                        VStack(spacing: 10) {
                            MapToolActionRow(
                                title: "Next best lead",
                                subtitle: "Jump to the highest-value nearby follow-up.",
                                icon: "sparkles",
                                color: Color.statusInterested,
                                accessibilityIdentifier: "nextBestLeadButton"
                            ) {
                                dismissThen {
                                    onSelectMode(.next)
                                }
                            }

                            MapToolActionRow(
                                title: "Route planner",
                                subtitle: "Build a route from the current map area.",
                                icon: "point.topleft.down.to.point.bottomright.curvepath",
                                color: Color.electricViolet,
                                accessibilityIdentifier: "routePlannerButton"
                            ) {
                                dismissThen(onOpenRoutePlanner)
                            }

                            if let teamSummary {
                                MapToolActionRow(
                                    title: teamSummary.role == .owner ? "Team field map" : "My team map",
                                    subtitle: teamSummary.detailLine,
                                    icon: "person.3.fill",
                                    color: Color.electricViolet,
                                    accessibilityIdentifier: "teamMapShortcut"
                                ) {
                                    dismissThen(onOpenTeamMap)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
        }
        .background(Color.obsidianBackground(for: colorScheme))
        .presentationBackground(Color.obsidianBackground(for: colorScheme))
    }

    private var header: some View {
        HStack(spacing: 12) {
            ObsidianIconTile(icon: "slider.horizontal.3", tint: Color.electricViolet, size: 42)

            VStack(alignment: .leading, spacing: 3) {
                Text("Map Tools")
                    .font(.obsidianSubheadline)
                    .foregroundColor(Color.textPrimary)
                    .accessibilityIdentifier("mapToolsSheet")

                Text("Change views without crowding the map.")
                    .font(.obsidianFootnote)
                    .foregroundColor(Color.textSecondary)
                    .lineLimit(1)
            }

            Spacer()

            ObsidianCompactIconButton(
                icon: "xmark",
                accessibilityLabel: "Close map tools"
            ) {
                dismiss()
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 14)
    }

    private func statusCard(_ text: String) -> some View {
        HStack(spacing: 10) {
            ObsidianIconTile(icon: "speedometer", tint: Color.textSecondary, size: 34)

            Text(text)
                .font(.obsidianFootnote)
                .foregroundColor(Color.textSecondary)
                .lineLimit(2)

            Spacer(minLength: 0)
        }
        .padding(14)
        .background(Color.obsidianSurface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.obsidianBorder.opacity(0.55), lineWidth: 0.5)
        )
        .accessibilityIdentifier("mapWorkflowStatusCard")
    }

    private func dismissThen(_ action: @escaping () -> Void) {
        dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            action()
        }
    }
}

private struct MapToolSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.micro)
                .foregroundColor(Color.textMuted)

            content()
        }
    }
}

private struct MapToolOptionButton: View {
    let title: String
    let icon: String
    let color: Color
    let isSelected: Bool
    let accessibilityIdentifier: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 7) {
                Image(systemName: icon)
                    .font(.obsidianFootnote)
                Text(title)
                    .font(.micro)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundColor(isSelected ? .white : color)
            .frame(maxWidth: .infinity)
            .frame(height: 70)
            .background(isSelected ? color : Color.obsidianSurface)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(isSelected ? color.opacity(0.45) : Color.obsidianBorder.opacity(0.55), lineWidth: 0.5)
            )
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityIdentifier(accessibilityIdentifier)
    }
}

private struct MapToolActionRow: View {
    let title: String
    let subtitle: String
    let icon: String
    let color: Color
    let accessibilityIdentifier: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                ObsidianIconTile(icon: icon, tint: color, size: 38)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.obsidianCallout)
                        .foregroundColor(Color.textPrimary)
                        .lineLimit(1)

                    Text(subtitle)
                        .font(.obsidianFootnote)
                        .foregroundColor(Color.textSecondary)
                        .lineLimit(2)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.obsidianFootnote)
                    .foregroundColor(Color.textMuted)
            }
            .padding(14)
            .background(Color.obsidianSurface)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.obsidianBorder.opacity(0.55), lineWidth: 0.5)
            )
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityIdentifier(accessibilityIdentifier)
    }
}

struct LeadClusterSheet: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext
    let selection: LeadClusterSelection
    let onViewLead: (Lead) -> Void
    let onFocusLead: (Lead) -> Void
    @State private var statusMessage: String?

    private var summary: LeadClusterSummary {
        selection.summary
    }

    private var bestLead: Lead? {
        selection.sortedLeads.first
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    summaryCard
                    quickActions
                    statusBreakdown

                    if let bestLead {
                        bestLeadCard(bestLead)
                    }

                    leadsList
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
        }
        .background(Color.obsidianBackground(for: colorScheme))
        .presentationBackground(Color.obsidianBackground(for: colorScheme))
    }

    private var quickActions: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                clusterActionButton(title: "Route", icon: "location.north.line.fill", color: Color.electricViolet) {
                    openDirectionsToCluster()
                }
                clusterActionButton(title: "Focus", icon: "scope", color: Color.statusInterested) {
                    if let bestLead {
                        dismiss()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                            onFocusLead(bestLead)
                        }
                    }
                }
                clusterActionButton(title: "Schedule", icon: "calendar.badge.plus", color: Color.statusConverted) {
                    if let bestLead {
                        openLead(bestLead)
                    }
                }
            }

            HStack(spacing: 8) {
                clusterActionButton(title: "Priority", icon: "star.fill", color: Color.statusInterested) {
                    updateClusterLeads("Marked cluster priority") { lead in
                        lead.priority = max(lead.priority, 1)
                    }
                }
                clusterActionButton(title: "Follow-up", icon: "calendar.badge.clock", color: Color.statusNotHome) {
                    let followUpDate = tomorrowMorning()
                    updateClusterLeads("Follow-ups set for tomorrow") { lead in
                        lead.setFollowUpDate(followUpDate, autoSave: false)
                    }
                }
                clusterActionButton(title: "Interest", icon: "heart.fill", color: Color.statusInterested) {
                    updateClusterLeads("Cluster marked interested") { lead in
                        if lead.leadStatus.allowsActiveFollowUp {
                            lead.applyLeadStatus(.interested, autoSave: false)
                        }
                    }
                }
            }

            if let statusMessage {
                Text(statusMessage)
                    .font(.micro)
                    .foregroundColor(Color.textSecondary)
                    .lineLimit(2)
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

    private func clusterActionButton(title: String, icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.obsidianFootnote)
                Text(title)
                    .font(.micro)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }
            .foregroundColor(color)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(color.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(PlainButtonStyle())
    }

    private var header: some View {
        HStack(spacing: 12) {
            ObsidianIconTile(icon: "circle.grid.2x2.fill", tint: summary.color, size: 42)

            VStack(alignment: .leading, spacing: 3) {
                Text(summary.headline)
                    .font(.obsidianSubheadline)
                    .foregroundColor(Color.textPrimary)
                    .lineLimit(1)

                Text(summary.detailLine)
                    .font(.obsidianFootnote)
                    .foregroundColor(Color.textSecondary)
                    .lineLimit(1)
            }

            Spacer()

            ObsidianCompactIconButton(
                icon: "xmark",
                accessibilityLabel: "Close cluster"
            ) {
                dismiss()
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 14)
    }

    private var summaryCard: some View {
        HStack(spacing: 10) {
            clusterMetric(value: "\(summary.count)", label: "Leads", color: summary.color)
            clusterMetric(value: "\(summary.hotLeadCount)", label: "Hot", color: Color.statusInterested)
            clusterMetric(value: "\(summary.dueFollowUpCount)", label: "Due", color: Color.statusNotHome)
            clusterMetric(value: "\(summary.soldCount)", label: "Sold", color: Color.statusConverted)
        }
        .padding(14)
        .background(Color.obsidianSurface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.obsidianBorder.opacity(0.55), lineWidth: 0.5)
        )
    }

    private var statusBreakdown: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(summary.statusCounts, id: \.status) { item in
                    HStack(spacing: 6) {
                        Image(systemName: item.status.icon)
                            .font(.micro)
                        Text("\(item.count)")
                            .font(.micro)
                        Text(item.status.displayName)
                            .font(.micro)
                    }
                    .foregroundColor(item.status.swiftUIColor)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(item.status.swiftUIColor.opacity(0.12))
                    .clipShape(Capsule())
                }
            }
        }
    }

    private func bestLeadCard(_ lead: Lead) -> some View {
        Button {
            openLead(lead)
        } label: {
            HStack(spacing: 12) {
                ObsidianIconTile(icon: "star.fill", tint: Color.statusNotHome, size: 38)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Best next lead")
                        .font(.micro)
                        .foregroundColor(Color.textMuted)
                    Text(lead.displayName)
                        .font(.obsidianCallout)
                        .foregroundColor(Color.textPrimary)
                        .lineLimit(1)
                    Text(lead.address ?? lead.leadStatus.displayName)
                        .font(.obsidianFootnote)
                        .foregroundColor(Color.textSecondary)
                        .lineLimit(1)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.obsidianFootnote)
                    .foregroundColor(Color.textMuted)
            }
            .padding(14)
            .background(Color.obsidianSurface)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.statusNotHome.opacity(0.35), lineWidth: 0.5)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }

    private var leadsList: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Leads in this area")
                    .font(.obsidianCallout)
                    .foregroundColor(Color.textPrimary)

                Spacer()

                Button {
                    openDirectionsToCluster()
                } label: {
                    Label("Route", systemImage: "location.north.line.fill")
                        .font(.micro)
                        .foregroundColor(Color.electricViolet)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(Color.electricViolet.opacity(0.12))
                        .clipShape(Capsule())
                }
                .buttonStyle(PlainButtonStyle())
            }

            VStack(spacing: 0) {
                ForEach(selection.sortedLeads, id: \.objectID) { lead in
                    Button {
                        openLead(lead)
                    } label: {
                        LeadClusterRow(lead: lead)
                    }
                    .buttonStyle(PlainButtonStyle())

                    if lead.objectID != selection.sortedLeads.last?.objectID {
                        Divider()
                            .padding(.leading, 58)
                    }
                }
            }
            .background(Color.obsidianSurface)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.obsidianBorder.opacity(0.55), lineWidth: 0.5)
            )
        }
    }

    private func clusterMetric(value: String, label: String, color: Color) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.obsidianCallout)
                .foregroundColor(color)
                .lineLimit(1)

            Text(label)
                .font(.micro)
                .foregroundColor(Color.textMuted)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }

    private func updateClusterLeads(_ message: String, update: (Lead) -> Void) {
        selection.sortedLeads.forEach { lead in
            update(lead)
            lead.updatedDate = Date()
        }

        do {
            try viewContext.save()
            UserDataSyncManager.shared.syncWithServer()
            statusMessage = "\(message) for \(selection.sortedLeads.count) leads."
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        } catch {
            statusMessage = "Could not update cluster: \(error.localizedDescription)"
        }
    }

    private func tomorrowMorning() -> Date {
        let calendar = Calendar.current
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: Date()) ?? Date().addingTimeInterval(24 * 60 * 60)
        return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow) ?? tomorrow
    }

    private func openLead(_ lead: Lead) {
        dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            onViewLead(lead)
        }
    }

    private func openDirectionsToCluster() {
        let placemark = MKPlacemark(coordinate: selection.coordinate)
        let mapItem = MKMapItem(placemark: placemark)
        mapItem.name = "Lead cluster"
        mapItem.openInMaps(launchOptions: [
            MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving
        ])
    }
}

private struct LeadClusterRow: View {
    let lead: Lead

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(lead.leadStatus.swiftUIColor.opacity(0.14))
                    .frame(width: 38, height: 38)
                Image(systemName: lead.leadStatus.icon)
                    .font(.obsidianFootnote)
                    .foregroundColor(lead.leadStatus.swiftUIColor)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(lead.displayName)
                    .font(.obsidianCallout)
                    .foregroundColor(Color.textPrimary)
                    .lineLimit(1)

                Text(lead.address ?? lead.leadStatus.displayName)
                    .font(.obsidianFootnote)
                    .foregroundColor(Color.textSecondary)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    statusChip(title: lead.leadStatus.displayName, color: lead.leadStatus.swiftUIColor)
                    if lead.priority > 0 {
                        statusChip(title: "Priority", color: Color.statusNotHome)
                    }
                    if LeadClusterSummary.isFollowUpDue(lead, now: Date()) {
                        statusChip(title: "Due", color: Color.statusNotHome)
                    }
                    if max(lead.price, lead.estimatedValue) > 0 {
                        statusChip(
                            title: max(lead.price, lead.estimatedValue).formatted(
                                .currency(code: Locale.current.currency?.identifier ?? "USD")
                                    .precision(.fractionLength(0))
                            ),
                            color: Color.statusConverted
                        )
                    }
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.obsidianFootnote)
                .foregroundColor(Color.textMuted)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private func statusChip(title: String, color: Color) -> some View {
        Text(title)
            .font(.micro)
            .foregroundColor(color)
            .lineLimit(1)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
    }
}

private extension View {
    func quickFormFieldStyle() -> some View {
        self
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color.obsidianSurface)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .foregroundColor(Color.textPrimary)
    }
}

// MARK: - Status Change Sheet

struct StatusChangeSheet: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    let lead: Lead?
    let onSelect: (Lead.Status) -> Void
    let onCancel: () -> Void

    var body: some View {
        let screenBackground = Color.obsidianBackground(for: colorScheme)

        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 14) {
                    ObsidianScreenTitle(
                        title: "Change Status",
                        subtitle: leadSubtitle,
                        icon: "flag.fill"
                    )

                    ObsidianSectionCard(
                        title: "Lead Status",
                        icon: "slider.horizontal.3",
                        subtitle: "Choose the next outcome for this lead."
                    ) {
                        VStack(spacing: 10) {
                            ForEach(Lead.Status.allCases, id: \.self) { status in
                                statusOption(status)
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 18)
                .padding(.bottom, 28)
            }
            .background(screenBackground.ignoresSafeArea())
            .obsidianPushedNavigation(
                "Change Status",
                backButtonAccessibilityIdentifier: "statusChangeBackButton",
                onBack: {
                    dismiss()
                    onCancel()
                }
            )
            .safeAreaInset(edge: .bottom) {
                Button {
                    dismiss()
                    onCancel()
                } label: {
                    Label("Cancel", systemImage: "xmark.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(ObsidianSecondaryButtonStyle())
                .accessibilityIdentifier("statusChangeCancelButton")
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(screenBackground.ignoresSafeArea(edges: .bottom))
            }
        }
        .presentationBackground(screenBackground)
    }

    private var leadSubtitle: String {
        guard let lead else { return "Update the selected lead from the map." }
        let address = lead.address?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if address.isEmpty {
            return lead.displayName
        }
        return "\(lead.displayName) at \(address)"
    }

    private func statusOption(_ status: Lead.Status) -> some View {
        let isSelected = lead?.leadStatus == status

        return Button {
            dismiss()
            onSelect(status)
        } label: {
            HStack(spacing: 12) {
                ObsidianIconTile(
                    icon: status.iconName,
                    tint: status.uiColor,
                    size: 38,
                    filled: isSelected
                )

                VStack(alignment: .leading, spacing: 3) {
                    Text(status.displayName)
                        .font(.obsidianCallout)
                        .foregroundColor(Color.textPrimary)

                    Text(isSelected ? "Current status" : "Tap to apply this status")
                        .font(.obsidianFootnote)
                        .foregroundColor(Color.textSecondary)
                }

                Spacer(minLength: 8)

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.obsidianCallout)
                        .foregroundColor(status.uiColor)
                } else {
                    Image(systemName: "chevron.right")
                        .font(.micro)
                        .foregroundColor(Color.textMuted)
                }
            }
            .padding(12)
            .background(Color.obsidianElevated)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(isSelected ? status.uiColor.opacity(0.7) : Color.obsidianBorder.opacity(0.45), lineWidth: isSelected ? 1 : 0.5)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Extensions
extension MKCoordinateRegion: @retroactive Equatable {
    public static func == (lhs: MKCoordinateRegion, rhs: MKCoordinateRegion) -> Bool {
        return lhs.center.latitude == rhs.center.latitude &&
               lhs.center.longitude == rhs.center.longitude &&
               lhs.span.latitudeDelta == rhs.span.latitudeDelta &&
               lhs.span.longitudeDelta == rhs.span.longitudeDelta
    }
}
