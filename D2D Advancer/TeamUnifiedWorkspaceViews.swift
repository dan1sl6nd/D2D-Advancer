import SwiftUI

struct TeamMapShortcutPill: View {
    let summary: TeamWorkspaceSurfaceSummary
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: summary.role == .owner ? "person.3.fill" : "briefcase.fill")
                    .font(.obsidianSmall)
                    .foregroundColor(.white)
                    .frame(width: 26, height: 26)
                    .background(Color.electricViolet)
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(summary.headline)
                        .font(.obsidianFootnote)
                        .foregroundColor(Color.textPrimary)
                        .lineLimit(1)

                    Text(summary.detailLine)
                        .font(.micro)
                        .foregroundColor(Color.textSecondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                Image(systemName: "map.fill")
                    .font(.obsidianSmall)
                    .foregroundColor(Color.electricViolet)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: 290)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: Color.black.opacity(0.16), radius: 8, x: 0, y: 3)
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityIdentifier("teamMapShortcut")
        .accessibilityLabel("Open team field map")
        .accessibilityValue("\(summary.headline), \(summary.detailLine)")
    }
}

struct TeamFieldMapSheet: View {
    let summary: TeamWorkspaceSurfaceSummary
    @Binding var selectedRepUserId: String?

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                VStack(spacing: 12) {
                    TeamUnifiedSummaryCard(summary: summary)

                    if summary.role == .owner && summary.workspaces.count > 1 {
                        TeamRepFilterStrip(
                            workspaces: summary.workspaces,
                            selectedRepUserId: $selectedRepUserId
                        )
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 8)
                .background(Color.obsidianBlack)

                TeamFieldMapView(
                    workspaces: summary.workspaces,
                    selectedRepUserId: $selectedRepUserId
                )
                .overlay(alignment: .bottomLeading) {
                    TeamMapLegend()
                        .padding(12)
                }
            }
            .background(Color.obsidianBlack)
            .navigationTitle(summary.role == .owner ? "Team Field Map" : "My Field Map")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

struct TeamUnifiedSummaryCard: View {
    let summary: TeamWorkspaceSurfaceSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: summary.role == .owner ? "person.3.fill" : "briefcase.fill")
                    .font(.obsidianAction)
                    .foregroundColor(.white)
                    .frame(width: 38, height: 38)
                    .background(Color.electricViolet)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text(summary.teamName)
                        .font(.obsidianCallout)
                        .foregroundColor(Color.textPrimary)
                        .lineLimit(1)

                    Text(summary.headline)
                        .font(.obsidianFootnote)
                        .foregroundColor(Color.textSecondary)
                        .lineLimit(1)
                }

                Spacer()
            }

            HStack(spacing: 8) {
                TeamSurfaceMetricPill(
                    value: summary.teamLeadCount,
                    label: summary.role == .owner ? "Team Leads" : "Assigned",
                    color: Color.electricViolet
                )
                TeamSurfaceMetricPill(
                    value: summary.importantLeadCount,
                    label: "Important",
                    color: Color.statusInterested
                )
                TeamSurfaceMetricPill(
                    value: summary.upcomingBookingCount,
                    label: "Bookings",
                    color: Color.statusConverted
                )
            }
        }
        .padding(14)
        .background(Color.obsidianSurface)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.obsidianBorder.opacity(0.42), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Team summary")
        .accessibilityValue("\(summary.headline), \(summary.detailLine)")
    }
}

struct TeamWorkInlineSection: View {
    let summary: TeamWorkspaceSurfaceSummary
    @Binding var selectedRepUserId: String?
    let onOpenMap: () -> Void

    @State private var isExpanded = false

    private var visibleWorkspaces: [TeamRepWorkspace] {
        guard let selectedRepUserId else { return summary.workspaces }
        return summary.workspaces.filter { $0.member.userId == selectedRepUserId }
    }

