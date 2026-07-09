import SwiftUI
import MapKit
import UIKit
import CoreData

struct AdvancedMapView: UIViewRepresentable {
    @Binding var region: MKCoordinateRegion
    @Binding var mapType: MKMapType
    @Binding var rotation: Double
    @Binding var pitch: Double
    @Binding var animateNextUpdate: Bool
    @Binding var is3DModeEnabled: Bool
    @Binding var visibleRegion: MKCoordinateRegion
    let launchCenteringResetToken: Int
    let launchLocationCenterRevision: Int

    let leads: [MapLeadPin]
    let isVisible: Bool
    @Binding var searchPin: SearchPin?
    let showsUserLocation: Bool
    let shouldFollowUserLocationOnLaunch: Bool
    let needsLaunchLocationCenteringConfirmation: Bool
    let hasLaunchLocationCandidate: Bool
    let onLaunchCenteringConfirmed: () -> Void
    let onLeadTap: (MapLeadPin) -> Void
    let onLeadClusterTap: ([MapLeadPin], CLLocationCoordinate2D) -> Void
    let onSearchPinTap: (SearchPin) -> Void
    let onLongPress: (CLLocationCoordinate2D?, MapLeadPin?) -> Void

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.showsUserLocation = showsUserLocation
        mapView.userTrackingMode = .none
        mapView.mapType = Self.renderedMapType(for: mapType, is3DModeEnabled: is3DModeEnabled)
        mapView.showsBuildings = Self.shouldShowBuildings(for: mapType, is3DModeEnabled: is3DModeEnabled)
        mapView.showsCompass = false // Hide default compass to avoid overlap with controls
        // Keep expensive 3D imagery opt-in so Satellite/Hybrid stay responsive.
        mapView.isRotateEnabled = true
        mapView.isPitchEnabled = Self.allowsPitch(is3DModeEnabled: is3DModeEnabled)

        let shouldFollowLaunchLocation = Self.shouldCenterUserLocationOnLaunch(
            showsUserLocation: showsUserLocation,
            shouldUseUserLocation: shouldFollowUserLocationOnLaunch,
            needsLaunchLocationCenteringConfirmation: needsLaunchLocationCenteringConfirmation,
            userHasInteracted: context.coordinator.userHasInteracted
        )
        Self.updateUserLocationLayoutMargins(
            on: mapView,
            isLaunchCenteringActive: shouldFollowLaunchLocation
        )

        // Set initial region (mark as programmatic to prevent sync-back)
        context.coordinator.isProgrammaticChange = true
        Self.applyMapRegion(
            region,
            to: mapView,
            animated: false,
            respectingVisibleControls: false
        )
        context.coordinator.lastAppliedStartupTargetRegion = region
        context.coordinator.lastAppliedStartupTargetRespectsVisibleControls = false

        // Add custom compass button positioned below the overlay controls
        let compassButton = MKCompassButton(mapView: mapView)
        compassButton.compassVisibility = .adaptive
        compassButton.translatesAutoresizingMaskIntoConstraints = false
        mapView.addSubview(compassButton)
        NSLayoutConstraint.activate([
            // Position below the SwiftUI overlay buttons (5 × 42pt + 4 × 10pt = 250pt, starting at safeArea+4)
            compassButton.topAnchor.constraint(equalTo: mapView.safeAreaLayoutGuide.topAnchor, constant: 272),
            // Align with SwiftUI overlay's .padding(.horizontal, 16)
            compassButton.trailingAnchor.constraint(equalTo: mapView.safeAreaLayoutGuide.trailingAnchor, constant: -16)
        ])

