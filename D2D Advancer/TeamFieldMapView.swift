import SwiftUI
import MapKit
import UIKit

struct TeamFieldMapView: UIViewRepresentable {
    let workspaces: [TeamRepWorkspace]
    @Binding var selectedRepUserId: String?

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.mapType = .standard
        mapView.showsCompass = false
        mapView.pointOfInterestFilter = .excludingAll
        mapView.isRotateEnabled = true
        mapView.isPitchEnabled = false
        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        context.coordinator.parent = self

        let visibleWorkspaces = filteredWorkspaces
        let signature = annotationSignature(for: visibleWorkspaces)
        guard signature != context.coordinator.lastSignature else { return }
        context.coordinator.lastSignature = signature

        let oldAnnotations = mapView.annotations.filter { !($0 is MKUserLocation) }
        mapView.removeAnnotations(oldAnnotations)
        mapView.removeOverlays(mapView.overlays)

        let leadAnnotations = visibleWorkspaces.flatMap { workspace in
            workspace.assignedLeads.map { lead in
                TeamLeadMapItemAnnotation(lead: lead, repName: workspace.member.displayName)
            }
        }
        let repAnnotations = visibleWorkspaces.compactMap { workspace -> TeamRepLiveAnnotation? in
            guard let liveLocation = workspace.liveLocation else { return nil }
            return TeamRepLiveAnnotation(workspace: workspace, liveLocation: liveLocation)
        }
        mapView.addAnnotations(leadAnnotations + repAnnotations)

        for workspace in visibleWorkspaces where workspace.routePoints.count > 1 {
            var coordinates = workspace.routePoints.map {
                CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
            }
            mapView.addOverlay(MKPolyline(coordinates: &coordinates, count: coordinates.count))
        }

        if !context.coordinator.userHasInteracted {
            let coordinates = visibleWorkspaces.flatMap { workspace -> [CLLocationCoordinate2D] in
                let leadCoordinates = workspace.assignedLeads.map {
                    CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
                }
                let liveCoordinates = workspace.liveLocation.map {
                    [CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)]
                } ?? []
                let routeCoordinates = workspace.routePoints.map {
                    CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
                }
                return leadCoordinates + liveCoordinates + routeCoordinates
            }
            if let region = Self.region(containing: coordinates) {
                mapView.setRegion(region, animated: true)
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    private var filteredWorkspaces: [TeamRepWorkspace] {
        guard let selectedRepUserId else { return workspaces }
        return workspaces.filter { $0.member.userId == selectedRepUserId }
    }

    private func annotationSignature(for workspaces: [TeamRepWorkspace]) -> String {
        workspaces.map { workspace in
            let live = workspace.liveLocation.map { "\($0.id):\($0.latitude):\($0.longitude)" } ?? "off"
            let leads = workspace.assignedLeads.map { "\($0.id):\($0.latitude):\($0.longitude):\($0.status.rawValue):\($0.isHighPriority)" }.joined(separator: ",")
            let route = workspace.routePoints.map { "\($0.id):\($0.latitude):\($0.longitude)" }.joined(separator: ",")
            return "\(workspace.member.userId)|\(live)|\(leads)|\(route)"
        }
        .joined(separator: "|")
    }

    private static func region(containing coordinates: [CLLocationCoordinate2D]) -> MKCoordinateRegion? {
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

        let latitudeDelta = max((maxLatitude - minLatitude) * 1.6, 0.01)
        let longitudeDelta = max((maxLongitude - minLongitude) * 1.6, 0.01)
        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(
                latitude: (minLatitude + maxLatitude) / 2,
                longitude: (minLongitude + maxLongitude) / 2
            ),
            span: MKCoordinateSpan(latitudeDelta: latitudeDelta, longitudeDelta: longitudeDelta)
        )
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var parent: TeamFieldMapView
        var lastSignature = ""
        var userHasInteracted = false

        init(parent: TeamFieldMapView) {
            self.parent = parent
        }

        func mapView(_ mapView: MKMapView, regionWillChangeAnimated animated: Bool) {
            userHasInteracted = true
        }

        func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
            if let repAnnotation = view.annotation as? TeamRepLiveAnnotation {
                parent.selectedRepUserId = repAnnotation.repUserId
            }
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if annotation is MKUserLocation { return nil }

            if let repAnnotation = annotation as? TeamRepLiveAnnotation {
                let identifier = "TeamRepLiveAnnotation"
                let view = mapView.dequeueReusableAnnotationView(withIdentifier: identifier) as? MKMarkerAnnotationView
                    ?? MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: identifier)
                view.annotation = repAnnotation
                view.canShowCallout = true
                view.markerTintColor = .systemBlue
                view.glyphImage = UIImage(systemName: "location.fill")
                view.displayPriority = .required
                return view
            }