    private var visibleLeads: [TeamLeadInlineItem] {
        visibleWorkspaces.flatMap { workspace in
            workspace.assignedLeads.map { TeamLeadInlineItem(workspace: workspace, lead: $0) }
        }
    }

    private var rowsToShow: [TeamLeadInlineItem] {
        isExpanded ? visibleLeads : Array(visibleLeads.prefix(4))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "person.3.fill")
                    .font(.obsidianAction)
                    .foregroundColor(.white)
                    .frame(width: 38, height: 38)
                    .background(Color.electricViolet)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(summary.role == .owner ? "Team Work" : "My Team Work")
                        .font(.obsidianCallout)
                        .foregroundColor(Color.textPrimary)

                    Text(summary.detailLine)
                        .font(.obsidianFootnote)
                        .foregroundColor(Color.textSecondary)
                        .lineLimit(1)
                }

                Spacer()

                Button(action: onOpenMap) {
                    Image(systemName: "map.fill")
                        .font(.obsidianSmall)
                        .foregroundColor(Color.electricViolet)
                        .frame(width: 34, height: 34)
                        .background(Color.electricViolet.opacity(0.12))
                        .clipShape(Circle())
                }
                .buttonStyle(PlainButtonStyle())
                .accessibilityLabel("Open team field map")
            }

            if summary.role == .owner && summary.workspaces.count > 1 {
                TeamRepFilterStrip(
                    workspaces: summary.workspaces,
                    selectedRepUserId: $selectedRepUserId
                )
            }

            HStack(spacing: 8) {
                TeamSurfaceMetricPill(value: summary.teamLeadCount, label: "Leads", color: Color.electricViolet)
                TeamSurfaceMetricPill(value: summary.importantLeadCount, label: "Important", color: Color.statusInterested)
                TeamSurfaceMetricPill(value: summary.activeRepCount, label: "On Duty", color: Color.statusConverted)
            }

            if rowsToShow.isEmpty {
                Text(summary.role == .owner ? "No assigned team leads yet." : "No assigned team leads yet.")
                    .font(.obsidianFootnote)
                    .foregroundColor(Color.textMuted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 6)
            } else {
                VStack(spacing: 0) {
                    ForEach(rowsToShow) { item in
                        TeamLeadInlineRow(
                            lead: item.lead,
                            repName: summary.role == .owner ? item.workspace.member.displayName : nil
                        )

                        if item.lead.id != rowsToShow.last?.lead.id {
                            Divider()
                                .background(Color.obsidianBorder.opacity(0.35))
                        }
                    }
                }
            }

            if visibleLeads.count > 4 {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(isExpanded ? "Show less" : "Show \(visibleLeads.count - 4) more")
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    }
                    .font(.obsidianFootnote)
                    .foregroundColor(Color.electricViolet)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(16)
        .background(Color.obsidianSurface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.obsidianBorder.opacity(0.4), lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("teamWorkInlineSection")
    }
}

private struct TeamLeadInlineItem: Identifiable {
    var id: String { lead.id }
    let workspace: TeamRepWorkspace
    let lead: TeamLead
}

struct TeamRepFilterStrip: View {
    let workspaces: [TeamRepWorkspace]
    @Binding var selectedRepUserId: String?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                TeamRepFilterChip(
                    title: "All",
                    isSelected: selectedRepUserId == nil,
                    isOnDuty: workspaces.contains { $0.isOnDuty }
                ) {
                    selectedRepUserId = nil
                }

                ForEach(workspaces) { workspace in
                    TeamRepFilterChip(
                        title: workspace.member.displayName,
                        isSelected: selectedRepUserId == workspace.member.userId,
                        isOnDuty: workspace.isOnDuty
                    ) {
                        selectedRepUserId = workspace.member.userId
                    }
                }
            }
            .padding(.vertical, 2)
        }
    }
}

