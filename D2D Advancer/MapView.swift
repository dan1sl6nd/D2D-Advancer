import SwiftUI
import MapKit
import CoreData

struct MapView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @ObservedObject private var locationManager = LocationManager.shared
    @ObservedObject private var preferences = AppPreferences.shared
    @State private var selectedLead: Lead?
    @State private var showingAddLead = false
    @State private var addLeadCoordinate: CLLocationCoordinate2D?
    @State private var mapType: MKMapType = AppPreferences.shared.mapDefaultViewType
    @State private var mapRotation: Double = 0.0
    @State private var mapPitch: Double = 0.0
    @State private var leadToChangeStatus: Lead? // New state variable
    @State private var triggerMapAnimation = false
    @State private var isMapMenuExpanded = false
    @ObservedObject private var paywallManager = PaywallManager.shared
    @StateObject private var overlayManager = NeighborhoodOverlayManager()
    @State private var isHeatmapEnabled = false
    @StateObject private var routeOptimizer = RouteOptimizer()
    @State private var showingRoutePlanner = false
    @State private var showingRouteSummary = false
    
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Lead.updatedDate, ascending: false)],
        animation: .default
    )
    private var leads: FetchedResults<Lead>
    
    var body: some View {
        ZStack {
                mapView
                overlayControls
                heatmapLegend

                // Show location permission status
                if locationManager.authorizationStatus == .notDetermined ||
                   locationManager.authorizationStatus == .denied ||
                   locationManager.authorizationStatus == .restricted {
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
            .sheet(isPresented: $showingAddLead) {
                AddLeadView(coordinate: addLeadCoordinate ?? locationManager.region.center)
            }
            .sheet(isPresented: $showingRoutePlanner) {
                RoutePlannerView(
                    routeOptimizer: routeOptimizer,
                    startCoordinate: locationManager.location?.coordinate ?? locationManager.region.center,
                    allLeads: Array(leads),
                    onRouteReady: { showingRouteSummary = true }
                )
            }
            .sheet(isPresented: $showingRouteSummary) {
                RouteSummaryView(
                    routeOptimizer: routeOptimizer,
                    onNavigate: { openAppleMapsRoute() },
                    onSkip: { lead in skipRouteStop(lead) },
                    onComplete: { lead in completeRouteStop(lead) },
                    onEndRoute: {
                        routeOptimizer.clearRoute()
                        showingRouteSummary = false
                    }
                )
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
            .confirmationDialog(
                "Change Status for \(leadToChangeStatus?.displayName ?? "Lead")",
                isPresented: .constant(leadToChangeStatus != nil),
                titleVisibility: .visible
            ) {
                ForEach(Lead.Status.allCases, id: \.self) { status in
                    Button(status.displayName) {
                        if let lead = leadToChangeStatus {
                            lead.leadStatus = status
                            do {
                                try viewContext.save()
                                
                                // Individual sync removed - will sync manually, hourly, or before sign-out
                                print("📝 Lead status updated locally - will sync on next manual/hourly/sign-out sync")
                                
                            } catch {
                                let nsError = error as NSError
                                print("Save error: \(nsError), \(nsError.userInfo)")
                            }
                        }
                        leadToChangeStatus = nil // Dismiss the dialog
                    }
                }
                Button("Cancel", role: .cancel) {
                    leadToChangeStatus = nil
                }
            } message: {
                Text("Select a new status for this lead.")
            }
    }
    
    private var mapView: some View {
        AdvancedMapView(
            region: $locationManager.region,
            mapType: $mapType,
            rotation: $mapRotation,
            pitch: $mapPitch,
            animateNextUpdate: $triggerMapAnimation,
            leads: Array(leads),
            heatmapOverlay: overlayManager.heatmapOverlay,
            routePolyline: routeOptimizer.currentRoute?.polyline,
            onLeadTap: { lead in
                selectedLead = lead
            },
            onLongPress: { coordinate, lead in
                handleLongPress(coordinate: coordinate, lead: lead)
            },
            onRegionChanged: { newRegion in
                if isHeatmapEnabled {
                    Task {
                        await overlayManager.generateHeatmap(for: newRegion)
                    }
                }
            }
        )
        .onAppear {
            print("🗺️ MapView: onAppear - AGGRESSIVE location setup and centering")
            setupLocationServices()

            // IMMEDIATE location actions
            handleImmediateLocationCentering()
        }
        .onChange(of: locationManager.region) { _, newRegion in
            print("MapView: Region changed to \(newRegion.center)")
        }
        .onChange(of: locationManager.location) { _, newLocation in
            // When we get a new location, center the map immediately for the first update
            if let location = newLocation {
                print("🎯 MapView: NEW LOCATION RECEIVED - centering map: \(location.coordinate)")
                print("🎯 MapView: hasInitialLocation: \(locationManager.hasInitialLocation), shouldUseUserLocation: \(locationManager.shouldUseUserLocation)")

                // Always center on the first location received during app launch
                if !locationManager.hasInitialLocation || locationManager.shouldUseUserLocation {
                    DispatchQueue.main.async {
                        print("🎯 MapView: CENTERING ON NEW LOCATION")
                        self.centerOnUserLocationWithAnimation()

                        // Mark that we've handled the initial location
                        self.locationManager.shouldUseUserLocation = false
                    }
                }
            }
        }
        .onChange(of: locationManager.authorizationStatus) { _, newStatus in
            // When permission is granted, immediately try to center on user location
            if newStatus == .authorizedWhenInUse || newStatus == .authorizedAlways {
                print("🎉 MapView: LOCATION PERMISSION GRANTED - immediate centering attempt")

                // Set flag to ensure we center on next location update
                locationManager.shouldUseUserLocation = true

                // Reset rate limiting and request location immediately
                locationManager.resetLocationRequestRetries()
                locationManager.startLocationUpdates()
                locationManager.requestImmediateLocation()

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    if self.locationManager.location != nil {
                        print("🎉 MapView: Permission granted and location available, centering now")
                        self.centerOnUserLocationWithAnimation()
                        self.locationManager.shouldUseUserLocation = false
                    } else {
                        print("🎉 MapView: Permission granted but no location yet, making multiple requests")
                        self.locationManager.requestImmediateLocation()

                        // Try again after a short delay
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            if self.locationManager.location == nil {
                                self.locationManager.requestImmediateLocation()
                            }
                        }
                    }
                }
            }
        }
    }
    
    
    
    private var overlayControls: some View {
        ZStack {
            // Dismiss overlay when menu is expanded (tap anywhere to close)
            if isMapMenuExpanded {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            isMapMenuExpanded = false
                        }
                    }
            }

            // Location button - top right
            VStack {
                HStack {
                    Spacer()
                    Button(action: {
                        centerOnUserLocationWithAnimation()
                    }) {
                        Circle()
                            .fill(Color.obsidianSurface)
                            .frame(width: 44, height: 44)
                            .overlay(
                                Image(systemName: "location.fill")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundColor(Color.textPrimary)
                            )
                            .overlay(
                                Circle()
                                    .stroke(Color.obsidianBorder, lineWidth: 1)
                            )
                            .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
                    }
                    .padding(.trailing, 16)
                    .padding(.top, 60)
                }
                Spacer()
            }

            // FAB and expanded menu - bottom right
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    VStack(spacing: 12) {
                        // Expanded menu items
                        if isMapMenuExpanded {
                            // Map Type Button (no paywall gate)
                            Button(action: {
                                cycleMapType()
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                    isMapMenuExpanded = false
                                }
                            }) {
                                Circle()
                                    .fill(Color.obsidianSurface)
                                    .frame(width: 44, height: 44)
                                    .overlay(
                                        Image(systemName: mapTypeIcon)
                                            .font(.system(size: 18, weight: .semibold))
                                            .foregroundColor(Color.electricViolet)
                                    )
                                    .overlay(
                                        Circle()
                                            .stroke(Color.obsidianBorder, lineWidth: 1)
                                    )
                                    .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
                            }
                            .transition(.scale.combined(with: .opacity))

                            // Not Interested Button
                            Button(action: {
                                guard paywallManager.gateAction() else { return }
                                createQuickLead(status: .notInterested)
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                    isMapMenuExpanded = false
                                }
                            }) {
                                Circle()
                                    .fill(Color.obsidianSurface)
                                    .frame(width: 44, height: 44)
                                    .overlay(
                                        Image(systemName: "hand.raised.fill")
                                            .font(.system(size: 18, weight: .semibold))
                                            .foregroundColor(Color.statusNotInterested)
                                    )
                                    .overlay(
                                        Circle()
                                            .stroke(Color.obsidianBorder, lineWidth: 1)
                                    )
                                    .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
                                    .premiumLock()
                            }
                            .buttonStyle(PlainButtonStyle())
                            .transition(.scale.combined(with: .opacity))

                            // Not Home Button
                            Button(action: {
                                guard paywallManager.gateAction() else { return }
                                createQuickLead(status: .notHome)
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                    isMapMenuExpanded = false
                                }
                            }) {
                                Circle()
                                    .fill(Color.obsidianSurface)
                                    .frame(width: 44, height: 44)
                                    .overlay(
                                        Image(systemName: "house.slash.fill")
                                            .font(.system(size: 18, weight: .semibold))
                                            .foregroundColor(Color.statusNotHome)
                                    )
                                    .overlay(
                                        Circle()
                                            .stroke(Color.obsidianBorder, lineWidth: 1)
                                    )
                                    .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
                                    .premiumLock()
                            }
                            .buttonStyle(PlainButtonStyle())
                            .transition(.scale.combined(with: .opacity))

                            // Add Lead Button
                            Button(action: {
                                guard paywallManager.gateAction() else { return }
                                showingAddLead = true
                                addLeadCoordinate = locationManager.location?.coordinate ?? locationManager.region.center
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                    isMapMenuExpanded = false
                                }
                            }) {
                                Circle()
                                    .fill(Color.obsidianSurface)
                                    .frame(width: 44, height: 44)
                                    .overlay(
                                        Image(systemName: "plus")
                                            .font(.system(size: 18, weight: .semibold))
                                            .foregroundColor(Color.electricViolet)
                                    )
                                    .overlay(
                                        Circle()
                                            .stroke(Color.obsidianBorder, lineWidth: 1)
                                    )
                                    .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
                                    .premiumLock()
                            }
                            .transition(.scale.combined(with: .opacity))

                            // Heatmap Toggle Button
                            Button(action: {
                                guard paywallManager.gateAction() else { return }
                                isHeatmapEnabled.toggle()
                                if isHeatmapEnabled {
                                    Task {
                                        await overlayManager.generateHeatmap(for: locationManager.region)
                                    }
                                } else {
                                    overlayManager.heatmapOverlay = nil
                                }
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                    isMapMenuExpanded = false
                                }
                            }) {
                                Circle()
                                    .fill(isHeatmapEnabled ? Color.electricViolet : Color.obsidianSurface)
                                    .frame(width: 44, height: 44)
                                    .overlay(
                                        Image(systemName: "flame.fill")
                                            .font(.system(size: 18, weight: .semibold))
                                            .foregroundColor(isHeatmapEnabled ? .white : Color.electricViolet)
                                    )
                                    .overlay(
                                        Circle()
                                            .stroke(Color.obsidianBorder, lineWidth: isHeatmapEnabled ? 0 : 1)
                                    )
                                    .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
                                    .premiumLock()
                            }
                            .buttonStyle(PlainButtonStyle())
                            .transition(.scale.combined(with: .opacity))

                            // Route Planner Button
                            Button(action: {
                                guard paywallManager.gateAction() else { return }
                                showingRoutePlanner = true
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                    isMapMenuExpanded = false
                                }
                            }) {
                                Circle()
                                    .fill(routeOptimizer.currentRoute != nil ? Color.electricViolet : Color.obsidianSurface)
                                    .frame(width: 44, height: 44)
                                    .overlay(
                                        Image(systemName: "point.topleft.down.to.point.bottomright.curvepath.fill")
                                            .font(.system(size: 18, weight: .semibold))
                                            .foregroundColor(routeOptimizer.currentRoute != nil ? .white : Color.electricViolet)
                                    )
                                    .overlay(
                                        Circle()
                                            .stroke(Color.obsidianBorder, lineWidth: routeOptimizer.currentRoute != nil ? 0 : 1)
                                    )
                                    .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
                                    .premiumLock()
                            }
                            .buttonStyle(PlainButtonStyle())
                            .transition(.scale.combined(with: .opacity))
                        }

                        // Main FAB button
                        Button(action: {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                isMapMenuExpanded.toggle()
                            }
                        }) {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [Color.electricViolet, Color.electricVioletDeep],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 56, height: 56)
                                .overlay(
                                    Image(systemName: isMapMenuExpanded ? "xmark" : "plus")
                                        .font(.system(size: 22, weight: .bold))
                                        .foregroundColor(.white)
                                        .rotationEffect(.degrees(isMapMenuExpanded ? 90 : 0))
                                )
                                .shadow(color: Color.electricViolet.opacity(0.3), radius: 8, x: 0, y: 4)
                        }
                    }
                    .padding(.trailing, 16)
                    .padding(.bottom, 24)
                }
            }
        }
    }

    @ViewBuilder
    private var heatmapLegend: some View {
        if isHeatmapEnabled {
            VStack {
                Spacer()
                HStack {
                    HStack(spacing: 8) {
                        LinearGradient(
                            colors: [
                                Color(red: 0.0, green: 0.3, blue: 0.8),
                                Color(red: 0.0, green: 0.7, blue: 0.8),
                                Color(red: 0.1, green: 0.8, blue: 0.3),
                                Color(red: 0.9, green: 0.8, blue: 0.0),
                                Color(red: 0.9, green: 0.5, blue: 0.0),
                                Color.electricViolet
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(width: 100, height: 8)
                        .clipShape(Capsule())

                        HStack(spacing: 0) {
                            Text("Low")
                                .foregroundColor(Color.textMuted)
                            Spacer()
                            Text("High")
                                .foregroundColor(Color.textMuted)
                        }
                        .font(.system(size: 9))
                        .frame(width: 100)
                    }
                    .padding(8)
                    .background(Color.obsidianSurface.opacity(0.9))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.obsidianBorder, lineWidth: 1)
                    )
                    Spacer()
                }
                .padding(.leading, 16)
                .padding(.bottom, 24)
            }
        }
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
                .font(.system(size: 32))
                .foregroundColor(Color.statusNotInterested)

            VStack(spacing: 8) {
                Text("Location Access Denied")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(Color.textPrimary)

                Text("Enable location access in Settings to use map features.")
                    .font(.system(size: 15))
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
        .padding(20)
        .background(Color.obsidianSurface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.obsidianBorder, lineWidth: 1)
        )
        .padding()
    }
    
    private var requestingLocationView: some View {
        VStack(spacing: 16) {
            Image(systemName: "location.badge.questionmark")
                .font(.system(size: 32))
                .foregroundColor(Color.electricViolet)

            VStack(spacing: 8) {
                Text("Location Permission Required")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(Color.textPrimary)

                Text("D2D Advancer needs location access to show your position on the map.")
                    .font(.system(size: 15))
                    .multilineTextAlignment(.center)
                    .foregroundColor(Color.textSecondary)
            }

            Button("Grant Location Access") {
                locationManager.requestLocationPermission()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    if locationManager.authorizationStatus == .notDetermined {
                        locationManager.requestLocationPermission()
                    }
                }
            }
            .buttonStyle(ObsidianPrimaryButtonStyle())
        }
        .padding(20)
        .background(Color.obsidianSurface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.obsidianBorder, lineWidth: 1)
        )
        .padding()
    }

    private var activeLocationView: some View {
        VStack(spacing: 16) {
            Image(systemName: "location.fill")
                .font(.system(size: 32))
                .foregroundColor(Color.statusInterested)

            VStack(spacing: 8) {
                Text("Location Tracking Active")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(Color.statusInterested)

                Text("Long press map to add lead at location")
                    .font(.system(size: 15))
                    .foregroundColor(Color.textSecondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(20)
        .background(Color.obsidianSurface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.obsidianBorder, lineWidth: 1)
        )
        .padding()
    }
    
    private func handleImmediateLocationCentering() {
        print("🎯 MapView: IMMEDIATE location centering attempt")

        // First, check if we already have a location
        if let location = locationManager.location {
            print("🎯 MapView: Using cached location immediately: \(location.coordinate)")
            centerOnUserLocationWithAnimation()
            return
        }

        // If authorized, bypass rate limiting for initial app load
        if locationManager.authorizationStatus == .authorizedWhenInUse || locationManager.authorizationStatus == .authorizedAlways {
            print("🎯 MapView: Authorized - forcing immediate location request")
            locationManager.resetLocationRequestRetries() // Reset any rate limiting
            locationManager.requestImmediateLocation()

            // Also try a direct CLLocationManager request for faster response
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                if self.locationManager.location == nil {
                    print("🎯 MapView: Still no location, requesting again")
                    self.locationManager.requestImmediateLocation()
                }
            }
        }
    }

    private func setupLocationServices() {
        print("MapView: Setting up location services")
        print("  - Current status: \(locationManager.authorizationStatus)")
        print("  - Has location: \(locationManager.location != nil)")
        print("  - Has initial location: \(locationManager.hasInitialLocation)")

        // Check if onboarding is completed before requesting permissions
        let onboardingCompleted = UserDefaults.standard.bool(forKey: "onboarding_completed")

        switch locationManager.authorizationStatus {
        case .notDetermined:
            if onboardingCompleted {
                print("MapView: Onboarding completed - requesting location permission")
                locationManager.requestLocationPermission()
            } else {
                print("MapView: Onboarding not completed - skipping location permission request (will be handled in onboarding)")
            }
        case .authorizedWhenInUse, .authorizedAlways:
            print("MapView: Permission already granted, starting updates")
            locationManager.startLocationUpdates()

            // If we already have location, center immediately
            if let location = locationManager.location {
                print("MapView: Already have location, centering on \(location.coordinate)")
                DispatchQueue.main.async {
                    self.locationManager.region = MKCoordinateRegion(
                        center: location.coordinate,
                        span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                    )
                }
            } else {
                print("MapView: No location yet, requesting immediate update")
                locationManager.requestImmediateLocation()
            }
        case .denied, .restricted:
            print("MapView: Location permission denied/restricted")
            break
        @unknown default:
            break
        }
    }
    
    private func handleLongPress(coordinate: CLLocationCoordinate2D?, lead: Lead?) {
        guard paywallManager.gateAction() else { return }

        // Show haptic feedback
        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
        impactFeedback.impactOccurred()

        if let lead = lead {
            leadToChangeStatus = lead
        } else if let coordinate = coordinate {
            addLeadCoordinate = coordinate
            showingAddLead = true
        }
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
                newLead.name = ""
                newLead.address = addressString.trimmingCharacters(in: .whitespacesAndNewlines)
                
                do {
                    try viewContext.save()
                    print("✅ Quick lead created: \(status.displayName) at \(Utilities.redactedText(addressString))")
                    
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
    
    private func distanceBetween(_ coord1: CLLocationCoordinate2D, _ coord2: CLLocationCoordinate2D) -> Double {
        let location1 = CLLocation(latitude: coord1.latitude, longitude: coord1.longitude)
        let location2 = CLLocation(latitude: coord2.latitude, longitude: coord2.longitude)
        return location1.distance(from: location2)
    }

    // MARK: - Route Helpers

    private func openAppleMapsRoute() {
        guard let route = routeOptimizer.currentRoute else { return }
        let mapItems = route.stops.map { stop -> MKMapItem in
            let placemark = MKPlacemark(coordinate: stop.lead.coordinate)
            let item = MKMapItem(placemark: placemark)
            item.name = stop.lead.displayName
            return item
        }
        MKMapItem.openMaps(with: mapItems, launchOptions: [
            MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving
        ])
    }

    private func skipRouteStop(_ lead: Lead) {
        Task {
            let remaining = routeOptimizer.currentRoute?.stops
                .filter { $0.lead.id != lead.id }
                .map { $0.lead } ?? []
            let start = locationManager.location?.coordinate ?? locationManager.region.center
            await routeOptimizer.optimizeRoute(from: start, leads: remaining)
        }
    }

    private func completeRouteStop(_ lead: Lead) {
        lead.visitCount += 1
        lead.lastContactDate = Date()
        try? viewContext.save()
        skipRouteStop(lead)
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
