import SwiftUI
import MapKit
import UIKit

struct AdvancedMapView: UIViewRepresentable {
    @Binding var region: MKCoordinateRegion
    @Binding var mapType: MKMapType
    @Binding var rotation: Double
    @Binding var pitch: Double
    @Binding var animateNextUpdate: Bool
    @State private var forceUpdate = false
    @State private var hasInitialRegionSet = false

    let leads: [Lead]
    let onLeadTap: (Lead) -> Void
    let onLongPress: (CLLocationCoordinate2D?, Lead?) -> Void // Modified to accept optional Lead

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.showsUserLocation = true
        mapView.userTrackingMode = .none
        mapView.mapType = mapType
        mapView.showsBuildings = true
        mapView.showsCompass = true
        // Enable gestures globally so users can always rotate/tilt when supported
        mapView.isRotateEnabled = true
        mapView.isPitchEnabled = true
        
        // Set initial region
        mapView.setRegion(region, animated: false)
        
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

        // Always use flyover variants for satellite/hybrid to enable 3D gestures
        var effectiveMapType = mapType
        switch mapType {
        case .satellite:
            effectiveMapType = .satelliteFlyover
        case .hybrid:
            effectiveMapType = .hybridFlyover
        default:
            effectiveMapType = mapType
        }

        // Update map type if changed
        if mapView.mapType != effectiveMapType {
            mapView.mapType = effectiveMapType
        }

        // Ensure pitch and rotation are always enabled
        mapView.isPitchEnabled = true
        mapView.isRotateEnabled = true

