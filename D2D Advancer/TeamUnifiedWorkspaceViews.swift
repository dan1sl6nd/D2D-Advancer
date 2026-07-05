import SwiftUI
import MapKit

struct TeamMapShortcutPill: View {
    let summary: TeamWorkspaceSurfaceSummary
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: summaryIconName)
                    .font(.micro)
                    .foregroundColor(.white)
                    .frame(width: 24, height: 24)
                    .background(Color.electricViolet)
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(summary.headline)
                        .font(.micro)
                        .foregroundColor(Color.textPrimary)
                        .lineLimit(1)

                    if summary.hasUrgentActivity {
                        Text(summary.detailLine)
                            .font(.nano)
                            .foregroundColor(Color.textSecondary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 2)

                Image(systemName: "map.fill")
                    .font(.micro)
                    .foregroundColor(Color.electricViolet)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: summary.hasUrgentActivity ? 230 : 170)
            .background(.ultraThinMaterial)
            .clipShape(Capsule())
            .shadow(color: Color.black.opacity(0.12), radius: 6, x: 0, y: 2)
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityIdentifier("teamMapShortcut")
        .accessibilityLabel("Open team field map")
        .accessibilityValue("\(summary.headline), \(summary.detailLine)")
    }

    private var summaryIconName: String {
        if summary.role == .owner { return "person.3.fill" }
        if summary.currentMemberWorkType == .technician { return "wrench.and.screwdriver.fill" }
        return "briefcase.fill"
    }
}

struct TeamFieldMapSheet: View {
    let summary: TeamWorkspaceSurfaceSummary
    @Binding var selectedRepUserId: String?
    @Environment(\.colorScheme) private var colorScheme
    @State private var selectedLead: TeamLead?
    @State private var selectedCluster: TeamLeadClusterSelection?

    var body: some View {
        NavigationStack {
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
                .background(Color.obsidianBackground(for: colorScheme))

                TeamFieldMapView(
                    workspaces: summary.workspaces,
                    selectedRepUserId: $selectedRepUserId,
                    onLeadTap: { lead in
                        selectedLead = lead
                    },
                    onLeadClusterTap: { items, coordinate in
                        selectedCluster = TeamLeadClusterSelection(items: items, coordinate: coordinate)
                    }
                )
                .overlay(alignment: .bottomLeading) {
                    TeamMapLegend()
                        .padding(12)
                }
            }
            .background(Color.obsidianBackground(for: colorScheme))
            .navigationTitle(summary.role == .owner ? "Team Field Map" : "My Field Map")
            .obsidianInlineNavigation()
        }
        .sheet(item: $selectedLead) { lead in
            TeamLeadDetailSheet(initialLead: lead)
        }
        .sheet(item: $selectedCluster) { cluster in
            TeamLeadClusterSheet(selection: cluster) { lead in
                selectedLead = lead
            }
            .presentationDetents([.medium, .large])
        }
    }
}

struct TeamLeadClusterSelection: Identifiable {
    let id = UUID()
    let items: [TeamLeadClusterItem]
    let coordinate: CLLocationCoordinate2D

    var summary: TeamLeadClusterSummary {
        TeamLeadClusterSummary(items: items)
    }
}