        // Add long press gesture
        let longPressGesture = UILongPressGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleLongPress(_:))
        )
        longPressGesture.minimumPressDuration = 0.5
        mapView.addGestureRecognizer(longPressGesture)

        return mapView
    }
    
    func updateUIView(_ mapView: MKMapView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self

        guard isVisible else {
            if mapView.showsUserLocation {
                mapView.showsUserLocation = false
            }
            coordinator.suspendHiddenAnnotationWork(mapView: mapView)
            return
        }

        if Self.shouldResetLaunchInteractionLock(
            previousToken: coordinator.lastLaunchCenteringResetToken,
            currentToken: launchCenteringResetToken
        ) {
            coordinator.lastLaunchCenteringResetToken = launchCenteringResetToken
            coordinator.userHasInteracted = false
            coordinator.isUserInteracting = false
            coordinator.lastAppliedStartupTargetRegion = nil
            coordinator.lastAppliedStartupTargetRespectsVisibleControls = false
            coordinator.hasAppliedFirstVisibleUserLocationCenter = false
            coordinator.resetStartupCenterVerification()
        }

        if Self.shouldForceStartupRegionUpdate(
            previousRevision: coordinator.lastLaunchLocationCenterRevision,
            currentRevision: launchLocationCenterRevision,
            showsUserLocation: showsUserLocation,
            shouldUseUserLocation: shouldFollowUserLocationOnLaunch,
            userHasInteracted: coordinator.userHasInteracted
        ) {
            coordinator.lastLaunchLocationCenterRevision = launchLocationCenterRevision
            coordinator.userHasInteracted = false
            coordinator.isUserInteracting = false
            coordinator.lastAppliedStartupTargetRegion = nil
            coordinator.lastAppliedStartupTargetRespectsVisibleControls = false
            coordinator.hasAppliedFirstVisibleUserLocationCenter = false
            coordinator.resetStartupCenterVerification()
        } else if coordinator.lastLaunchLocationCenterRevision != launchLocationCenterRevision {
            coordinator.lastLaunchLocationCenterRevision = launchLocationCenterRevision
        }

        let effectiveMapType = Self.renderedMapType(for: mapType, is3DModeEnabled: is3DModeEnabled)
        let didToggle3DMode = coordinator.last3DModeEnabled != nil && coordinator.last3DModeEnabled != is3DModeEnabled
        coordinator.last3DModeEnabled = is3DModeEnabled

        coordinator.lastEffectiveMapType = effectiveMapType

        // Update map type if changed
        if mapView.mapType != effectiveMapType {
            mapView.mapType = effectiveMapType
        }

        let pitchEnabled = Self.allowsPitch(is3DModeEnabled: is3DModeEnabled)
        if mapView.isPitchEnabled != pitchEnabled {
            mapView.isPitchEnabled = pitchEnabled
        }
        mapView.isRotateEnabled = true

        let showsBuildings = Self.shouldShowBuildings(for: effectiveMapType, is3DModeEnabled: is3DModeEnabled)
        if mapView.showsBuildings != showsBuildings {
            mapView.showsBuildings = showsBuildings
        }

        if mapView.showsUserLocation != showsUserLocation {
            mapView.showsUserLocation = showsUserLocation
        }

        let shouldFollowUser = Self.shouldCenterUserLocationOnLaunch(
            showsUserLocation: showsUserLocation,
            shouldUseUserLocation: shouldFollowUserLocationOnLaunch,
            needsLaunchLocationCenteringConfirmation: needsLaunchLocationCenteringConfirmation,
            userHasInteracted: coordinator.userHasInteracted
        )
        Self.updateUserLocationLayoutMargins(
            on: mapView,
            isLaunchCenteringActive: shouldFollowUser
        )
        var didApplyStartupRegionUpdate = false
        var startupVerificationTargetRegion = region
        var startupVerificationRespectsVisibleControls = false
        let shouldRespectVisibleControls = Self.shouldRespectVisibleControlsForStartupCentering(
            showsUserLocation: showsUserLocation,
            shouldFollowUserLocationOnLaunch: shouldFollowUser,
            needsLaunchLocationCenteringConfirmation: needsLaunchLocationCenteringConfirmation
        )
        let shouldReapplyStartupRegionForVisibleControls = shouldRespectVisibleControls
            && !coordinator.lastAppliedStartupTargetRespectsVisibleControls
            && mapView.bounds.width > 1
            && mapView.bounds.height > 1

        if didToggle3DMode {
            let targetPitch = is3DModeEnabled ? min(max(pitch, 45), Self.maximumPitch(for: effectiveMapType)) : 0
            let targetDistance = is3DModeEnabled ? min(mapView.camera.altitude, regionToDistance(mapView.region)) : mapView.camera.altitude
            coordinator.isProgrammaticChange = true
            let camera = MKMapCamera(
                lookingAtCenter: mapView.camera.centerCoordinate,
                fromDistance: targetDistance,
                pitch: targetPitch,
                heading: mapView.camera.heading
            )
            mapView.setCamera(camera, animated: true)
            DispatchQueue.main.async {
                self.pitch = targetPitch
            }
        } else if is3DModeEnabled {
            let maxPitch = Self.maximumPitch(for: effectiveMapType)
            if mapView.camera.pitch > maxPitch {
                coordinator.isProgrammaticChange = true
                let camera = MKMapCamera(
                    lookingAtCenter: mapView.camera.centerCoordinate,
                    fromDistance: mapView.camera.altitude,
                    pitch: maxPitch,
                    heading: mapView.camera.heading
                )
                mapView.setCamera(camera, animated: true)
                DispatchQueue.main.async {
                    self.pitch = maxPitch
                }
            }
        }
        
        // Handle explicit center action (center button pressed)
        if animateNextUpdate {
            DispatchQueue.main.async {
                animateNextUpdate = false
            }
            coordinator.isProgrammaticChange = true

            let cameraPitch = is3DModeEnabled ? min(pitch, Self.maximumPitch(for: effectiveMapType)) : 0
            if rotation != 0 || cameraPitch != 0 {
                let distance = regionToDistance(region)
                let camera = MKMapCamera(
                    lookingAtCenter: region.center,
                    fromDistance: distance,
                    pitch: cameraPitch,
                    heading: rotation
                )
                mapView.setCamera(camera, animated: true)
            } else {
                Self.applyMapRegion(
                    region,
                    to: mapView,
                    animated: true,
                    respectingVisibleControls: showsUserLocation
                )
            }
        }
        // Keep accepting programmatic startup/location regions until the user
        // actually pans or zooms the map. The first MKMapView region is often a
        // placeholder, and the real location can arrive after makeUIView.
        else if Self.shouldApplyStartupRegionUpdate(
            currentRegion: mapView.region,
            targetRegion: region,
            userHasInteracted: coordinator.userHasInteracted,
            shouldFollowUserLocationOnLaunch: shouldFollowUser,
            lastAppliedStartupTargetRegion: coordinator.lastAppliedStartupTargetRegion
        ) || shouldReapplyStartupRegionForVisibleControls {
            coordinator.isProgrammaticChange = true
            coordinator.hasSetInitialRegion = true
            coordinator.lastAppliedStartupTargetRegion = region
            coordinator.lastAppliedStartupTargetRespectsVisibleControls = shouldRespectVisibleControls
            Self.applyMapRegion(
                region,
                to: mapView,
                animated: false,
                respectingVisibleControls: shouldRespectVisibleControls
            )
            didApplyStartupRegionUpdate = true
            startupVerificationTargetRegion = region
            startupVerificationRespectsVisibleControls = shouldRespectVisibleControls
        } else if let userRegion = coordinator.applyVisibleUserLocationFallbackIfNeeded(
            mapView: mapView,
            shouldFollowUserLocationOnLaunch: shouldFollowUser,
            allowFirstVisibleUserLocationCenter: showsUserLocation,
            respectingVisibleControls: true
        ) {
            didApplyStartupRegionUpdate = true
            startupVerificationTargetRegion = userRegion
            startupVerificationRespectsVisibleControls = true
        }

        if mapView.userTrackingMode == .follow {
            mapView.setUserTrackingMode(.none, animated: false)
        }

        if didApplyStartupRegionUpdate || shouldFollowUser {
            coordinator.scheduleStartupCenterVerification(
                mapView: mapView,
                targetRegion: startupVerificationTargetRegion,
                shouldFollowUserLocationOnLaunch: shouldFollowUser,
                targetHasUserLocation: hasLaunchLocationCandidate,
                respectingVisibleControls: startupVerificationRespectsVisibleControls
            )
        }

        coordinator.updateAnnotationsIfNeeded(mapView: mapView, leads: leads)
        coordinator.updateSearchPin(mapView: mapView, searchPin: searchPin)
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    private func regionToDistance(_ region: MKCoordinateRegion) -> CLLocationDistance {
        let center = CLLocation(latitude: region.center.latitude, longitude: region.center.longitude)
        let edge = CLLocation(
            latitude: region.center.latitude + region.span.latitudeDelta / 2,
            longitude: region.center.longitude
        )
        let distance = center.distance(from: edge) * 2.5 // Multiply by 2.5 for better viewing distance
        return max(distance, 1000) // Minimum 1km distance
    }

    private static func updateUserLocationLayoutMargins(on mapView: MKMapView, isLaunchCenteringActive: Bool) {
        let margins = mapKitLayoutMargins(
            forHeight: max(mapView.bounds.height, UIScreen.main.bounds.height),
            isLaunchCenteringActive: isLaunchCenteringActive
        )
        guard mapView.layoutMargins != margins else { return }
        mapView.layoutMargins = margins
    }

    private static func applyMapRegion(
        _ region: MKCoordinateRegion,
        to mapView: MKMapView,
        animated: Bool,
        respectingVisibleControls: Bool
    ) {
        guard respectingVisibleControls else {
            mapView.setRegion(region, animated: animated)
            return
        }

        mapView.setRegion(
            visibleControlAdjustedRegion(
                for: region,
                in: mapView.bounds,
                padding: userLocationViewportPadding(for: mapView)
            ),
            animated: animated
        )
    }

    private static func userLocationViewportPadding(for mapView: MKMapView) -> UIEdgeInsets {
        userLocationViewportPadding(
            forHeight: max(mapView.bounds.height, UIScreen.main.bounds.height),
            isLaunchCenteringActive: false
        )
    }

    nonisolated static func userLocationViewportPadding(
        forHeight height: CGFloat,
        isLaunchCenteringActive: Bool
    ) -> UIEdgeInsets {
        if isLaunchCenteringActive {
            return UIEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        }

        let top = min(max(height * 0.14, 122), 176)
        let bottom = min(max(height * 0.27, 230), 300)

        return UIEdgeInsets(top: top, left: 20, bottom: bottom, right: 96)
    }

    nonisolated static func mapKitLayoutMargins(
        forHeight _: CGFloat,
        isLaunchCenteringActive _: Bool
    ) -> UIEdgeInsets {
        UIEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
    }

    nonisolated static func shouldRespectVisibleControlsForStartupCentering(
        showsUserLocation: Bool,
        shouldFollowUserLocationOnLaunch: Bool,
        needsLaunchLocationCenteringConfirmation: Bool
    ) -> Bool {
        showsUserLocation
            && (shouldFollowUserLocationOnLaunch || needsLaunchLocationCenteringConfirmation)
    }

    nonisolated static func usableViewportCenter(
        bounds: CGRect,
        padding: UIEdgeInsets
    ) -> CGPoint {
        let verticalOffset = (padding.top - padding.bottom) / 4

        return CGPoint(
            x: bounds.midX,
            y: bounds.midY + verticalOffset
        )
    }

    nonisolated static func isScreenPointCenteredInUsableViewport(
        _ point: CGPoint,
        bounds: CGRect,
        padding: UIEdgeInsets,
        tolerance: CGFloat = 44
    ) -> Bool {
        let target = usableViewportCenter(bounds: bounds, padding: padding)
        return abs(point.x - target.x) <= tolerance
            && abs(point.y - target.y) <= tolerance
    }

    nonisolated static func visibleControlAdjustedRegion(
        for region: MKCoordinateRegion,
        in bounds: CGRect,
        padding: UIEdgeInsets
    ) -> MKCoordinateRegion {
        guard bounds.width > 1, bounds.height > 1 else { return region }

        let target = usableViewportCenter(bounds: bounds, padding: padding)
        let horizontalOffsetRatio = (target.x / bounds.width) - 0.5
        let verticalOffsetRatio = (target.y / bounds.height) - 0.5
        let adjustedCenter = CLLocationCoordinate2D(
            latitude: max(
                min(region.center.latitude + verticalOffsetRatio * region.span.latitudeDelta, 85),
                -85
            ),
            longitude: region.center.longitude - horizontalOffsetRatio * region.span.longitudeDelta
        )

        return MKCoordinateRegion(center: adjustedCenter, span: region.span)
    }

    private nonisolated static func isMeaningfullyDifferent(
        _ lhs: CLLocationCoordinate2D,
        from rhs: CLLocationCoordinate2D,
        threshold: CLLocationDistance = 8
    ) -> Bool {
        CLLocation(latitude: lhs.latitude, longitude: lhs.longitude)
            .distance(from: CLLocation(latitude: rhs.latitude, longitude: rhs.longitude)) > threshold
    }

    private nonisolated static func isSpanMeaningfullyDifferent(
        _ lhs: MKCoordinateSpan,
        from rhs: MKCoordinateSpan
    ) -> Bool {
        let latitudeThreshold = max(abs(rhs.latitudeDelta) * 0.08, 0.0001)
        let longitudeThreshold = max(abs(rhs.longitudeDelta) * 0.08, 0.0001)

        return abs(lhs.latitudeDelta - rhs.latitudeDelta) > latitudeThreshold
            || abs(lhs.longitudeDelta - rhs.longitudeDelta) > longitudeThreshold
    }

    nonisolated static func shouldFollowUserLocationOnLaunch(
        showsUserLocation: Bool,
        shouldUseUserLocation: Bool,
        userHasInteracted: Bool
    ) -> Bool {
        showsUserLocation && shouldUseUserLocation && !userHasInteracted
    }

    nonisolated static func shouldCenterUserLocationOnLaunch(
        showsUserLocation: Bool,
        shouldUseUserLocation: Bool,
        needsLaunchLocationCenteringConfirmation: Bool,
        userHasInteracted: Bool
    ) -> Bool {
        showsUserLocation
            && !userHasInteracted
            && (shouldUseUserLocation || needsLaunchLocationCenteringConfirmation)
    }

    nonisolated static func shouldResetLaunchInteractionLock(
        previousToken: Int?,
        currentToken: Int
    ) -> Bool {
        previousToken != currentToken
    }

    nonisolated static func shouldForceStartupRegionUpdate(
        previousRevision: Int?,
        currentRevision: Int,
        showsUserLocation _: Bool,
        shouldUseUserLocation _: Bool,
        userHasInteracted: Bool
    ) -> Bool {
        guard currentRevision > 0 else { return false }
        guard !userHasInteracted else { return false }
        return previousRevision != currentRevision
    }

    nonisolated static func shouldApplyStartupRegionUpdate(
        currentRegion: MKCoordinateRegion,
        targetRegion: MKCoordinateRegion,
        userHasInteracted: Bool,
        shouldFollowUserLocationOnLaunch: Bool,
        lastAppliedStartupTargetRegion: MKCoordinateRegion?
    ) -> Bool {
        guard !userHasInteracted else { return false }

        let targetChangedSinceLastApply = lastAppliedStartupTargetRegion.map {
            isMeaningfullyDifferent($0.center, from: targetRegion.center)
                || isSpanMeaningfullyDifferent($0.span, from: targetRegion.span)
        } ?? true

        guard shouldFollowUserLocationOnLaunch || targetChangedSinceLastApply else {
            return false
        }

        if targetChangedSinceLastApply {
            return true
        }

        if isMeaningfullyDifferent(currentRegion.center, from: targetRegion.center)
            || isSpanMeaningfullyDifferent(currentRegion.span, from: targetRegion.span) {
            return true
        }

        return false
    }

    nonisolated static func shouldApplyVisibleUserLocationFallback(
        currentRegion: MKCoordinateRegion,
        userLocation: CLLocation?,
        userHasInteracted: Bool,
        shouldFollowUserLocationOnLaunch: Bool
    ) -> Bool {
        guard shouldFollowUserLocationOnLaunch else { return false }
        guard !userHasInteracted else { return false }
        guard let userLocation else { return false }
        guard CLLocationCoordinate2DIsValid(userLocation.coordinate) else { return false }
        guard LocationManager.isUsableForInitialMapCenter(userLocation)
                || LocationManager.isUsableForProvisionalInitialMapCenter(userLocation) else {
            return false
        }

        let targetRegion = LocationManager.initialMapCenterRegion(for: userLocation)
        return !isStartupMapCentered(currentRegion: currentRegion, targetRegion: targetRegion)
    }

    nonisolated static func shouldApplyFirstVisibleUserLocationCenter(
        currentRegion: MKCoordinateRegion,
        userLocation: CLLocation?,
        userHasInteracted: Bool,
        hasAppliedFirstVisibleUserLocationCenter: Bool,
        showsUserLocation: Bool
    ) -> Bool {
        guard showsUserLocation else { return false }
        guard !userHasInteracted else { return false }
        guard !hasAppliedFirstVisibleUserLocationCenter else { return false }
        guard let userLocation else { return false }
        guard CLLocationCoordinate2DIsValid(userLocation.coordinate) else { return false }
        guard LocationManager.isUsableForInitialMapCenter(userLocation) else { return false }

        let targetRegion = LocationManager.initialMapCenterRegion(for: userLocation)
        return !isStartupMapCentered(currentRegion: currentRegion, targetRegion: targetRegion)
    }

    nonisolated static func isStartupMapCentered(
        currentRegion: MKCoordinateRegion,
        targetRegion: MKCoordinateRegion
    ) -> Bool {
        !isMeaningfullyDifferent(currentRegion.center, from: targetRegion.center)
            && !isSpanMeaningfullyDifferent(currentRegion.span, from: targetRegion.span)
    }

    nonisolated static func shouldReapplyUserFollowModeAfterStartupRegionUpdate(
        shouldFollowUserLocationOnLaunch _: Bool,
        didApplyStartupRegionUpdate _: Bool
    ) -> Bool {
        false
    }

    nonisolated static func shouldRetryStartupMapCenter(
        currentRegion: MKCoordinateRegion,
        targetRegion: MKCoordinateRegion,
        userHasInteracted: Bool,
        attempt: Int,
        maxAttempts: Int
    ) -> Bool {
        guard attempt < maxAttempts else { return false }
        guard !userHasInteracted else { return false }

        return isMeaningfullyDifferent(currentRegion.center, from: targetRegion.center)
            || isSpanMeaningfullyDifferent(currentRegion.span, from: targetRegion.span)
    }

    nonisolated static func startupConfirmationTarget(
        lastAppliedStartupTargetRegion: MKCoordinateRegion?,
        parentRegion: MKCoordinateRegion
    ) -> MKCoordinateRegion {
        lastAppliedStartupTargetRegion ?? parentRegion
    }

    nonisolated static func shouldSyncVisibleRegionBackToBinding(
        changeWasProgrammatic: Bool,
        needsLaunchLocationCenteringConfirmation: Bool,
        userHasInteracted: Bool,
        currentRegion: MKCoordinateRegion,
        targetRegion: MKCoordinateRegion
    ) -> Bool {
        guard !changeWasProgrammatic else { return false }

        if needsLaunchLocationCenteringConfirmation && !userHasInteracted {
            return isStartupMapCentered(currentRegion: currentRegion, targetRegion: targetRegion)
        }

        return true
    }

    nonisolated static func shouldPublishVisibleRegion(
        _ currentRegion: MKCoordinateRegion,
        previousRegion: MKCoordinateRegion
    ) -> Bool {
        isMeaningfullyDifferent(currentRegion.center, from: previousRegion.center)
            || isSpanMeaningfullyDifferent(currentRegion.span, from: previousRegion.span)
    }

    nonisolated static func shouldRefreshLeadClusteringAfterRegionChange(
        changeWasProgrammatic: Bool,
        userHasInteracted: Bool
    ) -> Bool {
        userHasInteracted && !changeWasProgrammatic
    }

    private static func renderedMapType(for mapType: MKMapType, is3DModeEnabled: Bool) -> MKMapType {
        switch mapType {
        case .satellite, .satelliteFlyover:
            return is3DModeEnabled ? .satelliteFlyover : .satellite
        case .hybrid, .hybridFlyover:
            return is3DModeEnabled ? .hybridFlyover : .hybrid
        default:
            return mapType
        }
    }

    private static func isImageryMapType(_ mapType: MKMapType) -> Bool {
        switch mapType {
        case .satellite, .hybrid, .satelliteFlyover, .hybridFlyover:
            return true
        default:
            return false
        }
    }

    private static func shouldShowBuildings(for mapType: MKMapType, is3DModeEnabled: Bool) -> Bool {
        is3DModeEnabled && !isImageryMapType(mapType)
    }

    private static func allowsPitch(is3DModeEnabled: Bool) -> Bool {
        is3DModeEnabled
    }

    private static func maximumPitch(for mapType: MKMapType) -> Double {
        isImageryMapType(mapType) ? 50 : 65
    }
    
    class Coordinator: NSObject, MKMapViewDelegate {
        var parent: AdvancedMapView
        private static let annotationBatchSize = 48
        private static let annotationBatchDelay: TimeInterval = 0.045
        private var currentAnnotations: [LeadMapAnnotation] = []
        private var currentSearchPinAnnotation: MKPointAnnotation?
        private var currentAnnotationSignature: [LeadAnnotationSignature] = []
        private var currentLeadClusteringMode: LeadClusterDisplayPolicy.Mode?
        private var annotationUpdateGeneration = 0
        private var pendingAnnotationWorkItems: [DispatchWorkItem] = []
        var isUserInteracting = false
        var userHasInteracted = false
        var isProgrammaticChange = false
        var hasSetInitialRegion = false
        var lastEffectiveMapType: MKMapType?
        var last3DModeEnabled: Bool?
        var lastLaunchCenteringResetToken: Int?
        var lastLaunchLocationCenterRevision: Int?
        var lastAppliedStartupTargetRegion: MKCoordinateRegion?
        var lastAppliedStartupTargetRespectsVisibleControls = false
        var hasAppliedFirstVisibleUserLocationCenter = false
        private var updateTimer: Timer?
        private var startupCenterVerificationWorkItem: DispatchWorkItem?
        private var startupCenterVerificationAttempt = 0
        private let maxStartupCenterVerificationAttempts = 4
        
        init(_ parent: AdvancedMapView) {
            self.parent = parent
        }

        deinit {
            updateTimer?.invalidate()
            startupCenterVerificationWorkItem?.cancel()
            cancelPendingAnnotationUpdates()
        }

        func resetStartupCenterVerification() {
            startupCenterVerificationWorkItem?.cancel()
            startupCenterVerificationWorkItem = nil
            startupCenterVerificationAttempt = 0
        }

        func scheduleStartupCenterVerification(
            mapView: MKMapView,
            targetRegion: MKCoordinateRegion,
            shouldFollowUserLocationOnLaunch: Bool,
            targetHasUserLocation: Bool,
            respectingVisibleControls: Bool
        ) {
            startupCenterVerificationWorkItem?.cancel()

            let attempt = startupCenterVerificationAttempt
            let workItem = DispatchWorkItem { [weak self, weak mapView] in
                guard let self, let mapView else { return }

                let startupCenterSatisfied = self.isStartupCenterSatisfied(
                    mapView: mapView,
                    currentRegion: mapView.region,
                    targetRegion: targetRegion,
                    targetHasUserLocation: targetHasUserLocation,
                    respectingVisibleControls: respectingVisibleControls
                )

                guard !startupCenterSatisfied else {
                    if targetHasUserLocation {
                        DispatchQueue.main.async {
                            self.parent.onLaunchCenteringConfirmed()
                        }
                    }
                    return
                }

                let shouldRetry = respectingVisibleControls
                    ? attempt < self.maxStartupCenterVerificationAttempts && !self.userHasInteracted
                    : AdvancedMapView.shouldRetryStartupMapCenter(
                        currentRegion: mapView.region,
                        targetRegion: targetRegion,
                        userHasInteracted: self.userHasInteracted,
                        attempt: attempt,
                        maxAttempts: self.maxStartupCenterVerificationAttempts
                    )
                guard shouldRetry else { return }

                self.startupCenterVerificationAttempt = attempt + 1
                self.isProgrammaticChange = true
                self.hasSetInitialRegion = true
                self.lastAppliedStartupTargetRegion = targetRegion
                self.lastAppliedStartupTargetRespectsVisibleControls = respectingVisibleControls
                AdvancedMapView.applyMapRegion(
                    targetRegion,
                    to: mapView,
                    animated: false,
                    respectingVisibleControls: respectingVisibleControls
                )

                self.scheduleStartupCenterVerification(
                    mapView: mapView,
                    targetRegion: targetRegion,
                    shouldFollowUserLocationOnLaunch: shouldFollowUserLocationOnLaunch,
                    targetHasUserLocation: targetHasUserLocation,
                    respectingVisibleControls: respectingVisibleControls
                )
            }

            startupCenterVerificationWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45, execute: workItem)
        }

        @discardableResult
        func applyVisibleUserLocationFallbackIfNeeded(
            mapView: MKMapView,
            shouldFollowUserLocationOnLaunch: Bool,
            allowFirstVisibleUserLocationCenter: Bool,
            respectingVisibleControls: Bool
        ) -> MKCoordinateRegion? {
            guard let visibleUserLocation = mapView.userLocation.location else {
                return nil
            }

            let shouldApplyFollowFallback = AdvancedMapView.shouldApplyVisibleUserLocationFallback(
                currentRegion: mapView.region,
                userLocation: visibleUserLocation,
                userHasInteracted: userHasInteracted,
                shouldFollowUserLocationOnLaunch: shouldFollowUserLocationOnLaunch
            )
            let shouldApplyFirstVisibleCenter = AdvancedMapView.shouldApplyFirstVisibleUserLocationCenter(
                currentRegion: mapView.region,
                userLocation: visibleUserLocation,
                userHasInteracted: userHasInteracted,
                hasAppliedFirstVisibleUserLocationCenter: hasAppliedFirstVisibleUserLocationCenter,
                showsUserLocation: allowFirstVisibleUserLocationCenter
            )

            guard shouldApplyFollowFallback || shouldApplyFirstVisibleCenter else { return nil }

            let userRegion = LocationManager.initialMapCenterRegion(for: visibleUserLocation)
            isProgrammaticChange = true
            hasSetInitialRegion = true
            lastAppliedStartupTargetRegion = userRegion
            lastAppliedStartupTargetRespectsVisibleControls = respectingVisibleControls
            hasAppliedFirstVisibleUserLocationCenter = true
            AdvancedMapView.applyMapRegion(
                userRegion,
                to: mapView,
                animated: false,
                respectingVisibleControls: respectingVisibleControls
            )

            DispatchQueue.main.async { [weak self] in
                self?.parent.region = userRegion
            }

            return userRegion
        }

        private func isStartupCenterSatisfied(
            mapView: MKMapView,
            currentRegion: MKCoordinateRegion,
            targetRegion: MKCoordinateRegion,
            targetHasUserLocation: Bool,
            respectingVisibleControls: Bool
        ) -> Bool {
            guard respectingVisibleControls, targetHasUserLocation else {
                return AdvancedMapView.isStartupMapCentered(
                    currentRegion: currentRegion,
                    targetRegion: targetRegion
                )
            }

            let point = mapView.convert(targetRegion.center, toPointTo: mapView)
            return AdvancedMapView.isScreenPointCenteredInUsableViewport(
                point,
                bounds: mapView.bounds,
                padding: AdvancedMapView.userLocationViewportPadding(for: mapView)
            )
        }
        
        func updateAnnotationsIfNeeded(mapView: MKMapView, leads: [MapLeadPin]) {
            let newSignature = leads.map { LeadAnnotationSignature(pin: $0) }
            guard newSignature != currentAnnotationSignature else { return }

            annotationUpdateGeneration += 1
            let generation = annotationUpdateGeneration
            cancelPendingAnnotationUpdates()

            let previousSignatureByAnnotation = Dictionary(
                uniqueKeysWithValues: zip(currentAnnotations, currentAnnotationSignature)
                    .map { annotation, signature in (ObjectIdentifier(annotation), signature) }
            )
            let previousAnnotationsBySignature = Dictionary(
                uniqueKeysWithValues: zip(currentAnnotationSignature, currentAnnotations)
                    .map { signature, annotation in (signature, annotation) }
            )
            let newSignatureSet = Set(newSignature)
            let previousSignatureSet = Set(currentAnnotationSignature)

            let annotationsToRemove = currentAnnotations.filter { annotation in
                guard let signature = previousSignatureByAnnotation[ObjectIdentifier(annotation)] else {
                    return true
                }
                return !newSignatureSet.contains(signature)
            }

            let newAnnotations = zip(leads, newSignature).map { pin, signature in
                previousAnnotationsBySignature[signature] ?? LeadMapAnnotation(pin: pin)
            }
            let annotationsToAdd = zip(newAnnotations, newSignature).compactMap { annotation, signature in
                previousSignatureSet.contains(signature) ? nil : annotation
            }

            if !annotationsToRemove.isEmpty {
                mapView.removeAnnotations(annotationsToRemove)
            }
            if !annotationsToAdd.isEmpty {
                addAnnotationsInBatches(annotationsToAdd, to: mapView, generation: generation)
            }
            currentAnnotations = newAnnotations
            currentAnnotationSignature = newSignature
            currentLeadClusteringMode = LeadClusterDisplayPolicy.mode(for: mapView.region)

            AppLog.debug("Map", "Updated map annotations: \(currentAnnotations.count) leads displayed")
        }

        func updateLeadClusteringModeIfNeeded(mapView: MKMapView) {
            let nextMode = LeadClusterDisplayPolicy.mode(for: mapView.region)
            guard currentLeadClusteringMode != nextMode else { return }

            annotationUpdateGeneration += 1
            let generation = annotationUpdateGeneration
            cancelPendingAnnotationUpdates()

            currentLeadClusteringMode = nextMode
            guard !currentAnnotations.isEmpty else { return }

            mapView.removeAnnotations(currentAnnotations)
            addAnnotationsInBatches(currentAnnotations, to: mapView, generation: generation)
        }

        private func cancelPendingAnnotationUpdates() {
            pendingAnnotationWorkItems.forEach { $0.cancel() }
            pendingAnnotationWorkItems.removeAll()
        }

        func suspendHiddenAnnotationWork(mapView: MKMapView) {
            cancelPendingAnnotationUpdates()
            // The map view is kept alive behind other tabs. Retaining the current
            // annotation set avoids paying a full remove/re-add cost every time
            // the user opens the map tab.
            currentLeadClusteringMode = LeadClusterDisplayPolicy.mode(for: mapView.region)
        }

        private func addAnnotationsInBatches(
            _ annotations: [LeadMapAnnotation],
            to mapView: MKMapView,
            generation: Int
        ) {
            guard !annotations.isEmpty else { return }

            if annotations.count <= Self.annotationBatchSize {
                mapView.addAnnotations(annotations)
                return
            }

            var batchIndex = 0
            var startIndex = annotations.startIndex
            while startIndex < annotations.endIndex {
                let endIndex = annotations.index(
                    startIndex,
                    offsetBy: Self.annotationBatchSize,
                    limitedBy: annotations.endIndex
                ) ?? annotations.endIndex
                let batch = Array(annotations[startIndex..<endIndex])

                if batchIndex == 0 {
                    mapView.addAnnotations(batch)
                } else {
                    let workItem = DispatchWorkItem { [weak self, weak mapView] in
                        guard let self,
                              let mapView,
                              self.annotationUpdateGeneration == generation else { return }
                        mapView.addAnnotations(batch)
                    }
                    pendingAnnotationWorkItems.append(workItem)
                    DispatchQueue.main.asyncAfter(
                        deadline: .now() + (Double(batchIndex) * Self.annotationBatchDelay),
                        execute: workItem
                    )
                }

                batchIndex += 1
                startIndex = endIndex
            }
        }

        func updateSearchPin(mapView: MKMapView, searchPin: SearchPin?) {
            // Remove old search pin if it changed or cleared
            if let old = currentSearchPinAnnotation {
                if searchPin == nil ||
                   old.coordinate.latitude != searchPin?.coordinate.latitude ||
                   old.coordinate.longitude != searchPin?.coordinate.longitude ||
                    old.title != searchPin?.title {
                    mapView.removeAnnotation(old)
                    currentSearchPinAnnotation = nil
                }
            }

            // Add new search pin
            if let pin = searchPin, currentSearchPinAnnotation == nil {
                let annotation = MKPointAnnotation()
                annotation.coordinate = pin.coordinate
                annotation.title = pin.title
                mapView.addAnnotation(annotation)
                currentSearchPinAnnotation = annotation
            }
        }

        private struct LeadAnnotationSignature: Equatable, Hashable {
            let objectID: NSManagedObjectID
            let latitude: Double
            let longitude: Double
            let status: String
            let name: String
            let address: String
            let priority: Int16
            let followUpDate: TimeInterval
            let price: Double
            let estimatedValue: Double

            init(pin: MapLeadPin) {
                self.objectID = pin.objectID
                self.latitude = pin.latitude
                self.longitude = pin.longitude
                self.status = pin.status.rawValue
                self.name = pin.name
                self.address = pin.address
                self.priority = pin.priority
                self.followUpDate = pin.followUpDate?.timeIntervalSince1970 ?? 0
                self.price = pin.price
                self.estimatedValue = pin.estimatedValue
            }
        }

        @objc func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
            guard gesture.state == .began else { return }

            guard let mapView = gesture.view as? MKMapView else {
                AppLog.error("Map", "Long press gesture view is not an MKMapView")
                return
            }

            let location = gesture.location(in: mapView)
            let coordinate = mapView.convert(location, toCoordinateFrom: mapView)
            
            // Check if long press is on an annotation
            let annotationsAtPoint = mapView.annotations.compactMap { $0 as? LeadMapAnnotation }
            
            var tappedPin: MapLeadPin? = nil
            for annotation in annotationsAtPoint {
                let annotationPoint = mapView.convert(annotation.coordinate, toPointTo: mapView)
                if location.distance(to: annotationPoint) < 20 { // 20 points tolerance
                    tappedPin = annotation.pin
                    break
                }
            }
            
            if let pin = tappedPin {
                parent.onLongPress(nil, pin)
            } else {
                parent.onLongPress(coordinate, nil)
            }
        }
        
        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            // Search pin — blue marker with magnifying glass
            if annotation is MKPointAnnotation && !(annotation is LeadMapAnnotation) && !(annotation is MKUserLocation) {
                let id = "SearchPin"
                let view = mapView.dequeueReusableAnnotationView(withIdentifier: id) as? MKMarkerAnnotationView ?? MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: id)
                view.annotation = annotation
                view.markerTintColor = .systemBlue
                view.glyphImage = UIImage(systemName: "magnifyingglass")
                view.canShowCallout = true
                view.clusteringIdentifier = nil
                return view
            }

            if let cluster = annotation as? MKClusterAnnotation {
                let clusterID = "LeadCluster"
                let clusterView = mapView.dequeueReusableAnnotationView(withIdentifier: clusterID) as? MKMarkerAnnotationView ?? MKMarkerAnnotationView(annotation: cluster, reuseIdentifier: clusterID)
                clusterView.annotation = cluster
                let pins = cluster.memberAnnotations.compactMap { ($0 as? LeadMapAnnotation)?.pin }
                let summary = MapLeadPinClusterSummary(pins: pins)
                clusterView.glyphText = summary.glyphText
                clusterView.markerTintColor = summary.uiColor
                clusterView.glyphTintColor = .white
                clusterView.displayPriority = LeadMapAnnotationPriorityPolicy.clusterDisplayPriority(for: summary)
                clusterView.collisionMode = .circle
                return clusterView
            }

            guard let leadAnnotation = annotation as? LeadMapAnnotation else {
                return nil
            }

            let pin = leadAnnotation.pin
            let identifier = "LeadAnnotation"
            let annotationView = mapView.dequeueReusableAnnotationView(withIdentifier: identifier) as? MKMarkerAnnotationView ?? MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: identifier)

            annotationView.annotation = annotation
            annotationView.canShowCallout = true
            annotationView.clusteringIdentifier = LeadClusterDisplayPolicy.clusteringIdentifier(
                for: LeadClusterDisplayPolicy.mode(for: mapView.region)
            )
            annotationView.displayPriority = displayPriority(for: pin)

            // Customize based on lead status
            switch pin.status {
            case .notContacted:
                annotationView.markerTintColor = .gray
                annotationView.glyphImage = UIImage(systemName: "person.circle")
            case .interested:
                annotationView.markerTintColor = .orange
                annotationView.glyphImage = UIImage(systemName: "heart.circle")
            case .converted:
                annotationView.markerTintColor = .green
                annotationView.glyphImage = UIImage(systemName: "checkmark.circle")
            case .notInterested:
                annotationView.markerTintColor = .red
                annotationView.glyphImage = UIImage(systemName: "hand.raised.fill")
            case .notHome:
                annotationView.markerTintColor = .brown
                annotationView.glyphImage = UIImage(systemName: "house.slash.fill")
            }

            return annotationView
        }

        private func uiColor(for status: Lead.Status) -> UIColor {
            switch status {
            case .notContacted: return .gray
            case .interested: return .orange
            case .converted: return .green
            case .notInterested: return .red
            case .notHome: return .brown
            }
        }

        private func displayPriority(for pin: MapLeadPin) -> MKFeatureDisplayPriority {
            LeadMapAnnotationPriorityPolicy.displayPriority(for: pin)
        }
        
        func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
            if let cluster = view.annotation as? MKClusterAnnotation {
                let pins = MapLeadPinClusterSummary.sortedPins(
                    cluster.memberAnnotations.compactMap { ($0 as? LeadMapAnnotation)?.pin }
                )
                guard !pins.isEmpty else { return }
                mapView.deselectAnnotation(cluster, animated: false)

                if shouldOpenClusterSheet(mapView: mapView, cluster: cluster) {
                    parent.onLeadClusterTap(pins, cluster.coordinate)
                } else {
                    zoomIntoCluster(cluster, on: mapView)
                }
            } else if let leadAnnotation = view.annotation as? LeadMapAnnotation {
                parent.onLeadTap(leadAnnotation.pin)
            } else if view.annotation is MKPointAnnotation,
                      let pin = parent.searchPin {
                mapView.deselectAnnotation(view.annotation, animated: false)
                parent.onSearchPinTap(pin)
            }
        }

        func mapView(_ mapView: MKMapView, didUpdate userLocation: MKUserLocation) {
            let shouldFollowUser = AdvancedMapView.shouldCenterUserLocationOnLaunch(
                showsUserLocation: parent.showsUserLocation,
                shouldUseUserLocation: parent.shouldFollowUserLocationOnLaunch,
                needsLaunchLocationCenteringConfirmation: parent.needsLaunchLocationCenteringConfirmation,
                userHasInteracted: userHasInteracted
            )

            if let userRegion = applyVisibleUserLocationFallbackIfNeeded(
                mapView: mapView,
                shouldFollowUserLocationOnLaunch: shouldFollowUser,
                allowFirstVisibleUserLocationCenter: parent.showsUserLocation,
                respectingVisibleControls: true
            ) {
                scheduleStartupCenterVerification(
                    mapView: mapView,
                    targetRegion: userRegion,
                    shouldFollowUserLocationOnLaunch: shouldFollowUser,
                    targetHasUserLocation: true,
                    respectingVisibleControls: true
                )
            }
        }

        private func shouldOpenClusterSheet(mapView: MKMapView, cluster: MKClusterAnnotation) -> Bool {
            let maxSpan = max(mapView.region.span.latitudeDelta, mapView.region.span.longitudeDelta)
            let pins = cluster.memberAnnotations.compactMap { ($0 as? LeadMapAnnotation)?.pin }
            return LeadClusterInteractionPolicy.route(
                mapSpan: maxSpan,
                coordinateSpread: coordinateSpread(for: cluster),
                memberCount: cluster.memberAnnotations.count,
                containsUrgentLead: pins.contains(where: MapLeadPinClusterSummary.isUrgent)
            ) == .openSheet
        }

        private func zoomIntoCluster(_ cluster: MKClusterAnnotation, on mapView: MKMapView) {
            let coordinates = cluster.memberAnnotations.map(\.coordinate)
            guard let region = paddedRegion(containing: coordinates, currentRegion: mapView.region) else { return }
            userHasInteracted = true
            resetStartupCenterVerification()
            mapView.setRegion(region, animated: true)
        }

        private func paddedRegion(
            containing coordinates: [CLLocationCoordinate2D],
            currentRegion: MKCoordinateRegion
        ) -> MKCoordinateRegion? {
            guard let first = coordinates.first else { return nil }
            var minLatitude = first.latitude
            var maxLatitude = first.latitude
            var minLongitude = first.longitude
            var maxLongitude = first.longitude

            for coordinate in coordinates.dropFirst() {
                minLatitude = min(minLatitude, coordinate.latitude)
                maxLatitude = max(maxLatitude, coordinate.latitude)
                minLongitude = min(minLongitude, coordinate.longitude)
                maxLongitude = max(maxLongitude, coordinate.longitude)
            }

            let nextLatitudeDelta = max((maxLatitude - minLatitude) * 2.2, 0.0025)
            let nextLongitudeDelta = max((maxLongitude - minLongitude) * 2.2, 0.0025)
            let currentLatitudeDelta = currentRegion.span.latitudeDelta
            let currentLongitudeDelta = currentRegion.span.longitudeDelta

            return MKCoordinateRegion(
                center: CLLocationCoordinate2D(
                    latitude: (minLatitude + maxLatitude) / 2,
                    longitude: (minLongitude + maxLongitude) / 2
                ),
                span: MKCoordinateSpan(
                    latitudeDelta: min(nextLatitudeDelta, currentLatitudeDelta * 0.55),
                    longitudeDelta: min(nextLongitudeDelta, currentLongitudeDelta * 0.55)
                )
            )
        }

        private func coordinateSpread(for cluster: MKClusterAnnotation) -> CLLocationDegrees {
            let coordinates = cluster.memberAnnotations.map(\.coordinate)
            guard let first = coordinates.first else { return 0 }

            var minLatitude = first.latitude
            var maxLatitude = first.latitude
            var minLongitude = first.longitude
            var maxLongitude = first.longitude

            for coordinate in coordinates.dropFirst() {
                minLatitude = min(minLatitude, coordinate.latitude)
                maxLatitude = max(maxLatitude, coordinate.latitude)
                minLongitude = min(minLongitude, coordinate.longitude)
                maxLongitude = max(maxLongitude, coordinate.longitude)
            }

            return max(maxLatitude - minLatitude, maxLongitude - minLongitude)
        }
        
        func mapView(_ mapView: MKMapView, regionWillChangeAnimated animated: Bool) {
            let userGesture = isUserDrivenRegionGesture(in: mapView)
            handleRegionWillChange(userGesture: userGesture)
        }

        func handleRegionWillChange(userGesture: Bool) {
            isUserInteracting = userGesture
            updateTimer?.invalidate()
            if userGesture {
                userHasInteracted = true
                isProgrammaticChange = false
                resetStartupCenterVerification()
            }
        }

        private func isUserDrivenRegionGesture(in mapView: MKMapView) -> Bool {
            guard let gestureRecognizers = mapView.subviews.first?.gestureRecognizers else { return false }

            return gestureRecognizers.contains { recognizer in
                let isMapMovementGesture = recognizer is UIPanGestureRecognizer
                    || recognizer is UIPinchGestureRecognizer
                    || recognizer is UIRotationGestureRecognizer
                guard isMapMovementGesture else { return false }
                return recognizer.state == .began || recognizer.state == .changed
            }
        }
        
        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            updateTimer?.invalidate()

            let currentRegion = mapView.region
            let currentCamera = mapView.camera
            let changeWasProgrammatic = isProgrammaticChange

            if AdvancedMapView.shouldRefreshLeadClusteringAfterRegionChange(
                changeWasProgrammatic: changeWasProgrammatic,
                userHasInteracted: userHasInteracted
            ) {
                updateLeadClusteringModeIfNeeded(mapView: mapView)
            }

            updateTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { [weak self, weak mapView] _ in
                Task { @MainActor [weak self, weak mapView] in
                    guard let self = self else { return }
                    self.isUserInteracting = false

                    let startupTargetRegion = AdvancedMapView.startupConfirmationTarget(
                        lastAppliedStartupTargetRegion: self.lastAppliedStartupTargetRegion,
                        parentRegion: self.parent.region
                    )
                    let startupCenterSatisfied = mapView.map {
                        self.isStartupCenterSatisfied(
                            mapView: $0,
                            currentRegion: currentRegion,
                            targetRegion: startupTargetRegion,
                            targetHasUserLocation: self.parent.hasLaunchLocationCandidate,
                            respectingVisibleControls: self.lastAppliedStartupTargetRespectsVisibleControls
                        )
                    } ?? AdvancedMapView.isStartupMapCentered(
                        currentRegion: currentRegion,
                        targetRegion: startupTargetRegion
                    )

                    if self.parent.hasLaunchLocationCandidate,
                       self.parent.needsLaunchLocationCenteringConfirmation,
                       startupCenterSatisfied {
                        self.parent.onLaunchCenteringConfirmed()
                    }

                    // During startup, MapKit can emit passive region changes while
                    // it is still settling. Do not let those stale visible regions
                    // overwrite the launch target before the map actually centers.
                    guard AdvancedMapView.shouldSyncVisibleRegionBackToBinding(
                        changeWasProgrammatic: changeWasProgrammatic,
                        needsLaunchLocationCenteringConfirmation: self.parent.needsLaunchLocationCenteringConfirmation,
                        userHasInteracted: self.userHasInteracted,
                        currentRegion: currentRegion,
                        targetRegion: startupTargetRegion
                    ) else {
                        if changeWasProgrammatic {
                            self.isProgrammaticChange = false
                        }
                        return
                    }

                    if changeWasProgrammatic {
                        self.isProgrammaticChange = false
                    }

                    // Sync camera rotation and pitch
                    if abs(currentCamera.heading - self.parent.rotation) > 1.0 {
                        self.parent.rotation = currentCamera.heading
                    }
                    if abs(currentCamera.pitch - self.parent.pitch) > 1.0 {
                        self.parent.pitch = currentCamera.pitch
                    }
                    if AdvancedMapView.shouldPublishVisibleRegion(
                        currentRegion,
                        previousRegion: self.parent.visibleRegion
                    ) {
                        self.parent.visibleRegion = currentRegion
                    }

                    // Only sync center, NEVER sync span — prevents zoom feedback loop.
                    // MKMapView "normalizes" spans on setRegion, returning slightly
                    // different values. Syncing span back triggers updateUIView →
                    // setRegion → regionDidChange → repeat, causing gradual zoom-out.
                    if AdvancedMapView.isMeaningfullyDifferent(currentRegion.center, from: self.parent.region.center) {
                        var updatedRegion = self.parent.region
                        updatedRegion.center = currentRegion.center
                        self.parent.region = updatedRegion
                    }
                }
            }
        }
    }
}