        // Prefer modern configurations with realistic elevation for imagery/hybrid (iOS 16+)
        if #available(iOS 16.0, *) {
            let currentPref = mapView.preferredConfiguration
            var desired: MKMapConfiguration?
            switch effectiveMapType {
            case .satellite, .satelliteFlyover:
                let cfg = MKImageryMapConfiguration()
                cfg.elevationStyle = .realistic
                desired = cfg
            case .hybrid, .hybridFlyover:
                let cfg = MKHybridMapConfiguration()
                cfg.elevationStyle = .realistic
                desired = cfg
            default:
                // Keep current preferred config for standard, but ensure rotate/pitch stay enabled
                desired = nil
            }
            if let desired = desired {
                // Only set if different to avoid interrupting gestures
                let isDifferent = type(of: currentPref) != type(of: desired)
                if isDifferent {
                    mapView.preferredConfiguration = desired
                }
            }
        }
        
        // Only update if not user interacting and significant change
        if !coordinator.isUserInteracting {
            // Check for significant region changes to prevent excessive updates
            let regionChanged = !mapView.region.center.isEqual(to: region.center, tolerance: 0.005) ||
                              abs(mapView.region.span.latitudeDelta - region.span.latitudeDelta) > 0.005
            
            // Check for camera changes
            let currentCamera = mapView.camera
            let cameraChanged = abs(currentCamera.heading - rotation) > 10.0 || 
                               abs(currentCamera.pitch - pitch) > 10.0
            
            // Only update if there's a significant change or this is the initial setup
            if regionChanged || cameraChanged || !hasInitialRegionSet || animateNextUpdate {
                let shouldAnimate = hasInitialRegionSet || animateNextUpdate
                
                if !hasInitialRegionSet {
                    DispatchQueue.main.async {
                        hasInitialRegionSet = true
                    }
                }
                
                if animateNextUpdate {
                    DispatchQueue.main.async {
                        animateNextUpdate = false
                    }
                }
                
                if rotation != 0 || pitch != 0 {
                    // Use camera for 3D views
                    let distance = mapView.camera.altitude > 1000 ? mapView.camera.altitude : regionToDistance(region)
                    let camera = MKMapCamera(
                        lookingAtCenter: region.center,
                        fromDistance: distance,
                        pitch: pitch,
                        heading: rotation
                    )
                    mapView.setCamera(camera, animated: shouldAnimate)
                } else {
                    // Use region for standard view
                    mapView.setRegion(region, animated: shouldAnimate)
                }
            }
        }
        
        // Handle forced updates (like location centering)
        if forceUpdate {
            DispatchQueue.main.async {
                forceUpdate = false
            }
            coordinator.isUserInteracting = false
            
            if rotation != 0 || pitch != 0 {
                let camera = MKMapCamera(
                    lookingAtCenter: region.center,
                    fromDistance: mapView.camera.altitude > 1000 ? mapView.camera.altitude : 10000,
                    pitch: pitch,
                    heading: rotation
                )
                mapView.setCamera(camera, animated: true)
            } else {
                mapView.setRegion(region, animated: true)
            }
        }
        
        // Update annotations less frequently
        if coordinator.shouldUpdateAnnotations(leads: leads) {
            coordinator.updateAnnotations(mapView: mapView, leads: leads)
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    func forceLocationUpdate() {
        forceUpdate = true
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
    
    class Coordinator: NSObject, MKMapViewDelegate {
        var parent: AdvancedMapView
        private var currentAnnotations: [LeadMapAnnotation] = []
        private var lastLeadCount = 0
        var isUserInteracting = false
        private var updateTimer: Timer?
        
        init(_ parent: AdvancedMapView) {
            self.parent = parent
        }
        
        func shouldUpdateAnnotations(leads: [Lead]) -> Bool {
            // Update if count changed, no annotations, or if any lead was updated recently
            if leads.count != lastLeadCount || currentAnnotations.isEmpty {
                return true
            }
            
            // Check if any lead has been updated recently (within last 2 seconds)
            let recentUpdateThreshold = Date().addingTimeInterval(-2.0)
            for lead in leads {
                if let updatedDate = lead.updatedDate, updatedDate > recentUpdateThreshold {
                    return true
                }
            }
            
            return false
        }
        
        func updateAnnotations(mapView: MKMapView, leads: [Lead]) {
            // Remove existing annotations
            mapView.removeAnnotations(currentAnnotations)
            currentAnnotations.removeAll()
            
            // Add new annotations
            for lead in leads {
                let annotation = LeadMapAnnotation(lead: lead)
                currentAnnotations.append(annotation)
                mapView.addAnnotation(annotation)
            }
            
            // Only log summary, not each individual annotation
            print("🗺️ Updated map annotations: \(currentAnnotations.count) leads displayed")
            
            // Update count
            lastLeadCount = leads.count
        }
        
        @objc func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
            guard gesture.state == .began else { return }
            
            let mapView = gesture.view as! MKMapView
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
            guard let leadAnnotation = annotation as? LeadMapAnnotation else {
                return nil
            }
            
            let identifier = "LeadAnnotation"
            let annotationView = mapView.dequeueReusableAnnotationView(withIdentifier: identifier) as? MKMarkerAnnotationView ?? MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: identifier)
            
            annotationView.annotation = annotation
            annotationView.canShowCallout = true
            
            // Customize based on lead status
            let lead = leadAnnotation.lead
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
        
        func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
            guard let leadAnnotation = view.annotation as? LeadMapAnnotation else {
                return
            }
            parent.onLeadTap(leadAnnotation.lead)
        }
        
        func mapView(_ mapView: MKMapView, regionWillChangeAnimated animated: Bool) {
            isUserInteracting = true
            updateTimer?.invalidate()
        }
        
        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            // Debounce region updates to prevent feedback loops
            updateTimer?.invalidate()

            let currentRegion = mapView.region
            let currentCamera = mapView.camera

            updateTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    self.isUserInteracting = false

                    // Check if we're in 3D mode (pitch > 0 or heading != 0)
                    let isIn3DMode = currentCamera.pitch > 1.0 || currentCamera.heading > 1.0

                    // In 3D mode, only update camera parameters, not region (to prevent zoom changes)
                    if isIn3DMode {
                        // Only update rotation and pitch, avoid updating region which causes zoom issues
                        if abs(currentCamera.heading - self.parent.rotation) > 1.0 {
                            self.parent.rotation = currentCamera.heading
                        }
                        if abs(currentCamera.pitch - self.parent.pitch) > 1.0 {
                            self.parent.pitch = currentCamera.pitch
                        }

                        // Only update center if significantly changed, but preserve the original span
                        if !currentRegion.center.isEqual(to: self.parent.region.center, tolerance: 0.01) {
                            var updatedRegion = self.parent.region
                            updatedRegion.center = currentRegion.center
                            self.parent.region = updatedRegion
                        }
                    } else {
                        // In 2D mode, update region normally
                        if !currentRegion.center.isEqual(to: self.parent.region.center, tolerance: 0.01) ||
                           abs(currentRegion.span.latitudeDelta - self.parent.region.span.latitudeDelta) > 0.01 {
                            self.parent.region = currentRegion
                        }

                        // Reflect camera changes
                        if abs(currentCamera.heading - self.parent.rotation) > 1.0 {
                            self.parent.rotation = currentCamera.heading
                        }
                        if abs(currentCamera.pitch - self.parent.pitch) > 1.0 {
                            self.parent.pitch = currentCamera.pitch
                        }
                    }
                }
            }
        }
    }
}

class LeadMapAnnotation: NSObject, MKAnnotation {
    let lead: Lead
    
    var coordinate: CLLocationCoordinate2D {
        return lead.coordinate
    }
    
    var title: String? {
        // Prioritize name if it exists, otherwise show address
        if let name = lead.name, !name.isEmpty {
            return name
        } else if let address = lead.address, !address.isEmpty {
            return address
        }
        return lead.displayName
    }
    
    var subtitle: String? {
        return lead.leadStatus.displayName
    }
    
    init(lead: Lead) {
        self.lead = lead
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