struct TeamLeadClusterSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var teamService = TeamFirebaseService.shared
    let selection: TeamLeadClusterSelection
    let onViewLead: (TeamLead) -> Void
    @State private var isSaving = false
    @State private var statusMessage: String?
    @State private var jobStartDate = Date().addingTimeInterval(60 * 60)
    @State private var jobDurationHours = 2

    private var summary: TeamLeadClusterSummary {
        selection.summary
    }

    private var currentMember: TeamMember? {
        teamService.currentMember
    }

    private var activeTeam: TeamWorkspace? {
        teamService.activeTeam
    }

    private var activeAssignableReps: [TeamMember] {
        TeamMemberRoster.normalized(teamService.teamMembers)
            .filter { $0.isSalesRep && $0.status == .active && !$0.isPendingInvite }
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    private var activeTechnicians: [TeamMember] {
        TeamMemberRoster.normalized(teamService.teamMembers)
            .filter { $0.isTechnician && $0.status == .active && !$0.isPendingInvite }
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    private var canRunOwnerActions: Bool {
        guard let currentMember, let activeTeam else { return false }
        return currentMember.role == .owner
            && currentMember.status == .active
            && activeTeam.planStatus.allowsTeamWrite
    }

    private var jobEndDate: Date {
        jobStartDate.addingTimeInterval(TimeInterval(jobDurationHours) * 60 * 60)
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    metricsCard
                    ownerBatchActions
                    statusStrip
                    leadList
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
        }
        .background(Color.obsidianBackground(for: colorScheme))
        .presentationBackground(Color.obsidianBackground(for: colorScheme))
    }

    @ViewBuilder
    private var ownerBatchActions: some View {
        if canRunOwnerActions {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    clusterActionButton(title: "Priority", icon: "star.fill", color: Color.statusInterested) {
                        markClusterHighPriority()
                    }

                    Menu {
                        ForEach(activeAssignableReps) { rep in
                            Button(rep.displayName) {
                                assignCluster(to: rep)
                            }
                            .disabled(isSaving)
                        }
                    } label: {
                        clusterActionLabel(title: "Assign", icon: "person.crop.circle.badge.checkmark", color: Color.electricViolet)
                    }
                    .disabled(activeAssignableReps.isEmpty || isSaving)

                    Button {
                        openDirectionsToCluster()
                    } label: {
                        clusterActionLabel(title: "Route", icon: "location.north.line.fill", color: Color.statusConverted)
                    }
                    .buttonStyle(PlainButtonStyle())
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        DatePicker("Arrival", selection: $jobStartDate, displayedComponents: [.date, .hourAndMinute])
                            .labelsHidden()
                            .tint(Color.electricViolet)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        Stepper("\(jobDurationHours) hr", value: $jobDurationHours, in: 1...12)
                            .font(.micro)
                            .foregroundColor(Color.textSecondary)
                    }

                    Menu {
                        ForEach(activeTechnicians) { technician in
                            Button(technician.displayName) {
                                sendClusterJobs(to: technician)
                            }
                            .disabled(isSaving)
                        }
                    } label: {
                        Label("Send sold/booked to technician", systemImage: "wrench.and.screwdriver.fill")
                            .font(.obsidianFootnote)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 11)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(activeTechnicians.isEmpty ? Color.textMuted : Color.statusConverted)
                            )
                    }
                    .buttonStyle(PlainButtonStyle())
                    .disabled(activeTechnicians.isEmpty || isSaving)
                }

                if let statusMessage {
                    Text(statusMessage)
                        .font(.micro)
                        .foregroundColor(Color.textSecondary)
                        .lineLimit(2)
                }
            }
            .padding(14)
            .background(Color.obsidianSurface)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.obsidianBorder.opacity(0.55), lineWidth: 0.5)
            )
        }
    }

    private func clusterActionButton(title: String, icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            clusterActionLabel(title: title, icon: icon, color: color)
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(isSaving)
    }

    private func clusterActionLabel(title: String, icon: String, color: Color) -> some View {
        VStack(spacing: 5) {
            Image(systemName: icon)
                .font(.obsidianFootnote)
            Text(title)
                .font(.micro)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
        }
        .foregroundColor(color)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(color.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var header: some View {
        HStack(spacing: 12) {
            ObsidianIconTile(icon: "person.3.fill", tint: summary.color, size: 42)

            VStack(alignment: .leading, spacing: 3) {
                Text(summary.headline)
                    .font(.obsidianSubheadline)
                    .foregroundColor(Color.textPrimary)
                    .lineLimit(1)

                Text(summary.detailLine)
                    .font(.obsidianFootnote)
                    .foregroundColor(Color.textSecondary)
                    .lineLimit(1)
            }

            Spacer()

            ObsidianCompactIconButton(
                icon: "xmark",
                accessibilityLabel: "Close team cluster"
            ) {
                dismiss()
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 14)
    }

    private var metricsCard: some View {
        HStack(spacing: 10) {
            metric(value: "\(summary.count)", label: "Leads", color: summary.color)
            metric(value: "\(summary.hotLeadCount)", label: "Important", color: Color.statusInterested)
            metric(value: "\(summary.bookedCount)", label: "Booked", color: Color.electricViolet)
            metric(value: "\(summary.repCount)", label: "Workers", color: Color.textSecondary)
        }
        .padding(14)
        .background(Color.obsidianSurface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.obsidianBorder.opacity(0.55), lineWidth: 0.5)
        )
    }

    private var statusStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(summary.statusCounts, id: \.status) { item in
                    HStack(spacing: 6) {
                        Text("\(item.count)")
                            .font(.micro)
                        Text(item.status.teamDisplayName)
                            .font(.micro)
                    }
                    .foregroundColor(teamStatusColor(item.status))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(teamStatusColor(item.status).opacity(0.12))
                    .clipShape(Capsule())
                }
            }
        }
    }

    private var leadList: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Team leads in this area")
                    .font(.obsidianCallout)
                    .foregroundColor(Color.textPrimary)

                Spacer()

                Button {
                    openDirectionsToCluster()
                } label: {
                    Label("Route", systemImage: "location.north.line.fill")
                        .font(.micro)
                        .foregroundColor(Color.electricViolet)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(Color.electricViolet.opacity(0.12))
                        .clipShape(Capsule())
                }
                .buttonStyle(PlainButtonStyle())
            }

            VStack(spacing: 0) {
                ForEach(summary.sortedItems) { item in
                    Button {
                        openLead(item.lead)
                    } label: {
                        TeamLeadClusterRow(item: item)
                    }
                    .buttonStyle(PlainButtonStyle())

                    if item.id != summary.sortedItems.last?.id {
                        Divider()
                            .padding(.leading, 58)
                    }
                }
            }
            .background(Color.obsidianSurface)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.obsidianBorder.opacity(0.55), lineWidth: 0.5)
            )
        }
    }

    private func metric(value: String, label: String, color: Color) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.obsidianCallout)
                .foregroundColor(color)
                .lineLimit(1)
            Text(label)
                .font(.micro)
                .foregroundColor(Color.textMuted)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }

    private func markClusterHighPriority() {
        runBatchAction(startMessage: "Marking priority...") {
            var updatedCount = 0
            let eligibleItems = summary.sortedItems.filter { TeamLeadAttentionPolicy.canMarkHighPriority($0.lead) }
            for item in eligibleItems where !item.lead.isHighPriority {
                _ = try await teamService.updateTeamLead(
                    leadId: item.lead.id,
                    isHighPriority: true,
                    highPriorityReason: "Marked from map cluster"
                )
                updatedCount += 1
            }
            if eligibleItems.isEmpty {
                return "No open leads in this cluster can be marked high priority."
            }
            return updatedCount == 0 ? "Cluster was already high priority." : "Marked \(updatedCount) leads high priority."
        }
    }

    private func assignCluster(to rep: TeamMember) {
        runBatchAction(startMessage: "Assigning cluster...") {
            var updatedCount = 0
            for item in summary.sortedItems where item.lead.assignedToUserId != rep.userId {
                _ = try await teamService.assignTeamLead(item.lead, to: rep)
                updatedCount += 1
            }
            return updatedCount == 0 ? "All leads were already assigned to \(rep.displayName)." : "Assigned \(updatedCount) leads to \(rep.displayName)."
        }
    }

    private func sendClusterJobs(to technician: TeamMember) {
        let sortedItems = summary.sortedItems
        let leads = sortedItems.map { $0.lead }
        let dispatchableLeads = leads.filter { lead in
            lead.status == .converted || lead.status == .booked || lead.price > 0
        }

        guard !dispatchableLeads.isEmpty else {
            statusMessage = "No sold, booked, or priced leads in this cluster."
            return
        }

        runBatchAction(startMessage: "Sending jobs...") {
            var sentCount = 0
            for lead in dispatchableLeads {
                _ = try await teamService.dispatchTeamLeadToTechnicianJob(
                    lead: lead,
                    technician: technician,
                    startDate: jobStartDate,
                    endDate: jobEndDate
                )
                sentCount += 1
            }
            return "Sent \(sentCount) jobs to \(technician.displayName)."
        }
    }

    private func runBatchAction(startMessage: String, operation: @escaping () async throws -> String) {
        guard !isSaving else { return }
        isSaving = true
        statusMessage = startMessage

        Task {
            do {
                let message = try await operation()
                statusMessage = message
                isSaving = false
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            } catch {
                statusMessage = "Team action failed: \(error.localizedDescription)"
                isSaving = false
            }
        }
    }

    private func openLead(_ lead: TeamLead) {
        dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            onViewLead(lead)
        }
    }

    private func openDirectionsToCluster() {
        let placemark = MKPlacemark(coordinate: selection.coordinate)
        let mapItem = MKMapItem(placemark: placemark)
        mapItem.name = "Team lead cluster"
        mapItem.openInMaps(launchOptions: [
            MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving
        ])
    }
}

