# Territory Intelligence Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add heatmap visualization, route optimization, and scoring weight sliders to the map tab.

**Architecture:** Three independent features sharing the existing Neighborhood/NeighborhoodScoreEngine infrastructure. The heatmap replaces unused circle overlays with a kernel-density renderer. Route optimization uses nearest-neighbor TSP with MKDirections refinement. Scoring weights expose existing AppStorage keys via new UI sliders.

**Tech Stack:** SwiftUI, MapKit (MKOverlay, MKOverlayRenderer, MKDirections), Core Data, CoreLocation

---

### Task 1: Scoring Weight Sliders UI

**Files:**
- Create: `D2D Advancer/ScoringWeightsView.swift`
- Modify: `D2D Advancer/DemographicsPreferencesView.swift` (line ~155, before `Spacer(minLength: 80)`)
- Modify: `D2D Advancer/NeighborhoodScoreEngine.swift` (lines 17-33, `ScoringWeights` struct)

**Why first:** Simplest feature. The scoring engine already reads weights — we just need UI. This also validates that weight changes flow through to score recalculation, which the heatmap depends on.

**Step 1: Add AppStorage-backed weight properties to ScoringWeights**

In `NeighborhoodScoreEngine.swift`, add a convenience initializer that reads from AppStorage defaults. The existing `ScoringWeights` struct stays unchanged, but add a static factory:

```swift
// Add after the ScoringWeights struct (after line 33):

extension NeighborhoodScoreEngine.ScoringWeights {
    /// Creates weights from the user's saved preferences.
    static func fromUserDefaults() -> NeighborhoodScoreEngine.ScoringWeights {
        let defaults = UserDefaults.standard
        return NeighborhoodScoreEngine.ScoringWeights(
            incomeMatch: defaults.double(forKey: "weightIncome") > 0 ? defaults.double(forKey: "weightIncome") / 100.0 : 0.30,
            populationDensity: defaults.double(forKey: "weightDensity") > 0 ? defaults.double(forKey: "weightDensity") / 100.0 : 0.20,
            homeValueMatch: defaults.double(forKey: "weightHomeValue") > 0 ? defaults.double(forKey: "weightHomeValue") / 100.0 : 0.25,
            conversionRate: defaults.double(forKey: "weightConversion") > 0 ? defaults.double(forKey: "weightConversion") / 100.0 : 0.25
        )
    }
}
```

**Step 2: Create ScoringWeightsView.swift**

New file with 4 sliders (0-100 each), a stacked bar visualization, auto-normalization, and a live preview section. Each slider is bound to `@AppStorage` keys: `weightIncome`, `weightDensity`, `weightHomeValue`, `weightConversion`.

```swift
import SwiftUI

struct ScoringWeightsView: View {
    @AppStorage("weightIncome") private var weightIncome: Double = 30
    @AppStorage("weightDensity") private var weightDensity: Double = 20
    @AppStorage("weightHomeValue") private var weightHomeValue: Double = 25
    @AppStorage("weightConversion") private var weightConversion: Double = 25

    private var total: Double {
        weightIncome + weightDensity + weightHomeValue + weightConversion
    }

    private func normalized(_ value: Double) -> Double {
        guard total > 0 else { return 0.25 }
        return value / total
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "slider.horizontal.3")
                    .foregroundColor(Color.electricViolet)
                Text("Scoring Weights")
                    .font(.headline)
                Spacer()
                Button("Reset") {
                    weightIncome = 30
                    weightDensity = 20
                    weightHomeValue = 25
                    weightConversion = 25
                }
                .font(.caption)
                .foregroundColor(Color.textSecondary)
            }
            .padding(.horizontal, 20)

            VStack(spacing: 16) {
                // Stacked bar visualization
                GeometryReader { geometry in
                    HStack(spacing: 1) {
                        Rectangle()
                            .fill(Color.statusConverted)
                            .frame(width: geometry.size.width * normalized(weightIncome))
                        Rectangle()
                            .fill(Color.dataCyan)
                            .frame(width: geometry.size.width * normalized(weightDensity))
                        Rectangle()
                            .fill(Color.statusNotHome)
                            .frame(width: geometry.size.width * normalized(weightHomeValue))
                        Rectangle()
                            .fill(Color.electricViolet)
                            .frame(width: geometry.size.width * normalized(weightConversion))
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .frame(height: 12)

                // Sliders
                weightSlider(label: "Income", icon: "dollarsign.circle", color: .statusConverted, value: $weightIncome)
                weightSlider(label: "Density", icon: "person.3", color: .dataCyan, value: $weightDensity)
                weightSlider(label: "Home Value", icon: "house", color: .statusNotHome, value: $weightHomeValue)
                weightSlider(label: "Conversion", icon: "chart.line.uptrend.xyaxis", color: .electricViolet, value: $weightConversion)

                // Live preview
                VStack(alignment: .leading, spacing: 4) {
                    Text("Effective Weights")
                        .font(.caption)
                        .foregroundColor(Color.textMuted)
                    HStack(spacing: 12) {
                        weightBadge("Inc", normalized(weightIncome), color: .statusConverted)
                        weightBadge("Den", normalized(weightDensity), color: .dataCyan)
                        weightBadge("Val", normalized(weightHomeValue), color: .statusNotHome)
                        weightBadge("Conv", normalized(weightConversion), color: .electricViolet)
                    }
                }
            }
            .padding(16)
            .background(Color.obsidianSurface)
            .cornerRadius(12)
            .padding(.horizontal, 20)
        }
    }

    @ViewBuilder
    private func weightSlider(label: String, icon: String, color: Color, value: Binding<Double>) -> some View {
        VStack(spacing: 4) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                    .frame(width: 20)
                Text(label)
                    .font(.subheadline)
                    .foregroundColor(Color.textPrimary)
                Spacer()
                Text("\(Int(normalized(value.wrappedValue) * 100))%")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(color)
                    .frame(width: 44, alignment: .trailing)
            }
            Slider(value: value, in: 0...100, step: 5)
                .tint(color)
        }
    }

    @ViewBuilder
    private func weightBadge(_ label: String, _ value: Double, color: Color) -> some View {
        VStack(spacing: 2) {
            Text("\(Int(value * 100))%")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundColor(color)
            Text(label)
                .font(.system(size: 10))
                .foregroundColor(Color.textMuted)
        }
        .frame(maxWidth: .infinity)
    }
}
```

