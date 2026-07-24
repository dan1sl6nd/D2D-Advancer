import Foundation
import CoreLocation
import MapKit

class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = LocationManager()
    static let initialMapCenterMaxAge: TimeInterval = 180
    static let provisionalInitialMapCenterMaxAge: TimeInterval = 20 * 60
    static let initialMapCenterPreferredHorizontalAccuracy: CLLocationAccuracy = 250
    static let initialMapCenterMaxHorizontalAccuracy: CLLocationAccuracy = 25_000
    static let provisionalInitialMapCenterMaxHorizontalAccuracy: CLLocationAccuracy = 5_000
    static let initialMapCenterDefaultSpanDelta: CLLocationDegrees = 0.01
    static let initialMapCenterMaximumSpanDelta: CLLocationDegrees = 0.18
    static let liveInitialMapCenterTimestampSlack: TimeInterval = 15
    private static let initialMapCenterImprovementRatio: CLLocationAccuracy = 0.5
    private static let initialMapCenterMinimumCoordinateChange: CLLocationDistance = 75
    
    private let locationManager = CLLocationManager()
    @Published var hasInitialLocation = false
    @Published var initialMapCenterRevision = 0
    private var hasLiveInitialLocation = false
    
    @Published var location: CLLocation?
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
        span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
    )
    @Published var shouldUseUserLocation = false // Flag to indicate we should center on user location

    static func shouldShowPermissionPrompt(for status: CLAuthorizationStatus) -> Bool {
        shouldShowPermissionPrompt(for: status, hasKnownLocation: false)
    }

    static func shouldShowPermissionPrompt(for status: CLAuthorizationStatus, hasKnownLocation: Bool) -> Bool {
        switch status {
        case .notDetermined:
            return !hasKnownLocation
        case .denied, .restricted:
            return true
        case .authorizedAlways, .authorizedWhenInUse:
            return false
        @unknown default:
            return !hasKnownLocation
        }
    }

    static func shouldShowPermissionPrompt(
        for status: CLAuthorizationStatus,
        hasKnownLocation: Bool,
        isOnboardingPresented: Bool
    ) -> Bool {
        guard !isOnboardingPresented else { return false }
        return shouldShowPermissionPrompt(for: status, hasKnownLocation: hasKnownLocation)
    }

    static func isAuthorized(_ status: CLAuthorizationStatus) -> Bool {
        status == .authorizedWhenInUse || status == .authorizedAlways
    }

    static func isUsableForInitialMapCenter(_ location: CLLocation, now: Date = Date()) -> Bool {
        guard location.horizontalAccuracy >= 0 else { return false }
        guard now.timeIntervalSince(location.timestamp) <= initialMapCenterMaxAge else { return false }
        return location.horizontalAccuracy <= initialMapCenterMaxHorizontalAccuracy
    }

    static func isUsableForProvisionalInitialMapCenter(_ location: CLLocation, now: Date = Date()) -> Bool {
        guard location.horizontalAccuracy >= 0 else { return false }
        guard now.timeIntervalSince(location.timestamp) <= provisionalInitialMapCenterMaxAge else { return false }
        return location.horizontalAccuracy <= provisionalInitialMapCenterMaxHorizontalAccuracy
    }

    static func shouldApplyProvisionalInitialMapCenter(
        hasInitialLocation: Bool,
        hasProvisionalInitialLocation: Bool,
        isLaunchLocationCenteringActive: Bool,
        candidateLocation: CLLocation,
        now: Date = Date()
    ) -> Bool {
        guard !hasInitialLocation else { return false }
        guard !hasProvisionalInitialLocation else { return false }
        guard isLaunchLocationCenteringActive else { return false }
        guard !isUsableForInitialMapCenter(candidateLocation, now: now) else { return false }
        return isUsableForProvisionalInitialMapCenter(candidateLocation, now: now)
    }

    static func initialMapCenterSpan(for location: CLLocation) -> MKCoordinateSpan {
        guard location.horizontalAccuracy >= 0 else {
            return MKCoordinateSpan(
                latitudeDelta: initialMapCenterDefaultSpanDelta,
                longitudeDelta: initialMapCenterDefaultSpanDelta
            )
        }

        let accuracy = max(location.horizontalAccuracy, initialMapCenterPreferredHorizontalAccuracy)
        let latitudeDelta = min(
            initialMapCenterMaximumSpanDelta,
            max(initialMapCenterDefaultSpanDelta, (accuracy * 4) / 111_000)
        )

        return MKCoordinateSpan(latitudeDelta: latitudeDelta, longitudeDelta: latitudeDelta)
    }

    static func initialMapCenterRegion(for location: CLLocation) -> MKCoordinateRegion {
        MKCoordinateRegion(
            center: location.coordinate,
            span: initialMapCenterSpan(for: location)
        )
    }

    static func isInitialMapCenterRegion(
        _ region: MKCoordinateRegion,
        centeredOn location: CLLocation,
        tolerance: CLLocationDegrees = 0.0001
    ) -> Bool {
        let targetSpan = initialMapCenterSpan(for: location)
        let centerIsCurrent =
            abs(region.center.latitude - location.coordinate.latitude) < tolerance
            && abs(region.center.longitude - location.coordinate.longitude) < tolerance
        let spanIsCurrent =
            abs(region.span.latitudeDelta - targetSpan.latitudeDelta) < tolerance
            && abs(region.span.longitudeDelta - targetSpan.longitudeDelta) < tolerance
        return centerIsCurrent && spanIsCurrent
    }

    static func shouldApplyCachedAuthorizationRefreshLocation(
        startIfAuthorized: Bool,
        isLaunchLocationCenteringActive: Bool
    ) -> Bool {
        startIfAuthorized || isLaunchLocationCenteringActive
    }

    static func bestLaunchMapCenterCandidate(from locations: [CLLocation], now: Date = Date()) -> CLLocation? {
        let candidates = locations.filter { location in
            CLLocationCoordinate2DIsValid(location.coordinate)
                && location.horizontalAccuracy >= 0
        }

        let initialCandidates = candidates.filter { isUsableForInitialMapCenter($0, now: now) }
        if let bestInitialCandidate = bestLocationCandidate(from: initialCandidates, now: now) {
            return bestInitialCandidate
        }

        let provisionalCandidates = candidates.filter { isUsableForProvisionalInitialMapCenter($0, now: now) }
        return bestLocationCandidate(from: provisionalCandidates, now: now)
    }

    static func locationForLaunchMapUpdate(
        deliveredLocations: [CLLocation],
        currentLocation: CLLocation?,
        managerLocation: CLLocation?,
        isLaunchLocationCenteringActive: Bool,
        now: Date = Date()
    ) -> CLLocation? {
        if isLaunchLocationCenteringActive {
            let launchCandidates = deliveredLocations + [currentLocation, managerLocation].compactMap { $0 }
            if let bestLaunchCandidate = bestLaunchMapCenterCandidate(from: launchCandidates, now: now) {
                return bestLaunchCandidate
            }
        }

        return deliveredLocations.last
    }

    private static func bestLocationCandidate(from locations: [CLLocation], now: Date) -> CLLocation? {
        locations.reduce(nil) { best, candidate in
            guard let best else { return candidate }
            return shouldPreferLaunchMapCenterCandidate(candidate, over: best, now: now) ? candidate : best
        }
    }

    static func shouldPreferLaunchMapCenterCandidate(
        _ candidate: CLLocation,
        over current: CLLocation,
        now: Date = Date()
    ) -> Bool {
        let candidateAge = now.timeIntervalSince(candidate.timestamp)
        let currentAge = now.timeIntervalSince(current.timestamp)
        let candidateIsNewer = candidate.timestamp > current.timestamp
        let candidateIsMeaningfullyFar = current.distance(from: candidate) > max(
            initialMapCenterMinimumCoordinateChange,
            current.horizontalAccuracy + candidate.horizontalAccuracy
        )

        if candidateIsNewer && candidateIsMeaningfullyFar {
            return true
        }

        let currentIsNewerAndFar = current.timestamp > candidate.timestamp && candidateIsMeaningfullyFar
        if currentIsNewerAndFar {
            return false
        }

        let candidateIsMuchMoreAccurate = candidate.horizontalAccuracy <= current.horizontalAccuracy * initialMapCenterImprovementRatio
        let currentIsMuchMoreAccurate = current.horizontalAccuracy <= candidate.horizontalAccuracy * initialMapCenterImprovementRatio

        if candidateIsMuchMoreAccurate {
            return true
        }
        if currentIsMuchMoreAccurate {
            return false
        }

        if candidateAge != currentAge {
            return candidateAge < currentAge
        }

        return candidate.horizontalAccuracy < current.horizontalAccuracy
    }

    static func shouldAttemptInitialMapCenter(
        hasInitialLocation: Bool,
        wasFirstLocation: Bool,
        isLaunchLocationCenteringActive: Bool,
        previousLocation: CLLocation?,
        candidateLocation: CLLocation
    ) -> Bool {
        if !hasInitialLocation || wasFirstLocation {
            return true
        }

        if isLaunchLocationCenteringActive {
            return isMeaningfulInitialMapCenterImprovement(
                previousLocation: previousLocation,
                candidateLocation: candidateLocation
            )
        }

        return isMeaningfulInitialMapCenterImprovement(
            previousLocation: previousLocation,
            candidateLocation: candidateLocation
        )
    }

    private static func isMeaningfulInitialMapCenterImprovement(
        previousLocation: CLLocation?,
        candidateLocation: CLLocation
    ) -> Bool {
        guard candidateLocation.horizontalAccuracy >= 0 else { return false }
        guard let previousLocation, previousLocation.horizontalAccuracy >= 0 else { return true }

        let coordinateChangeThreshold = max(
            initialMapCenterMinimumCoordinateChange,
            previousLocation.horizontalAccuracy + candidateLocation.horizontalAccuracy
        )
        let candidateIsClearlyNewerPlace = candidateLocation.timestamp > previousLocation.timestamp
            && previousLocation.distance(from: candidateLocation) > coordinateChangeThreshold

        // Once the map has a genuinely usable GPS fix, do not keep recentering
        // while the user is working. Still allow a clearly different newer
        // place so a cached launch fix cannot trap the map on the wrong area.
        guard previousLocation.horizontalAccuracy > initialMapCenterPreferredHorizontalAccuracy else {
            return candidateIsClearlyNewerPlace
        }

        let candidateIsPreferred = candidateLocation.horizontalAccuracy <= initialMapCenterPreferredHorizontalAccuracy
        let candidateIsMuchBetter = candidateLocation.horizontalAccuracy <= previousLocation.horizontalAccuracy * initialMapCenterImprovementRatio

        return candidateIsPreferred || candidateIsMuchBetter || candidateIsClearlyNewerPlace
    }

    static func shouldStartLocationRequest(
        isRequestInFlight: Bool,
        locationRequestAttempts: Int,
        maxLocationRequestAttempts: Int,
        lastLocationRequestTime: Date?,
        locationRequestCooldown: TimeInterval,
        isLaunchLocationCenteringActive: Bool,
        now: Date = Date()
    ) -> Bool {
        guard !isRequestInFlight else { return false }
        guard locationRequestAttempts < maxLocationRequestAttempts else { return false }

        if isLaunchLocationCenteringActive {
            return true
        }

        if let lastLocationRequestTime,
           now.timeIntervalSince(lastLocationRequestTime) < locationRequestCooldown {
            return false
        }

        return true
    }

    static func shouldClearStaleLocationRequest(
        isRequestInFlight: Bool,
        lastLocationRequestTime: Date?,
        staleTimeout: TimeInterval,
        isLaunchLocationCenteringActive: Bool,
        now: Date = Date()
    ) -> Bool {
        guard isRequestInFlight else { return false }
        guard isLaunchLocationCenteringActive else { return false }
        guard let lastLocationRequestTime else { return false }
        return now.timeIntervalSince(lastLocationRequestTime) >= staleTimeout
    }

    static func shouldRetryLaunchLocationRequest(
        isLaunchLocationCenteringActive: Bool,
        hasLiveInitialLocation: Bool
    ) -> Bool {
        isLaunchLocationCenteringActive && !hasLiveInitialLocation
    }

    static func shouldRunStaleLaunchLocationRequestWatchdog(
        isRequestInFlight: Bool,
        lastLocationRequestTime: Date?,
        watchedRequestStartedAt: Date?,
        staleTimeout: TimeInterval,
        isLaunchLocationCenteringActive: Bool,
        hasLiveInitialLocation: Bool,
        now: Date = Date()
    ) -> Bool {
        guard shouldRetryLaunchLocationRequest(
            isLaunchLocationCenteringActive: isLaunchLocationCenteringActive,
            hasLiveInitialLocation: hasLiveInitialLocation
        ) else { return false }
        guard isRequestInFlight else { return false }
        guard let lastLocationRequestTime, let watchedRequestStartedAt else { return false }
        guard lastLocationRequestTime == watchedRequestStartedAt else { return false }
        return now.timeIntervalSince(lastLocationRequestTime) >= staleTimeout
    }

    static func isLiveForLaunchInitialMapCenter(
        _ location: CLLocation,
        launchStartedAt: Date?,
        now: Date = Date()
    ) -> Bool {
        guard isUsableForInitialMapCenter(location, now: now) else { return false }
        guard let launchStartedAt else {
            return now.timeIntervalSince(location.timestamp) <= liveInitialMapCenterTimestampSlack
        }

        return location.timestamp >= launchStartedAt.addingTimeInterval(-liveInitialMapCenterTimestampSlack)
    }
    
    // Geocoding status indicators
    @Published var isReverseGeocoding = false
    @Published var isForwardGeocoding = false
    @Published var lastGeocodingError: String?
    
    // Rate limiting for location requests
    private var lastLocationRequestTime: Date?
    private var locationRequestAttempts: Int = 0
    private var isLocationRequestInFlight = false
    private let maxLocationRequestAttempts = 3
    private let locationRequestCooldown: TimeInterval = 10.0 // 10 seconds between requests
    private let launchLocationCenteringDuration: TimeInterval = 60.0
    private let staleLaunchLocationRequestTimeout: TimeInterval = 8.0
    private var launchLocationCenteringExpiresAt: Date?
    private var launchLocationCenteringStartedAt: Date?
    private var launchLocationCenteringEndWorkItem: DispatchWorkItem?
    private var launchLocationRequestWatchdogWorkItem: DispatchWorkItem?
    private var hasProvisionalInitialLocation = false
    
    private override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.distanceFilter = 10 // Update every 10 meters
        authorizationStatus = locationManager.authorizationStatus

        print("LocationManager: Initializing - current status: \(authorizationStatus)")

        if authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways {
            print("LocationManager: Already authorized - waiting for app startup to begin launch centering")
        } else if authorizationStatus == .notDetermined {
            print("LocationManager: Permission not determined - will be requested by onboarding or MainTabView after onboarding completes")
        }
    }

    func refreshAuthorizationStatusFromSystem(startIfAuthorized: Bool = true) {
        authorizationStatus = locationManager.authorizationStatus
        if Self.isAuthorized(authorizationStatus) {
            if Self.shouldApplyCachedAuthorizationRefreshLocation(
                startIfAuthorized: startIfAuthorized,
                isLaunchLocationCenteringActive: isLaunchLocationCenteringActive
            ) {
                adoptCachedLaunchLocationIfAvailable(reason: "system cached authorization refresh location")
            } else {
                cacheBestLaunchLocationIfAvailable()
            }

            if startIfAuthorized {
                startLocationUpdates()
                requestImmediateLocation()
            }
        }
    }
    
    private func shouldRequestLocation() -> Bool {
        if Self.shouldClearStaleLocationRequest(
            isRequestInFlight: isLocationRequestInFlight,
            lastLocationRequestTime: lastLocationRequestTime,
            staleTimeout: staleLaunchLocationRequestTimeout,
            isLaunchLocationCenteringActive: isLaunchLocationCenteringActive
        ) {
            print("LocationManager: Clearing stale launch location request")
            isLocationRequestInFlight = false
        }

        if isLocationRequestInFlight {
            print("LocationManager: Location request already in flight")
            return false
        }

        // If we want to use user location (app launch), be more lenient with rate limiting
        if isLaunchLocationCenteringActive {
            if locationRequestAttempts >= maxLocationRequestAttempts {
                print("LocationManager: Initial location request attempts reached (\(maxLocationRequestAttempts))")
                return false
            }
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
        guard shouldRequestLocation(),
              Self.shouldStartLocationRequest(
                isRequestInFlight: isLocationRequestInFlight,
                locationRequestAttempts: locationRequestAttempts,
                maxLocationRequestAttempts: maxLocationRequestAttempts,
                lastLocationRequestTime: lastLocationRequestTime,
                locationRequestCooldown: locationRequestCooldown,
                isLaunchLocationCenteringActive: isLaunchLocationCenteringActive
              ) else { return }
        
        lastLocationRequestTime = Date()
        locationRequestAttempts += 1
        isLocationRequestInFlight = true
        
        print("LocationManager: Making location request (attempt \(locationRequestAttempts)/\(maxLocationRequestAttempts))")
        locationManager.requestLocation()
        scheduleLaunchLocationRequestWatchdog()
    }

    private func markLocationRequestFinished() {
        let finish = {
            self.isLocationRequestInFlight = false
            self.launchLocationRequestWatchdogWorkItem?.cancel()
            self.launchLocationRequestWatchdogWorkItem = nil
        }

        if Thread.isMainThread {
            finish()
        } else {
            DispatchQueue.main.async(execute: finish)
        }
    }
    
    func resetLocationRequestRetries() {
        let reset = {
            self.locationRequestAttempts = 0
            self.lastLocationRequestTime = nil
            print("LocationManager: Location request retry counter reset")
        }

        if Thread.isMainThread {
            reset()
        } else {
            DispatchQueue.main.async(execute: reset)
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

    func startLaunchLocationCentering() {
        let start = {
            guard Self.isAuthorized(self.authorizationStatus) else {
                print("LocationManager: Cannot prepare launch centering - no permission")
                return
            }

            let cachedLaunchCandidate = self.bestCachedLaunchLocation()
            let alreadyCenteredOnCandidate = cachedLaunchCandidate.map {
                self.hasInitialLocation && Self.isInitialMapCenterRegion(self.region, centeredOn: $0)
            } ?? false

            self.beginLaunchLocationCenteringWindow()
            if !alreadyCenteredOnCandidate {
                self.hasInitialLocation = false
                self.hasLiveInitialLocation = false
                self.hasProvisionalInitialLocation = false
            }
            self.locationRequestAttempts = 0
            self.lastLocationRequestTime = nil
            self.startLocationUpdates()

            self.adoptCachedLaunchLocationIfAvailable(reason: "cached launch location")
            if !self.hasLiveInitialLocation {
                self.makeLocationRequest()
            }
        }

        if Thread.isMainThread {
            start()
        } else {
            DispatchQueue.main.async(execute: start)
        }
    }
    
    func centerOnUserLocation() {
        DispatchQueue.main.async {
            if let location = self.location {
                self.region = MKCoordinateRegion(
                    center: location.coordinate,
                    span: Self.initialMapCenterSpan(for: location)
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
            guard Self.isUsableForInitialMapCenter(location) else {
                startLaunchLocationCentering()
                return
            }
            applyInitialMapCenter(location, reason: "cached location")
        } else {
            startLaunchLocationCentering()
        }
    }

    func applyLaunchMapCenter(_ location: CLLocation, reason: String = "launch location") {
        applyInitialMapCenter(location, reason: reason)
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard !locations.isEmpty else { return }

        DispatchQueue.main.async {
            guard let location = Self.locationForLaunchMapUpdate(
                deliveredLocations: locations,
                currentLocation: self.location,
                managerLocation: manager.location,
                isLaunchLocationCenteringActive: self.isLaunchLocationCenteringActive
            ) else { return }
            let previousLocation = self.location
            let wasFirstLocation = previousLocation == nil
            let isLiveInitialLocation = Self.isLiveForLaunchInitialMapCenter(
                location,
                launchStartedAt: self.launchLocationCenteringStartedAt
            )
            self.location = location
            self.isLocationRequestInFlight = false
            self.launchLocationRequestWatchdogWorkItem?.cancel()
            self.launchLocationRequestWatchdogWorkItem = nil
            if isLiveInitialLocation {
                self.hasLiveInitialLocation = true
            }
            
            if !self.isLaunchLocationCenteringActive || isLiveInitialLocation {
                self.locationRequestAttempts = 0
                self.lastLocationRequestTime = nil
            }
            
            // Always update region for startup location work, and keep replacing
            // a rough startup center when a much better GPS fix arrives later.
            if Self.shouldAttemptInitialMapCenter(
                hasInitialLocation: self.hasInitialLocation,
                wasFirstLocation: wasFirstLocation,
                isLaunchLocationCenteringActive: self.isLaunchLocationCenteringActive,
                previousLocation: previousLocation,
                candidateLocation: location
            ) {
                guard Self.isUsableForInitialMapCenter(location) else {
                    if Self.shouldApplyProvisionalInitialMapCenter(
                        hasInitialLocation: self.hasInitialLocation,
                        hasProvisionalInitialLocation: self.hasProvisionalInitialLocation,
                        isLaunchLocationCenteringActive: self.isLaunchLocationCenteringActive,
                        candidateLocation: location
                    ) {
                        self.applyProvisionalInitialMapCenter(location, reason: "provisional initial location")
                    }

                    self.hasInitialLocation = false
                    self.beginLaunchLocationCenteringWindow()
                    print("LocationManager: Ignoring stale or inaccurate initial location (age: \(Int(Date().timeIntervalSince(location.timestamp)))s, accuracy: \(Int(location.horizontalAccuracy))m)")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        if self.isLaunchLocationCenteringActive && !self.hasInitialLocation {
                            self.makeLocationRequest()
                        }
                    }
                    return
                }

                let reason = isLiveInitialLocation ? "live initial location" : "cached initial location"
                self.applyInitialMapCenter(location, reason: reason, isLiveFix: isLiveInitialLocation)
                if !isLiveInitialLocation {
                    self.retryLaunchLocationRequestIfNeeded()
                }
            }
        }
    }

    private func applyInitialMapCenter(_ location: CLLocation, reason: String, isLiveFix: Bool = false) {
        applyMapCenter(location, reason: reason, isProvisional: false, isLiveFix: isLiveFix)
    }

    private func applyProvisionalInitialMapCenter(_ location: CLLocation, reason: String) {
        hasProvisionalInitialLocation = true
        applyMapCenter(location, reason: reason, isProvisional: true, isLiveFix: false)
    }

    @discardableResult
    private func adoptCachedLaunchLocationIfAvailable(reason: String) -> Bool {
        guard let candidate = bestCachedLaunchLocation() else {
            if let location = candidates.sorted(by: { $0.timestamp > $1.timestamp }).first {
                print("LocationManager: Ignoring stale or inaccurate cached launch location (age: \(Int(Date().timeIntervalSince(location.timestamp)))s, accuracy: \(Int(location.horizontalAccuracy))m)")
            }
            return false
        }

        location = candidate

        if isAlreadyCenteredOnLaunchCandidate(candidate) {
            return false
        }

        if Self.isUsableForInitialMapCenter(candidate) {
            applyInitialMapCenter(
                candidate,
                reason: reason,
                isLiveFix: Self.isLiveForLaunchInitialMapCenter(
                    candidate,
                    launchStartedAt: launchLocationCenteringStartedAt
                )
            )
            return true
        }

        if Self.shouldApplyProvisionalInitialMapCenter(
            hasInitialLocation: hasInitialLocation,
            hasProvisionalInitialLocation: hasProvisionalInitialLocation,
            isLaunchLocationCenteringActive: isLaunchLocationCenteringActive,
            candidateLocation: candidate
        ) {
            applyProvisionalInitialMapCenter(candidate, reason: "provisional \(reason)")
            return true
        }

        return false
    }

    private var candidates: [CLLocation] {
        [location, locationManager.location].compactMap { $0 }
    }

    private func bestCachedLaunchLocation() -> CLLocation? {
        Self.bestLaunchMapCenterCandidate(from: candidates)
    }

    @discardableResult
    private func cacheBestLaunchLocationIfAvailable() -> Bool {
        guard let candidate = bestCachedLaunchLocation() else { return false }
        location = candidate
        return true
    }

    private func isAlreadyCenteredOnLaunchCandidate(_ location: CLLocation) -> Bool {
        guard hasInitialLocation else { return false }
        return Self.isInitialMapCenterRegion(region, centeredOn: location)
    }

    private func applyMapCenter(_ location: CLLocation, reason: String, isProvisional: Bool, isLiveFix: Bool) {
        let newRegion = Self.initialMapCenterRegion(for: location)
        region = newRegion
        if !isProvisional {
            hasInitialLocation = true
            hasProvisionalInitialLocation = false
            if isLiveFix {
                hasLiveInitialLocation = true
            }
        }
        initialMapCenterRevision += 1
        let marker = isProvisional ? "📍" : "✅"
        print("LocationManager: \(marker) \(reason) received and map centered on \(location.coordinate)")

        if isLaunchLocationCenteringActive {
            print("LocationManager: 🎯 Keeping launch centering active for better GPS fixes")
        }
    }

    private var isLaunchLocationCenteringActive: Bool {
        guard shouldUseUserLocation else { return false }
        guard let expiresAt = launchLocationCenteringExpiresAt else { return true }
        return Date() <= expiresAt
    }

    private func beginLaunchLocationCenteringWindow() {
        shouldUseUserLocation = true
        launchLocationCenteringStartedAt = Date()
        launchLocationCenteringExpiresAt = Date().addingTimeInterval(launchLocationCenteringDuration)
        launchLocationCenteringEndWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.shouldUseUserLocation = false
            self.launchLocationCenteringExpiresAt = nil
            self.launchLocationCenteringStartedAt = nil
            print("LocationManager: 🎯 Launch centering window ended")
        }

        launchLocationCenteringEndWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + launchLocationCenteringDuration, execute: workItem)
    }

    private func scheduleLaunchLocationRequestWatchdog() {
        guard isLaunchLocationCenteringActive else { return }

        let watchedRequestStartedAt = lastLocationRequestTime
        launchLocationRequestWatchdogWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            guard Self.shouldRunStaleLaunchLocationRequestWatchdog(
                isRequestInFlight: self.isLocationRequestInFlight,
                lastLocationRequestTime: self.lastLocationRequestTime,
                watchedRequestStartedAt: watchedRequestStartedAt,
                staleTimeout: self.staleLaunchLocationRequestTimeout,
                isLaunchLocationCenteringActive: self.isLaunchLocationCenteringActive,
                hasLiveInitialLocation: self.hasLiveInitialLocation
            ) else { return }

            print("LocationManager: 🔄 Launch location request stalled, retrying")
            self.isLocationRequestInFlight = false
            self.makeLocationRequest()
        }

        launchLocationRequestWatchdogWorkItem = workItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + staleLaunchLocationRequestTimeout + 0.25,
            execute: workItem
        )
    }
    
    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        DispatchQueue.main.async {
            self.authorizationStatus = status
            
            switch status {
            case .authorizedWhenInUse, .authorizedAlways:
                print("LocationManager: 🎉 Permission granted, starting location updates and requesting immediate location")
                self.startLaunchLocationCentering()

                // Also start continuous updates for faster initial location
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    if !self.hasLiveInitialLocation {
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
        markLocationRequestFinished()

        if let clError = error as? CLError {
            switch clError.code {
            case .denied:
                print("LocationManager: Location access denied by user")
            case .locationUnknown:
                print("LocationManager: Location service unable to determine location")
                retryLaunchLocationRequestIfNeeded()
            case .network:
                ErrorHandler.shared.handle(error, context: "Location Network")
                retryLaunchLocationRequestIfNeeded()
            default:
                print("LocationManager: Non-blocking location service error: \(error.localizedDescription)")
                retryLaunchLocationRequestIfNeeded()
            }
        } else {
            print("LocationManager: Non-blocking location error: \(error.localizedDescription)")
            retryLaunchLocationRequestIfNeeded()
        }
    }

    private func retryLaunchLocationRequestIfNeeded() {
        guard Self.shouldRetryLaunchLocationRequest(
            isLaunchLocationCenteringActive: isLaunchLocationCenteringActive,
            hasLiveInitialLocation: hasLiveInitialLocation
        ) else { return }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            guard Self.shouldRetryLaunchLocationRequest(
                isLaunchLocationCenteringActive: self.isLaunchLocationCenteringActive,
                hasLiveInitialLocation: self.hasLiveInitialLocation
            ) else { return }
            print("LocationManager: 🔄 Retrying launch location request")
            self.makeLocationRequest()
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
        
        print("🗺️ [Forward Geocoding] Attempt \(attempt)/\(maxAttempts) for address: \(Utilities.redactedText(address))")
        
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
                    print("📍 [Forward Geocoding] No results found for address: \(Utilities.redactedText(address))")
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
                print("📍 [Forward Geocoding] No placemark found for address: \(Utilities.redactedText(address))")
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
                let redacted = address.map { Utilities.redactedText($0) } ?? "Unknown address"
                print("✅ [Reverse Geocoding] Success: \(redacted)")
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
            self.hasLiveInitialLocation = false
            self.isLocationRequestInFlight = false
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