enum LeadClusterInteractionPolicy {
    enum Route {
        case openSheet
        case zoomIn
    }

    static func route(
        mapSpan: CLLocationDegrees,
        coordinateSpread: CLLocationDegrees,
        memberCount: Int,
        containsUrgentLead: Bool
    ) -> Route {
        if containsUrgentLead {
            return .openSheet
        }

        if memberCount <= 35, mapSpan <= 0.04 {
            return .openSheet
        }

        if mapSpan <= 0.018 || coordinateSpread <= 0.004 {
            return .openSheet
        }

        return .zoomIn
    }
}

enum LeadClusterDisplayPolicy {
    enum Mode {
        case clustered
        case expanded
    }

    static func mode(for region: MKCoordinateRegion) -> Mode {
        mode(mapSpan: max(region.span.latitudeDelta, region.span.longitudeDelta))
    }

    static func mode(mapSpan: CLLocationDegrees) -> Mode {
        mapSpan <= 0.04 ? .expanded : .clustered
    }

    static func clusteringIdentifier(for mode: Mode) -> String? {
        mode == .clustered ? "LeadCluster" : nil
    }
}

enum LeadMapAnnotationPriorityPolicy {
    private static let interestedPriority = MKFeatureDisplayPriority(
        rawValue: (MKFeatureDisplayPriority.required.rawValue + MKFeatureDisplayPriority.defaultHigh.rawValue) / 2
    )