**Step 3: Embed ScoringWeightsView in DemographicsPreferencesView**

In `DemographicsPreferencesView.swift`, add the weights section after the Homeownership section (before line 156 `Spacer(minLength: 80)`):

```swift
                    // Scoring Weights
                    ScoringWeightsView()
```

**Step 4: Update industry presets to include weights**

In `DemographicsPreferencesView.swift`, find the existing `TargetProfile` enum and its `apply()` method. When a profile is selected, also set the weight AppStorage values. Add to each profile case in the selection handler:

```swift
// After setting income/homeValue targets for each profile, also set:
UserDefaults.standard.set(incomeWeight, forKey: "weightIncome")
UserDefaults.standard.set(densityWeight, forKey: "weightDensity")
UserDefaults.standard.set(homeValueWeight, forKey: "weightHomeValue")
UserDefaults.standard.set(conversionWeight, forKey: "weightConversion")
```

Profile weight mappings (from design doc):
- Solar: 35, 15, 35, 15
- Roofing: 25, 20, 30, 25
- HVAC: 30, 20, 25, 25
- Windows: 25, 20, 30, 25
- Landscaping: 25, 10, 40, 25
- Remodeling: 30, 15, 35, 20
- Security: 30, 25, 20, 25
- Pools: 25, 10, 40, 25
- Toronto General: 30, 20, 25, 25
- Toronto Premium: 25, 15, 40, 20
- Custom: no weight change

**Step 5: Build and verify**

Build the project in Xcode. Open More > Demographics and verify:
- Weight sliders appear below Homeownership
- Stacked bar updates in real-time
- Percentages normalize to 100%
- Reset button restores defaults (30/20/25/25)
- Selecting a profile preset updates the weight sliders

**Step 6: Commit**

```bash
git add "D2D Advancer/ScoringWeightsView.swift" "D2D Advancer/DemographicsPreferencesView.swift" "D2D Advancer/NeighborhoodScoreEngine.swift"
git commit -m "feat: add scoring weight sliders to demographics preferences"
```

---

### Task 2: Heatmap Overlay Infrastructure

**Files:**
- Create: `D2D Advancer/HeatmapOverlay.swift`
- Create: `D2D Advancer/HeatmapOverlayRenderer.swift`

**Step 1: Create HeatmapOverlay.swift**

This is an `MKOverlay` that represents the heatmap data — an array of heat points (coordinate + intensity) covering the visible map region.

```swift
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
```

**Step 2: Create HeatmapOverlayRenderer.swift**

Custom `MKOverlayRenderer` that performs kernel density estimation and draws a color gradient.

```swift
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
```

**Step 3: Build and verify**

Build the project. These are standalone files with no consumers yet — they should compile cleanly.

**Step 4: Commit**

```bash
git add "D2D Advancer/HeatmapOverlay.swift" "D2D Advancer/HeatmapOverlayRenderer.swift"
git commit -m "feat: add heatmap overlay and kernel-density renderer"
```

---

### Task 3: Heatmap Data Provider

**Files:**
- Modify: `D2D Advancer/NeighborhoodOverlayManager.swift` (add heatmap data generation)

**Step 1: Add heatmap data generation to NeighborhoodOverlayManager**

Add a method that converts visible neighborhoods into `HeatPoint` array and creates a `HeatmapOverlay`. Also add a published property for the overlay:

