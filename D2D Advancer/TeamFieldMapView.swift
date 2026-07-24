import SwiftUI
import MapKit
import UIKit

struct TeamFieldMapView: UIViewRepresentable {
    let workspaces: [TeamRepWorkspace]
    @Binding var selectedRepUserId: String?
    var onLeadTap: (TeamLead) -> Void = { _ in }
    var onLeadClusterTap: ([TeamLeadClusterItem], CLLocationCoordinate2D) -> Void = { _, _ in }

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
            let bookedLeadIDs = Set(
                workspace.assignedBookings
                    .filter(\.isFutureEditable)
                    .map(\.leadId)
            )
            return workspace.assignedLeads.map { lead in
                TeamLeadMapItemAnnotation(
                    lead: lead,
                    repName: workspace.member.displayName,
                    hasActiveBooking: bookedLeadIDs.contains(lead.id)
                )
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
            let leads = workspace.assignedLeads.map { "\($0.id):\($0.latitude):\($0.longitude):\($0.status.rawValue):\($0.isHighPriority):\($0.price):\($0.estimatedValue):\($0.updatedAt.timeIntervalSince1970)" }.joined(separator: ",")
            let bookings = workspace.assignedBookings.map { "\($0.id):\($0.leadId):\($0.status.rawValue):\($0.updatedAt.timeIntervalSince1970)" }.joined(separator: ",")
            let route = workspace.routePoints.map { "\($0.id):\($0.latitude):\($0.longitude)" }.joined(separator: ",")
            return "\(workspace.member.userId)|\(live)|\(leads)|\(bookings)|\(route)"
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
            if let cluster = view.annotation as? MKClusterAnnotation {
                let items = TeamLeadClusterSummary.sortedItems(
                    cluster.memberAnnotations.compactMap { ($0 as? TeamLeadMapItemAnnotation)?.clusterItem }
                )
                guard !items.isEmpty else { return }
                mapView.deselectAnnotation(cluster, animated: false)

                if shouldOpenClusterSheet(mapView: mapView, cluster: cluster) {
                    parent.onLeadClusterTap(items, cluster.coordinate)
                } else {
                    zoomIntoCluster(cluster, on: mapView)
                }
            } else if let repAnnotation = view.annotation as? TeamRepLiveAnnotation {
                parent.selectedRepUserId = repAnnotation.repUserId
            } else if let leadAnnotation = view.annotation as? TeamLeadMapItemAnnotation {
                parent.onLeadTap(leadAnnotation.lead)
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
                view.clusteringIdentifier = nil
                return view
            }

            if let cluster = annotation as? MKClusterAnnotation {
                let identifier = "TeamLeadClusterAnnotation"
                let view = mapView.dequeueReusableAnnotationView(withIdentifier: identifier) as? MKMarkerAnnotationView
                    ?? MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: identifier)
                let items = cluster.memberAnnotations.compactMap { ($0 as? TeamLeadMapItemAnnotation)?.clusterItem }
                let summary = TeamLeadClusterSummary(items: items)
                view.annotation = cluster
                view.glyphText = summary.glyphText
                view.markerTintColor = summary.uiColor
                view.glyphTintColor = .white
                view.displayPriority = summary.isImportant ? .required : .defaultHigh
                view.collisionMode = .circle
                return view
            }

            guard let leadAnnotation = annotation as? TeamLeadMapItemAnnotation else { return nil }
            let identifier = "TeamLeadMapItemAnnotation"
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: identifier) as? MKMarkerAnnotationView
                ?? MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: identifier)
            view.annotation = leadAnnotation
            view.canShowCallout = true
            view.markerTintColor = leadAnnotation.hasActiveBooking
                ? .systemIndigo
                : uiColor(for: leadAnnotation.lead.workflowStatus)
            let glyph = leadAnnotation.hasActiveBooking
                ? "calendar.badge.checkmark"
                : glyphName(for: leadAnnotation.lead.workflowStatus)
            view.glyphImage = UIImage(systemName: TeamLeadAttentionPolicy.isActionableHighPriority(leadAnnotation.lead) ? "star.fill" : glyph)
            view.clusteringIdentifier = "TeamLeadCluster"
            view.displayPriority = TeamLeadAttentionPolicy.needsOwnerAttention(leadAnnotation.lead) ? .required : .defaultHigh
            return view
        }

        private func shouldOpenClusterSheet(mapView: MKMapView, cluster: MKClusterAnnotation) -> Bool {
            let maxSpan = max(mapView.region.span.latitudeDelta, mapView.region.span.longitudeDelta)
            return maxSpan <= 0.012 || coordinateSpread(for: cluster) <= 0.0012
        }

        private func zoomIntoCluster(_ cluster: MKClusterAnnotation, on mapView: MKMapView) {
            let coordinates = cluster.memberAnnotations.map(\.coordinate)
            guard let region = paddedRegion(containing: coordinates, currentRegion: mapView.region) else { return }
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

            return MKCoordinateRegion(
                center: CLLocationCoordinate2D(
                    latitude: (minLatitude + maxLatitude) / 2,
                    longitude: (minLongitude + maxLongitude) / 2
                ),
                span: MKCoordinateSpan(
                    latitudeDelta: min(max((maxLatitude - minLatitude) * 2.2, 0.0025), currentRegion.span.latitudeDelta * 0.55),
                    longitudeDelta: min(max((maxLongitude - minLongitude) * 2.2, 0.0025), currentRegion.span.longitudeDelta * 0.55)
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
            switch status.workflowStatus {
            case .notContacted:
                return "person.circle"
            case .notHome:
                return "house.slash.fill"
            case .interested:
                return "heart.circle"
            case .converted:
                return "checkmark.circle"
            case .notInterested:
                return "hand.raised.fill"
            case .contacted, .followUp, .booked:
                return "person.circle"
            }
        }

        private func uiColor(for status: TeamLeadStatus) -> UIColor {
            switch status.workflowStatus {
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
            case .contacted, .followUp, .booked:
                return .systemGray
            }
        }
    }
}