    static func displayPriority(for lead: Lead) -> MKFeatureDisplayPriority {
        if lead.leadStatus == .converted {
            return .required
        }

        if lead.leadStatus == .interested {
            return interestedPriority
        }

        if LeadClusterSummary.isUrgent(lead) {
            return .defaultHigh
        }

        return .defaultLow
    }

    static func displayPriority(for pin: MapLeadPin) -> MKFeatureDisplayPriority {
        if pin.status == .converted {
            return .required
        }

        if pin.status == .interested {
            return interestedPriority
        }

        if MapLeadPinClusterSummary.isUrgent(pin) {
            return .defaultHigh
        }

        return .defaultLow
    }

    static func clusterDisplayPriority(for summary: LeadClusterSummary) -> MKFeatureDisplayPriority {
        if summary.soldCount > 0 {
            return .required
        }

        if summary.leads.contains(where: { $0.leadStatus == .interested }) {
            return interestedPriority
        }

        if summary.isUrgent {
            return .defaultHigh
        }

        return .defaultHigh
    }

    static func clusterDisplayPriority(for summary: MapLeadPinClusterSummary) -> MKFeatureDisplayPriority {
        if summary.soldCount > 0 {
            return .required
        }

        if summary.pins.contains(where: { $0.status == .interested }) {
            return interestedPriority
        }

        if summary.isUrgent {
            return .defaultHigh
        }

        return .defaultHigh
    }
}