```swift
// Add to NeighborhoodOverlayManager:
@Published var heatmapOverlay: HeatmapOverlay?

/// Generates a heatmap overlay from currently visible neighborhoods.
func generateHeatmap(for region: MKCoordinateRegion) async {
    // Ensure neighborhoods are loaded
    if visibleNeighborhoods.isEmpty {
        await loadNeighborhoods(for: region)
    }

    let points = visibleNeighborhoods.compactMap { neighborhood -> HeatPoint? in
        guard neighborhood.centerLatitude != 0 || neighborhood.centerLongitude != 0 else { return nil }
        return HeatPoint(
            coordinate: CLLocationCoordinate2D(
                latitude: neighborhood.centerLatitude,
                longitude: neighborhood.centerLongitude
            ),
            intensity: neighborhood.score
        )
    }

    guard !points.isEmpty else {
        heatmapOverlay = nil
        return
    }

    let overlay = HeatmapOverlay(heatPoints: points, region: region)
    // Adjust radius based on zoom — tighter at street level, wider when zoomed out
    let spanKm = region.span.latitudeDelta * 111 // rough km per degree
    overlay.radiusInMeters = max(300, min(2000, spanKm * 50))
    heatmapOverlay = overlay
}
```

**Step 2: Also backfill neighborhoods from existing leads in the region**

Add to `loadNeighborhoods(for:)` method: after loading cached neighborhoods, if fewer than 3 are found, also create neighborhood entries from lead clusters in the visible area (using existing `NeighborhoodDataService`).

Look at the existing `loadNeighborhoods` method and add lead-cluster sampling after the cached neighborhood check. For each visible lead with no neighborhood, call `NeighborhoodDataService.shared.fetchNeighborhoodData(for:)` to populate data.

**Step 3: Build and verify**

Build project. The new method won't be called yet but should compile.

**Step 4: Commit**

```bash
git add "D2D Advancer/NeighborhoodOverlayManager.swift"
git commit -m "feat: add heatmap data generation to overlay manager"
```

---

### Task 4: Wire Heatmap into MapView

**Files:**
- Modify: `D2D Advancer/MapView.swift` (add heatmap toggle + state)
- Modify: `D2D Advancer/AdvancedMapView.swift` (add overlay rendering to Coordinator)

**Step 1: Add heatmap state to MapView.swift**

Add to the state variables section (after line 18):

```swift
@StateObject private var overlayManager = NeighborhoodOverlayManager()
@State private var isHeatmapEnabled = false
```

**Step 2: Add heatmap toggle button to FAB menu**

Inside the `if isMapMenuExpanded {` block (after the Map Type button, around line 230), add:

```swift
// Heatmap Toggle Button
Button(action: {
    guard paywallManager.gateAction() else { return }
    isHeatmapEnabled.toggle()
    if isHeatmapEnabled {
        Task {
            await overlayManager.generateHeatmap(for: locationManager.region)
        }
    } else {
        overlayManager.heatmapOverlay = nil
    }
    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
        isMapMenuExpanded = false
    }
}) {
    Circle()
        .fill(isHeatmapEnabled ? Color.electricViolet : Color.obsidianSurface)
        .frame(width: 44, height: 44)
        .overlay(
            Image(systemName: "flame.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(isHeatmapEnabled ? .white : Color.electricViolet)
        )
        .overlay(
            Circle()
                .stroke(Color.obsidianBorder, lineWidth: isHeatmapEnabled ? 0 : 1)
        )
        .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
        .premiumLock()
}
.buttonStyle(PlainButtonStyle())
.transition(.scale.combined(with: .opacity))
```

**Step 3: Pass overlay data to AdvancedMapView**

Modify AdvancedMapView to accept optional overlay:

In `AdvancedMapView.swift`, add a new property:

```swift
var heatmapOverlay: HeatmapOverlay?
```

In `updateUIView`, add overlay management:

```swift
// After annotation updates (after line 160):
// Update heatmap overlay
let existingHeatmaps = mapView.overlays.compactMap { $0 as? HeatmapOverlay }
if let overlay = heatmapOverlay {
    if existingHeatmaps.isEmpty {
        mapView.addOverlay(overlay, level: .aboveRoads)
    } else if existingHeatmaps.first !== overlay {
        mapView.removeOverlays(existingHeatmaps)
        mapView.addOverlay(overlay, level: .aboveRoads)
    }
} else if !existingHeatmaps.isEmpty {
    mapView.removeOverlays(existingHeatmaps)
}
```

**Step 4: Add overlay renderer delegate method to Coordinator**

In `AdvancedMapView.Coordinator`, add the missing delegate method:

```swift
func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
    if overlay is HeatmapOverlay {
        return HeatmapOverlayRenderer(overlay: overlay)
    }
    return MKOverlayRenderer(overlay: overlay)
}
```

**Step 5: Refresh heatmap on region change**

In the Coordinator's `regionDidChangeAnimated` method, after updating region/camera, trigger a heatmap refresh if enabled. Add a callback closure to AdvancedMapView:

```swift
var onRegionChanged: ((MKCoordinateRegion) -> Void)?
```

Call it at the end of `regionDidChangeAnimated`:

```swift
self.parent.onRegionChanged?(currentRegion)
```

In `MapView.swift`, pass this callback when creating AdvancedMapView and use it to refresh:

```swift
onRegionChanged: { newRegion in
    if isHeatmapEnabled {
        Task {
            await overlayManager.generateHeatmap(for: newRegion)
        }
    }
}
```

**Step 6: Update all AdvancedMapView call sites**

Update the AdvancedMapView initializer call in MapView.swift to include the new parameters:

```swift
AdvancedMapView(
    region: $locationManager.region,
    mapType: $mapType,
    rotation: $mapRotation,
    pitch: $mapPitch,
    animateNextUpdate: $triggerMapAnimation,
    leads: Array(leads),
    heatmapOverlay: overlayManager.heatmapOverlay,
    onLeadTap: { lead in selectedLead = lead },
    onLongPress: { coordinate, lead in ... },
    onRegionChanged: { newRegion in ... }
)
```

**Step 7: Build and test**

Build the project. On the map, tap FAB → flame icon. Verify heatmap overlay appears (may need neighborhoods with non-zero scores in the area).

**Step 8: Commit**

```bash
git add "D2D Advancer/MapView.swift" "D2D Advancer/AdvancedMapView.swift"
git commit -m "feat: wire heatmap overlay into map with toggle button"
```

---

### Task 5: Heatmap Legend

**Files:**
- Modify: `D2D Advancer/MapView.swift` (add legend overlay when heatmap is active)

**Step 1: Add a compact legend view at the bottom-left of the map**

When `isHeatmapEnabled` is true, show a small legend strip. Add this in the map ZStack (after the FAB VStack):

```swift
// Heatmap Legend — bottom left
if isHeatmapEnabled {
    VStack {
        Spacer()
        HStack {
            HStack(spacing: 8) {
                LinearGradient(
                    colors: [
                        Color(red: 0.0, green: 0.3, blue: 0.8),
                        Color(red: 0.0, green: 0.7, blue: 0.8),
                        Color(red: 0.1, green: 0.8, blue: 0.3),
                        Color(red: 0.9, green: 0.8, blue: 0.0),
                        Color(red: 0.9, green: 0.5, blue: 0.0),
                        Color.electricViolet
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: 100, height: 8)
                .clipShape(Capsule())

                HStack(spacing: 0) {
                    Text("Low")
                        .foregroundColor(Color.textMuted)
                    Spacer()
                    Text("High")
                        .foregroundColor(Color.textMuted)
                }
                .font(.system(size: 9))
                .frame(width: 100)
            }
            .padding(8)
            .background(Color.obsidianSurface.opacity(0.9))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.obsidianBorder, lineWidth: 1)
            )
            Spacer()
        }
        .padding(.leading, 16)
        .padding(.bottom, 24)
    }
}
```

**Step 2: Build and verify**

Build. Toggle heatmap on — legend strip should appear bottom-left.

**Step 3: Commit**

```bash
git add "D2D Advancer/MapView.swift"
git commit -m "feat: add heatmap legend strip to map view"
```

---

### Task 6: Route Optimizer Engine

**Files:**
- Create: `D2D Advancer/RouteOptimizer.swift`

**Step 1: Create RouteOptimizer.swift**

A class that takes a starting coordinate and array of leads, then returns an optimally ordered route using nearest-neighbor heuristic with MKDirections refinement.