            guard let leadAnnotation = annotation as? TeamLeadMapItemAnnotation else { return nil }
            let identifier = "TeamLeadMapItemAnnotation"
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: identifier) as? MKMarkerAnnotationView
                ?? MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: identifier)
            view.annotation = leadAnnotation
            view.canShowCallout = true
            view.markerTintColor = uiColor(for: leadAnnotation.lead.status)
            view.glyphImage = UIImage(systemName: leadAnnotation.lead.isHighPriority ? "star.fill" : glyphName(for: leadAnnotation.lead.status))
            return view
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            guard let polyline = overlay as? MKPolyline else { return MKOverlayRenderer(overlay: overlay) }
            let renderer = MKPolylineRenderer(polyline: polyline)
            renderer.strokeColor = UIColor.systemBlue.withAlphaComponent(0.72)
            renderer.lineWidth = 4
            renderer.lineJoin = .round
            renderer.lineCap = .round
            return renderer
        }

        private func glyphName(for status: TeamLeadStatus) -> String {
            switch status {
            case .notContacted:
                return "person.circle"
            case .notHome:
                return "house.slash.fill"
            case .contacted:
                return "bubble.left.and.bubble.right.fill"
            case .interested:
                return "heart.circle"
            case .followUp:
                return "arrow.clockwise.circle.fill"
            case .booked:
                return "calendar.badge.checkmark"
            case .converted:
                return "checkmark.circle"
            case .notInterested:
                return "hand.raised.fill"
            }
        }

        private func uiColor(for status: TeamLeadStatus) -> UIColor {
            switch status {
            case .notContacted:
                return .systemGray
            case .notHome:
                return .brown
            case .contacted:
                return .systemTeal
            case .interested:
                return .systemOrange
            case .followUp:
                return .systemPurple
            case .booked:
                return .systemIndigo
            case .converted:
                return .systemGreen
            case .notInterested:
                return .systemRed
            }
        }
    }
}

private final class TeamLeadMapItemAnnotation: NSObject, MKAnnotation {
    let lead: TeamLead
    let repName: String

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: lead.latitude, longitude: lead.longitude)
    }

    var title: String? {
        lead.name
    }

    var subtitle: String? {
        "\(repName) • \(lead.status.rawValue.replacingOccurrences(of: "_", with: " "))"
    }

    init(lead: TeamLead, repName: String) {
        self.lead = lead
        self.repName = repName
        super.init()
    }
}

private final class TeamRepLiveAnnotation: NSObject, MKAnnotation {
    let repUserId: String
    let repName: String
    let liveLocation: TeamDutyLocationPoint

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: liveLocation.latitude, longitude: liveLocation.longitude)
    }

    var title: String? {
        "\(repName) live"
    }

    var subtitle: String? {
        "Updated \(liveLocation.recordedAt.formatted(date: .omitted, time: .shortened))"
    }

    init(workspace: TeamRepWorkspace, liveLocation: TeamDutyLocationPoint) {
        self.repUserId = workspace.member.userId
        self.repName = workspace.member.displayName
        self.liveLocation = liveLocation
        super.init()
    }
}
