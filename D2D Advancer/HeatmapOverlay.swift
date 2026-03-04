import MapKit

/// A heat point representing a neighborhood center with its score as intensity.
struct HeatPoint {
    let coordinate: CLLocationCoordinate2D
    let intensity: Double // 0-100 (neighborhood score)
}

/// MKOverlay that covers the visible map region and holds heat point data.
class HeatmapOverlay: NSObject, MKOverlay {
    let heatPoints: [HeatPoint]
    let boundingMapRect: MKMapRect
    let coordinate: CLLocationCoordinate2D

    /// Radius in meters for the Gaussian kernel falloff.
    var radiusInMeters: CLLocationDistance = 500

    init(heatPoints: [HeatPoint], region: MKCoordinateRegion) {
        self.heatPoints = heatPoints

        // Calculate bounding rect from region
        let topLeft = MKMapPoint(CLLocationCoordinate2D(
            latitude: region.center.latitude + region.span.latitudeDelta / 2,
            longitude: region.center.longitude - region.span.longitudeDelta / 2
        ))
        let bottomRight = MKMapPoint(CLLocationCoordinate2D(
            latitude: region.center.latitude - region.span.latitudeDelta / 2,
            longitude: region.center.longitude + region.span.longitudeDelta / 2
        ))
        self.boundingMapRect = MKMapRect(
            x: min(topLeft.x, bottomRight.x),
            y: min(topLeft.y, bottomRight.y),
            width: abs(bottomRight.x - topLeft.x),
            height: abs(bottomRight.y - topLeft.y)
        )
        self.coordinate = region.center
        super.init()
    }
}