private struct TeamLeadClusterRow: View {
    let item: TeamLeadClusterItem

    var body: some View {
        let isActionableHighPriority = TeamLeadAttentionPolicy.isActionableHighPriority(item.lead)

        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(teamStatusColor(item.lead.status).opacity(0.14))
                    .frame(width: 38, height: 38)
                Image(systemName: isActionableHighPriority ? "star.fill" : "mappin.circle.fill")
                    .font(.obsidianFootnote)
                    .foregroundColor(teamStatusColor(item.lead.status))
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(item.lead.name)
                    .font(.obsidianCallout)
                    .foregroundColor(Color.textPrimary)
                    .lineLimit(1)

                Text(item.lead.address)
                    .font(.obsidianFootnote)
                    .foregroundColor(Color.textSecondary)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    chip(item.lead.status.teamDisplayName, color: teamStatusColor(item.lead.status))
                    chip(item.repName, color: Color.textSecondary)
                    if isActionableHighPriority {
                        chip("High priority", color: Color.statusNotHome)
                    }
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.obsidianFootnote)
                .foregroundColor(Color.textMuted)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private func chip(_ title: String, color: Color) -> some View {
        Text(title)
            .font(.micro)
            .foregroundColor(color)
            .lineLimit(1)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
    }
}

private func teamStatusColor(_ status: TeamLeadStatus) -> Color {
    switch status {
    case .notContacted:
        return Color.textSecondary
    case .notHome:
        return Color.statusNotHome
    case .contacted:
        return Color.statusInterested
    case .interested:
        return Color.statusNotHome
    case .followUp:
        return Color.electricViolet
    case .booked:
        return Color.electricViolet
    case .converted:
        return Color.statusConverted
    case .notInterested:
        return Color.statusNotInterested
    }
}

