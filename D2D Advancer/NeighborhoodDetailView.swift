import SwiftUI
import MapKit
import CoreData

struct NeighborhoodDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext
    let neighborhood: Neighborhood
    @State private var region: MKCoordinateRegion
    @State private var isEditingNotes = false
    @State private var noteDraft = ""
    @State private var noteSaveError: String?

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
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    ObsidianScreenTitle(
                        title: neighborhood.name ?? "Unknown Area",
                        subtitle: "\(neighborhood.cityName ?? ""), \(neighborhood.state ?? "")",
                        icon: "map.circle.fill"
                    )
                    .padding(.horizontal, 20)
                    .padding(.top, 18)

                    mapPreviewSection

                    // Score card
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Area Score")
                                .font(.obsidianSmall)
                                .foregroundColor(Color.textSecondary)

                            HStack(spacing: 8) {
                                Text(String(format: "%.0f", neighborhood.score))
                                    .font(.displayLarge)
                                    .foregroundColor(scoreColor)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text("out of 100")
                                        .font(.obsidianSmall)
                                        .foregroundColor(Color.textSecondary)

                                    Text(neighborhood.scoreGrade)
                                        .font(.obsidianSmall)
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
                            Label("Navigate", systemImage: "location.fill")
                        }
                        .buttonStyle(ObsidianPrimaryButtonStyle())
                    }
                    .padding(16)
                    .surfaceCard()
                    .padding(.horizontal, 20)

                    ObsidianSectionCard(
                        title: "Demographics",
                        icon: "chart.bar.xaxis",
                        subtitle: "Area-level signals used in recommendations."
                    ) {
                        VStack(spacing: 12) {
                            DemographicRow(
                                icon: "dollarsign.circle.fill",
                                label: "Median Income",
                                value: neighborhood.formattedIncome,
                                color: .statusInterested
                            )

                            DemographicRow(
                                icon: "house.circle.fill",
                                label: "Avg Home Value",
                                value: neighborhood.formattedHomeValue,
                                color: .electricViolet
                            )

                            DemographicRow(
                                icon: "person.3.circle.fill",
                                label: "Population",
                                value: neighborhood.formattedPopulation,
                                color: .electricViolet
                            )

                            DemographicRow(
                                icon: "key.circle.fill",
                                label: "Homeownership",
                                value: String(format: "%.0f%%", neighborhood.homeOwnershipRate * 100),
                                color: .statusNotHome
                            )
                        }
                    }
                    .padding(.horizontal, 20)

                    if let leads = neighborhood.leads, leads.count > 0 {
                        ObsidianSectionCard(
                            title: "Your Performance",
                            icon: "chart.line.uptrend.xyaxis",
                            subtitle: "\(leads.count) lead\(leads.count == 1 ? "" : "s") in this area."
                        ) {
                            PerformanceStatsView(neighborhood: neighborhood)
                        }
                        .padding(.horizontal, 20)
                    }

                    ObsidianSectionCard(
                        title: "Notes",
                        icon: "note.text",
                        subtitle: "Local notes for this area."
                    ) {
                        HStack {
                            Spacer()
                            Button("Edit") {
                                beginEditingNotes()
                            }
                            .buttonStyle(ObsidianSecondaryButtonStyle())
                        }

                        if let notes = neighborhood.userNotes, !notes.isEmpty {
                            Text(notes)
                                .font(.obsidianBody)
                                .foregroundColor(Color.textSecondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            Text("No notes yet")
                                .font(.obsidianBody)
                                .foregroundColor(Color.textSecondary)
                                .italic()
                        }
                    }
                    .padding(.horizontal, 20)
                }
                .padding(.bottom, 40)
            }
            .obsidianScreenBackground()
            .navigationTitle("Area Details")
            .obsidianInlineNavigation()
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    ObsidianCompactIconButton(
                        icon: "xmark",
                        accessibilityLabel: "Close area details",
                        accentColor: Color.textSecondary
                    ) {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $isEditingNotes) {
                notesEditorSheet
            }
        }
    }

    private var notesEditorSheet: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                ObsidianScreenTitle(
                    title: "Area Notes",
                    subtitle: neighborhood.name ?? "Recommended area",
                    icon: "note.text"
                )

                TextEditor(text: $noteDraft)
                    .font(.obsidianBody)
                    .foregroundColor(Color.textPrimary)
                    .scrollContentBackground(.hidden)
                    .padding(12)
                    .frame(minHeight: 220)
                    .background(Color.obsidianElevated)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.obsidianBorder.opacity(0.55), lineWidth: 0.5)
                    )

                if let noteSaveError {
                    Text(noteSaveError)
                        .font(.obsidianFootnote)
                        .foregroundColor(Color.statusNotInterested)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 12) {
                    Button("Cancel") {
                        isEditingNotes = false
                    }
                    .buttonStyle(ObsidianSecondaryButtonStyle())

                    Button("Save Notes") {
                        saveNotes()
                    }
                    .buttonStyle(ObsidianPrimaryButtonStyle())
                }

                Spacer(minLength: 0)
            }
            .padding(20)
            .obsidianScreenBackground()
            .navigationBarHidden(true)
        }
        .presentationDetents([.medium, .large])
    }

    private var mapPreviewSection: some View {
        ObsidianSectionCard(
            title: "Map Preview",
            icon: "location.viewfinder",
            subtitle: "Center point for this recommended area."
        ) {
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
            .frame(height: 190)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.obsidianBorder.opacity(0.55), lineWidth: 0.5)
            )
        }
        .padding(.horizontal, 20)
    }

    private var scoreColor: Color {
        switch neighborhood.score {
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

    private func beginEditingNotes() {
        noteDraft = neighborhood.userNotes ?? ""
        noteSaveError = nil
        isEditingNotes = true
    }

    private func saveNotes() {
        let trimmedNotes = noteDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        neighborhood.userNotes = trimmedNotes.isEmpty ? nil : trimmedNotes
        neighborhood.lastUpdated = Date()

        do {
            try viewContext.save()
            noteSaveError = nil
            isEditingNotes = false
        } catch {
            viewContext.rollback()
            noteSaveError = "Could not save notes. Try again."
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
                .font(.obsidianHeadline)
                .foregroundColor(color)
                .frame(width: 40, height: 40)
                .background(color.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.obsidianFootnote)
                    .foregroundColor(Color.textSecondary)

                Text(value)
                    .font(.obsidianCallout)
                    .foregroundColor(.textPrimary)
            }

            Spacer()
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.obsidianSurface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.obsidianBorder.opacity(0.55), lineWidth: 0.5)
        )
    }
}

struct PerformanceStatsView: View {
    let neighborhood: Neighborhood
    @State private var stats: (total: Int, converted: Int, interested: Int, conversionRate: Double) = (0, 0, 0, 0)

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 16) {
                StatBox(label: "Total Leads", value: "\(stats.total)", color: .electricViolet)
                StatBox(label: "Converted", value: "\(stats.converted)", color: .statusInterested)
                StatBox(label: "Interested", value: "\(stats.interested)", color: .statusNotHome)
            }

            HStack {
                Image(systemName: "chart.line.uptrend.xyaxis.circle.fill")
                    .foregroundColor(Color.statusInterested)

                Text("Conversion Rate")
                    .font(.obsidianFootnote)
                    .foregroundColor(Color.textSecondary)

                Spacer()

                Text(String(format: "%.1f%%", stats.conversionRate))
                    .font(.obsidianCallout)
                    .foregroundColor(Color.statusInterested)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.statusInterested.opacity(0.1))
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
                .font(.obsidianHeadline)
                .foregroundColor(color)

            Text(label)
                .font(.obsidianSmall)
                .foregroundColor(Color.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(color.opacity(0.1))
        )
    }
}