class LeadMapAnnotation: NSObject, MKAnnotation {
    let pin: MapLeadPin
    // Cache coordinate at creation time so accessing a deleted managed object won't crash
    private let cachedCoordinate: CLLocationCoordinate2D
    private let cachedTitle: String?
    private let cachedSubtitle: String?

    var coordinate: CLLocationCoordinate2D {
        return cachedCoordinate
    }

    var title: String? {
        return cachedTitle
    }

    var subtitle: String? {
        return cachedSubtitle
    }
    
    init(pin: MapLeadPin) {
        self.pin = pin
        self.cachedCoordinate = pin.coordinate
        self.cachedTitle = pin.title
        self.cachedSubtitle = pin.subtitle
        super.init()
    }
}

struct LeadClusterSummary {
    let leads: [Lead]
    private let now: Date

    init(leads: [Lead], now: Date = Date()) {
        self.leads = leads
        self.now = now
    }

    var count: Int {
        leads.count
    }

    var glyphText: String {
        count > 99 ? "99+" : "\(count)"
    }

    var isUrgent: Bool {
        leads.contains(where: Self.isUrgent)
    }

    var dueFollowUpCount: Int {
        leads.filter { Self.isFollowUpDue($0, now: now) }.count
    }

    var hotLeadCount: Int {
        leads.filter { Self.isHotLead($0, now: now) }.count
    }

