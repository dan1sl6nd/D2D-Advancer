import SwiftUI
import CoreData
import MapKit

struct AreaRecommendationsView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    @StateObject private var neighborhoodManager = NeighborhoodOverlayManager()
    @ObservedObject private var preferences = TargetDemographicsPreferences.shared
    @State private var topNeighborhoods: [Neighborhood] = []
    @State private var isLoading = true
    @State private var showingPreferences = false
    @State private var selectedNeighborhood: Neighborhood?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if isLoading {
                    loadingView
                } else if topNeighborhoods.isEmpty {
                    ObsidianEmptyState(
                        icon: "map.circle",
                        title: "No areas found",
                        message: "Add leads to start analyzing neighborhoods, or adjust your target demographics.",
                        actionTitle: "Adjust Preferences",
                        actionIcon: "slider.horizontal.3",
                        action: { showingPreferences = true }
                    )
                } else {
                    ScrollView {
                        LazyVStack(spacing: 16) {
                            ObsidianScreenTitle(
                                title: "Best Areas",
                                subtitle: "Recommended neighborhoods for door-to-door.",
                                icon: "map.circle.fill"
                            )

                            currentPreferencesCard

                            ForEach(topNeighborhoods.indices, id: \.self) { index in
                                NeighborhoodRecommendationCard(
                                    neighborhood: topNeighborhoods[index],
                                    rank: index + 1,
                                    onTap: {
                                        selectedNeighborhood = topNeighborhoods[index]
                                    }
                                )
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 18)
                        .padding(.bottom, 28)
                    }
                }
            }
            .obsidianScreenBackground()
            .navigationTitle("Best Areas")
            .obsidianInlineNavigation()
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    ObsidianCompactIconButton(
                        icon: "xmark",
                        accessibilityLabel: "Close area recommendations",
                        accentColor: Color.textSecondary
                    ) {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    ObsidianCompactIconButton(
                        icon: "slider.horizontal.3",
                        accessibilityLabel: "Adjust target demographics",
                        action: { showingPreferences = true }
                    )
                }
            }
        }
        .sheet(isPresented: $showingPreferences) {
            DemographicsPreferencesView()
        }
        .sheet(item: $selectedNeighborhood) { neighborhood in
            NeighborhoodDetailView(neighborhood: neighborhood)
        }
        .task {
            await loadRecommendations()
        }
    }

    // MARK: - Loading & Empty States

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .tint(.electricViolet)
                .scaleEffect(1.2)
            Text("Analyzing neighborhoods...")
                .font(.obsidianBody)
                .foregroundColor(Color.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Current Preferences Card

    private var currentPreferencesCard: some View {
        ObsidianSectionCard(
            title: "Target Demographics",
            icon: "target",
            subtitle: preferences.selectedProfile.rawValue
        ) {
            VStack(spacing: 8) {
                PreferenceRow(icon: "dollarsign.circle", label: "Income", value: preferences.formattedIncomeRange)
                PreferenceRow(icon: "house.circle", label: "Home Value", value: preferences.formattedHomeValueRange)
            }
        }
    }

    // MARK: - Data Loading

    @MainActor
    private func loadRecommendations() async {
        isLoading = true

        do {
            // Get top neighborhoods
            let scoreEngine = NeighborhoodScoreEngine.shared
            topNeighborhoods = try scoreEngine.getTopNeighborhoods(limit: 10)

            // If we have no neighborhoods, create initial scan from user's current leads
            if topNeighborhoods.isEmpty {
                await scanLeadLocations()
                topNeighborhoods = try scoreEngine.getTopNeighborhoods(limit: 10)
            }

            isLoading = false
        } catch {
            print("❌ Failed to load recommendations: \(error)")
            isLoading = false
        }
    }

    private func scanLeadLocations() async {
        let fetchRequest: NSFetchRequest<Lead> = Lead.fetchRequest(in: viewContext)
        fetchRequest.fetchLimit = 50 // Sample first 50 leads

        do {
            let leads = try viewContext.fetch(fetchRequest)
            let dataService = NeighborhoodDataService.shared
            let scoreEngine = NeighborhoodScoreEngine.shared

            for lead in leads {
                let coordinate = CLLocationCoordinate2D(
                    latitude: lead.latitude,
                    longitude: lead.longitude
                )

                do {
                    let neighborhood = try await dataService.fetchNeighborhoodData(for: coordinate)
                    _ = try await scoreEngine.calculateScore(
                        for: neighborhood,
                        preferences: preferences
                    )
                } catch {
                    print("⚠️ Failed to process lead location: \(error)")
                }
            }
        } catch {
            print("❌ Failed to scan lead locations: \(error)")
        }
    }
}

// MARK: - Supporting Views

struct PreferenceRow: View {
    let icon: String
    let label: String
    let value: String

    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(Color.electricViolet)
                .frame(width: 24)

            Text(label)
                .font(.obsidianFootnote)
                .foregroundColor(Color.textSecondary)

            Spacer()

            Text(value)
                .font(.obsidianFootnote)
                .foregroundColor(Color.textPrimary)
        }
    }
}

struct NeighborhoodRecommendationCard: View {
    let neighborhood: Neighborhood
    let rank: Int
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 16) {
                // Rank badge
                ZStack {
                    Circle()
                        .fill(rankColor)
                        .frame(width: 48, height: 48)

                    Text("#\(rank)")
                        .font(.obsidianCallout)
                        .foregroundColor(.white)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(neighborhood.name ?? "Unknown")
                        .font(.obsidianTitle)
                        .foregroundColor(Color.textPrimary)
                        .lineLimit(1)

                    HStack(spacing: 8) {
                        ScoreBadge(score: neighborhood.score)

                        Text(neighborhood.formattedIncome)
                            .font(.obsidianSmall)
                            .foregroundColor(Color.textSecondary)
                    }

                    Text("\(neighborhood.cityName ?? ""), \(neighborhood.state ?? "")")
                        .font(.obsidianSmall)
                        .foregroundColor(Color.textSecondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .foregroundColor(Color.textSecondary)
                    .font(.obsidianCaption)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.obsidianSurface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.obsidianBorder.opacity(0.55), lineWidth: 0.5)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }

    private var rankColor: Color {
        switch rank {
        case 1:
            return Color(red: 1.0, green: 0.84, blue: 0.0) // Gold
        case 2:
            return Color(red: 0.75, green: 0.75, blue: 0.75) // Silver
        case 3:
            return Color(red: 0.80, green: 0.50, blue: 0.20) // Bronze
        default:
            return Color.electricViolet
        }
    }
}

struct ScoreBadge: View {
    let score: Double

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "star.fill")
                .font(.nano)
                .foregroundColor(scoreColor)

            Text(String(format: "%.0f", score))
                .font(.obsidianSmall)
                .foregroundColor(scoreColor)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(scoreColor.opacity(0.15))
        )
    }

    private var scoreColor: Color {
        switch score {
        case 90...100:
            return .statusInterested
        case 75..<90:
            return Color(red: 0.7, green: 0.9, blue: 0.4)
        case 60..<75:
            return .yellow
        case 45..<60:
            return .statusNotHome
        default:
            return .statusNotInterested
        }
    }
}

#Preview {
    AreaRecommendationsView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}