struct TeamUnifiedSummaryCard: View {
    let summary: TeamWorkspaceSurfaceSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: summaryIconName)
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
                    value: primaryMetricValue,
                    label: primaryMetricLabel,
                    color: Color.electricViolet
                )
                if summary.currentMemberWorkType == .technician && summary.role == .member {
                    TeamSurfaceMetricPill(
                        value: summary.activeRepCount,
                        label: "On Duty",
                        color: Color.statusConverted
                    )
                } else {
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

    private var summaryIconName: String {
        if summary.role == .owner { return "person.3.fill" }
        if summary.currentMemberWorkType == .technician { return "wrench.and.screwdriver.fill" }
        return "briefcase.fill"
    }

    private var primaryMetricValue: Int {
        summary.currentMemberWorkType == .technician && summary.role == .member
            ? summary.upcomingBookingCount
            : summary.teamLeadCount
    }

    private var primaryMetricLabel: String {
        if summary.currentMemberWorkType == .technician && summary.role == .member {
            return "Jobs"
        }
        return summary.role == .owner ? "Team Leads" : "Assigned"
    }
}

struct TeamCommandCenterCard: View {
    let summary: TeamWorkspaceSurfaceSummary
    let visibleWorkspaces: [TeamRepWorkspace]

    private var leads: [TeamLead] {
        visibleWorkspaces.flatMap(\.assignedLeads)
    }