    var soldCount: Int {
        leads.filter { $0.leadStatus == .converted }.count
    }

    var interestedCount: Int {
        leads.filter { $0.leadStatus == .interested }.count
    }

    var totalValue: Double {
        leads.reduce(0) { partial, lead in
            partial + max(lead.price, lead.estimatedValue)
        }
    }

    var statusCounts: [(status: Lead.Status, count: Int)] {
        Lead.Status.allCases
            .map { status in (status, leads.filter { $0.leadStatus == status }.count) }
            .filter { $0.count > 0 }
            .sorted { lhs, rhs in
                if lhs.count != rhs.count { return lhs.count > rhs.count }
                return Self.statusRank(lhs.status) > Self.statusRank(rhs.status)
            }
    }

    var headline: String {
        if soldCount > 0 {
            return soldCount == count ? "Sold cluster" : "\(soldCount) sold"
        }
        if interestedCount > 0 {
            return "\(interestedCount) interested"
        }
        if dueFollowUpCount > 0 {
            return "\(dueFollowUpCount) follow-up due"
        }
        if hotLeadCount > 0 {
            return "\(hotLeadCount) hot \(hotLeadCount == 1 ? "lead" : "leads")"
        }
        if let dominant = statusCounts.first {
            return dominant.status.displayName
        }
        return "Lead cluster"
    }

