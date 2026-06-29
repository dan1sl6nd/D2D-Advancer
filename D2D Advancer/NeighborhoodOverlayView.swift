import Foundation
import MapKit
import SwiftUI
import UIKit

// MARK: - Neighborhood Overlay Classes

/// MKCircle overlay representing a neighborhood on the map
class NeighborhoodOverlay: NSObject, MKOverlay {
    let neighborhood: Neighborhood
    let score: Double
    let circle: MKCircle

    var coordinate: CLLocationCoordinate2D {
        return circle.coordinate
    }

    var boundingMapRect: MKMapRect {
        return circle.boundingMapRect
    }

    init(neighborhood: Neighborhood, radius: CLLocationDistance = 2500) {
        self.neighborhood = neighborhood
        self.score = neighborhood.score

        let coordinate = CLLocationCoordinate2D(
            latitude: neighborhood.centerLatitude,
            longitude: neighborhood.centerLongitude
        )

        self.circle = MKCircle(center: coordinate, radius: radius)
        super.init()
    }

    // Color based on score
    var fillColor: UIColor {
        switch score {
        case 90...100:
            return UIColor.systemGreen.withAlphaComponent(0.4)
        case 75..<90:
            return UIColor.systemGreen.withAlphaComponent(0.3)
        case 60..<75:
            return UIColor.systemYellow.withAlphaComponent(0.3)
        case 45..<60:
            return UIColor.systemOrange.withAlphaComponent(0.3)
        default:
            return UIColor.systemRed.withAlphaComponent(0.2)
        }
    }

    var strokeColor: UIColor {
        switch score {
        case 90...100:
            return UIColor.systemGreen
        case 75..<90:
            return UIColor.systemGreen.withAlphaComponent(0.8)
        case 60..<75:
            return UIColor.systemYellow
        case 45..<60:
            return UIColor.systemOrange
        default:
            return UIColor.systemRed
        }
    }
}

/// Renderer for neighborhood overlays
class NeighborhoodOverlayRenderer: MKCircleRenderer {
    init(neighborhoodOverlay: NeighborhoodOverlay) {
        super.init(circle: neighborhoodOverlay.circle)
        self.fillColor = neighborhoodOverlay.fillColor
        self.strokeColor = neighborhoodOverlay.strokeColor
        self.lineWidth = 2.0
    }
}

/// Annotation showing neighborhood details
class NeighborhoodAnnotation: NSObject, MKAnnotation {
    let neighborhood: Neighborhood
    dynamic var coordinate: CLLocationCoordinate2D

    var title: String? {
        return neighborhood.name
    }

    var subtitle: String? {
        let scoreText = String(format: "Score: %.0f", neighborhood.score)
        let incomeText = neighborhood.formattedIncome
        return "\(scoreText) • \(incomeText)"
    }

    init(neighborhood: Neighborhood) {
        self.neighborhood = neighborhood
        self.coordinate = CLLocationCoordinate2D(
            latitude: neighborhood.centerLatitude,
            longitude: neighborhood.centerLongitude
        )
        super.init()
    }
}

// MARK: - SwiftUI Integration

/// Manager for neighborhood overlays on the map
@MainActor
class NeighborhoodOverlayManager: ObservableObject {
    @Published var isShowingOverlays = false
    @Published var visibleNeighborhoods: [Neighborhood] = []
    @Published var selectedNeighborhood: Neighborhood?

    private let dataService = NeighborhoodDataService.shared
    private let scoreEngine = NeighborhoodScoreEngine.shared
    private let preferences = TargetDemographicsPreferences.shared

    /// Loads neighborhoods for the visible map region
    func loadNeighborhoods(for region: MKCoordinateRegion) async {
        var neighborhoods: [Neighborhood] = []

        // Approach 1: Load neighborhoods from existing leads in the visible area
        do {
            let existingNeighborhoods = try dataService.getCachedNeighborhoods()

            for neighborhood in existingNeighborhoods {
                // Check if neighborhood is within visible region
                let latInRange = abs(neighborhood.centerLatitude - region.center.latitude) < region.span.latitudeDelta / 2
                let lonInRange = abs(neighborhood.centerLongitude - region.center.longitude) < region.span.longitudeDelta / 2

                if latInRange && lonInRange {
                    // Always recalculate score with current preferences
                    do {
                        _ = try await scoreEngine.calculateScore(
                            for: neighborhood,
                            preferences: preferences
                        )
                    } catch {
                        print("⚠️ Failed to calculate score: \(error)")
                    }
                    neighborhoods.append(neighborhood)
                }
            }

            print("📍 Found \(neighborhoods.count) cached neighborhoods in visible region")
        } catch {
            print("⚠️ Failed to load cached neighborhoods: \(error)")
        }

        // Approach 2: If no neighborhoods found, sample the center point
        if neighborhoods.isEmpty {
            print("📍 No cached neighborhoods, sampling center of visible region")
            do {
                let centerNeighborhood = try await dataService.fetchNeighborhoodData(for: region.center)

                // Always recalculate score with current preferences
                _ = try await scoreEngine.calculateScore(
                    for: centerNeighborhood,
                    preferences: preferences
                )

                neighborhoods.append(centerNeighborhood)
            } catch {
                print("⚠️ Failed to fetch neighborhood for center: \(error)")
            }
        }

        visibleNeighborhoods = neighborhoods
        print("✅ Loaded \(neighborhoods.count) neighborhoods for visible region")
    }