    private var jobs: [TeamBooking] {
        visibleWorkspaces.flatMap(\.assignedBookings)
    }

    private var importantLeads: [TeamLead] {
        leads.filter(TeamLeadAttentionPolicy.needsOwnerAttention)
    }

    private var dispatchReadyLeads: [TeamLead] {
        leads.filter { $0.status == .converted || $0.status == .booked || $0.price > 0 }
    }

    private var upcomingJobs: [TeamBooking] {
        jobs
            .filter { $0.isFutureEditable && $0.endDate >= Date() }
            .sorted { $0.startDate < $1.startDate }
    }

    private var nextAction: (title: String, subtitle: String, icon: String, color: Color) {
        if summary.unreadNotificationCount > 0 {
            return ("Owner alerts", "\(summary.unreadNotificationCount) unread smart alerts", "bell.badge.fill", Color.statusInterested)
        }
        if !importantLeads.isEmpty {
            return ("Review important leads", "\(importantLeads.count) need owner attention", "exclamationmark.triangle.fill", Color.statusInterested)
        }
        if summary.role == .owner && !dispatchReadyLeads.isEmpty {
            return ("Dispatch sold work", "\(dispatchReadyLeads.count) ready for technicians", "wrench.and.screwdriver.fill", Color.statusConverted)
        }
        if let nextJob = upcomingJobs.first {
            return ("Next service job", nextJob.startDate.formatted(date: .abbreviated, time: .shortened), "calendar.badge.clock", Color.electricViolet)
        }
        if summary.activeRepCount == 0 && summary.role == .owner {
            return ("No workers on duty", "Team is quiet right now", "moon.zzz.fill", Color.textMuted)
        }
        return ("Team is caught up", summary.detailLine, "checkmark.seal.fill", Color.statusConverted)
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: nextAction.icon)
                .font(.obsidianAction)
                .foregroundColor(nextAction.color)
                .frame(width: 38, height: 38)
                .background(nextAction.color.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(nextAction.title)
                    .font(.obsidianFootnote)
                    .foregroundColor(Color.textPrimary)
                    .lineLimit(1)

                Text(nextAction.subtitle)
                    .font(.micro)
                    .foregroundColor(Color.textSecondary)
                    .lineLimit(1)
            }

            Spacer()
        }
        .padding(12)
        .background(Color.obsidianBlack.opacity(0.42))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(nextAction.color.opacity(0.24), lineWidth: 0.8)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Team command center")
        .accessibilityValue("\(nextAction.title), \(nextAction.subtitle)")
    }
}

struct TeamTechnicianJobBoard: View {
    @ObservedObject private var teamService = TeamFirebaseService.shared
    let workspaces: [TeamRepWorkspace]
    let role: TeamRole
    @State private var savingBookingId: String?
    @State private var statusMessage: String?