struct TeamRepFilterChip: View {
    let title: String
    let isSelected: Bool
    let isOnDuty: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Circle()
                    .fill(isOnDuty ? Color.statusConverted : Color.textMuted)
                    .frame(width: 7, height: 7)

                Text(title)
                    .font(.obsidianSmall)
                    .lineLimit(1)
            }
            .foregroundColor(isSelected ? .white : Color.textSecondary)
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .background(isSelected ? Color.electricViolet : Color.obsidianBlack.opacity(0.45))
            .clipShape(Capsule())
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityLabel(title)
        .accessibilityValue(isOnDuty ? "On duty" : "Off duty")
    }
}

struct TeamLeadInlineRow: View {
    let lead: TeamLead
    let repName: String?

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: lead.status.teamIconName)
                .font(.obsidianSmall)
                .foregroundColor(lead.status.teamColor)
                .frame(width: 28, height: 28)
                .background(lead.status.teamColor.opacity(0.12))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(lead.name.isEmpty ? "Unnamed Lead" : lead.name)
                        .font(.obsidianFootnote)
                        .foregroundColor(Color.textPrimary)
                        .lineLimit(1)

                    if lead.isHighPriority {
                        Image(systemName: "star.fill")
                            .font(.nano)
                            .foregroundColor(Color.statusInterested)
                    }
                }

                Text(lead.address)
                    .font(.micro)
                    .foregroundColor(Color.textSecondary)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Text(lead.status.teamDisplayName)
                        .font(.micro)
                        .foregroundColor(lead.status.teamColor)

                    if let repName {
                        Text("• \(repName)")
                            .font(.micro)
                            .foregroundColor(Color.textMuted)
                            .lineLimit(1)
                    }
                }
            }

            Spacer(minLength: 6)
        }
        .padding(.vertical, 9)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(lead.name), \(lead.status.teamDisplayName)")
    }
}

struct TeamSurfaceMetricPill: View {
    let value: Int
    let label: String
    let color: Color

    var body: some View {
        HStack(spacing: 5) {
            Text("\(value)")
                .font(.obsidianFootnote)
                .foregroundColor(color)

            Text(label)
                .font(.micro)
                .foregroundColor(Color.textSecondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(color.opacity(0.1))
        .clipShape(Capsule())
    }
}

struct TeamMapLegend: View {
    var body: some View {
        HStack(spacing: 8) {
            Label("Rep", systemImage: "location.fill")
            Label("Lead", systemImage: "mappin.circle.fill")
            Label("Route", systemImage: "point.topleft.down.curvedto.point.bottomright.up")
        }
        .font(.micro)
        .foregroundColor(Color.textSecondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
    }
}

extension TeamLeadStatus {
    var teamDisplayName: String {
        switch self {
        case .notContacted:
            return "New"
        case .notHome:
            return "Not home"
        case .contacted:
            return "Contacted"
        case .interested:
            return "Interested"
        case .followUp:
            return "Follow-up"
        case .booked:
            return "Booked"
        case .converted:
            return "Sold"
        case .notInterested:
            return "Passed"
        }
    }

    var teamIconName: String {
        switch self {
        case .notContacted:
            return "person.circle"
        case .notHome:
            return "house.slash.fill"
        case .contacted:
            return "bubble.left.and.bubble.right.fill"
        case .interested:
            return "heart.fill"
        case .followUp:
            return "arrow.clockwise.circle.fill"
        case .booked:
            return "calendar.badge.checkmark"
        case .converted:
            return "checkmark.seal.fill"
        case .notInterested:
            return "hand.raised.fill"
        }
    }

    var teamColor: Color {
        switch self {
        case .notContacted:
            return Color.textMuted
        case .notHome:
            return Color.statusNotHome
        case .contacted, .interested:
            return Color.statusInterested
        case .followUp, .booked:
            return Color.electricViolet
        case .converted:
            return Color.statusConverted
        case .notInterested:
            return Color.statusNotInterested
        }
    }
}