```swift
import Foundation
import MapKit
import CoreLocation

/// A single stop in an optimized route.
struct RouteStop {
    let lead: Lead
    let order: Int
    let estimatedArrival: Date?
    let drivingDurationFromPrevious: TimeInterval? // seconds
    let distanceFromPrevious: CLLocationDistance? // meters
}

/// Result of route optimization.
struct OptimizedRoute {
    let stops: [RouteStop]
    let totalDuration: TimeInterval
    let totalDistance: CLLocationDistance
    let polyline: MKPolyline?
}

@MainActor
class RouteOptimizer: ObservableObject {
    @Published var currentRoute: OptimizedRoute?
    @Published var isCalculating = false

    /// Optimizes visit order using nearest-neighbor heuristic + MKDirections refinement.
    func optimizeRoute(from start: CLLocationCoordinate2D, leads: [Lead]) async -> OptimizedRoute? {
        guard !leads.isEmpty else { return nil }
        isCalculating = true
        defer { isCalculating = false }

        var remaining = leads
        var ordered: [Lead] = []
        var currentLocation = start

        // Nearest-neighbor with MKDirections refinement for top candidates
        while !remaining.isEmpty {
            // Sort by haversine distance
            remaining.sort { lead1, lead2 in
                haversineDistance(from: currentLocation, to: lead1.coordinate) <
                haversineDistance(from: currentLocation, to: lead2.coordinate)
            }

            // Take top 3 candidates and get driving ETAs
            let candidates = Array(remaining.prefix(min(3, remaining.count)))

            if candidates.count == 1 {
                ordered.append(candidates[0])
                remaining.removeAll { $0.id == candidates[0].id }
                currentLocation = candidates[0].coordinate
                continue
            }

            // Get driving times for top candidates
            let best = await bestByDrivingTime(from: currentLocation, candidates: candidates)
            ordered.append(best)
            remaining.removeAll { $0.id == best.id }
            currentLocation = best.coordinate
        }

        // Respect appointment time windows: reorder leads with appointments to their correct slot
        let reordered = adjustForAppointments(ordered, startTime: Date(), startLocation: start)

        // Build route with ETAs
        let route = await buildRouteDetails(from: start, leads: reordered)
        currentRoute = route
        return route
    }

    /// Clears the current route.
    func clearRoute() {
        currentRoute = nil
    }

    // MARK: - Private

    private func haversineDistance(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) -> CLLocationDistance {
        let loc1 = CLLocation(latitude: from.latitude, longitude: from.longitude)
        let loc2 = CLLocation(latitude: to.latitude, longitude: to.longitude)
        return loc1.distance(from: loc2)
    }

    private func bestByDrivingTime(from: CLLocationCoordinate2D, candidates: [Lead]) async -> Lead {
        // Request MKDirections for each candidate
        var results: [(lead: Lead, eta: TimeInterval)] = []

        await withTaskGroup(of: (Lead, TimeInterval?).self) { group in
            for lead in candidates {
                group.addTask {
                    let eta = await self.getDrivingETA(from: from, to: lead.coordinate)
                    return (lead, eta)
                }
            }
            for await result in group {
                let eta = result.1 ?? self.haversineDistance(from: from, to: result.0.coordinate) / 13.0 // ~47km/h fallback
                results.append((result.0, eta))
            }
        }

        return results.min(by: { $0.eta < $1.eta })?.lead ?? candidates[0]
    }

    private nonisolated func getDrivingETA(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) async -> TimeInterval? {
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: from))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: to))
        request.transportType = .automobile

        do {
            let response = try await MKDirections(request: request).calculateETA()
            return response.expectedTravelTime
        } catch {
            return nil
        }
    }

    private func adjustForAppointments(_ leads: [Lead], startTime: Date, startLocation: CLLocationCoordinate2D) -> [Lead] {
        // Separate leads with and without appointment times
        var withAppointment: [(lead: Lead, time: Date)] = []
        var withoutAppointment: [Lead] = []

        for lead in leads {
            if let followUp = lead.followUpDate {
                withAppointment.append((lead, followUp))
            } else {
                withoutAppointment.append(lead)
            }
        }

        // If no appointments, return original order
        guard !withAppointment.isEmpty else { return leads }

        // Sort appointments by time
        withAppointment.sort { $0.time < $1.time }

        // Insert appointment leads at their correct time slots
        var result: [Lead] = []
        var freeLeads = withoutAppointment
        var appointmentIdx = 0
        var currentTime = startTime

        // Estimate ~10 min per stop + 5 min driving average
        let avgStopTime: TimeInterval = 15 * 60

        while appointmentIdx < withAppointment.count || !freeLeads.isEmpty {
            if appointmentIdx < withAppointment.count {
                let nextAppointment = withAppointment[appointmentIdx]
                let timeUntilAppointment = nextAppointment.time.timeIntervalSince(currentTime)

                // Fill time with free leads
                while !freeLeads.isEmpty && timeUntilAppointment > avgStopTime {
                    result.append(freeLeads.removeFirst())
                    currentTime = currentTime.addingTimeInterval(avgStopTime)
                    let remaining = nextAppointment.time.timeIntervalSince(currentTime)
                    if remaining <= avgStopTime { break }
                }

                result.append(nextAppointment.lead)
                currentTime = nextAppointment.time.addingTimeInterval(avgStopTime)
                appointmentIdx += 1
            } else {
                result.append(contentsOf: freeLeads)
                freeLeads.removeAll()
            }
        }

        return result
    }

    private func buildRouteDetails(from start: CLLocationCoordinate2D, leads: [Lead]) async -> OptimizedRoute {
        var stops: [RouteStop] = []
        var totalDuration: TimeInterval = 0
        var totalDistance: CLLocationDistance = 0
        var currentLocation = start
        var currentTime = Date()
        var allCoordinates: [CLLocationCoordinate2D] = [start]

        for (index, lead) in leads.enumerated() {
            let eta = await getDrivingETA(from: currentLocation, to: lead.coordinate)
            let distance = haversineDistance(from: currentLocation, to: lead.coordinate)
            let duration = eta ?? (distance / 13.0) // fallback ~47km/h

            currentTime = currentTime.addingTimeInterval(duration)
            totalDuration += duration
            totalDistance += distance

            stops.append(RouteStop(
                lead: lead,
                order: index + 1,
                estimatedArrival: currentTime,
                drivingDurationFromPrevious: duration,
                distanceFromPrevious: distance
            ))

            allCoordinates.append(lead.coordinate)
            currentLocation = lead.coordinate
        }

        let polyline = MKPolyline(coordinates: allCoordinates, count: allCoordinates.count)

        return OptimizedRoute(
            stops: stops,
            totalDuration: totalDuration,
            totalDistance: totalDistance,
            polyline: polyline
        )
    }
}
```

