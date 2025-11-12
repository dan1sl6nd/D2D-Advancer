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
    
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Lead.updatedDate, ascending: false)],
        animation: .default
    )
    private var leads: FetchedResults<Lead>
    
    var body: some View {
        ZStack {
                mapView
                overlayControls

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
                // Clean up any leads without addresses on app start
                cleanupLeadsWithoutAddresses()
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
        VStack {
            HStack {
                // Left Side Controls
                VStack(spacing: 8) {
                    // Center Location Button
                    Button(action: {
                        centerOnUserLocationWithAnimation()
                    }) {
                        Circle()
                            .fill(Color.blue)
                            .frame(width: 44, height: 44)
                            .overlay(
                                Image(systemName: "location.fill")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundColor(.white)
                            )
                    }

                    // Add Lead Button
                    Button(action: {
                        showingAddLead = true
                        addLeadCoordinate = locationManager.location?.coordinate ?? locationManager.region.center
                    }) {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 44, height: 44)
                            .overlay(
                                Image(systemName: "plus")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundColor(.white)
                            )
                    }

                    // Map Type Button
                    Button(action: {
                        cycleMapType()
                    }) {
                        Circle()
                            .fill(Color.purple)
                            .frame(width: 44, height: 44)
                            .overlay(
                                Image(systemName: mapTypeIcon)
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundColor(.white)
                            )
                    }

                    // Not Home Button
                    Button(action: {
                        createQuickLead(status: .notHome)
                    }) {
                        Circle()
                            .fill(Color.brown)
                            .frame(width: 44, height: 44)
                            .overlay(
                                Image(systemName: "house.slash.fill")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundColor(.white)
                            )
                    }
                    .buttonStyle(PlainButtonStyle())

                    // Not Interested Button
                    Button(action: {
                        createQuickLead(status: .notInterested)
                    }) {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 44, height: 44)
                            .overlay(
                                Image(systemName: "hand.raised.fill")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundColor(.white)
                            )
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color(.systemBackground).opacity(0.95))
                        .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 2)
                )
                .padding(.leading, 16)
                .padding(.top, 60) // Extra padding for Dynamic Island area

                Spacer()
            }
            Spacer()
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
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "location.slash")
                    .foregroundColor(.red)
                    .font(.title2)
                
                Text("Location Access")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            
            VStack(spacing: 20) {
                // Status Display
                VStack(spacing: 16) {
                    Circle()
                        .fill(Color.red.opacity(0.1))
                        .frame(width: 80, height: 80)
                        .overlay(
                            Image(systemName: "location.slash")
                                .font(.system(size: 32))
                                .foregroundColor(.red)
                        )
                    
                    VStack(spacing: 8) {
                        Text("Location Access Denied")
                            .font(.headline)
                            .fontWeight(.semibold)
                            .foregroundColor(.primary)
                        
                        Text("To use map features and navigate to leads, please enable location access in Settings.")
                            .font(.body)
                            .multilineTextAlignment(.center)
                            .foregroundColor(.secondary)
                    }
                }
                
                // Action Button
                Button("Open Settings") {
                    if let settingsUrl = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(settingsUrl)
                    }
                }
                .font(.headline)
                .fontWeight(.semibold)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(Color.red)
                .cornerRadius(12)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        .background(Color(UIColor.tertiarySystemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 2)
        .padding()
    }
    
    private var requestingLocationView: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "location.badge.questionmark")
                    .foregroundColor(.blue)
                    .font(.title2)
                
                Text("Location Permission")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            
            VStack(spacing: 20) {
                // Status Display
                VStack(spacing: 16) {
                    Circle()
                        .fill(Color.blue.opacity(0.1))
                        .frame(width: 80, height: 80)
                        .overlay(
                            Image(systemName: "location.badge.questionmark")
                                .font(.system(size: 32))
                                .foregroundColor(.blue)
                        )
                    
                    VStack(spacing: 8) {
                        Text("Location Permission Required")
                            .font(.headline)
                            .fontWeight(.semibold)
                            .foregroundColor(.primary)
                        
                        Text("D2D Advancer needs location access to show your position on the map and help navigate to leads.")
                            .font(.body)
                            .multilineTextAlignment(.center)
                            .foregroundColor(.secondary)
                    }
                }
                
                // Action Button
                Button("Grant Location Access") {
                    print("Location permission button tapped")
                    locationManager.requestLocationPermission()
                    
                    // Force immediate request if still not determined
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        if locationManager.authorizationStatus == .notDetermined {
                            locationManager.requestLocationPermission()
                        }
                    }
                }
                .font(.headline)
                .fontWeight(.semibold)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(Color.blue)
                .cornerRadius(12)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        .background(Color(UIColor.tertiarySystemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 2)
        .padding()
    }
    
    private var activeLocationView: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "location.fill")
                    .foregroundColor(.green)
                    .font(.title2)
                
                Text("Location Active")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            
            VStack(spacing: 20) {
                // Status Display
                VStack(spacing: 16) {
                    Circle()
                        .fill(Color.green.opacity(0.1))
                        .frame(width: 80, height: 80)
                        .overlay(
                            Image(systemName: "location.fill")
                                .font(.system(size: 32))
                                .foregroundColor(.green)
                        )
                    
                    VStack(spacing: 8) {
                        Text("Location Tracking Active")
                            .font(.headline)
                            .fontWeight(.semibold)
                            .foregroundColor(.green)
                        
                        VStack(spacing: 4) {
                            Text("Long press map to add lead at specific location")
                                .font(.body)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                            
                            Text("Use controls above for map view and navigation")
                                .font(.body)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        .background(Color(UIColor.tertiarySystemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 2)
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
        // Ensure context is in a clean state
        if viewContext.hasChanges {
            viewContext.rollback()
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
                    print("✅ Quick lead created: \(status.displayName) at \(addressString)")
                    
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
    
    private func cleanupLeadsWithoutAddresses() {
        let fetchRequest: NSFetchRequest<Lead> = Lead.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "address == nil OR address == ''")
        
        do {
            let leadsToDelete = try viewContext.fetch(fetchRequest)
            print("🧹 Found \(leadsToDelete.count) leads without addresses to delete")
            
            for lead in leadsToDelete {
                print("🗑️ Deleting lead: \(lead.displayName) (no address)")
                viewContext.delete(lead)
            }
            
            if !leadsToDelete.isEmpty {
                try viewContext.save()
                print("✅ Deleted \(leadsToDelete.count) leads without addresses")
            }
            
        } catch {
            print("❌ Error cleaning up leads without addresses: \(error)")
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