    private var jobItems: [TeamBookingInlineItem] {
        workspaces
            .flatMap { workspace in
                workspace.assignedBookings.map { TeamBookingInlineItem(workspace: workspace, booking: $0) }
            }
            .filter { $0.booking.isFutureEditable || $0.booking.status == .needsOwnerFollowUp }
            .sorted {
                if $0.booking.startDate != $1.booking.startDate {
                    return $0.booking.startDate < $1.booking.startDate
                }
                return $0.workspace.member.displayName.localizedCaseInsensitiveCompare($1.workspace.member.displayName) == .orderedAscending
            }
    }

    var body: some View {
        if !jobItems.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: "wrench.and.screwdriver.fill")
                        .font(.obsidianSmall)
                        .foregroundColor(Color.statusConverted)
                        .frame(width: 30, height: 30)
                        .background(Color.statusConverted.opacity(0.12))
                        .clipShape(Circle())

                    VStack(alignment: .leading, spacing: 2) {
                        Text(role == .owner ? "Technician Jobs" : "My Job Board")
                            .font(.obsidianFootnote)
                            .foregroundColor(Color.textPrimary)
                        Text("\(jobItems.count) active \(jobItems.count == 1 ? "job" : "jobs")")
                            .font(.micro)
                            .foregroundColor(Color.textSecondary)
                    }

                    Spacer()
                }

                VStack(spacing: 0) {
                    ForEach(Array(jobItems.prefix(4))) { item in
                        TeamTechnicianJobRow(
                            item: item,
                            role: role,
                            isSaving: savingBookingId == item.booking.id,
                            onRoute: { route(to: item.booking) },
                            onStatus: { status in update(item.booking, status: status) }
                        )

                        if item.id != jobItems.prefix(4).last?.id {
                            Divider()
                                .background(Color.obsidianBorder.opacity(0.35))
                        }
                    }
                }

                if let statusMessage {
                    Text(statusMessage)
                        .font(.micro)
                        .foregroundColor(Color.textSecondary)
                        .lineLimit(2)
                }
            }
            .padding(12)
            .background(Color.obsidianBlack.opacity(0.42))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.statusConverted.opacity(0.22), lineWidth: 0.8)
            )
        }
    }

    private func route(to booking: TeamBooking) {
        if let latitude = booking.latitude, let longitude = booking.longitude {
            Utilities.openMapsDirections(latitude: latitude, longitude: longitude)
        } else {
            Utilities.openMapsSearch(query: booking.location)
        }
    }

    private func update(_ booking: TeamBooking, status: TeamBookingStatus) {
        guard savingBookingId == nil else { return }
        savingBookingId = booking.id
        statusMessage = nil

        Task {
            do {
                _ = try await teamService.updateTeamBookingStatus(booking, status: status)
                statusMessage = "\(booking.title) marked \(status.displayName.lowercased())."
                savingBookingId = nil
            } catch {
                statusMessage = "Could not update job: \(error.localizedDescription)"
                savingBookingId = nil
            }
        }
    }
}

