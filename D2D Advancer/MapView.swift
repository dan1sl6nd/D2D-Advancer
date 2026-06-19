import SwiftUI
import MapKit
import CoreData
import UIKit

struct MapView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @ObservedObject private var locationManager = LocationManager.shared
    @ObservedObject private var onboardingManager = OnboardingManager.shared
    @ObservedObject private var preferences = AppPreferences.shared
    @ObservedObject private var firebaseService = FirebaseService.shared
    @ObservedObject private var teamService = TeamFirebaseService.shared
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
    @State private var statChipsCollapsed = false
    @State private var toastLead: Lead?
    @State private var toastMessage: String = ""
    @State private var showToast = false
    @State private var showingLookAround = false
    @State private var showingRoutePlanner = false
    @State private var lookAroundCoordinate = CLLocationCoordinate2D(latitude: 0, longitude: 0)
    @State private var longPressCoordinate: CLLocationCoordinate2D?
    @State private var longPressAddress: String?
    @State private var activeDialog: MapDialog?
    @State private var isSearching = false
    @State private var searchPin: SearchPin?
    @State private var showingSearchPinActions = false
    @State private var matchingLeadsForPin: [Lead] = []
    @State private var showingInterestedForm = false
    @State private var interestedFormCoordinate: CLLocationCoordinate2D?
    @State private var showingComeBackPicker = false
    @State private var comeBackCoordinate: CLLocationCoordinate2D?
    @State private var showingTeamFieldMap = false
    @State private var selectedTeamRepUserId: String?

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
            }
            .sheet(item: $selectedLead) { lead in
                LeadDetailView(lead: lead)
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
                                lead.leadStatus = status
                                try? viewContext.save()
                                UserDataSyncManager.shared.syncWithServer()
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
                        address: $longPressAddress,
                        onAddLead: { resolvedAddress in
                            guard paywallManager.gateAction() else { return }
                            if let coordinate = longPressCoordinate {
                                presentAddLead(
                                    coordinate: coordinate,
                                    initialAddress: resolvedAddress,
                                    after: 0.4
                                )
                            }
                            activeDialog = nil
                            longPressAddress = resolvedAddress
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
                    .presentationDetents([.height(340)])
                }
            }
            .sheet(isPresented: $showingLookAround) {
                LookAroundSheet(
                    coordinate: $lookAroundCoordinate,
                    title: "Street View"
                )
            }
            .sheet(isPresented: $showingRoutePlanner) {
                RoutePlannerSheet(region: locationManager.region)
            }
            .sheet(isPresented: $isSearching) {
                MapSearchSheet { coordinate, title in
                    searchPin = SearchPin(coordinate: coordinate, title: title)
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
                        presentAddLead(
                            coordinate: pin.coordinate,
                            initialAddress: pin.title,
                            after: 0.4
                        )
                    }
                )
                .presentationDetents([.medium])
            }
            .sheet(isPresented: $showingInterestedForm) {
                InterestedQuickForm(coordinate: interestedFormCoordinate ?? locationManager.region.center) {
                    showingInterestedForm = false
                }
                .presentationDetents([.height(380), .medium])
            }
            .sheet(isPresented: $showingComeBackPicker) {
                ComeBackLaterSheet(
                    coordinate: comeBackCoordinate ?? locationManager.region.center,
                    onDone: { showingComeBackPicker = false }
                )
                .presentationDetents([.height(300)])
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
            leads: Array(leads),
            searchPin: $searchPin,
            showsUserLocation: !isRunningUITests && LocationManager.isAuthorized(locationManager.authorizationStatus),
            onLeadTap: { lead in
                selectedLead = lead
            },
            onSearchPinTap: { pin in
                handleSearchPinTap(pin)
            },
            onLongPress: { coordinate, lead in
                handleLongPress(coordinate: coordinate, lead: lead)
            }
        )
        .onAppear {
            if !isRunningUITests {
                setupLocationServices()
            }
        }
        .onChangeCompat(of: onboardingManager.showOnboarding) { isPresented in
            if !isPresented && !isRunningUITests {
                setupLocationServices()
            }
        }
        .onChange(of: locationManager.authorizationStatus) { _, newStatus in
            guard !isRunningUITests else { return }
            if newStatus == .authorizedWhenInUse || newStatus == .authorizedAlways {
                locationManager.startLocationUpdates()
                locationManager.requestImmediateLocation()
            }
        }
    }
    
    
    
    private var topSafeAreaInset: CGFloat {
        (UIApplication.shared.connectedScenes.first as? UIWindowScene)?
            .keyWindow?.safeAreaInsets.top ?? 59
    }

    private var overlayControls: some View {
        VStack(spacing: 0) {
            // Top bar: stats + map controls
            HStack(alignment: .top) {
                statSummaryPill
                Spacer()
                mapControlsGroup
            }
            .padding(.horizontal, 16)
            .padding(.top, topSafeAreaInset + 4)

            if let summary = teamSurfaceSummary {
                HStack {
                    TeamMapShortcutPill(summary: summary) {
                        showingTeamFieldMap = true
                    }
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }

            Spacer()

            // Bottom: floating action bar
            floatingActionBar
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
        }
        .ignoresSafeArea()
    }
    
    
    private var mapTypeLabel: String {
        switch mapType {
        case .standard:
            return "Standard"
        case .satellite:
            return "Satellite"
        case .hybrid:
            return "Hybrid"
        case .satelliteFlyover:
            return "Flyover"
        case .hybridFlyover:
            return "Hybrid 3D"
        case .mutedStandard:
            return "Muted"
        @unknown default:
            return "Unknown"
        }
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
        locationManager.refreshAuthorizationStatusFromSystem()

        let canRequestLocationOutsideOnboarding = OnboardingManager.shared.isCompleted && !OnboardingManager.shared.showOnboarding

        switch locationManager.authorizationStatus {
        case .notDetermined:
            if canRequestLocationOutsideOnboarding {
                locationManager.requestLocationPermission()
            }
        case .authorizedWhenInUse, .authorizedAlways:
            locationManager.startLocationUpdates()
            if locationManager.location == nil {
                locationManager.requestImmediateLocation()
            }
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
            // Reverse geocode to show address in the menu
            locationManager.reverseGeocode(coordinate: coordinate) { address in
                DispatchQueue.main.async {
                    guard longPressCoordinate?.isEqual(to: coordinate, tolerance: 0.000001) == true else { return }
                    longPressAddress = address
                }
            }
        }
    }

    private func handleSearchPinTap(_ pin: SearchPin) {
        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
        impactFeedback.impactOccurred()

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
        showingSearchPinActions = true
    }

    private var mapTypeIcon: String {
        switch mapType {
        case .standard:
            return "map"
        case .satellite:
            return "globe.americas.fill"
        case .hybrid:
            return "map.fill"
        default:
            return "map"
        }
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
            mapControlButton(icon: mapTypeIcon, color: .electricViolet) {
                cycleMapType()
            }
            mapControlButton(icon: "cube.fill", color: is3DModeEnabled ? .statusInterested : .textPrimary) {
                toggle3DMode()
            }
            .accessibilityLabel(is3DModeEnabled ? "Turn Off 3D Map" : "Turn On 3D Map")
            .accessibilityIdentifier("threeDMapButton")
            mapControlButton(icon: "point.topleft.down.to.point.bottomright.curvepath", color: .electricViolet) {
                showingRoutePlanner = true
            }
            .accessibilityIdentifier("routePlannerButton")
        }
    }

    private func loadTeamWorkspaceIfNeeded() async {
        guard shouldLoadTeamWorkspace else { return }
        guard firebaseService.currentUser != nil || userAccountManager.isLoggedIn else { return }
        await teamService.loadCurrentTeam(
            displayName: userAccountManager.currentUserDisplayName,
            email: userAccountManager.currentUserEmail
        )
    }

    private func loadTeamWorkspaceUntilAvailable() async {
        guard shouldLoadTeamWorkspace else { return }

        for attempt in 0..<8 {
            if teamService.activeTeam != nil && teamService.currentMember != nil {
                return
            }

            await loadTeamWorkspaceIfNeeded()

            if teamService.activeTeam != nil && teamService.currentMember != nil {
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
    private func quickActionButton(icon: String, label: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: icon)
                    .font(.obsidianFootnote)
                Text(label)
                    .font(.nano)
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
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                statChipsCollapsed.toggle()
            }
        } label: {
            HStack(spacing: statChipsCollapsed ? 6 : 10) {
                if statChipsCollapsed {
                    // Compact: just total
                    Image(systemName: "chart.bar.fill")
                        .font(.obsidianSmall)
                        .foregroundColor(.electricViolet)
                    Text("\(leads.count)")
                        .font(.obsidianFootnote)
                        .foregroundColor(.primary)
                } else {
                    // Expanded: colored dots with counts
                    statDot(color: .statusInterested, count: interestedCount)
                    statDot(color: .statusNotHome, count: notHomeCount)
                    statDot(color: .statusNotInterested, count: notInterestedCount)
                    statDot(color: .statusConverted, count: soldCount)

                    if todayCount > 0 {
                        Text("·")
                            .foregroundColor(.secondary)
                        Text("\(todayCount) today")
                            .font(.micro)
                            .foregroundColor(.electricViolet)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial)
            .clipShape(Capsule())
            .shadow(color: .black.opacity(0.12), radius: 6, x: 0, y: 2)
        }
        .buttonStyle(PlainButtonStyle())
    }

    @ViewBuilder
    private func statDot(color: Color, count: Int) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text("\(count)")
                .font(.obsidianCaption)
                .foregroundColor(.primary)
        }
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
                        .foregroundColor(.primary)
                        .lineLimit(1)

                    Spacer()

                    Button("Undo") {
                        undoQuickLead()
                    }
                    .font(.obsidianFootnote)
                    .foregroundColor(Color.electricViolet)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(.ultraThinMaterial)
                .clipShape(Capsule())
                .shadow(color: .black.opacity(0.15), radius: 10, x: 0, y: 3)
                .transition(.move(edge: .top).combined(with: .opacity))
                .padding(.horizontal, 20)
                .padding(.top, 60)

                Spacer()
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: showToast)
    }

    private func showQuickLeadToast(status: Lead.Status, address: String, lead: Lead) {
        toastLead = lead
        toastMessage = "\(status.displayName) — \(address)"
        withAnimation {
            showToast = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            withAnimation {
                showToast = false
            }
            toastLead = nil
        }
    }

    private func undoQuickLead() {
        if let lead = toastLead {
            viewContext.delete(lead)
            try? viewContext.save()
        }
        withAnimation {
            showToast = false
        }
        toastLead = nil
    }

    private func cycleMapType() {
        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
        impactFeedback.impactOccurred()
        
        switch mapType {
        case .standard:
            mapType = .satellite
        case .satellite:
            mapType = .hybrid
        case .hybrid:
            mapType = .standard
        default:
            mapType = .standard
        }
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
            span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
        )
        
        // First set the animation trigger to true
        triggerMapAnimation = true
        
        // Then update the region - the AdvancedMapView will animate to it
        locationManager.region = newRegion
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
            try? viewContext.save()
        }
        
        // Find the nearest building/house using geocoding with precise location
        findNearestBuilding(from: coordinate) { (buildingCoordinate, addressString) in
            DispatchQueue.main.async {
                guard let addressString = addressString, !addressString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    // Show user feedback that address couldn't be resolved
                    let impactFeedback = UIImpactFeedbackGenerator(style: .heavy)
                    impactFeedback.impactOccurred()
                    print("❌ Failed to create quick lead: No address found")
                    return
                }
                
                // Use the building coordinate if found, otherwise use original
                let finalCoordinate = buildingCoordinate ?? coordinate
                
                // Create the lead with the resolved address and building coordinate
                let newLead = Lead(context: viewContext)
                newLead.id = UUID()
                newLead.createdDate = Date()
                newLead.updatedDate = Date()
                newLead.leadStatus = status
                newLead.latitude = finalCoordinate.latitude
                newLead.longitude = finalCoordinate.longitude
                newLead.name = nil
                newLead.address = addressString.trimmingCharacters(in: .whitespacesAndNewlines)

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
                    print("✅ Quick lead created: \(status.displayName) at \(Utilities.redactedText(addressString))")
                    UserDataSyncManager.shared.syncWithServer()
                    // Schedule notification for Not Home follow-ups
                    if status == .notHome {
                        NotificationService.shared.scheduleFollowUpNotification(for: newLead)
                    }
                    showQuickLeadToast(status: status, address: addressString, lead: newLead)
                } catch {
                    print("❌ Error creating quick lead: \(error.localizedDescription)")
                    ErrorHandler.shared.handle(error, context: "Create Quick Lead")
                }
            }
        }
    }
    
    private func findNearestBuilding(from coordinate: CLLocationCoordinate2D, completion: @escaping (CLLocationCoordinate2D?, String?) -> Void) {
        let geocoder = CLGeocoder()
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        
        // Use high precision reverse geocoding to find the nearest address
        geocoder.reverseGeocodeLocation(location, preferredLocale: Locale.current) { placemarks, error in
            guard let placemark = placemarks?.first, error == nil else {
                completion(nil, nil)
                return
            }
            
            // Get the precise building coordinate from placemark if available
            let buildingCoordinate = placemark.location?.coordinate ?? coordinate
            
            // Create a detailed address string
            var addressComponents: [String] = []
            
            if let streetNumber = placemark.subThoroughfare {
                addressComponents.append(streetNumber)
            }
            if let streetName = placemark.thoroughfare {
                addressComponents.append(streetName)
            }
            if let city = placemark.locality {
                addressComponents.append(city)
            }
            if let state = placemark.administrativeArea {
                addressComponents.append(state)
            }
            if let postalCode = placemark.postalCode {
                addressComponents.append(postalCode)
            }
            
            let fullAddress = addressComponents.joined(separator: ", ")
            completion(buildingCoordinate, fullAddress.isEmpty ? nil : fullAddress)
        }
    }
    
}