**Step 2: Build and verify**

Build the project. The class compiles but has no consumers yet.

**Step 3: Commit**

```bash
git add "D2D Advancer/RouteOptimizer.swift"
git commit -m "feat: add route optimizer with nearest-neighbor TSP and MKDirections"
```

---

### Task 7: Route Planner UI — Lead Selection Sheet

**Files:**
- Create: `D2D Advancer/RoutePlannerView.swift`

**Step 1: Create RoutePlannerView.swift**

A sheet view where the user selects which leads to include in the route. Pre-selects today's overdue + due follow-ups.

```swift
import SwiftUI
import CoreData
import MapKit

struct RoutePlannerView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var routeOptimizer: RouteOptimizer
    let startCoordinate: CLLocationCoordinate2D
    let allLeads: [Lead]
    var onRouteReady: () -> Void

    @State private var selectedLeadIDs: Set<UUID> = []
    @State private var searchText = ""

    private var filteredLeads: [Lead] {
        let base = allLeads.filter { $0.latitude != 0 || $0.longitude != 0 }
        if searchText.isEmpty { return base }
        return base.filter {
            ($0.name ?? "").localizedCaseInsensitiveContains(searchText) ||
            ($0.address ?? "").localizedCaseInsensitiveContains(searchText)
        }
    }

    private var todayFollowUps: [Lead] {
        let calendar = Calendar.current
        return allLeads.filter { lead in
            guard let followUp = lead.followUpDate else { return false }
            return calendar.isDateInToday(followUp) || followUp < Date()
        }
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Summary bar
                HStack {
                    Image(systemName: "mappin.and.ellipse")
                        .foregroundColor(Color.electricViolet)
                    Text("\(selectedLeadIDs.count) stops selected")
                        .font(.subheadline)
                        .foregroundColor(Color.textPrimary)
                    Spacer()
                    if !todayFollowUps.isEmpty {
                        Button("Add Today's (\(todayFollowUps.count))") {
                            for lead in todayFollowUps {
                                if let id = lead.id { selectedLeadIDs.insert(id) }
                            }
                        }
                        .font(.caption)
                        .foregroundColor(Color.electricViolet)
                    }
                }
                .padding()
                .background(Color.obsidianSurface)

                // Search
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(Color.textMuted)
                    TextField("Search leads...", text: $searchText)
                        .foregroundColor(Color.textPrimary)
                }
                .padding(10)
                .background(Color.obsidianElevated)
                .cornerRadius(8)
                .padding(.horizontal)
                .padding(.vertical, 8)

                // Lead list
                List {
                    ForEach(filteredLeads, id: \.objectID) { lead in
                        let isSelected = lead.id != nil && selectedLeadIDs.contains(lead.id!)
                        Button {
                            if let id = lead.id {
                                if isSelected {
                                    selectedLeadIDs.remove(id)
                                } else {
                                    selectedLeadIDs.insert(id)
                                }
                            }
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                    .foregroundColor(isSelected ? Color.electricViolet : Color.textMuted)
                                    .font(.title3)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(lead.displayName)
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                        .foregroundColor(Color.textPrimary)
                                    if let address = lead.address, !address.isEmpty {
                                        Text(address)
                                            .font(.caption)
                                            .foregroundColor(Color.textSecondary)
                                            .lineLimit(1)
                                    }
                                }

                                Spacer()

                                if let followUp = lead.followUpDate {
                                    Text(followUp < Date() ? "Overdue" : "Today")
                                        .font(.caption2)
                                        .fontWeight(.semibold)
                                        .foregroundColor(followUp < Date() ? Color.statusNotInterested : Color.electricViolet)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background((followUp < Date() ? Color.statusNotInterested : Color.electricViolet).opacity(0.15))
                                        .clipShape(RoundedRectangle(cornerRadius: 4))
                                }
                            }
                        }
                        .listRowBackground(Color.obsidianSurface)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .background(Color.obsidianBlack)
            }
            .background(Color.obsidianBlack)
            .navigationTitle("Plan Route")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(Color.textSecondary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Optimize") {
                        let selectedLeads = allLeads.filter { lead in
                            guard let id = lead.id else { return false }
                            return selectedLeadIDs.contains(id)
                        }
                        Task {
                            await routeOptimizer.optimizeRoute(from: startCoordinate, leads: selectedLeads)
                            dismiss()
                            onRouteReady()
                        }
                    }
                    .fontWeight(.semibold)
                    .foregroundColor(Color.electricViolet)
                    .disabled(selectedLeadIDs.isEmpty)
                }
            }
        }
    }
}
```

**Step 2: Build and verify**

Build the project. Should compile cleanly.

**Step 3: Commit**

```bash
git add "D2D Advancer/RoutePlannerView.swift"
git commit -m "feat: add route planner lead selection sheet"
```

---

### Task 8: Route Summary Sheet + Map Integration

**Files:**
- Create: `D2D Advancer/RouteSummaryView.swift`
- Modify: `D2D Advancer/MapView.swift` (add route button to FAB, show route on map)
- Modify: `D2D Advancer/AdvancedMapView.swift` (render route polyline + numbered markers)

