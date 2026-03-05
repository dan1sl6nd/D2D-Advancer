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
    @ObservedObject private var paywallManager = PaywallManager.shared
    @State private var toastLead: Lead?
    @State private var toastMessage: String = ""
    @State private var showToast = false

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

    var body: some View {
        ZStack {
                mapView
                overlayControls
                toastOverlay

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
            onLeadTap: { lead in
                selectedLead = lead
            },
            onLongPress: { coordinate, lead in // Updated closure signature
                handleLongPress(coordinate: coordinate, lead: lead)
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
            // Top-left: stat chips
            VStack {
                statChipsRow
                    .padding(.top, 62)
                    .padding(.trailing, 70)
                Spacer()
            }

            // Top-right: map controls
            VStack {
                HStack {
                    Spacer()
                    mapControlsGroup
                        .fixedSize()
                        .padding(.trailing, 16)
                        .padding(.top, 58)
                }
                Spacer()
            }

            // Bottom: floating action bar
            VStack {
                Spacer()
                floatingActionBar
                    .padding(.bottom, 30)
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
    
    // MARK: - HUD Components

    private var mapControlsGroup: some View {
        VStack(spacing: 0) {
            Button {
                centerOnUserLocationWithAnimation()
            } label: {
                Image(systemName: "location.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(Color.textPrimary)
                    .frame(width: 44, height: 44)
            }

            Divider()
                .background(.white.opacity(0.1))

            Button {
                cycleMapType()
            } label: {
                Image(systemName: mapTypeIcon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(Color.electricViolet)
                    .frame(width: 44, height: 44)
            }
        }
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.25), radius: 4, x: 0, y: 2)
    }

    private var floatingActionBar: some View {
        HStack(spacing: 0) {
            // Not Home
            Button {
                guard paywallManager.gateAction() else { return }
                createQuickLead(status: .notHome)
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: "house.slash.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(Color.statusNotHome)
                    Text("NOT HOME")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(Color.statusNotHome)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }

            // No Interest
            Button {
                guard paywallManager.gateAction() else { return }
                createQuickLead(status: .notInterested)
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: "hand.raised.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(Color.statusNotInterested)
                    Text("NO INTEREST")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(Color.statusNotInterested)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }

            // Add Lead
            Button {
                guard paywallManager.gateAction() else { return }
                showingAddLead = true
                addLeadCoordinate = locationManager.location?.coordinate ?? locationManager.region.center
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: "plus")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(Color.electricViolet)
                    Text("ADD LEAD")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(Color.electricViolet)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }
        }
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .shadow(color: .black.opacity(0.25), radius: 6, x: 0, y: 2)
        .padding(.horizontal, 16)
    }

    private var statChipsRow: some View {
        HStack(spacing: 6) {
            statChip(color: Color.statusInterested, count: interestedCount)
            statChip(color: Color.statusNotHome, count: notHomeCount)
            statChip(color: Color.statusNotInterested, count: notInterestedCount)
            statChip(color: Color.statusConverted, count: soldCount)
            Spacer()
            Text("\(leads.count) total")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(.regularMaterial)
                .clipShape(Capsule())
        }
        .padding(.horizontal, 14)
    }

    @ViewBuilder
    private func statChip(color: Color, count: Int) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text("\(count)")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.primary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(.regularMaterial)
        .clipShape(Capsule())
    }

    private var toastOverlay: some View {
        VStack {
            Spacer()
            if showToast {
                HStack(spacing: 12) {
                    Text(toastMessage)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white)
                        .lineLimit(1)

                    Button("Undo") {
                        undoQuickLead()
                    }
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(Color.electricViolet)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color.black.opacity(0.85))
                .clipShape(Capsule())
                .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 2)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .padding(.horizontal, 20)
                .padding(.bottom, 100)
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
    
    private func distanceBetween(_ coord1: CLLocationCoordinate2D, _ coord2: CLLocationCoordinate2D) -> Double {
        let location1 = CLLocation(latitude: coord1.latitude, longitude: coord1.longitude)
        let location2 = CLLocation(latitude: coord2.latitude, longitude: coord2.longitude)
        return location1.distance(from: location2)
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