// MARK: - Interested Quick Form

struct InterestedQuickForm: View {
    @Environment(\.managedObjectContext) private var viewContext
    @ObservedObject private var paywallManager = PaywallManager.shared

    let coordinate: CLLocationCoordinate2D
    let onDismiss: () -> Void

    @State private var name = ""
    @State private var phone = ""
    @State private var note = ""
    @State private var address = ""
    @State private var isSaving = false
    @State private var showingMessageConfirmation = false
    @State private var createdLead: Lead?

    var body: some View {
        VStack(spacing: 18) {
            header
            fields

            Spacer(minLength: 4)

            saveButton
        }
        .padding(.horizontal, 20)
        .padding(.top, 22)
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.obsidianBlack)
        .sheet(isPresented: $showingMessageConfirmation) {
            if let lead = createdLead {
                FirstMessageConfirmationView(lead: lead) {
                    onDismiss()
                }
            }
        }
        .onAppear {
            reverseGeocode()
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Button("Cancel") { onDismiss() }
                .font(.obsidianCallout)
                .foregroundColor(Color.textSecondary)
                .lineLimit(1)
                .frame(width: 86, alignment: .leading)

            Spacer(minLength: 0)

            Text("Interested Lead")
                .font(.obsidianTitle)
                .foregroundColor(Color.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
                .frame(maxWidth: .infinity)

            Spacer(minLength: 0)

            Color.clear
                .frame(width: 86, height: 1)
                .accessibilityHidden(true)
        }
    }