**Step 1: Create RouteSummaryView.swift**

A bottom sheet that shows the optimized route — total stats and per-stop breakdown with swipe actions.

```swift
import SwiftUI
import MapKit

struct RouteSummaryView: View {
    @ObservedObject var routeOptimizer: RouteOptimizer
    var onNavigate: () -> Void
    var onSkip: (Lead) -> Void
    var onComplete: (Lead) -> Void
    var onEndRoute: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Route Plan")
                        .font(.headline)
                        .foregroundColor(Color.textPrimary)
                    if let route = routeOptimizer.currentRoute {
                        Text("\(route.stops.count) stops \u{00B7} \(formatDuration(route.totalDuration)) \u{00B7} \(formatDistance(route.totalDistance))")
                            .font(.caption)
                            .foregroundColor(Color.textSecondary)
                    }
                }
                Spacer()
                Button("Navigate") {
                    onNavigate()
                }
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.electricViolet)
                .clipShape(Capsule())
            }
            .padding()
            .background(Color.obsidianSurface)

            // Stop list
            if let route = routeOptimizer.currentRoute {
                List {
                    ForEach(route.stops, id: \.lead.objectID) { stop in
                        HStack(spacing: 12) {
                            // Order number
                            Text("\(stop.order)")
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                                .frame(width: 28, height: 28)
                                .background(Color.electricViolet)
                                .clipShape(Circle())

                            VStack(alignment: .leading, spacing: 2) {
                                Text(stop.lead.displayName)
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .foregroundColor(Color.textPrimary)
                                if let address = stop.lead.address, !address.isEmpty {
                                    Text(address)
                                        .font(.caption)
                                        .foregroundColor(Color.textSecondary)
                                        .lineLimit(1)
                                }
                            }

                            Spacer()

                            VStack(alignment: .trailing, spacing: 2) {
                                if let eta = stop.estimatedArrival {
                                    Text(eta, style: .time)
                                        .font(.caption)
                                        .fontWeight(.medium)
                                        .foregroundColor(Color.textPrimary)
                                }
                                if let duration = stop.drivingDurationFromPrevious {
                                    Text(formatDuration(duration))
                                        .font(.caption2)
                                        .foregroundColor(Color.textMuted)
                                }
                            }
                        }
                        .listRowBackground(Color.obsidianSurface)
                        .swipeActions(edge: .trailing) {
                            Button("Skip") { onSkip(stop.lead) }
                                .tint(Color.statusNotHome)
                        }
                        .swipeActions(edge: .leading) {
                            Button("Done") { onComplete(stop.lead) }
                                .tint(Color.statusInterested)
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }

            // End route button
            Button(action: onEndRoute) {
                Text("End Route")
                    .font(.subheadline)
                    .foregroundColor(Color.statusNotInterested)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .background(Color.obsidianSurface)
        }
        .background(Color.obsidianBlack)
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes) min"
    }

    private func formatDistance(_ meters: CLLocationDistance) -> String {
        if meters >= 1000 {
            return String(format: "%.1f km", meters / 1000)
        }
        return "\(Int(meters)) m"
    }
}
```

**Step 2: Add route state and button to MapView.swift**

Add state variables:
```swift
@StateObject private var routeOptimizer = RouteOptimizer()
@State private var showingRoutePlanner = false
@State private var showingRouteSummary = false
```

Add "Plan Route" button to FAB menu (after heatmap button):

```swift
// Route Planner Button
Button(action: {
    guard paywallManager.gateAction() else { return }
    showingRoutePlanner = true
    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
        isMapMenuExpanded = false
    }
}) {
    Circle()
        .fill(routeOptimizer.currentRoute != nil ? Color.electricViolet : Color.obsidianSurface)
        .frame(width: 44, height: 44)
        .overlay(
            Image(systemName: "point.topleft.down.to.point.bottomright.curvepath.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(routeOptimizer.currentRoute != nil ? .white : Color.electricViolet)
        )
        .overlay(
            Circle()
                .stroke(Color.obsidianBorder, lineWidth: routeOptimizer.currentRoute != nil ? 0 : 1)
        )
        .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
        .premiumLock()
}
.buttonStyle(PlainButtonStyle())
.transition(.scale.combined(with: .opacity))
```

Add sheets and route summary:

```swift
.sheet(isPresented: $showingRoutePlanner) {
    RoutePlannerView(
        routeOptimizer: routeOptimizer,
        startCoordinate: locationManager.location?.coordinate ?? locationManager.region.center,
        allLeads: Array(leads),
        onRouteReady: { showingRouteSummary = true }
    )
}
.sheet(isPresented: $showingRouteSummary) {
    RouteSummaryView(
        routeOptimizer: routeOptimizer,
        onNavigate: { openAppleMapsRoute() },
        onSkip: { lead in skipRouteStop(lead) },
        onComplete: { lead in completeRouteStop(lead) },
        onEndRoute: {
            routeOptimizer.clearRoute()
            showingRouteSummary = false
        }
    )
    .presentationDetents([.medium, .large])
    .presentationDragIndicator(.visible)
}
```