private final class TeamLeadMapItemAnnotation: NSObject, MKAnnotation {
    let lead: TeamLead
    let repName: String
    let hasActiveBooking: Bool
    var clusterItem: TeamLeadClusterItem {
        TeamLeadClusterItem(lead: lead, repName: repName, hasActiveBooking: hasActiveBooking)
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: lead.latitude, longitude: lead.longitude)
    }

    var title: String? {
        lead.name
    }

    var subtitle: String? {
        "\(repName) • \(lead.workflowStatus.teamDisplayName)"
    }

    init(lead: TeamLead, repName: String, hasActiveBooking: Bool) {
        self.lead = lead
        self.repName = repName
        self.hasActiveBooking = hasActiveBooking
        super.init()
    }
}

struct TeamLeadClusterItem: Identifiable, Equatable {
    var id: String { lead.id }
    let lead: TeamLead
    let repName: String
    var hasActiveBooking = false
}

struct TeamLeadClusterSummary {
    let items: [TeamLeadClusterItem]

    var count: Int {
        items.count
    }

    var glyphText: String {
        count > 99 ? "99+" : "\(count)"
    }

    var isImportant: Bool {
        items.contains { item in
            TeamLeadAttentionPolicy.needsOwnerAttention(item.lead)
        }
    }

    var highPriorityCount: Int {
        items.filter { TeamLeadAttentionPolicy.isActionableHighPriority($0.lead) }.count
    }

    var bookedCount: Int {
        items.filter { $0.hasActiveBooking || $0.lead.status == .booked }.count
    }

    var hotLeadCount: Int {
        items.filter { item in
            TeamLeadAttentionPolicy.needsOwnerAttention(item.lead)
        }.count
    }

    var convertedCount: Int {
        items.filter { $0.lead.workflowStatus == .converted }.count
    }

    var repCount: Int {
        Set(items.map(\.repName)).count
    }

    var statusCounts: [(status: TeamLeadStatus, count: Int)] {
        TeamLeadStatus.allCases
            .map { status in (status, items.filter { $0.lead.workflowStatus == status }.count) }
            .filter { $0.count > 0 }
            .sorted { lhs, rhs in
                if lhs.count != rhs.count { return lhs.count > rhs.count }
                return TeamLeadImportance.rank(lhs.status) > TeamLeadImportance.rank(rhs.status)
            }
    }

    var headline: String {
        if highPriorityCount > 0 {
            return "\(highPriorityCount) high priority"
        }
        if bookedCount > 0 {
            return "\(bookedCount) booked"
        }
        if hotLeadCount > 0 {
            return "\(hotLeadCount) important"
        }
        return "Team lead cluster"
    }

    var detailLine: String {
        var parts = ["\(count) \(count == 1 ? "lead" : "leads")"]
        parts.append("\(repCount) \(repCount == 1 ? "worker" : "workers")")
        if let dominant = statusCounts.first {
            parts.append(dominant.status.teamDisplayName)
        }
        return parts.joined(separator: " • ")
    }

    var uiColor: UIColor {
        if highPriorityCount > 0 {
            return .systemPink
        }
        if bookedCount > 0 {
            return .systemIndigo
        }
        if hotLeadCount > 0 {
            return .systemOrange
        }
        if convertedCount > 0 && convertedCount >= max(1, count / 2) {
            return .systemGreen
        }
        guard let dominant = statusCounts.first?.status else {
            return .systemPurple
        }
        switch dominant.workflowStatus {
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
        case .contacted, .followUp, .booked:
            return .systemGray
        }
    }

    var color: Color {
        Color(uiColor)
    }

    var sortedItems: [TeamLeadClusterItem] {
        Self.sortedItems(items)
    }

    static func sortedItems(_ items: [TeamLeadClusterItem]) -> [TeamLeadClusterItem] {
        items.sorted { lhs, rhs in
            let lhsScore = priorityScore(for: lhs.lead)
            let rhsScore = priorityScore(for: rhs.lead)
            if lhsScore != rhsScore { return lhsScore > rhsScore }
            return lhs.lead.updatedAt > rhs.lead.updatedAt
        }
    }

    private static func priorityScore(for lead: TeamLead) -> Int {
        var score = 0
        if TeamLeadAttentionPolicy.isActionableHighPriority(lead) { score += 700 }
        score += TeamLeadImportance.rank(lead.status) * 120
        if max(lead.price, lead.estimatedValue) > 0 {
            score += min(120, Int(max(lead.price, lead.estimatedValue) / 100))
        }
        return score
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