    private var fields: some View {
        VStack(spacing: 14) {
            TextField("Name", text: $name)
                .quickFormFieldStyle()

            TextField("Phone", text: $phone)
                .keyboardType(.phonePad)
                .quickFormFieldStyle()
                .onChange(of: phone) { _, newValue in
                    phone = Utilities.formatPhoneNumber(newValue)
                }

            TextField("Note (optional)", text: $note)
                .quickFormFieldStyle()

            if !address.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "mappin.circle.fill")
                        .foregroundColor(Color.electricViolet)
                        .font(.caption)
                    Text(address)
                        .font(.caption)
                        .foregroundColor(Color.textSecondary)
                        .lineLimit(1)
                    Spacer()
                }
                .padding(.horizontal, 4)
            }
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
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.electricViolet)
            )
        }
        .disabled(isSaving)
    }

    private func reverseGeocode() {
        let geocoder = CLGeocoder()
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        geocoder.reverseGeocodeLocation(location) { placemarks, _ in
            guard let placemark = placemarks?.first else { return }
            var parts: [String] = []
            if let sub = placemark.subThoroughfare { parts.append(sub) }
            if let street = placemark.thoroughfare { parts.append(street) }
            if let city = placemark.locality { parts.append(city) }
            if let state = placemark.administrativeArea { parts.append(state) }
            if let zip = placemark.postalCode { parts.append(zip) }
            DispatchQueue.main.async {
                address = parts.joined(separator: ", ")
            }
        }
    }

    private func saveInterestedLead() {
        isSaving = true

        // Save pending changes first
        if viewContext.hasChanges {
            try? viewContext.save()
        }

        let newLead = Lead(context: viewContext)
        newLead.id = UUID()
        newLead.createdDate = Date()
        newLead.updatedDate = Date()
        newLead.leadStatus = .interested
        newLead.latitude = coordinate.latitude
        newLead.longitude = coordinate.longitude
        newLead.name = name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : name.trimmingCharacters(in: .whitespacesAndNewlines)
        newLead.phone = phone.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : phone.trimmingCharacters(in: .whitespacesAndNewlines)
        newLead.notes = note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : note.trimmingCharacters(in: .whitespacesAndNewlines)
        newLead.address = address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : address.trimmingCharacters(in: .whitespacesAndNewlines)

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
            print("❌ Error saving interested lead: \(error.localizedDescription)")
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
        print("⚠️ Search completer error: \(error.localizedDescription)")
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
        .background(Color.obsidianBlack)
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
    @Environment(\.managedObjectContext) private var viewContext
    let coordinate: CLLocationCoordinate2D
    let onDone: () -> Void
    @ObservedObject private var locationManager = LocationManager.shared
    @State private var selectedTime = Date()
    @State private var address = ""

    private let quickTimes: [(String, Int)] = [
        ("1 Hour", 1), ("2 Hours", 2), ("4 Hours", 4), ("Tomorrow", 24)
    ]

    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(Color.obsidianBorder)
                .frame(width: 36, height: 5)
                .padding(.top, 10)
                .padding(.bottom, 14)

            Text("Come Back Later")
                .font(.obsidianAction)
                .foregroundColor(.textPrimary)
                .padding(.bottom, 4)

            if !address.isEmpty {
                Text(address)
                    .font(.obsidianSmall)
                    .foregroundColor(.textMuted)
                    .lineLimit(1)
                    .padding(.bottom, 12)
            }

            // Quick time buttons
            HStack(spacing: 8) {
                ForEach(quickTimes, id: \.1) { label, hours in
                    Button {
                        createComeBackLead(hoursFromNow: hours)
                    } label: {
                        Text(label)
                            .font(.obsidianCaption)
                            .foregroundColor(.textPrimary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.obsidianSurface)
                            .cornerRadius(10)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(Color.obsidianBorder, lineWidth: 0.5)
                            )
                    }
                }
            }
            .padding(.horizontal, 20)

            Spacer()
        }
        .background(Color.obsidianBlack)
        .presentationBackground(Color.obsidianBlack)
        .onAppear {
            locationManager.reverseGeocode(coordinate: coordinate) { addr in
                if let addr = addr { address = addr }
            }
        }
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

        let newLead = Lead(context: viewContext)
        newLead.id = UUID()
        newLead.createdDate = Date()
        newLead.updatedDate = Date()
        newLead.leadStatus = .notHome
        newLead.latitude = coordinate.latitude
        newLead.longitude = coordinate.longitude
        newLead.address = address.isEmpty ? nil : address
        newLead.name = nil
        newLead.setFollowUpDate(followUpDate, autoSave: false)

        do {
            try viewContext.save()
            UserDataSyncManager.shared.syncWithServer()
            NotificationService.shared.scheduleFollowUpNotification(for: newLead)
            let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
            impactFeedback.impactOccurred()
        } catch {
            print("❌ Error creating come-back lead: \(error)")
        }
        onDone()
    }
}

