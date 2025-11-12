import Foundation
import CoreLocation
import MapKit

class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = LocationManager()
    
    private let locationManager = CLLocationManager()
    @Published var hasInitialLocation = false
    
    @Published var location: CLLocation?
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
        span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
    )
    @Published var shouldUseUserLocation = false // Flag to indicate we should center on user location
    
    // Geocoding status indicators
    @Published var isReverseGeocoding = false
    @Published var isForwardGeocoding = false
    @Published var lastGeocodingError: String?
    
    // Rate limiting for location requests
    private var lastLocationRequestTime: Date?
    private var locationRequestAttempts: Int = 0
    private let maxLocationRequestAttempts = 3
    private let locationRequestCooldown: TimeInterval = 10.0 // 10 seconds between requests
    
    private override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.distanceFilter = 10 // Update every 10 meters
        authorizationStatus = locationManager.authorizationStatus

        print("LocationManager: Initializing - current status: \(authorizationStatus)")

        // Set flag to indicate we want to use user location
        shouldUseUserLocation = true

        // Immediately try to get location if already authorized
        if authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways {
            print("LocationManager: Already authorized, starting location updates immediately")
            startLocationUpdates()
            requestImmediateLocation()
        } else if authorizationStatus == .notDetermined {
            print("LocationManager: Permission not determined - will be requested by onboarding or MainTabView after onboarding completes")
        }
    }
    
    private func shouldRequestLocation() -> Bool {
        // If we want to use user location (app launch), be more lenient with rate limiting
        if shouldUseUserLocation {
            print("LocationManager: shouldUseUserLocation=true, allowing immediate request")
            return true
        }

        // Check if we've exceeded max attempts
        if locationRequestAttempts >= maxLocationRequestAttempts {
            print("LocationManager: Max location request attempts reached (\(maxLocationRequestAttempts))")
            return false
        }

        // Check cooldown period
        if let lastRequest = lastLocationRequestTime {
            let timeSinceLastRequest = Date().timeIntervalSince(lastRequest)
            if timeSinceLastRequest < locationRequestCooldown {
                let remainingCooldown = locationRequestCooldown - timeSinceLastRequest
                print("LocationManager: Location request cooldown active (\(Int(remainingCooldown))s remaining)")
                return false
            }
        }

        return true
    }
    
    private func makeLocationRequest() {
        guard shouldRequestLocation() else { return }
        
        lastLocationRequestTime = Date()
        locationRequestAttempts += 1
        
        print("LocationManager: Making location request (attempt \(locationRequestAttempts)/\(maxLocationRequestAttempts))")
        locationManager.requestLocation()
    }
    
    func resetLocationRequestRetries() {
        DispatchQueue.main.async {
            self.locationRequestAttempts = 0
            self.lastLocationRequestTime = nil
            print("LocationManager: Location request retry counter reset")
        }
    }
    
    func requestLocationPermission() {
        print("LocationManager: Requesting location permission, current status: \(authorizationStatus)")
        
        // Move location services check off main thread to avoid UI blocking
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            // Check if location services are enabled on device (on background thread)
            guard CLLocationManager.locationServicesEnabled() else {
                DispatchQueue.main.async {
                    print("LocationManager: Location services are disabled on device")
                }
                return
            }
            
            DispatchQueue.main.async {
                self.continueLocationPermissionRequest()
            }
        }
    }
    
    private func continueLocationPermissionRequest() {
        guard authorizationStatus == .notDetermined else {
            print("LocationManager: Permission already determined, status: \(authorizationStatus)")
            return
        }
        
        print("LocationManager: Sending authorization request...")
        
        // Ensure the authorization request is made on the main thread
        DispatchQueue.main.async {
            self.locationManager.requestWhenInUseAuthorization()
            print("LocationManager: Permission request sent")
        }
        
        // Debug: Check bundle info for location keys
        if let bundle = Bundle.main.infoDictionary {
            print("LocationManager: Bundle keys check:")
            print("  NSLocationWhenInUseUsageDescription: \(bundle["NSLocationWhenInUseUsageDescription"] as? String ?? "NOT FOUND")")
            print("  NSLocationAlwaysAndWhenInUseUsageDescription: \(bundle["NSLocationAlwaysAndWhenInUseUsageDescription"] as? String ?? "NOT FOUND")")
        }
    }
    
    func startLocationUpdates() {
        guard authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways else {
            return
        }
        locationManager.startUpdatingLocation()
    }
    
    func stopLocationUpdates() {
        locationManager.stopUpdatingLocation()
    }
    
    func requestImmediateLocation() {
        guard authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways else {
            print("LocationManager: Cannot request location - no permission")
            return
        }
        
        makeLocationRequest()
    }
    
    func centerOnUserLocation() {
        DispatchQueue.main.async {
            if let location = self.location {
                self.region = MKCoordinateRegion(
                    center: location.coordinate,
                    span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                )
            } else {
                print("LocationManager: No location available for centering")

                // Check authorization status first
                if self.authorizationStatus == .authorizedWhenInUse || self.authorizationStatus == .authorizedAlways {
                    print("LocationManager: Permission granted but no location, attempting rate-limited location request")
                    self.makeLocationRequest()
                } else if self.authorizationStatus == .notDetermined {
                    // Check if onboarding is completed before requesting permission
                    let onboardingCompleted = UserDefaults.standard.bool(forKey: "onboarding_completed")
                    if onboardingCompleted {
                        print("LocationManager: Onboarding completed, permission not determined - requesting permission")
                        // Dispatch to background thread to avoid blocking UI
                        DispatchQueue.global(qos: .userInitiated).async {
                            self.requestLocationPermission()
                        }
                    } else {
                        print("LocationManager: Onboarding not completed yet - cannot request permission outside onboarding flow")
                    }
                } else {
                    print("LocationManager: Location permission denied or restricted")
                }
            }
        }
    }
    
    func forceInitialLocationCenter() {
        hasInitialLocation = false
        if let location = location {
            DispatchQueue.main.async {
                self.region = MKCoordinateRegion(
                    center: location.coordinate,
                    span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                )
                self.hasInitialLocation = true
            }
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        
        DispatchQueue.main.async {
            let wasFirstLocation = self.location == nil
            self.location = location
            
            // Reset retry counter on successful location update
            self.locationRequestAttempts = 0
            self.lastLocationRequestTime = nil
            
            // Always update region for the first location update, or if we haven't set initial location yet
            if !self.hasInitialLocation || wasFirstLocation || self.shouldUseUserLocation {
                let newRegion = MKCoordinateRegion(
                    center: location.coordinate,
                    span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                )
                self.region = newRegion
                self.hasInitialLocation = true
                print("LocationManager: ✅ INITIAL location received and map centered on \(location.coordinate)")

                // Force multiple updates to ensure the map centers properly
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    self.region = newRegion
                    print("LocationManager: 🔄 Map centering reinforced (0.1s)")
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    self.region = newRegion
                    print("LocationManager: 🔄 Map centering reinforced (0.3s)")
                }

                // Turn off the shouldUseUserLocation flag after successful initial centering
                if self.shouldUseUserLocation {
                    print("LocationManager: 🎯 Turning off shouldUseUserLocation flag after successful initial location")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        self.shouldUseUserLocation = false
                    }
                }
            }
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        DispatchQueue.main.async {
            self.authorizationStatus = status
            
            switch status {
            case .authorizedWhenInUse, .authorizedAlways:
                print("LocationManager: 🎉 Permission granted, starting location updates and requesting immediate location")
                self.startLocationUpdates()
                // Reset hasInitialLocation when permission is granted to ensure centering
                self.hasInitialLocation = false

                // Reset retry counter when permission is granted
                self.locationRequestAttempts = 0
                self.lastLocationRequestTime = nil

                // Request immediate location update using rate-limited approach
                self.makeLocationRequest()

                // Also start continuous updates for faster initial location
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    if !self.hasInitialLocation {
                        self.makeLocationRequest()
                        print("LocationManager: 🔄 Additional location request for faster initial positioning")
                    }
                }
            case .denied, .restricted:
                print("LocationManager: Permission denied/restricted")
                self.stopLocationUpdates()
                // Reset retry counter on permission denial
                self.locationRequestAttempts = 0
                self.lastLocationRequestTime = nil
            case .notDetermined:
                print("LocationManager: Permission not determined")
                break
            @unknown default:
                break
            }
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        if let clError = error as? CLError {
            switch clError.code {
            case .denied:
                print("LocationManager: Location access denied by user")
            case .locationUnknown:
                print("LocationManager: Location service unable to determine location")
            case .network:
                ErrorHandler.shared.handle(error, context: "Location Network")
            default:
                ErrorHandler.shared.handle(error, context: "Location Service")
            }
        } else {
            ErrorHandler.shared.handle(error, context: "Location")
        }
    }
    
    func geocodeAddress(_ address: String, completion: @escaping (CLLocationCoordinate2D?) -> Void) {
        DispatchQueue.main.async {
            self.isForwardGeocoding = true
            self.lastGeocodingError = nil
        }
        geocodeAddressWithRetry(address: address, attempt: 1, completion: completion)
    }
    
    private func geocodeAddressWithRetry(address: String, attempt: Int, completion: @escaping (CLLocationCoordinate2D?) -> Void) {
        let maxAttempts = 3
        let retryDelay: TimeInterval = Double(attempt) * 2.0 // Progressive delay: 2s, 4s, 6s
        
        let geocoder = CLGeocoder()
        
        print("🗺️ [Forward Geocoding] Attempt \(attempt)/\(maxAttempts) for address: \(address)")
        
        geocoder.geocodeAddressString(address) { [weak self] placemarks, error in
            if let error = error {
                let clError = error as? CLError
                let errorCode = clError?.code.rawValue ?? -1
                
                print("🚨 [Forward Geocoding] Error: \(error.localizedDescription) (Code: \(errorCode))")
                
                // Handle specific error types
                switch clError?.code {
                case .network:
                    print("🌐 [Forward Geocoding] Network error - checking retry policy")
                    if attempt < maxAttempts {
                        print("🔄 [Forward Geocoding] Retrying in \(retryDelay)s (attempt \(attempt + 1)/\(maxAttempts))")
                        DispatchQueue.main.asyncAfter(deadline: .now() + retryDelay) {
                            self?.geocodeAddressWithRetry(address: address, attempt: attempt + 1, completion: completion)
                        }
                        return
                    } else {
                        print("❌ [Forward Geocoding] Max network retry attempts reached")
                        DispatchQueue.main.async {
                            self?.isForwardGeocoding = false
                            self?.lastGeocodingError = "Network error - please check your connection"
                        }
                        completion(nil)
                        return
                    }
                case .geocodeFoundNoResult:
                    print("📍 [Forward Geocoding] No results found for address: \(address)")
                    DispatchQueue.main.async {
                        self?.isForwardGeocoding = false
                        self?.lastGeocodingError = "Address not found"
                    }
                    completion(nil)
                    return
                case .geocodeCanceled:
                    print("⏹️ [Forward Geocoding] Request was canceled")
                    DispatchQueue.main.async {
                        self?.isForwardGeocoding = false
                    }
                    completion(nil)
                    return
                default:
                    print("⚠️ [Forward Geocoding] Other error: \(error.localizedDescription)")
                    if attempt < maxAttempts {
                        print("🔄 [Forward Geocoding] Retrying in \(retryDelay)s (attempt \(attempt + 1)/\(maxAttempts))")
                        DispatchQueue.main.asyncAfter(deadline: .now() + retryDelay) {
                            self?.geocodeAddressWithRetry(address: address, attempt: attempt + 1, completion: completion)
                        }
                        return
                    } else {
                        DispatchQueue.main.async {
                            self?.isForwardGeocoding = false
                            self?.lastGeocodingError = error.localizedDescription
                        }
                        completion(nil)
                        return
                    }
                }
            }
            
            // Success case
            if let placemark = placemarks?.first,
               let location = placemark.location {
                print("✅ [Forward Geocoding] Success: \(location.coordinate)")
                DispatchQueue.main.async {
                    self?.isForwardGeocoding = false
                    self?.lastGeocodingError = nil
                }
                completion(location.coordinate)
            } else {
                print("📍 [Forward Geocoding] No placemark found for address: \(address)")
                DispatchQueue.main.async {
                    self?.isForwardGeocoding = false
                    self?.lastGeocodingError = "Address not found"
                }
                completion(nil)
            }
        }
    }
    
    func reverseGeocode(coordinate: CLLocationCoordinate2D, completion: @escaping (String?) -> Void) {
        DispatchQueue.main.async {
            self.isReverseGeocoding = true
            self.lastGeocodingError = nil
        }
        reverseGeocodeWithRetry(coordinate: coordinate, attempt: 1, completion: completion)
    }
    
    private func reverseGeocodeWithRetry(coordinate: CLLocationCoordinate2D, attempt: Int, completion: @escaping (String?) -> Void) {
        let maxAttempts = 3
        let retryDelay: TimeInterval = Double(attempt) * 2.0 // Progressive delay: 2s, 4s, 6s
        
        let geocoder = CLGeocoder()
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        
        print("🗺️ [Reverse Geocoding] Attempt \(attempt)/\(maxAttempts) for coordinate: (\(coordinate.latitude), \(coordinate.longitude))")
        
        geocoder.reverseGeocodeLocation(location) { [weak self] placemarks, error in
            if let error = error {
                let clError = error as? CLError
                let errorCode = clError?.code.rawValue ?? -1
                
                print("🚨 [Reverse Geocoding] Error: \(error.localizedDescription) (Code: \(errorCode))")
                
                // Handle specific error types
                switch clError?.code {
                case .network:
                    print("🌐 [Reverse Geocoding] Network error - checking retry policy")
                    if attempt < maxAttempts {
                        print("🔄 [Reverse Geocoding] Retrying in \(retryDelay)s (attempt \(attempt + 1)/\(maxAttempts))")
                        DispatchQueue.main.asyncAfter(deadline: .now() + retryDelay) {
                            self?.reverseGeocodeWithRetry(coordinate: coordinate, attempt: attempt + 1, completion: completion)
                        }
                        return
                    } else {
                        print("❌ [Reverse Geocoding] Max network retry attempts reached, using fallback")
                        DispatchQueue.main.async {
                            self?.isReverseGeocoding = false
                            self?.lastGeocodingError = "Network error - using approximate location"
                        }
                        let fallbackAddress = self?.generateFallbackAddress(for: coordinate)
                        completion(fallbackAddress)
                        return
                    }
                case .geocodeFoundNoResult:
                    print("📍 [Reverse Geocoding] No results found for coordinate")
                    DispatchQueue.main.async {
                        self?.isReverseGeocoding = false
                        self?.lastGeocodingError = "Location not found - using approximate address"
                    }
                    let fallbackAddress = self?.generateFallbackAddress(for: coordinate)
                    completion(fallbackAddress)
                    return
                case .geocodeCanceled:
                    print("⏹️ [Reverse Geocoding] Request was canceled")
                    DispatchQueue.main.async {
                        self?.isReverseGeocoding = false
                    }
                    completion(nil)
                    return
                default:
                    print("⚠️ [Reverse Geocoding] Other error: \(error.localizedDescription)")
                    if attempt < maxAttempts {
                        print("🔄 [Reverse Geocoding] Retrying in \(retryDelay)s (attempt \(attempt + 1)/\(maxAttempts))")
                        DispatchQueue.main.asyncAfter(deadline: .now() + retryDelay) {
                            self?.reverseGeocodeWithRetry(coordinate: coordinate, attempt: attempt + 1, completion: completion)
                        }
                        return
                    } else {
                        DispatchQueue.main.async {
                            self?.isReverseGeocoding = false
                            self?.lastGeocodingError = "Using approximate location"
                        }
                        let fallbackAddress = self?.generateFallbackAddress(for: coordinate)
                        completion(fallbackAddress)
                        return
                    }
                }
            }
            
            // Success case
            if let placemark = placemarks?.first {
                let address = self?.formatAddress(from: placemark)
                print("✅ [Reverse Geocoding] Success: \(address ?? "Unknown address")")
                DispatchQueue.main.async {
                    self?.isReverseGeocoding = false
                    self?.lastGeocodingError = nil
                }
                completion(address)
            } else {
                print("📍 [Reverse Geocoding] No placemark found, using fallback")
                DispatchQueue.main.async {
                    self?.isReverseGeocoding = false
                    self?.lastGeocodingError = "Using approximate location"
                }
                let fallbackAddress = self?.generateFallbackAddress(for: coordinate)
                completion(fallbackAddress)
            }
        }
    }
    
    private func formatAddress(from placemark: CLPlacemark) -> String {
        var addressComponents: [String] = []
        
        // Combine street number and street name without comma
        if let subThoroughfare = placemark.subThoroughfare,
           let thoroughfare = placemark.thoroughfare {
            addressComponents.append("\(subThoroughfare) \(thoroughfare)")
        } else if let thoroughfare = placemark.thoroughfare {
            addressComponents.append(thoroughfare)
        }
        
        // Add remaining components with commas
        if let locality = placemark.locality {
            addressComponents.append(locality)
        }
        if let administrativeArea = placemark.administrativeArea {
            addressComponents.append(administrativeArea)
        }
        if let postalCode = placemark.postalCode {
            addressComponents.append(postalCode)
        }
        
        let address = addressComponents.joined(separator: ", ")
        return address.isEmpty ? generateFallbackAddress(for: placemark.location?.coordinate ?? CLLocationCoordinate2D()) : address
    }
    
    private func generateFallbackAddress(for coordinate: CLLocationCoordinate2D) -> String {
        // Create a user-friendly fallback address with approximate location
        let lat = coordinate.latitude
        let lon = coordinate.longitude
        
        // Simple region detection based on coordinates (US-focused)
        var regionName = "Unknown Location"
        
        // US coordinate ranges (approximate)
        if lat >= 24.396308 && lat <= 49.384358 && lon >= -125.0 && lon <= -66.93457 {
            if lat >= 37.0 && lat <= 42.0 && lon >= -124.0 && lon <= -120.0 {
                regionName = "Northern California Area"
            } else if lat >= 32.0 && lat <= 37.0 && lon >= -121.0 && lon <= -117.0 {
                regionName = "Southern California Area"
            } else if lat >= 40.0 && lat <= 45.0 && lon >= -74.5 && lon <= -73.5 {
                regionName = "New York Area"
            } else if lat >= 25.0 && lat <= 31.0 && lon >= -81.0 && lon <= -80.0 {
                regionName = "Florida Area"
            } else if lat >= 32.0 && lat <= 36.0 && lon >= -97.0 && lon <= -94.0 {
                regionName = "Texas Area"
            } else {
                regionName = "United States"
            }
        } else {
            // International coordinates
            regionName = "International Location"
        }
        
        return "Near \(regionName) (Lat: \(String(format: "%.4f", lat)), Lon: \(String(format: "%.4f", lon)))"
    }
    
    func clearLocationState() {
        print("📍 Clearing location manager state...")
        
        DispatchQueue.main.async {
            self.location = nil
            self.hasInitialLocation = false
            // Reset retry counters
            self.locationRequestAttempts = 0
            self.lastLocationRequestTime = nil
            // Reset to default region (San Francisco)
            self.region = MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
                span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
            )
        }
        
        print("✅ Location manager state cleared")
    }
}