    /// Updates scores for all visible neighborhoods
    func updateScores() async {
        for neighborhood in visibleNeighborhoods {
            do {
                _ = try await scoreEngine.calculateScore(
                    for: neighborhood,
                    preferences: preferences
                )
            } catch {
                print("⚠️ Failed to update score for neighborhood: \(error)")
            }
        }
    }

    /// Populates neighborhoods from all existing leads
    func populateFromLeads(leads: [Lead]) async {
        print("📍 Populating neighborhoods from \(leads.count) leads...")
        var count = 0

        for lead in leads {
            // Skip if lead already has neighborhood data
            if lead.neighborhood != nil {
                continue
            }

            do {
                let neighborhood = try await dataService.fetchNeighborhoodData(for: lead.coordinate)

                // Always recalculate score with current preferences
                do {
                    _ = try await scoreEngine.calculateScore(
                        for: neighborhood,
                        preferences: preferences
                    )
                } catch {
                    print("⚠️ Failed to calculate score: \(error)")
                }

                // Link lead to neighborhood
                lead.neighborhood = neighborhood
                count += 1
            } catch {
                print("⚠️ Failed to fetch neighborhood for lead \(lead.displayName): \(error)")
            }
        }

        // Context is already saved when neighborhoods are created
        if count > 0 {
            print("✅ Populated \(count) neighborhoods from leads")
        }
    }
}

// MARK: - SwiftUI Overlay Controls

struct NeighborhoodOverlayControls: View {
    @ObservedObject var manager: NeighborhoodOverlayManager
    @State private var showingLegend = false

    var body: some View {
        VStack(spacing: 12) {
            // Toggle overlay button
            Button(action: {
                withAnimation {
                    manager.isShowingOverlays.toggle()
                }
            }) {
                Circle()
                    .fill(manager.isShowingOverlays ? Color.electricViolet : Color.textSecondary)
                    .frame(width: 44, height: 44)
                    .overlay(
                        Image(systemName: "map.circle.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.white)
                    )
            }

            // Legend button
            if manager.isShowingOverlays {
                Button(action: {
                    showingLegend.toggle()
                }) {
                    Circle()
                        .fill(Color.electricViolet)
                        .frame(width: 44, height: 44)
                        .overlay(
                            Image(systemName: "info.circle.fill")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(.white)
                        )
                }
            }
        }
        .sheet(isPresented: $showingLegend) {
            NeighborhoodLegendView()
                .presentationDetents([.height(400)])
        }
    }
}

struct NeighborhoodLegendView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 16) {
                ObsidianScreenTitle(
                    title: "Area Score Legend",
                    subtitle: "How neighborhood recommendation scores are grouped.",
                    icon: "info.circle.fill"
                )
                .padding(.top, 18)

                ObsidianSectionCard(
                    title: "Score Bands",
                    icon: "chart.bar.fill",
                    subtitle: "Higher scores mean a stronger fit for your target profile."
                ) {
                    VStack(spacing: 12) {
                    LegendRow(color: .statusInterested, label: "Excellent", range: "90-100", description: "Best fit for your target demographics")
                    LegendRow(color: Color(red: 0.7, green: 0.9, blue: 0.4), label: "Very Good", range: "75-89", description: "Strong match with good potential")
                    LegendRow(color: .yellow, label: "Good", range: "60-74", description: "Moderate match worth considering")
                    LegendRow(color: .statusNotHome, label: "Fair", range: "45-59", description: "Some potential but not ideal")
                    LegendRow(color: .statusNotInterested, label: "Poor", range: "0-44", description: "Low match with target demographics")
                    }
                }

                ObsidianStatusBanner(
                    icon: "target",
                    title: "How scores are calculated",
                    message: "Scores are based on income, home values, population density, and your historical conversion rate in each area.",
                    tint: Color.electricViolet
                )
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 28)
            }
            .background(Color.obsidianBlack.ignoresSafeArea())
            .navigationTitle("Area Score Legend")
            .obsidianInlineNavigation()
            .safeAreaInset(edge: .bottom) {
                Button {
                    dismiss()
                } label: {
                    Label("Done", systemImage: "checkmark")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(ObsidianPrimaryButtonStyle())
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color.obsidianBlack)
            }
        }
    }
}

struct LegendRow: View {
    let color: Color
    let label: String
    let range: String
    let description: String

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(color.opacity(0.3))
                .stroke(color, lineWidth: 2)
                .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(label)
                        .font(.obsidianCallout)
                        .foregroundColor(.textPrimary)
                    Text("(\(range))")
                        .font(.obsidianFootnote)
                        .foregroundColor(Color.textSecondary)
                }

                Text(description)
                    .font(.obsidianSmall)
                    .foregroundColor(Color.textSecondary)
            }

            Spacer()
        }
    }
}
