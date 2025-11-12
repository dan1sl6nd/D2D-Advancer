import SwiftUI
import MapKit
import CoreData

struct NeighborhoodDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let neighborhood: Neighborhood
    @State private var region: MKCoordinateRegion

    init(neighborhood: Neighborhood) {
        self.neighborhood = neighborhood
        _region = State(initialValue: MKCoordinateRegion(
            center: CLLocationCoordinate2D(
                latitude: neighborhood.centerLatitude,
                longitude: neighborhood.centerLongitude
            ),
            span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
        ))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Header with map preview
                ZStack(alignment: .topTrailing) {
                    Map(position: .constant(.region(region))) {
                        Annotation("", coordinate: CLLocationCoordinate2D(
                            latitude: neighborhood.centerLatitude,
                            longitude: neighborhood.centerLongitude
                        )) {
                            Circle()
                                .fill(scoreColor.opacity(0.3))
                                .stroke(scoreColor, lineWidth: 2)
                                .frame(width: 40, height: 40)
                        }
                    }
                    .frame(height: 200)
                    .cornerRadius(0)

                    Button(action: {
                        dismiss()
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundColor(.white)
                            .background(
                                Circle()
                                    .fill(Color.black.opacity(0.3))
                                    .frame(width: 32, height: 32)
                            )
                    }
                    .padding(12)
                }

                VStack(spacing: 16) {
                    // Name and location
                    VStack(alignment: .leading, spacing: 8) {
                        Text(neighborhood.name ?? "Unknown Area")
                            .font(.title)
                            .fontWeight(.bold)

                        HStack {
                            Image(systemName: "mappin.circle.fill")
                                .foregroundColor(.blue)
                            Text("\(neighborhood.cityName ?? ""), \(neighborhood.state ?? "")")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)

                    // Score card
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Area Score")
                                .font(.caption)
                                .foregroundColor(.secondary)

                            HStack(spacing: 8) {
                                Text(String(format: "%.0f", neighborhood.score))
                                    .font(.system(size: 36, weight: .bold, design: .rounded))
                                    .foregroundColor(scoreColor)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text("out of 100")
                                        .font(.caption)
                                        .foregroundColor(.secondary)

                                    Text(neighborhood.scoreGrade)
                                        .font(.caption)
                                        .fontWeight(.semibold)
                                        .foregroundColor(scoreColor)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 2)
                                        .background(
                                            Capsule()
                                                .fill(scoreColor.opacity(0.15))
                                        )
                                }
                            }
                        }

                        Spacer()

                        Button(action: {
                            navigateToArea()
                        }) {
                            HStack {
                                Image(systemName: "location.fill")
                                Text("Navigate")
                            }
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .background(Color.blue)
                            .cornerRadius(10)
                        }
                    }
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color(UIColor.tertiarySystemBackground))
                    )
                    .padding(.horizontal, 20)

                    // Demographics section
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Demographics")
                            .font(.headline)
                            .padding(.horizontal, 20)

                        VStack(spacing: 12) {
                            DemographicRow(
                                icon: "dollarsign.circle.fill",
                                label: "Median Income",
                                value: neighborhood.formattedIncome,
                                color: .green
                            )

                            DemographicRow(
                                icon: "house.circle.fill",
                                label: "Avg Home Value",
                                value: neighborhood.formattedHomeValue,
                                color: .blue
                            )

                            DemographicRow(
                                icon: "person.3.circle.fill",
                                label: "Population",
                                value: neighborhood.formattedPopulation,
                                color: .purple
                            )

                            DemographicRow(
                                icon: "key.circle.fill",
                                label: "Homeownership",
                                value: String(format: "%.0f%%", neighborhood.homeOwnershipRate * 100),
                                color: .orange
                            )
                        }
                        .padding(.horizontal, 20)
                    }

                    // Performance section (if there are leads in this area)
                    if let leads = neighborhood.leads, leads.count > 0 {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Your Performance")
                                .font(.headline)
                                .padding(.horizontal, 20)

                            PerformanceStatsView(neighborhood: neighborhood)
                                .padding(.horizontal, 20)
                        }
                    }

                    // Notes section
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Notes")
                                .font(.headline)

                            Spacer()

                            Button("Edit") {
                                // TODO: Add note editing
                            }
                            .font(.subheadline)
                            .foregroundColor(.blue)
                        }
                        .padding(.horizontal, 20)

                        if let notes = neighborhood.userNotes, !notes.isEmpty {
                            Text(notes)
                                .font(.body)
                                .foregroundColor(.secondary)
                                .padding(16)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color(UIColor.tertiarySystemBackground))
                                )
                                .padding(.horizontal, 20)
                        } else {
                            Text("No notes yet")
                                .font(.body)
                                .foregroundColor(.secondary)
                                .italic()
                                .padding(.horizontal, 20)
                        }
                    }
                }
                .padding(.bottom, 40)
            }
        }
        .navigationBarHidden(true)
    }

    private var scoreColor: Color {
        switch neighborhood.score {
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

    private func navigateToArea() {
        let coordinate = CLLocationCoordinate2D(
            latitude: neighborhood.centerLatitude,
            longitude: neighborhood.centerLongitude
        )
        let mapItem = MKMapItem(placemark: MKPlacemark(coordinate: coordinate))
        mapItem.name = neighborhood.name
        mapItem.openInMaps(launchOptions: [
            MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving
        ])
    }
}

struct DemographicRow: View {
    let icon: String
    let label: String
    let value: String
    let color: Color

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)
                .frame(width: 40)

            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                Text(value)
                    .font(.headline)
                    .fontWeight(.semibold)
            }

            Spacer()
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(UIColor.tertiarySystemBackground))
        )
    }
}

struct PerformanceStatsView: View {
    let neighborhood: Neighborhood
    @State private var stats: (total: Int, converted: Int, interested: Int, conversionRate: Double) = (0, 0, 0, 0)

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 16) {
                StatBox(label: "Total Leads", value: "\(stats.total)", color: .blue)
                StatBox(label: "Converted", value: "\(stats.converted)", color: .green)
                StatBox(label: "Interested", value: "\(stats.interested)", color: .orange)
            }

            HStack {
                Image(systemName: "chart.line.uptrend.xyaxis.circle.fill")
                    .foregroundColor(.green)

                Text("Conversion Rate")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                Spacer()

                Text(String(format: "%.1f%%", stats.conversionRate))
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundColor(.green)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.green.opacity(0.1))
            )
        }
        .onAppear {
            calculateStats()
        }
    }

    private func calculateStats() {
        guard let leads = neighborhood.leads?.allObjects as? [Lead] else {
            return
        }

        let total = leads.count
        let converted = leads.filter { $0.leadStatus == .converted }.count
        let interested = leads.filter { $0.leadStatus == .interested }.count
        let conversionRate = total > 0 ? (Double(converted) / Double(total)) * 100 : 0

        stats = (total, converted, interested, conversionRate)
    }
}

struct StatBox: View {
    let label: String
    let value: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(color)

            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(color.opacity(0.1))
        )
    }
}