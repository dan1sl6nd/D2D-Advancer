import SwiftUI
import MapKit
import UIKit

struct TeamRepDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var teamService = TeamFirebaseService.shared

    let initialWorkspace: TeamRepWorkspace
    @State private var selectedLead: TeamLead?
    @State private var isSaving = false
    @State private var statusMessage: String?
    @State private var statusMessageIsError = false

    private var workspace: TeamRepWorkspace {
        guard let member = teamService.teamMembers.first(where: { $0.userId == initialWorkspace.member.userId }) else {
            return initialWorkspace
        }

        return TeamRepWorkspace.makeMemberWorkspace(
            member: member,
            leads: teamService.teamLeads.filter { $0.assignedToUserId == member.userId },
            bookings: teamService.teamBookings.filter { $0.assignedToUserId == member.userId },
            dutySessions: teamService.dutySessions,
            dutyLocationPoints: teamService.dutyLocationPoints
        )
    }

    private var member: TeamMember {
        workspace.member
    }

    private var title: String {
        member.role == .owner ? "Owner Location" : member.displayRoleTitle
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    headerCard
                    if let statusMessage {
                        TeamRepDetailNotice(message: statusMessage, isError: statusMessageIsError)
                    }
                    actionCard
                    mapCard
                    if member.isTechnician {
                        bookingsCard
                        leadsCard
                    } else {
                        leadsCard
                        bookingsCard
                    }
                    routeHistoryCard
                }
                .padding(16)
                .padding(.bottom, 24)
            }
            .obsidianScreenBackground()
            .obsidianPushedNavigation(
                title,
                backButtonAccessibilityIdentifier: "teamRepDetailBackButton",
                onBack: { dismiss() }
            ) {
                TeamToolbarDoneButton {
                    dismiss()
                }
                .accessibilityIdentifier("teamRepDetailCloseButton")
            }
        }
        .obsidianModalBackground()
        .sheet(item: $selectedLead) { lead in
            TeamLeadDetailSheet(initialLead: lead)
        }
        .accessibilityIdentifier("teamRepDetailSheet")
    }

    private var headerCard: some View {
        TeamRepDetailCard {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: memberWorkTypeIcon)
                    .font(.obsidianAction)
                    .foregroundColor(.white)
                    .frame(width: 46, height: 46)
                    .background(memberWorkTypeColor)
                    .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))

                VStack(alignment: .leading, spacing: 5) {
                    Text(member.displayName)
                        .font(.obsidianHeadline)
                        .foregroundColor(Color.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(member.email ?? member.displayRoleTitle)
                        .font(.obsidianFootnote)
                        .foregroundColor(Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 6)
            }

            HStack(spacing: 8) {
                TeamRepMetricPill(
                    title: workspace.isOnDuty ? "On duty" : "Off duty",
                    systemImage: workspace.isOnDuty ? "location.fill" : "location.slash.fill",
                    color: workspace.isOnDuty ? Color.statusInterested : Color.textMuted
                )
                if !member.isTechnician {
                    TeamRepMetricPill(
                        title: "\(workspace.assignedLeads.count) leads",
                        systemImage: "mappin.circle.fill",
                        color: Color.electricViolet
                    )
                }
                TeamRepMetricPill(
                    title: "\(workspace.assignedBookings.count) \(member.isTechnician ? "jobs" : "bookings")",
                    systemImage: "calendar.badge.clock",
                    color: Color.statusConverted
                )
            }
        }
    }

    private var actionCard: some View {
        TeamRepDetailCard {
            Label(workspaceSubtitle, systemImage: workspace.isOnDuty ? "location.fill" : "clock.fill")
                .font(.obsidianFootnote)
                .foregroundColor(Color.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            if let liveLocation = workspace.liveLocation {
                Button {
                    openDirections(to: liveLocation)
                } label: {
                    Label("Navigate to \(member.displayName)", systemImage: "arrow.triangle.turn.up.right.diamond.fill")
                        .font(.obsidianFootnote)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.electricViolet)
                        )
                }
                .buttonStyle(PlainButtonStyle())
                .accessibilityIdentifier("teamRepNavigateButton")
            }
        }
    }

    private var mapCard: some View {
        TeamRepDetailCard {
            Text(member.role == .owner ? "Owner Location" : "\(member.displayRoleTitle) Map")
                .font(.obsidianCallout)
                .foregroundColor(Color.textPrimary)

            TeamFieldMapView(
                workspaces: [workspace],
                selectedRepUserId: constantSelection(nil),
                onLeadTap: { lead in
                    selectedLead = lead
                }
            )
            .frame(height: 240)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.obsidianBorder.opacity(0.35), lineWidth: 0.5)
            )
        }
    }

    @ViewBuilder
    private var leadsCard: some View {
        if !workspace.assignedLeads.isEmpty {
            TeamRepDetailCard {
                Text("Assigned Leads")
                    .font(.obsidianCallout)
                    .foregroundColor(Color.textPrimary)

                ForEach(workspace.assignedLeads) { lead in
                    Button {
                        selectedLead = lead
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: lead.isHighPriority ? "star.fill" : lead.status.teamIconName)
                                .font(.micro)
                                .foregroundColor(lead.isHighPriority ? Color.statusInterested : lead.status.teamColor)
                                .frame(width: 20)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(lead.name.isEmpty ? "Unnamed Lead" : lead.name)
                                    .font(.obsidianFootnote)
                                    .foregroundColor(Color.textPrimary)
                                    .lineLimit(1)
                                Text(lead.address)
                                    .font(.micro)
                                    .foregroundColor(Color.textMuted)
                                    .lineLimit(2)
                            }

                            Spacer()

                            Text(lead.status.teamDisplayName)
                                .font(.nano)
                                .foregroundColor(lead.status.teamColor)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Capsule().fill(lead.status.teamColor.opacity(0.12)))
                        }
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .accessibilityIdentifier("teamRepDetailLeadRow")
                }
            }
        }
    }

    @ViewBuilder
    private var bookingsCard: some View {
        if !workspace.assignedBookings.isEmpty || member.isTechnician {
            TeamRepDetailCard {
                Text(member.isTechnician ? "Assigned Jobs" : "Bookings")
                    .font(.obsidianCallout)
                    .foregroundColor(Color.textPrimary)

                if workspace.assignedBookings.isEmpty {
                    Text(member.isTechnician ? "No service jobs assigned yet." : "No bookings assigned yet.")
                        .font(.obsidianFootnote)
                        .foregroundColor(Color.textMuted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    ForEach(workspace.assignedBookings) { booking in
                        VStack(alignment: .leading, spacing: 10) {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(spacing: 8) {
                                    Label(booking.customerDisplayName, systemImage: "calendar.badge.clock")
                                        .font(.obsidianFootnote)
                                        .foregroundColor(Color.textPrimary)
                                    Spacer()
                                    Text(booking.status.displayName)
                                        .font(.nano)
                                        .foregroundColor(Color.statusInterested)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Capsule().fill(Color.statusInterested.opacity(0.12)))
                                }

                                Text(booking.title.isEmpty ? "Scheduled Job" : booking.title)
                                    .font(.micro)
                                    .foregroundColor(Color.textSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }

                            bookingDetailRows(for: booking)

                            if !booking.location.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                Button {
                                    openDirections(to: booking)
                                } label: {
                                    Label("Navigate to job", systemImage: "arrow.triangle.turn.up.right.diamond.fill")
                                        .font(.micro)
                                        .foregroundColor(Color.electricViolet)
                                }
                                .buttonStyle(PlainButtonStyle())
                            }

                            if canUpdateBooking(booking) {
                                jobStatusButtons(booking)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 6)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var routeHistoryCard: some View {
        if let latestSession = workspace.latestSession {
            TeamRepDetailCard {
                Text("Active-Hours Graph")
                    .font(.obsidianCallout)
                    .foregroundColor(Color.textPrimary)

                TeamRepDetailStatRow(title: "Started", value: latestSession.startedAt.formatted(date: .abbreviated, time: .shortened))
                if let endedAt = latestSession.endedAt {
                    TeamRepDetailStatRow(title: "Ended", value: endedAt.formatted(date: .abbreviated, time: .shortened))
                }
                TeamRepDetailStatRow(title: "Distance", value: distanceText(latestSession.distanceMeters))
                TeamRepDetailStatRow(title: "GPS points", value: "\(workspace.routePoints.count)")
            }
        }
    }

    private var workspaceSubtitle: String {
        if let liveLocation = workspace.liveLocation {
            return "\(member.displayName) is live. Updated \(liveLocation.recordedAt.formatted(date: .omitted, time: .shortened))."
        }
        if let latestSession = workspace.latestSession, let endedAt = latestSession.endedAt {
            return "Last active-hours route ended \(endedAt.formatted(date: .abbreviated, time: .shortened))."
        }
        if member.role == .owner {
            return "Owner location sharing is off."
        }
        return "This \(member.displayRoleTitle.lowercased()) is off duty."
    }

    private func bookingDetailRows(for booking: TeamBooking) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            TeamRepDetailJobRow(title: "Approx. arrival", value: bookingArrivalText(booking))
            TeamRepDetailJobRow(title: "Address", value: booking.location.isEmpty ? "No location" : booking.location)

            if let phone = trimmed(booking.customerPhone) {
                TeamRepDetailJobRow(title: "Phone", value: phone)
            }
            if let email = trimmed(booking.customerEmail) {
                TeamRepDetailJobRow(title: "Email", value: email)
            }
            if let service = trimmed(booking.serviceCategory) {
                TeamRepDetailJobRow(title: "Service", value: service)
            }
            if let price = booking.quotedPrice, price > 0 {
                TeamRepDetailJobRow(title: "Price", value: currencyText(price))
            }
            if let notes = trimmed(booking.notes) {
                TeamRepDetailJobRow(title: "Notes", value: notes)
            }
        }
    }

    private func bookingArrivalText(_ booking: TeamBooking) -> String {
        let start = booking.startDate.formatted(date: .abbreviated, time: .shortened)
        let end = booking.endDate.formatted(date: .omitted, time: .shortened)
        if let window = booking.arrivalWindowMinutes, window > 0 {
            return "\(start) • approx. \(window) min"
        }
        return "\(start) - \(end)"
    }

    private var memberWorkTypeIcon: String {
        if member.role == .owner { return "crown.fill" }
        if member.isTechnician { return "wrench.and.screwdriver.fill" }
        return "person.fill"
    }

    private var memberWorkTypeColor: Color {
        if member.role == .owner { return Color.electricViolet }
        if member.isTechnician { return Color.statusNotHome }
        return Color.statusInterested
    }

    private func jobStatusButtons(_ booking: TeamBooking) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 88), spacing: 8)], alignment: .leading, spacing: 8) {
            jobStatusButton("On way", status: .enRoute, booking: booking)
            jobStatusButton("Started", status: .inProgress, booking: booking)
            jobStatusButton("Done", status: .completed, booking: booking)
            jobStatusButton("Owner follow-up", status: .needsOwnerFollowUp, booking: booking)
        }
    }

    private func jobStatusButton(_ title: String, status: TeamBookingStatus, booking: TeamBooking) -> some View {
        Button {
            updateBookingStatus(booking, status: status)
        } label: {
            Text(title)
                .font(.nano)
                .foregroundColor(canUpdateBooking(booking) ? Color.electricViolet : Color.textMuted)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(
                    Capsule()
                        .fill(Color.electricViolet.opacity(canUpdateBooking(booking) ? 0.12 : 0.05))
                )
                .contentShape(Capsule())
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(!canUpdateBooking(booking) || booking.status == status || isSaving || teamService.isLoading)
    }

    private func canUpdateBooking(_ booking: TeamBooking) -> Bool {
        guard let team = teamService.activeTeam,
              let currentMember = teamService.currentMember else { return false }
        return TeamAccessPolicy.canWriteAssignedRecord(
            userId: currentMember.userId,
            role: currentMember.role,
            planStatus: team.planStatus,
            assignedToUserId: booking.assignedToUserId
        )
    }

    private func updateBookingStatus(_ booking: TeamBooking, status: TeamBookingStatus) {
        guard !isSaving else { return }
        isSaving = true
        statusMessage = nil

        Task {
            do {
                _ = try await teamService.updateTeamBookingStatus(booking, status: status)
                statusMessage = "Job marked \(status.displayName.lowercased())."
                statusMessageIsError = false
            } catch {
                statusMessage = TeamFirebaseService.userFacingErrorMessage(for: error)
                statusMessageIsError = true
            }
            isSaving = false
        }
    }

    private func openDirections(to point: TeamDutyLocationPoint) {
        let coordinate = CLLocationCoordinate2D(latitude: point.latitude, longitude: point.longitude)
        let placemark = MKPlacemark(coordinate: coordinate)
        let item = MKMapItem(placemark: placemark)
        item.name = "\(member.displayName) live location"
        item.openInMaps(launchOptions: [
            MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving
        ])
    }

    private func openDirections(to booking: TeamBooking) {
        if let latitude = booking.latitude, let longitude = booking.longitude {
            let coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
            let placemark = MKPlacemark(coordinate: coordinate)
            let item = MKMapItem(placemark: placemark)
            item.name = booking.location.isEmpty ? booking.title : booking.location
            item.openInMaps(launchOptions: [
                MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving
            ])
            return
        }

        let encodedAddress = booking.location.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? booking.location
        guard let url = URL(string: "http://maps.apple.com/?daddr=\(encodedAddress)") else { return }
        UIApplication.shared.open(url)
    }

    private func trimmed(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }

    private func currencyText(_ value: Double) -> String {
        String(format: "$%.2f", value)
    }

    private func distanceText(_ meters: Double) -> String {
        if meters >= 1_000 {
            return String(format: "%.1f km", meters / 1_000)
        }
        return "\(Int(meters.rounded())) m"
    }

    private func constantSelection(_ userId: String?) -> Binding<String?> {
        Binding(get: { userId }, set: { _ in })
    }
}