**Step 3: Add route polyline rendering to AdvancedMapView**

Add a property:
```swift
var routePolyline: MKPolyline?
```

In `updateUIView`, manage the polyline:
```swift
// Update route polyline
let existingPolylines = mapView.overlays.compactMap { $0 as? MKPolyline }
if let polyline = routePolyline {
    if existingPolylines.isEmpty || existingPolylines.first?.pointCount != polyline.pointCount {
        mapView.removeOverlays(existingPolylines)
        mapView.addOverlay(polyline, level: .aboveRoads)
    }
} else if !existingPolylines.isEmpty {
    mapView.removeOverlays(existingPolylines)
}
```

In the Coordinator's `rendererFor overlay:` method, add polyline handling:
```swift
if let polyline = overlay as? MKPolyline {
    let renderer = MKPolylineRenderer(polyline: polyline)
    renderer.strokeColor = UIColor(Color.electricViolet)
    renderer.lineWidth = 3
    return renderer
}
```

**Step 4: Add Apple Maps handoff and stop actions**

In MapView.swift, add helper methods:

```swift
private func openAppleMapsRoute() {
    guard let route = routeOptimizer.currentRoute else { return }
    let mapItems = route.stops.map { stop -> MKMapItem in
        let placemark = MKPlacemark(coordinate: stop.lead.coordinate)
        let item = MKMapItem(placemark: placemark)
        item.name = stop.lead.displayName
        return item
    }
    MKMapItem.openMaps(with: mapItems, launchOptions: [
        MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving
    ])
}

private func skipRouteStop(_ lead: Lead) {
    Task {
        let remaining = routeOptimizer.currentRoute?.stops
            .filter { $0.lead.id != lead.id }
            .map { $0.lead } ?? []
        let start = locationManager.location?.coordinate ?? locationManager.region.center
        await routeOptimizer.optimizeRoute(from: start, leads: remaining)
    }
}

private func completeRouteStop(_ lead: Lead) {
    lead.visitCount += 1
    lead.lastContactDate = Date()
    try? viewContext.save()
    skipRouteStop(lead)
}
```

**Step 5: Pass route data to AdvancedMapView**

Update AdvancedMapView call to include `routePolyline: routeOptimizer.currentRoute?.polyline`.

**Step 6: Build and test**

Build. On map, tap FAB → route icon → select leads → Optimize → verify polyline appears on map and summary sheet shows stops.

**Step 7: Commit**

```bash
git add "D2D Advancer/RouteSummaryView.swift" "D2D Advancer/MapView.swift" "D2D Advancer/AdvancedMapView.swift"
git commit -m "feat: add route planner with optimized routing and summary sheet"
```

---

### Task 9: Add new files to Xcode project

**Files:**
- Modify: `D2D Advancer.xcodeproj/project.pbxproj`

**Step 1: Ensure all new Swift files are added to the Xcode target**

New files created:
- `ScoringWeightsView.swift`
- `HeatmapOverlay.swift`
- `HeatmapOverlayRenderer.swift`
- `RouteOptimizer.swift`
- `RoutePlannerView.swift`
- `RouteSummaryView.swift`

If using Xcode's file management, drag each file into the D2D Advancer group in the project navigator and ensure "Add to target: D2D Advancer" is checked.

If files were created via CLI, open Xcode and go to File > Add Files to "D2D Advancer" for each new file.

**Step 2: Build and verify all files compile together**

Clean build (Cmd+Shift+K then Cmd+B). Fix any missing imports or type errors.

**Step 3: Commit**

```bash
git add -A
git commit -m "chore: add territory intelligence files to Xcode project"
```

---

### Task 10: Final Integration Test and Polish

**Step 1: End-to-end testing**

Test each feature in the simulator or device:

1. **Scoring Weights:**
   - Open More > Demographics > scroll to Scoring Weights
   - Adjust sliders — bar chart updates, percentages sum to 100%
   - Select a profile preset — weights update to match
   - Reset button restores defaults

2. **Heatmap:**
   - On map tab, tap FAB → flame icon
   - Heatmap overlay appears (need neighborhoods with scores in the area)
   - Pan the map — heatmap refreshes
   - Legend strip visible bottom-left
   - Toggle off — overlay disappears

3. **Route Optimization:**
   - Tap FAB → route icon
   - Select 3+ leads → Optimize
   - Route polyline appears on map in electric violet
   - Summary sheet shows stops in order with ETAs
   - Swipe right on a stop → "Done" marks as visited
   - Swipe left → "Skip" removes and recalculates
   - "Navigate" opens Apple Maps with waypoints
   - "End Route" clears everything

**Step 2: Fix any issues found during testing**

Address build errors, UI glitches, or logic bugs.

**Step 3: Final commit**

```bash
git add -A
git commit -m "feat: complete territory intelligence - heatmap, routing, scoring weights"
```
