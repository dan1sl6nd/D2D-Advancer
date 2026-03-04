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