private struct TeamRepDetailCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.obsidianSurface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.obsidianBorder.opacity(0.42), lineWidth: 1)
        )
    }
}

private struct TeamRepMetricPill: View {
    let title: String
    let systemImage: String
    let color: Color

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.micro)
            .foregroundColor(color)
            .lineLimit(1)
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(Capsule().fill(color.opacity(0.12)))
    }
}

private struct TeamRepDetailNotice: View {
    let message: String
    let isError: Bool

    var body: some View {
        Label(message, systemImage: isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
            .font(.obsidianFootnote)
            .foregroundColor(isError ? Color.statusNotInterested : Color.statusInterested)
            .fixedSize(horizontal: false, vertical: true)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.obsidianSurface)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke((isError ? Color.statusNotInterested : Color.statusInterested).opacity(0.35), lineWidth: 1)
            )
    }
}

private struct TeamRepDetailStatRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack {
            Text(title)
                .foregroundColor(Color.textSecondary)
            Spacer()
            Text(value)
                .foregroundColor(Color.textPrimary)
                .fontWeight(.semibold)
        }
        .font(.obsidianFootnote)
    }
}

private struct TeamRepDetailJobRow: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.nano)
                .foregroundColor(Color.textMuted)
            Text(value)
                .font(.micro)
                .foregroundColor(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