    var detailLine: String {
        var parts: [String] = ["\(count) \(count == 1 ? "lead" : "leads")"]
        if totalValue > 0 {
            parts.append(totalValue.formatted(.currency(code: Locale.current.currency?.identifier ?? "USD").precision(.fractionLength(0))))
        }
        if let dominant = statusCounts.first {
            parts.append(dominant.status.displayName)
        }
        return parts.joined(separator: " • ")
    }

    var uiColor: UIColor {
        if soldCount > 0 {
            return .systemGreen
        }
        if interestedCount > 0 {
            return .systemOrange
        }
        if dueFollowUpCount > 0 || leads.contains(where: { Self.isPriorityActionable($0) }) {
            return .systemPink
        }
        if hotLeadCount > 0 {
            return .systemOrange
        }
        guard let dominant = statusCounts.first?.status else {
            return .systemPurple
        }
        switch dominant {
        case .notContacted:
            return .systemGray
        case .notHome:
            return .brown
        case .interested:
            return .systemOrange
        case .converted:
            return .systemGreen
        case .notInterested:
            return .systemRed
        }
    }

    var color: Color {
        Color(uiColor)
    }

    var sortedLeads: [Lead] {
        Self.sortedLeads(leads, now: now)
    }

    static func sortedLeads(_ leads: [Lead], now: Date = Date()) -> [Lead] {
        leads.sorted { lhs, rhs in
            prioritySortKey(for: lhs, now: now) > prioritySortKey(for: rhs, now: now)
        }
    }

