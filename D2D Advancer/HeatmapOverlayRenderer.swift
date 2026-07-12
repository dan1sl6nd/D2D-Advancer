import MapKit
import UIKit

class HeatmapOverlayRenderer: MKOverlayRenderer {
    /// Color gradient stops: (position 0-1, UIColor)
    private let gradientColors: [(position: Double, color: UIColor)] = [
        (0.0, UIColor.clear),
        (0.15, UIColor(red: 0.0, green: 0.3, blue: 0.8, alpha: 0.25)),   // blue
        (0.30, UIColor(red: 0.0, green: 0.7, blue: 0.8, alpha: 0.35)),   // cyan
        (0.45, UIColor(red: 0.1, green: 0.8, blue: 0.3, alpha: 0.40)),   // green
        (0.60, UIColor(red: 0.9, green: 0.8, blue: 0.0, alpha: 0.45)),   // yellow
        (0.75, UIColor(red: 0.9, green: 0.5, blue: 0.0, alpha: 0.50)),   // orange
        (0.90, UIColor(red: 0.486, green: 0.228, blue: 0.929, alpha: 0.55)), // electric violet
        (1.0, UIColor(red: 0.486, green: 0.228, blue: 0.929, alpha: 0.65))   // electric violet deep
    ]

    override func draw(_ mapRect: MKMapRect, zoomScale: MKZoomScale, in context: CGContext) {
        guard let heatmapOverlay = overlay as? HeatmapOverlay,
              !heatmapOverlay.heatPoints.isEmpty else { return }

        let rect = self.rect(for: mapRect)

        // Determine grid resolution based on zoom level (fewer pixels when zoomed out)
        let pixelSize = max(4.0, 8.0 / Double(zoomScale))
        let cols = Int(rect.width / pixelSize) + 1
        let rows = Int(rect.height / pixelSize) + 1

        guard cols > 0, rows > 0 else { return }

        // Convert heat points to map points once
        let mapPoints = heatmapOverlay.heatPoints.map { hp -> (point: MKMapPoint, intensity: Double) in
            (MKMapPoint(hp.coordinate), hp.intensity)
        }

        // Kernel radius in map points
        let radiusMapPoints = heatmapOverlay.radiusInMeters * MKMapPointsPerMeterAtLatitude(heatmapOverlay.coordinate.latitude)

        for row in 0..<rows {
            for col in 0..<cols {
                let x = mapRect.origin.x + Double(col) * (mapRect.size.width / Double(cols))
                let y = mapRect.origin.y + Double(row) * (mapRect.size.height / Double(rows))
                let samplePoint = MKMapPoint(x: x, y: y)

                // Sum Gaussian-weighted intensities from all heat points
                var weightedSum: Double = 0
                var weightSum: Double = 0

                for hp in mapPoints {
                    let dx = samplePoint.x - hp.point.x
                    let dy = samplePoint.y - hp.point.y
                    let distSq = dx * dx + dy * dy
                    let radiusSq = radiusMapPoints * radiusMapPoints

                    if distSq < radiusSq * 4 { // Only consider points within 2x radius
                        let weight = exp(-distSq / (2 * radiusSq))
                        weightedSum += hp.intensity * weight
                        weightSum += weight
                    }
                }

                guard weightSum > 0.01 else { continue }

                let value = min(weightedSum / max(weightSum, 1.0), 100.0) / 100.0 // Normalize to 0-1

                if value < 0.05 { continue } // Skip near-zero

                let color = interpolateColor(at: value)
                context.setFillColor(color.cgColor)

                let drawRect = self.rect(for: MKMapRect(x: x, y: y,
                    width: mapRect.size.width / Double(cols),
                    height: mapRect.size.height / Double(rows)))
                context.fill(drawRect)
            }
        }
    }

    private func interpolateColor(at position: Double) -> UIColor {
        let clamped = max(0, min(1, position))

        // Find the two gradient stops to interpolate between
        var lower = gradientColors.first!
        var upper = gradientColors.last!

        for i in 0..<gradientColors.count - 1 {
            if clamped >= gradientColors[i].position && clamped <= gradientColors[i + 1].position {
                lower = gradientColors[i]
                upper = gradientColors[i + 1]
                break
            }
        }

        let range = upper.position - lower.position
        guard range > 0 else { return lower.color }
        let t = (clamped - lower.position) / range

        var lr: CGFloat = 0, lg: CGFloat = 0, lb: CGFloat = 0, la: CGFloat = 0
        var ur: CGFloat = 0, ug: CGFloat = 0, ub: CGFloat = 0, ua: CGFloat = 0
        lower.color.getRed(&lr, green: &lg, blue: &lb, alpha: &la)
        upper.color.getRed(&ur, green: &ug, blue: &ub, alpha: &ua)

        return UIColor(
            red: lr + (ur - lr) * t,
            green: lg + (ug - lg) * t,
            blue: lb + (ub - lb) * t,
            alpha: la + (ua - la) * t
        )
    }
}