private struct TeamTechnicianJobRow: View {
    let item: TeamBookingInlineItem
    let role: TeamRole
    let isSaving: Bool
    let onRoute: () -> Void
    let onStatus: (TeamBookingStatus) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: item.booking.status.jobIconName)
                .font(.obsidianSmall)
                .foregroundColor(item.booking.status.jobColor)
                .frame(width: 28, height: 28)
                .background(item.booking.status.jobColor.opacity(0.12))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 5) {
                Text(item.booking.title.isEmpty ? "Scheduled Job" : item.booking.title)
                    .font(.obsidianFootnote)
                    .foregroundColor(Color.textPrimary)
                    .lineLimit(1)

                Text(item.booking.startDate.formatted(date: .abbreviated, time: .shortened))
                    .font(.micro)
                    .foregroundColor(Color.textSecondary)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Text(item.booking.status.displayName)
                        .font(.micro)
                        .foregroundColor(item.booking.status.jobColor)

                    if role == .owner {
                        Text("• \(item.workspace.member.displayName)")
                            .font(.micro)
                            .foregroundColor(Color.textMuted)
                            .lineLimit(1)
                    }
                }
            }

            Spacer(minLength: 4)

            HStack(spacing: 6) {
                Button(action: onRoute) {
                    Image(systemName: "location.north.line.fill")
                        .font(.micro)
                        .foregroundColor(Color.electricViolet)
                        .frame(width: 30, height: 30)
                        .background(Color.electricViolet.opacity(0.12))
                        .clipShape(Circle())
                }
                .buttonStyle(PlainButtonStyle())
                .accessibilityLabel("Route to job")

                Menu {
                    Button("On the way") { onStatus(.enRoute) }
                    Button("Started") { onStatus(.inProgress) }
                    Button("Done") { onStatus(.completed) }
                    Button("Needs owner follow-up") { onStatus(.needsOwnerFollowUp) }
                } label: {
                    if isSaving {
                        ProgressView()
                            .tint(Color.textSecondary)
                            .frame(width: 30, height: 30)
                    } else {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.micro)
                            .foregroundColor(Color.statusConverted)
                            .frame(width: 30, height: 30)
                            .background(Color.statusConverted.opacity(0.12))
                            .clipShape(Circle())
                    }
                }
                .disabled(isSaving)
            }
        }
        .padding(.vertical, 9)
    }
}

struct TeamWorkInlineSection: View {
    let summary: TeamWorkspaceSurfaceSummary
    @Binding var selectedRepUserId: String?
    let onOpenMap: () -> Void
    let onSelectLead: (TeamLead) -> Void

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

    private var visibleBookings: [TeamBookingInlineItem] {
        visibleWorkspaces.flatMap { workspace in
            workspace.assignedBookings.map { TeamBookingInlineItem(workspace: workspace, booking: $0) }
        }
    }

    private var shouldShowJobs: Bool {
        summary.currentMemberWorkType == .technician || (visibleLeads.isEmpty && !visibleBookings.isEmpty)
    }

    private var rowsToShow: [TeamLeadInlineItem] {
        isExpanded ? visibleLeads : Array(visibleLeads.prefix(4))
    }