    static func prioritySortKey(for lead: Lead, now: Date = Date()) -> LeadClusterSortKey {
        LeadClusterSortKey(
            score: priorityScore(for: lead, now: now),
            date: lead.updatedDate ?? lead.createdDate ?? .distantPast
        )
    }

    static func isUrgent(_ lead: Lead) -> Bool {
        isHotLead(lead, now: Date())
    }

    static func isFollowUpDue(_ lead: Lead, now: Date) -> Bool {
        guard let followUpDate = lead.followUpDate else { return false }
        guard lead.leadStatus != .converted && lead.leadStatus != .notInterested else { return false }
        return followUpDate <= now
    }

    private static func isHotLead(_ lead: Lead, now: Date) -> Bool {
        guard lead.leadStatus.allowsActiveFollowUp else { return false }
        return isPriorityActionable(lead) || lead.leadStatus == .interested || isFollowUpDue(lead, now: now)
    }

    private static func isPriorityActionable(_ lead: Lead) -> Bool {
        lead.leadStatus.allowsActiveFollowUp && lead.priority > 0
    }

    static func priorityScore(for lead: Lead, now: Date) -> Int {
        var score = 0
        if isPriorityActionable(lead) { score += 600 + Int(lead.priority) }
        if isFollowUpDue(lead, now: now) { score += 520 }
        switch lead.leadStatus {
        case .converted:
            score += 2_000
        case .interested:
            score += 1_500
        case .notHome:
            score += 260
        case .notContacted:
            score += 180
        case .notInterested:
            score += 20
        }
        if max(lead.price, lead.estimatedValue) > 0 {
            score += min(120, Int(max(lead.price, lead.estimatedValue) / 100))
        }
        return score
    }

    private static func statusRank(_ status: Lead.Status) -> Int {
        switch status {
        case .converted:
            return 5
        case .interested:
            return 4
        case .notHome:
            return 3
        case .notContacted:
            return 2
        case .notInterested:
            return 1
        }
    }
}

struct MapLeadPinClusterSummary {
    let pins: [MapLeadPin]
    private let now: Date

    init(pins: [MapLeadPin], now: Date = Date()) {
        self.pins = pins
        self.now = now
    }

    var count: Int {
        pins.count
    }

    var glyphText: String {
        count > 99 ? "99+" : "\(count)"
    }

    var isUrgent: Bool {
        pins.contains(where: Self.isUrgent)
    }

    var dueFollowUpCount: Int {
        pins.filter { Self.isFollowUpDue($0, now: now) }.count
    }

    var hotLeadCount: Int {
        pins.filter { Self.isHotLead($0, now: now) }.count
    }

    var soldCount: Int {
        pins.filter { $0.status == .converted }.count
    }

    var interestedCount: Int {
        pins.filter { $0.status == .interested }.count
    }

    var uiColor: UIColor {
        if soldCount > 0 {
            return .systemGreen
        }
        if interestedCount > 0 {
            return .systemOrange
        }
        if dueFollowUpCount > 0 || pins.contains(where: { Self.isPriorityActionable($0) }) {
            return .systemPink
        }
        if hotLeadCount > 0 {
            return .systemOrange
        }
        guard let dominant = dominantStatus else {
            return .systemPurple
        }
        switch dominant {
        case .notContacted:
            return .systemGray
        case .notHome:
            return .brown
        case .interested:
            return .systemOrange
        case .converted:
            return .systemGreen
        case .notInterested:
            return .systemRed
        }
    }

    var sortedPins: [MapLeadPin] {
        Self.sortedPins(pins, now: now)
    }

    static func sortedPins(_ pins: [MapLeadPin], now: Date = Date()) -> [MapLeadPin] {
        pins.sorted { lhs, rhs in
            prioritySortKey(for: lhs, now: now) > prioritySortKey(for: rhs, now: now)
        }
    }

    static func prioritySortKey(for pin: MapLeadPin, now: Date = Date()) -> LeadClusterSortKey {
        LeadClusterSortKey(
            score: priorityScore(for: pin, now: now),
            date: pin.updatedDate ?? pin.createdDate ?? .distantPast
        )
    }

    static func isUrgent(_ pin: MapLeadPin) -> Bool {
        isHotLead(pin, now: Date())
    }

    static func isFollowUpDue(_ pin: MapLeadPin, now: Date) -> Bool {
        guard let followUpDate = pin.followUpDate else { return false }
        guard pin.status != .converted && pin.status != .notInterested else { return false }
        return followUpDate <= now
    }

    private var dominantStatus: Lead.Status? {
        Lead.Status.allCases
            .map { status in (status, pins.filter { $0.status == status }.count) }
            .filter { $0.1 > 0 }
            .sorted { lhs, rhs in
                if lhs.1 != rhs.1 { return lhs.1 > rhs.1 }
                return Self.statusRank(lhs.0) > Self.statusRank(rhs.0)
            }
            .first?
            .0
    }

    private static func isHotLead(_ pin: MapLeadPin, now: Date) -> Bool {
        guard pin.status.allowsActiveFollowUp else { return false }
        return isPriorityActionable(pin) || pin.status == .interested || isFollowUpDue(pin, now: now)
    }

    private static func isPriorityActionable(_ pin: MapLeadPin) -> Bool {
        pin.status.allowsActiveFollowUp && pin.priority > 0
    }

    private static func priorityScore(for pin: MapLeadPin, now: Date) -> Int {
        var score = 0
        if isPriorityActionable(pin) { score += 600 + Int(pin.priority) }
        if isFollowUpDue(pin, now: now) { score += 520 }
        switch pin.status {
        case .converted:
            score += 2_000
        case .interested:
            score += 1_500
        case .notHome:
            score += 260
        case .notContacted:
            score += 180
        case .notInterested:
            score += 20
        }
        if max(pin.price, pin.estimatedValue) > 0 {
            score += min(120, Int(max(pin.price, pin.estimatedValue) / 100))
        }
        return score
    }

    private static func statusRank(_ status: Lead.Status) -> Int {
        switch status {
        case .converted:
            return 5
        case .interested:
            return 4
        case .notHome:
            return 3
        case .notContacted:
            return 2
        case .notInterested:
            return 1
        }
    }
}

struct LeadClusterSortKey: Comparable {
    let score: Int
    let date: Date

    static func < (lhs: LeadClusterSortKey, rhs: LeadClusterSortKey) -> Bool {
        if lhs.score != rhs.score {
            return lhs.score < rhs.score
        }
        return lhs.date < rhs.date
    }
}

extension CLLocationCoordinate2D {
    func isEqual(to coordinate: CLLocationCoordinate2D, tolerance: Double) -> Bool {
        return abs(self.latitude - coordinate.latitude) < tolerance &&
               abs(self.longitude - coordinate.longitude) < tolerance
    }
}

extension CGPoint {
    func distance(to point: CGPoint) -> CGFloat {
        return sqrt(pow(x - point.x, 2) + pow(y - point.y, 2))
    }
}