struct LongPressMenuSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var address: String?
    let onAddLead: (String) -> Void
    let onStreetView: () -> Void
    let onNavigate: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Grab handle
            Capsule()
                .fill(Color.obsidianBorder)
                .frame(width: 36, height: 5)
                .padding(.top, 10)
                .padding(.bottom, 14)

            // Address header
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.statusConverted.opacity(0.12))
                        .frame(width: 38, height: 38)
                    Image(systemName: "mappin.circle.fill")
                        .font(.obsidianTitle)
                        .foregroundColor(.statusConverted)
                }
                VStack(alignment: .leading, spacing: 3) {
                    if let address = address {
                        Text(address)
                            .font(.obsidianFootnote)
                            .foregroundColor(.textPrimary)
                            .lineLimit(2)
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
                        HStack(spacing: 6) {
                            ProgressView()
                                .scaleEffect(0.7)
                            Text("Getting address...")
                                .font(.obsidianCaption)
                                .foregroundColor(.textMuted)
                        }
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(Color.obsidianSurface)
            .cornerRadius(14)
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.obsidianBorder, lineWidth: 0.5)
            )
            .padding(.horizontal, 20)
            .padding(.bottom, 16)

            // Actions
            VStack(spacing: 0) {
                mapActionRow(
                    icon: "plus.circle.fill",
                    color: .electricViolet,
                    title: "Add Lead Here",
                    isDisabled: address == nil
                ) {
                    guard let address else { return }
                    dismiss()
                    onAddLead(address)
                }
                Divider().padding(.leading, 72)
                mapActionRow(icon: "binoculars.fill", color: .statusInterested, title: "Street View Here") {
                    dismiss()
                    onStreetView()
                }
                Divider().padding(.leading, 72)
                mapActionRow(icon: "location.north.line.fill", color: .statusNotHome, title: "Navigate Here") {
                    dismiss()
                    onNavigate()
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
        .presentationBackground(Color.obsidianBlack)
    }

    private func copyAddress(_ address: String) {
        UIPasteboard.general.string = address
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        UIAccessibility.post(notification: .announcement, argument: "Address copied")
    }

    private func mapActionRow(
        icon: String,
        color: Color,
        title: String,
        isDisabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(color.opacity(0.12))
                        .frame(width: 38, height: 38)
                    Image(systemName: icon)
                        .font(.obsidianCallout)
                        .foregroundColor(color)
                }
                Text(title)
                    .font(.obsidianCallout)
                    .foregroundColor(.textPrimary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.obsidianSmall)
                    .foregroundColor(.textMuted)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.55 : 1)
    }
}

// MARK: - Search Pin Actions Sheet

struct SearchPinActionsSheet: View {
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
        }
        .background(Color.obsidianBlack)
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
    @Environment(\.dismiss) private var dismiss
    let lead: Lead?
    let onSelect: (Lead.Status) -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationView {
            List {
                ForEach(Lead.Status.allCases, id: \.self) { status in
                    Button {
                        dismiss()
                        onSelect(status)
                    } label: {
                        HStack(spacing: 12) {
                            Circle()
                                .fill(status.swiftUIColor)
                                .frame(width: 12, height: 12)
                            Text(status.displayName)
                                .foregroundColor(.primary)
                            Spacer()
                        }
                    }
                }
            }
            .listStyle(.plain)
            .navigationTitle("Change Status")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                        onCancel()
                    }
                }
            }
        }
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
