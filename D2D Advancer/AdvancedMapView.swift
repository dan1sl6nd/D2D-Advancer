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

    let leads: [Lead]
    @Binding var searchPin: SearchPin?
    let showsUserLocation: Bool
    let onLeadTap: (Lead) -> Void
    let onSearchPinTap: (SearchPin) -> Void
    let onLongPress: (CLLocationCoordinate2D?, Lead?) -> Void

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

        // Set initial region (mark as programmatic to prevent sync-back)
        context.coordinator.isProgrammaticChange = true
        mapView.setRegion(region, animated: false)

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
                mapView.setRegion(region, animated: true)
            }
        }
        // Only auto-update region once at startup before user interacts.
        // Check center only (not span) — MKMapView normalizes spans on setRegion,
        // which would cause a false "changed" and prematurely lock out the real
        // user location update from LocationManager.
        else if !coordinator.hasSetInitialRegion && !coordinator.userHasInteracted {
            let centerChanged = !mapView.region.center.isEqual(to: region.center, tolerance: 0.005)

            if centerChanged {
                coordinator.isProgrammaticChange = true
                coordinator.hasSetInitialRegion = true
                mapView.setRegion(region, animated: false)
            }
        }

        coordinator.updateAnnotationsIfNeeded(mapView: mapView, leads: leads)

        // Update search pin
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
        private var currentAnnotations: [LeadMapAnnotation] = []
        private var currentSearchPinAnnotation: MKPointAnnotation?
        private var currentAnnotationSignature: [LeadAnnotationSignature] = []
        var isUserInteracting = false
        var userHasInteracted = false
        var isProgrammaticChange = false
        var hasSetInitialRegion = false
        var lastEffectiveMapType: MKMapType?
        var last3DModeEnabled: Bool?
        private var updateTimer: Timer?
        
        init(_ parent: AdvancedMapView) {
            self.parent = parent
        }

        deinit {
            updateTimer?.invalidate()
        }
        
        func updateAnnotationsIfNeeded(mapView: MKMapView, leads: [Lead]) {
            let newSignature = leads.map { LeadAnnotationSignature(lead: $0) }
            guard newSignature != currentAnnotationSignature else { return }

            if !currentAnnotations.isEmpty {
                mapView.removeAnnotations(currentAnnotations)
            }

            currentAnnotations = leads.map { LeadMapAnnotation(lead: $0) }
            if !currentAnnotations.isEmpty {
                mapView.addAnnotations(currentAnnotations)
            }
            currentAnnotationSignature = newSignature

            #if DEBUG
            print("Updated map annotations: \(currentAnnotations.count) leads displayed")
            #endif
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

        private struct LeadAnnotationSignature: Equatable {
            let id: String
            let latitude: Double
            let longitude: Double
            let status: String
            let name: String
            let address: String

            init(lead: Lead) {
                self.id = lead.objectID.uriRepresentation().absoluteString
                self.latitude = lead.latitude
                self.longitude = lead.longitude
                self.status = lead.status ?? ""
                self.name = lead.name ?? ""
                self.address = lead.address ?? ""
            }
        }

        @objc func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
            guard gesture.state == .began else { return }

            guard let mapView = gesture.view as? MKMapView else {
                print("❌ Long press gesture view is not an MKMapView")
                return
            }

            let location = gesture.location(in: mapView)
            let coordinate = mapView.convert(location, toCoordinateFrom: mapView)
            
            // Check if long press is on an annotation
            let annotationsAtPoint = mapView.annotations.compactMap { $0 as? LeadMapAnnotation }
            
            var tappedLead: Lead? = nil
            for annotation in annotationsAtPoint {
                let annotationPoint = mapView.convert(annotation.coordinate, toPointTo: mapView)
                if location.distance(to: annotationPoint) < 20 { // 20 points tolerance
                    tappedLead = annotation.lead
                    break
                }
            }
            
            if let lead = tappedLead {
                parent.onLongPress(nil, lead) // Pass Lead object
            } else {
                parent.onLongPress(coordinate, nil) // Pass coordinate for new lead
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
                clusterView.glyphText = "\(cluster.memberAnnotations.count)"

                // Color cluster by the status of its members (all same status)
                if let firstLead = (cluster.memberAnnotations.first as? LeadMapAnnotation)?.lead {
                    clusterView.markerTintColor = uiColor(for: firstLead.leadStatus)
                } else {
                    clusterView.markerTintColor = .systemPurple
                }
                return clusterView
            }

            guard let leadAnnotation = annotation as? LeadMapAnnotation else {
                return nil
            }

            let lead = leadAnnotation.lead
            let identifier = "LeadAnnotation"
            let annotationView = mapView.dequeueReusableAnnotationView(withIdentifier: identifier) as? MKMarkerAnnotationView ?? MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: identifier)

            annotationView.annotation = annotation
            annotationView.canShowCallout = true
            annotationView.clusteringIdentifier = "LeadCluster_\(lead.status ?? "unknown")"

            // Customize based on lead status
            switch lead.leadStatus {
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
        
        func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
            if let leadAnnotation = view.annotation as? LeadMapAnnotation {
                parent.onLeadTap(leadAnnotation.lead)
            } else if view.annotation is MKPointAnnotation,
                      let pin = parent.searchPin {
                mapView.deselectAnnotation(view.annotation, animated: false)
                parent.onSearchPinTap(pin)
            }
        }
        
        func mapView(_ mapView: MKMapView, regionWillChangeAnimated animated: Bool) {
            isUserInteracting = true
            updateTimer?.invalidate()

            // Detect if this region change was caused by a user gesture (not programmatic)
            if let gestureRecognizers = mapView.subviews.first?.gestureRecognizers {
                for recognizer in gestureRecognizers {
                    if recognizer.state == .began || recognizer.state == .changed || recognizer.state == .ended {
                        userHasInteracted = true
                        break
                    }
                }
            }
        }
        
        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            updateTimer?.invalidate()

            let currentRegion = mapView.region
            let currentCamera = mapView.camera

            updateTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    self.isUserInteracting = false

                    // If this was a programmatic change, don't sync back to binding
                    if self.isProgrammaticChange {
                        self.isProgrammaticChange = false
                        return
                    }

                    // Sync camera rotation and pitch
                    if abs(currentCamera.heading - self.parent.rotation) > 1.0 {
                        self.parent.rotation = currentCamera.heading
                    }
                    if abs(currentCamera.pitch - self.parent.pitch) > 1.0 {
                        self.parent.pitch = currentCamera.pitch
                    }

                    // Only sync center, NEVER sync span — prevents zoom feedback loop.
                    // MKMapView "normalizes" spans on setRegion, returning slightly
                    // different values. Syncing span back triggers updateUIView →
                    // setRegion → regionDidChange → repeat, causing gradual zoom-out.
                    if !currentRegion.center.isEqual(to: self.parent.region.center, tolerance: 0.001) {
                        var updatedRegion = self.parent.region
                        updatedRegion.center = currentRegion.center
                        self.parent.region = updatedRegion
                    }
                }
            }
        }
    }
}

class LeadMapAnnotation: NSObject, MKAnnotation {
    let lead: Lead
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
    
    init(lead: Lead) {
        self.lead = lead
        self.cachedCoordinate = lead.coordinate
        if let name = lead.name, !name.isEmpty {
            self.cachedTitle = name
        } else if let address = lead.address, !address.isEmpty {
            self.cachedTitle = address
        } else {
            self.cachedTitle = lead.displayName
        }
        self.cachedSubtitle = lead.leadStatus.displayName
        super.init()
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