    private var jobRowsToShow: [TeamBookingInlineItem] {
        isExpanded ? visibleBookings : Array(visibleBookings.prefix(4))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: sectionIconName)
                    .font(.obsidianAction)
                    .foregroundColor(.white)
                    .frame(width: 38, height: 38)
                    .background(Color.electricViolet)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(sectionTitle)
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
                TeamSurfaceMetricPill(value: shouldShowJobs ? summary.upcomingBookingCount : summary.teamLeadCount, label: shouldShowJobs ? "Jobs" : "Leads", color: Color.electricViolet)
                if !shouldShowJobs {
                    TeamSurfaceMetricPill(value: summary.importantLeadCount, label: "Important", color: Color.statusInterested)
                }
                TeamSurfaceMetricPill(value: summary.activeRepCount, label: "On Duty", color: Color.statusConverted)
            }

            TeamCommandCenterCard(
                summary: summary,
                visibleWorkspaces: visibleWorkspaces
            )

            TeamTechnicianJobBoard(
                workspaces: visibleWorkspaces,
                role: summary.role
            )

            if shouldShowJobs {
                if jobRowsToShow.isEmpty {
                    Text(summary.role == .owner ? "No assigned team jobs yet." : "No assigned service jobs yet.")
                        .font(.obsidianFootnote)
                        .foregroundColor(Color.textMuted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 6)
                } else {
                    VStack(spacing: 0) {
                        ForEach(jobRowsToShow) { item in
                            TeamBookingInlineRow(
                                booking: item.booking,
                                repName: summary.role == .owner ? item.workspace.member.displayName : nil
                            )

                            if item.booking.id != jobRowsToShow.last?.booking.id {
                                Divider()
                                    .background(Color.obsidianBorder.opacity(0.35))
                            }
                        }
                    }
                }
            } else if rowsToShow.isEmpty {
                Text("No assigned team leads yet.")
                    .font(.obsidianFootnote)
                    .foregroundColor(Color.textMuted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 6)
            } else {
                VStack(spacing: 0) {
                    ForEach(rowsToShow) { item in
                        Button {
                            onSelectLead(item.lead)
                        } label: {
                            TeamLeadInlineRow(
                                lead: item.lead,
                                repName: summary.role == .owner ? item.workspace.member.displayName : nil
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                        .accessibilityIdentifier("teamLeadInlineRow")

                        if item.lead.id != rowsToShow.last?.lead.id {
                            Divider()
                                .background(Color.obsidianBorder.opacity(0.35))
                        }
                    }
                }
            }

            if (shouldShowJobs ? visibleBookings.count : visibleLeads.count) > 4 {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(isExpanded ? "Show less" : "Show \((shouldShowJobs ? visibleBookings.count : visibleLeads.count) - 4) more")
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

    private var sectionIconName: String {
        if summary.role == .owner { return "person.3.fill" }
        if summary.currentMemberWorkType == .technician { return "wrench.and.screwdriver.fill" }
        return "briefcase.fill"
    }

    private var sectionTitle: String {
        if summary.role == .owner { return "Team Work" }
        if summary.currentMemberWorkType == .technician { return "My Jobs" }
        return "My Leads"
    }
}

private struct TeamLeadInlineItem: Identifiable {
    var id: String { lead.id }
    let workspace: TeamRepWorkspace
    let lead: TeamLead
}

private struct TeamBookingInlineItem: Identifiable {
    var id: String { booking.id }
    let workspace: TeamRepWorkspace
    let booking: TeamBooking
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
        let isActionableHighPriority = TeamLeadAttentionPolicy.isActionableHighPriority(lead)

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

                    if isActionableHighPriority {
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

struct TeamBookingInlineRow: View {
    let booking: TeamBooking
    let repName: String?

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "calendar.badge.clock")
                .font(.obsidianSmall)
                .foregroundColor(Color.statusConverted)
                .frame(width: 28, height: 28)
                .background(Color.statusConverted.opacity(0.12))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 5) {
                Text(booking.title.isEmpty ? "Scheduled Job" : booking.title)
                    .font(.obsidianFootnote)
                    .foregroundColor(Color.textPrimary)
                    .lineLimit(1)

                Text("Approx. arrival \(booking.startDate.formatted(date: .abbreviated, time: .shortened)) • \(booking.status.displayName)")
                    .font(.micro)
                    .foregroundColor(Color.textSecondary)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Text(booking.location.isEmpty ? "No location" : booking.location)
                        .font(.micro)
                        .foregroundColor(Color.textMuted)
                        .lineLimit(1)

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
        .accessibilityLabel("\(booking.title), \(booking.status.displayName)")
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
            Label("Team", systemImage: "location.fill")
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

extension TeamBookingStatus {
    var jobIconName: String {
        switch self {
        case .scheduled:
            return "calendar.badge.clock"
        case .confirmed:
            return "checkmark.seal.fill"
        case .enRoute:
            return "location.north.line.fill"
        case .inProgress:
            return "play.circle.fill"
        case .completed:
            return "checkmark.circle.fill"
        case .needsOwnerFollowUp:
            return "exclamationmark.bubble.fill"
        case .cancelled:
            return "xmark.circle.fill"
        case .rescheduled:
            return "arrow.clockwise.circle.fill"
        }
    }

    var jobColor: Color {
        switch self {
        case .scheduled:
            return Color.electricViolet
        case .confirmed:
            return Color.statusConverted
        case .enRoute:
            return Color.statusInterested
        case .inProgress:
            return Color.statusNotHome
        case .completed:
            return Color.statusConverted
        case .needsOwnerFollowUp:
            return Color.statusInterested
        case .cancelled:
            return Color.statusNotInterested
        case .rescheduled:
            return Color.textSecondary
        }
    }
}
