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
        GeometryReader { geometry in
            VStack(spacing: 0) {
                // Header
                headerSection(geometry: geometry)

                if isLoading {
                    loadingView
                } else if topNeighborhoods.isEmpty {
                    emptyStateView
                } else {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            // Current preferences card
                            currentPreferencesCard

                            // Top recommendations
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
                        .padding(.vertical, 8)
                    }
                }
            }
            .navigationBarHidden(true)
            .ignoresSafeArea(.all, edges: .top)
            .safeAreaInset(edge: .bottom) {
                backButton
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

    // MARK: - Header

    private func headerSection(geometry: GeometryProxy) -> some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(
                    LinearGradient(
                        gradient: Gradient(colors: [
                            Color(UIColor.systemBackground),
                            Color(UIColor.systemBackground).opacity(0.98)
                        ]),
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(height: max(geometry.safeAreaInsets.top + 10, 60))

            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Best Areas")
                        .font(.title)
                        .fontWeight(.bold)

                    Text("Recommended neighborhoods for door-to-door")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Button(action: {
                    showingPreferences = true
                }) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.blue)
                        .padding(10)
                        .background(Color.blue.opacity(0.1))
                        .clipShape(Circle())
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
    }

    // MARK: - Loading & Empty States

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.2)
            Text("Analyzing neighborhoods...")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Circle()
                .fill(Color.blue.opacity(0.2))
                .frame(width: 80, height: 80)
                .overlay(
                    Image(systemName: "map.circle")
                        .font(.system(size: 32))
                        .foregroundColor(.blue)
                )

            VStack(spacing: 8) {
                Text("No Areas Found")
                    .font(.title2)
                    .fontWeight(.bold)

                Text("Add some leads to start analyzing neighborhoods, or adjust your target demographics.")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }

            Button("Adjust Preferences") {
                showingPreferences = true
            }
            .font(.headline)
            .foregroundColor(.white)
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .background(Color.blue)
            .cornerRadius(12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Current Preferences Card

    private var currentPreferencesCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "target")
                    .foregroundColor(.blue)
                Text("Target Demographics")
                    .font(.headline)
                    .fontWeight(.semibold)
                Spacer()
            }

            VStack(spacing: 8) {
                PreferenceRow(icon: "dollarsign.circle", label: "Income", value: preferences.formattedIncomeRange)
                PreferenceRow(icon: "house.circle", label: "Home Value", value: preferences.formattedHomeValueRange)
                PreferenceRow(icon: "person.3.circle", label: "Profile", value: preferences.selectedProfile.rawValue)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(UIColor.tertiarySystemBackground))
                .shadow(color: .black.opacity(0.08), radius: 4, x: 0, y: 2)
        )
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    // MARK: - Back Button

    private var backButton: some View {
        Button(action: {
            dismiss()
        }) {
            HStack {
                Image(systemName: "chevron.left.circle.fill")
                    .font(.title3)
                Text("Back")
                    .font(.headline)
                    .fontWeight(.semibold)
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [Color.blue, Color.blue.opacity(0.8)]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .shadow(color: .blue.opacity(0.3), radius: 4, x: 0, y: 2)
            )
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            Rectangle()
                .fill(Color(UIColor.systemBackground))
                .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: -2)
        )
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
        let fetchRequest: NSFetchRequest<Lead> = Lead.fetchRequest()
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
                .foregroundColor(.blue)
                .frame(width: 24)

            Text(label)
                .font(.subheadline)
                .foregroundColor(.secondary)

            Spacer()

            Text(value)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.primary)
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
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(neighborhood.name ?? "Unknown")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.primary)
                        .lineLimit(1)

                    HStack(spacing: 8) {
                        ScoreBadge(score: neighborhood.score)

                        Text(neighborhood.formattedIncome)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Text("\(neighborhood.cityName ?? ""), \(neighborhood.state ?? "")")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .foregroundColor(.secondary)
                    .font(.system(size: 14, weight: .medium))
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(UIColor.tertiarySystemBackground))
                    .shadow(color: .black.opacity(0.08), radius: 4, x: 0, y: 2)
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
            return Color.blue
        }
    }
}

struct ScoreBadge: View {
    let score: Double

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "star.fill")
                .font(.system(size: 10))
                .foregroundColor(scoreColor)

            Text(String(format: "%.0f", score))
                .font(.system(size: 12, weight: .semibold))
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
            return .green
        case 75..<90:
            return Color(red: 0.7, green: 0.9, blue: 0.4)
        case 60..<75:
            return .yellow
        case 45..<60:
            return .orange
        default:
            return .red
        }
    }
}

#Preview {
    AreaRecommendationsView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}