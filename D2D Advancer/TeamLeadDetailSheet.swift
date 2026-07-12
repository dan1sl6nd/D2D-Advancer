import SwiftUI
import MapKit
import UIKit

struct TeamLeadDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var teamService = TeamFirebaseService.shared

    let initialLead: TeamLead

    @State private var isSaving = false
    @State private var copiedFieldName: String?
    @State private var copyToastDismissTask: Task<Void, Never>?
    @State private var statusMessage: String?
    @State private var statusMessageIsError = false
    @State private var showingAdvancedDetails = false
    @State private var selectedRepWorkspace: TeamRepWorkspace?
    @State private var editableLeadId: String?
    @State private var editName = ""
    @State private var editPhone = ""
    @State private var editEmail = ""
    @State private var editAddress = ""
    @State private var editServiceCategory = ""
    @State private var editPrice = ""
    @State private var editEstimatedValue = ""
    @State private var editTags = ""
    @State private var editNotes = ""
    @State private var jobStartDate = Date().addingTimeInterval(60 * 60)
    @State private var jobDurationHours = 2

    private var lead: TeamLead {
        teamService.teamLeads.first(where: { $0.id == initialLead.id }) ?? initialLead
    }

    private var currentMember: TeamMember? {
        teamService.currentMember
    }

    private var activeTeam: TeamWorkspace? {
        teamService.activeTeam
    }

    private var assignedMember: TeamMember? {
        teamService.teamMembers.first { $0.userId == lead.assignedToUserId }
    }

    private var assignedWorkspace: TeamRepWorkspace? {
        guard let assignedMember else { return nil }
        return TeamRepWorkspace.makeMemberWorkspace(
            member: assignedMember,
            leads: teamService.teamLeads.filter { $0.assignedToUserId == assignedMember.userId },
            bookings: teamService.teamBookings.filter { $0.assignedToUserId == assignedMember.userId },
            dutySessions: teamService.dutySessions,
            dutyLocationPoints: teamService.dutyLocationPoints
        )
    }

    private var creatorMember: TeamMember? {
        teamService.teamMembers.first { $0.userId == lead.createdByUserId }
    }

    private var updaterMember: TeamMember? {
        teamService.teamMembers.first { $0.userId == lead.updatedByUserId }
    }

    private var relatedBookings: [TeamBooking] {
        teamService.teamBookings
            .filter { $0.leadId == lead.id }
            .sorted { $0.startDate < $1.startDate }
    }

    private var relatedActivity: [TeamActivityLogEntry] {
        teamService.activityLog
            .filter { $0.subjectId == lead.id }
            .sorted { $0.createdAt > $1.createdAt }
    }

    private var relatedAlerts: [TeamOwnerNotification] {
        teamService.ownerNotifications
            .filter { $0.leadId == lead.id }
            .sorted { $0.createdAt > $1.createdAt }
    }

    private var nextBooking: TeamBooking? {
        relatedBookings.first { $0.endDate >= Date() } ?? relatedBookings.last
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

    private var canWriteLead: Bool {
        guard let currentMember, let activeTeam else { return false }
        return TeamAccessPolicy.canWriteAssignedRecord(
            userId: currentMember.userId,
            role: currentMember.role,
            planStatus: activeTeam.effectivePlanStatus(),
            assignedToUserId: lead.assignedToUserId
        )
    }

    private var canAssignLead: Bool {
        guard let currentMember, let activeTeam else { return false }
        return currentMember.role == .owner
            && currentMember.status == .active
            && activeTeam.effectivePlanStatus().allowsTeamWrite
            && !activeAssignableReps.isEmpty
    }

    private var canDispatchLeadToTechnician: Bool {
        guard let currentMember, let activeTeam else { return false }
        return currentMember.role == .owner
            && currentMember.status == .active
            && activeTeam.effectivePlanStatus().allowsTeamWrite
            && !activeTechnicians.isEmpty
    }

    private var editableFields: TeamLeadEditableFields {
        TeamLeadEditableFields(
            name: editName,
            address: editAddress,
            phone: editPhone,
            email: editEmail,
            notes: editNotes,
            serviceCategory: editServiceCategory,
            price: decimalValue(editPrice),
            estimatedValue: decimalValue(editEstimatedValue),
            tags: editTags
                .split(separator: ",")
                .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        )
    }

    private var jobEndDate: Date {
        jobStartDate.addingTimeInterval(TimeInterval(jobDurationHours) * 60 * 60)
    }

    private var phoneText: String? {
        copyableValue(lead.phone)
    }

    private var emailText: String? {
        copyableValue(lead.email)
    }

    private var isActionableHighPriority: Bool {
        TeamLeadAttentionPolicy.isActionableHighPriority(lead)
    }

    private var priorityText: String {
        isActionableHighPriority ? "High priority" : "Normal"
    }

    private var valueText: String {
        if lead.estimatedValue > 0 {
            return moneyText(lead.estimatedValue)
        }
        if lead.price > 0 {
            return moneyText(lead.price)
        }
        return "Not set"
    }

    private var hasSalesDetails: Bool {
        lead.serviceCategory != nil || lead.price > 0 || lead.estimatedValue > 0 || !lead.tags.isEmpty
    }

    private var nextActionTitle: String {
        if isActionableHighPriority {
            return "High-priority lead"
        }

        switch lead.status {
        case .interested:
            return "Follow up while interest is fresh"
        case .followUp:
            return "Owner follow-up needed"
        case .booked:
            return "Booking needs review"
        case .converted:
            return "Converted lead"
        case .notHome:
            return "Comeback opportunity"
        case .contacted:
            return "Contacted, not closed"
        case .notContacted:
            return "New team lead"
        case .notInterested:
            return "Low-priority lead"
        }
    }

    private var nextActionDetail: String {
        if isActionableHighPriority, let reason = copyableValue(lead.highPriorityReason) {
            return reason
        }
        if let note = copyableValue(lead.notes) {
            return note
        }
        if let nextBooking {
            return "Booked for \(nextBooking.startDate.formatted(date: .abbreviated, time: .shortened))."
        }
        if let assignedMember {
            return "Assigned to \(assignedMember.displayName)."
        }
        return "Review the lead, update status, or reassign it to the right rep."
    }

    private var nextActionIcon: String {
        if isActionableHighPriority { return "star.fill" }
        return lead.status.teamIconName
    }

    private var nextActionColor: Color {
        if isActionableHighPriority { return Color.statusInterested }
        return lead.status.teamColor
    }

    private var primaryActionTitle: String {
        if phoneText != nil {
            return lead.status == .notHome ? "Text comeback" : "Text customer"
        }
        return "Open route"
    }

    private var primaryActionIcon: String {
        phoneText == nil ? "arrow.triangle.turn.up.right.diamond.fill" : "message.fill"
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        headerCard

                        if let statusMessage {
                            TeamLeadDetailNotice(
                                message: statusMessage,
                                isError: statusMessageIsError
                            )
                        }

                        nextActionCard
                        quickActions

                        TeamLeadDetailSection("Pipeline") {
                            statusChips
                            priorityRow
                            assignmentRow
                        }

                        editableFieldsSection
                        technicianDispatchSection

                        TeamLeadDetailSection("Contact") {
                            TeamLeadDetailFieldRow(title: "Name", value: lead.name, onCopy: copyField)
                            TeamLeadDetailFieldRow(title: "Phone", value: phoneText ?? "Not provided", onCopy: copyField)
                            TeamLeadDetailFieldRow(title: "Email", value: emailText ?? "Not provided", onCopy: copyField)
                            TeamLeadDetailFieldRow(title: "Address", value: lead.address, onCopy: copyField)
                        }

                        salesDetailsSection

                        notesSection
                        bookingsSection
                        alertsSection
                        activitySection
                        advancedDetailsSection
                    }
                    .padding(16)
                    .padding(.bottom, 24)
                }
                .obsidianScreenBackground()

                copyToastOverlay
            }
            .obsidianPushedNavigation(
                "Team Lead Detail",
                backButtonAccessibilityIdentifier: "teamLeadDetailBackButton",
                onBack: { dismiss() }
            ) {
                TeamToolbarDoneButton {
                    dismiss()
                }
                .accessibilityIdentifier("teamLeadDetailCloseButton")
            }
        }
        .obsidianModalBackground()
        .onDisappear {
            copyToastDismissTask?.cancel()
            copyToastDismissTask = nil
        }
        .onAppear {
            resetEditableFields(from: lead)
        }
        .sheet(item: $selectedRepWorkspace) { workspace in
            TeamRepDetailSheet(initialWorkspace: workspace) {
                selectedRepWorkspace = nil
            }
        }
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: isActionableHighPriority ? "star.fill" : lead.status.teamIconName)
                    .font(.obsidianAction)
                    .foregroundColor(.white)
                    .frame(width: 44, height: 44)
                    .background(isActionableHighPriority ? Color.statusInterested : lead.status.teamColor)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                VStack(alignment: .leading, spacing: 5) {
                    Text(lead.name.isEmpty ? "Unnamed Lead" : lead.name)
                        .font(.obsidianHeadline)
                        .foregroundColor(Color.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("teamLeadDetailName")

                    Text(lead.address)
                        .font(.obsidianFootnote)
                        .foregroundColor(Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    TeamLeadDetailPill(
                        title: lead.status.teamDisplayName,
                        systemImage: lead.status.teamIconName,
                        color: lead.status.teamColor
                    )
                    TeamLeadDetailPill(
                        title: assignedMember?.displayName ?? "Unassigned",
                        systemImage: "person.crop.circle.badge.checkmark",
                        color: Color.electricViolet
                    )
                    TeamLeadDetailPill(
                        title: valueText,
                        systemImage: "dollarsign.circle.fill",
                        color: Color.statusConverted
                    )
                }
            }
        }
        .padding(16)
        .background(Color.obsidianSurface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.obsidianBorder.opacity(0.42), lineWidth: 1)
        )
    }

    private var nextActionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: nextActionIcon)
                    .font(.obsidianCallout)
                    .foregroundColor(.white)
                    .frame(width: 34, height: 34)
                    .background(nextActionColor)
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 4) {
                    Text(nextActionTitle)
                        .font(.obsidianCallout)
                        .foregroundColor(Color.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(nextActionDetail)
                        .font(.obsidianFootnote)
                        .foregroundColor(Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 4)
            }

            Button {
                runPrimaryAction()
            } label: {
                Label(primaryActionTitle, systemImage: primaryActionIcon)
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
            .accessibilityIdentifier("teamLeadDetailPrimaryAction")
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(nextActionColor.opacity(0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(nextActionColor.opacity(0.35), lineWidth: 1)
        )
    }

    private var quickActions: some View {
        HStack(spacing: 10) {
            TeamLeadDetailActionButton(title: "Call", systemImage: "phone.fill", isEnabled: phoneText != nil) {
                guard let phoneText else { return }
                Utilities.makePhoneCall(to: phoneText)
            }

            TeamLeadDetailActionButton(title: "Text", systemImage: "message.fill", isEnabled: phoneText != nil) {
                guard let phoneText else { return }
                Utilities.sendSMS(to: phoneText)
            }

            TeamLeadDetailActionButton(title: "Email", systemImage: "envelope.fill", isEnabled: emailText != nil) {
                guard let emailText else { return }
                Utilities.sendEmail(to: emailText)
            }

            TeamLeadDetailActionButton(title: "Route", systemImage: "arrow.triangle.turn.up.right.diamond.fill", isEnabled: true) {
                Utilities.openMapsDirections(latitude: lead.latitude, longitude: lead.longitude)
            }
        }
    }

    private var statusChips: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                TeamLeadDetailFieldText(title: "Status", value: lead.status.teamDisplayName)
                Spacer()
                if !canWriteLead {
                    Text("Read-only")
                        .font(.nano)
                        .foregroundColor(Color.textMuted)
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 8) {
                    ForEach(TeamLeadStatus.allCases, id: \.rawValue) { status in
                        TeamLeadStatusChip(
                            status: status,
                            isSelected: status == lead.status,
                            isDisabled: !canWriteLead || isSaving
                        ) {
                            updateLead(status: status)
                        }
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .padding(.vertical, 8)
    }

    private var priorityRow: some View {
        HStack(spacing: 12) {
            TeamLeadDetailFieldText(title: "Priority", value: priorityText)
            Spacer()
            if canWriteLead {
                Button {
                    togglePriority()
                } label: {
                    Label(lead.isHighPriority ? "Clear" : "Mark high", systemImage: lead.isHighPriority ? "star.slash" : "star.fill")
                        .font(.micro)
                        .foregroundColor(lead.isHighPriority ? Color.textSecondary : Color.statusInterested)
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(isSaving || (!lead.isHighPriority && !TeamLeadAttentionPolicy.canMarkHighPriority(lead)))
                .accessibilityIdentifier("teamLeadDetailPriorityButton")
            }
        }
        .padding(.vertical, 8)
    }

    private var assignmentRow: some View {
        HStack(spacing: 12) {
            TeamLeadDetailFieldText(
                title: "Assigned to",
                value: assignedMember?.displayName ?? "Unassigned"
            )
            .accessibilityIdentifier("teamLeadDetailAssignedRep")

            Spacer()

            if let assignedWorkspace {
                Button {
                    selectedRepWorkspace = assignedWorkspace
                } label: {
                    Label(assignedMember?.role == .owner ? "View Owner" : "View \(assignedMember?.displayRoleTitle ?? "Worker")", systemImage: "person.text.rectangle.fill")
                        .font(.micro)
                        .foregroundColor(Color.electricViolet)
                }
                .buttonStyle(PlainButtonStyle())
                .accessibilityIdentifier("teamLeadViewRepButton")
            }

            if canAssignLead {
                Menu {
                    ForEach(activeAssignableReps) { rep in
                        Button(rep.displayName) {
                            assignLead(to: rep)
                        }
                        .disabled(rep.userId == lead.assignedToUserId || isSaving)
                    }
                } label: {
                    Label("Reassign", systemImage: "person.crop.circle.badge.checkmark")
                        .font(.micro)
                        .foregroundColor(Color.electricViolet)
                }
                .accessibilityIdentifier("teamLeadDetailAssignMenu")
            }
        }
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var editableFieldsSection: some View {
        if canWriteLead {
            TeamLeadDetailSection("Edit Lead Fields", systemImage: "square.and.pencil") {
                VStack(spacing: 16) {
                    TeamLeadDetailEditField(title: "Name", text: $editName, icon: "person.fill")
                    TeamLeadDetailEditField(title: "Phone", text: $editPhone, icon: "phone.fill", keyboardType: .phonePad)
                    TeamLeadDetailEditField(title: "Email", text: $editEmail, icon: "envelope.fill", keyboardType: .emailAddress)
                    TeamLeadDetailEditField(title: "Address", text: $editAddress, icon: "location.fill")
                    TeamLeadDetailEditField(title: "Service", text: $editServiceCategory, icon: "tag.fill")
                    TeamLeadDetailEditField(title: "Sold price", text: $editPrice, icon: "dollarsign.circle.fill", keyboardType: .decimalPad)
                    TeamLeadDetailEditField(title: "Est. value", text: $editEstimatedValue, icon: "chart.line.uptrend.xyaxis", keyboardType: .decimalPad)
                    TeamLeadDetailEditField(title: "Tags", text: $editTags, icon: "number")
                    TeamLeadDetailEditTextArea(title: "Notes", text: $editNotes, icon: "note.text")
                }

                Button {
                    saveEditableFields()
                } label: {
                    Label("Save Changes", systemImage: "square.and.arrow.down.fill")
                        .font(.obsidianFootnote)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(Color.electricViolet)
                        )
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(isSaving)
                .accessibilityIdentifier("teamLeadDetailSaveFieldsButton")
            }
        }
    }

    @ViewBuilder
    private var technicianDispatchSection: some View {
        if currentMember?.role == .owner {
            TeamLeadDetailSection("Send To Technician", systemImage: "wrench.and.screwdriver.fill") {
                if activeTechnicians.isEmpty {
                    TeamLeadDetailInlineNotice(
                        text: "Create a Technician invite before sending sold work.",
                        icon: "person.badge.plus"
                    )
                } else {
                    VStack(spacing: 16) {
                        TeamLeadDetailInlineNotice(
                            text: lead.status == .converted ? "Create or update the service job for this sold lead." : "This will mark the lead sold and create the service job.",
                            icon: "checkmark.seal.fill"
                        )

                        TeamLeadDetailDateField(
                            title: "Approx. arrival",
                            selection: $jobStartDate
                        )
                        .accessibilityIdentifier("teamLeadDetailJobDatePicker")

                        TeamLeadDetailStepperField(
                            title: "Duration",
                            value: $jobDurationHours,
                            range: 1...12,
                            suffix: "hr"
                        )
                        .accessibilityIdentifier("teamLeadDetailJobDurationStepper")
                    }

                    Menu {
                        ForEach(activeTechnicians) { technician in
                            Button("\(technician.displayName) • Technician") {
                                dispatchLead(to: technician)
                            }
                            .disabled(isSaving)
                        }
                    } label: {
                        Label(lead.status == .converted ? "Send Job" : "Mark Sold & Send Job", systemImage: "wrench.and.screwdriver.fill")
                            .font(.obsidianFootnote)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(canDispatchLeadToTechnician ? Color.statusConverted : Color.textMuted)
                            )
                    }
                    .buttonStyle(PlainButtonStyle())
                    .disabled(!canDispatchLeadToTechnician || isSaving)
                    .accessibilityIdentifier("teamLeadDetailDispatchTechnicianMenu")
                }
            }
        }
    }

    @ViewBuilder
    private var salesDetailsSection: some View {
        if hasSalesDetails {
            TeamLeadDetailSection("Sales details") {
                if let serviceCategory = lead.serviceCategory {
                    TeamLeadDetailFieldRow(title: "Service", value: serviceCategory, onCopy: copyField)
                }
                if lead.price > 0 {
                    TeamLeadDetailFieldRow(title: "Price", value: moneyText(lead.price), onCopy: copyField)
                }
                if lead.estimatedValue > 0 {
                    TeamLeadDetailFieldRow(title: "Estimated value", value: moneyText(lead.estimatedValue), onCopy: copyField)
                }
                if !lead.tags.isEmpty {
                    TeamLeadDetailFieldRow(title: "Tags", value: lead.tags.joined(separator: ", "), onCopy: copyField)
                }
            }
        }
    }

    @ViewBuilder
    private var notesSection: some View {
        let note = copyableValue(lead.notes)
        let priorityReason = copyableValue(lead.highPriorityReason)

        if note != nil || priorityReason != nil {
            TeamLeadDetailSection("Notes") {
                if let priorityReason {
                    TeamLeadDetailFieldRow(title: "Priority reason", value: priorityReason, onCopy: copyField)
                }
                if let note {
                    TeamLeadDetailFieldRow(title: "Rep note", value: note, onCopy: copyField)
                }
            }
        }
    }

    @ViewBuilder
    private var bookingsSection: some View {
        if relatedBookings.isEmpty {
            EmptyView()
        } else {
            TeamLeadDetailSection("Bookings") {
                ForEach(relatedBookings) { booking in
                    TeamLeadDetailBookingRow(booking: booking, assignedName: displayName(forUserId: booking.assignedToUserId))
                }
            }
        }
    }

    @ViewBuilder
    private var alertsSection: some View {
        if !relatedAlerts.isEmpty {
            TeamLeadDetailSection("Owner Alerts") {
                ForEach(relatedAlerts) { alert in
                    TeamLeadDetailAlertRow(alert: alert)
                }
            }
        }
    }

    @ViewBuilder
    private var activitySection: some View {
        if relatedActivity.isEmpty {
            EmptyView()
        } else {
            TeamLeadDetailSection("Recent activity") {
                ForEach(relatedActivity.prefix(8)) { entry in
                    TeamLeadDetailActivityRow(entry: entry)
                }
            }
        }
    }

    private var advancedDetailsSection: some View {
        DisclosureGroup(isExpanded: $showingAdvancedDetails) {
            VStack(spacing: 0) {
                TeamLeadDetailFieldRow(title: "Created by", value: displayName(for: creatorMember, fallback: lead.createdByUserId), onCopy: copyField)
                TeamLeadDetailFieldRow(title: "Last updated by", value: displayName(for: updaterMember, fallback: lead.updatedByUserId), onCopy: copyField)
                TeamLeadDetailFieldRow(title: "Created", value: dateText(lead.createdAt), onCopy: copyField)
                TeamLeadDetailFieldRow(title: "Updated", value: dateText(lead.updatedAt), onCopy: copyField)
                TeamLeadDetailFieldRow(title: "Lead ID", value: lead.id, onCopy: copyField)
                TeamLeadDetailFieldRow(title: "Team ID", value: lead.teamId, onCopy: copyField)
                TeamLeadDetailFieldRow(title: "Coordinates", value: coordinateText, onCopy: copyField)
            }
            .padding(.top, 8)
        } label: {
            Label("Advanced details", systemImage: "info.circle")
                .font(.obsidianFootnote)
                .foregroundColor(Color.textSecondary)
        }
        .padding(14)
        .background(Color.obsidianSurface)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.obsidianBorder.opacity(0.35), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var copyToastOverlay: some View {
        if let copiedFieldName {
            Text("\(copiedFieldName) copied")
                .font(.obsidianFootnote)
                .fontWeight(.semibold)
                .foregroundColor(Color.textPrimary)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color.obsidianElevated.opacity(0.96))
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .stroke(Color.obsidianBorder.opacity(0.5), lineWidth: 0.5)
                )
                .shadow(color: Color.black.opacity(0.28), radius: 10, x: 0, y: 4)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .padding(.bottom, 14)
                .accessibilityLabel("\(copiedFieldName) copied")
        }
    }

    private var coordinateText: String {
        "\(lead.latitude), \(lead.longitude)"
    }

    private func updateLead(status: TeamLeadStatus) {
        runLeadUpdate {
            try await teamService.updateTeamLead(leadId: lead.id, status: status)
        }
    }

    private func togglePriority() {
        let shouldBeHighPriority = !lead.isHighPriority
        if shouldBeHighPriority && !TeamLeadAttentionPolicy.canMarkHighPriority(lead) {
            statusMessage = "Closed leads cannot be marked high priority."
            statusMessageIsError = true
            return
        }

        runLeadUpdate {
            try await teamService.updateTeamLead(
                leadId: lead.id,
                isHighPriority: shouldBeHighPriority,
                highPriorityReason: shouldBeHighPriority ? "Marked from detail" : ""
            )
        }
    }

    private func assignLead(to rep: TeamMember) {
        runLeadUpdate {
            try await teamService.assignTeamLead(lead, to: rep)
        }
    }

    private func saveEditableFields() {
        runLeadUpdate(successMessage: "Lead fields saved.") {
            try await teamService.updateTeamLead(
                leadId: lead.id,
                editableFields: editableFields
            )
        }
    }

    private func dispatchLead(to technician: TeamMember) {
        runLeadUpdate(successMessage: "Job sent to \(technician.displayName).") {
            _ = try await teamService.dispatchTeamLeadToTechnicianJob(
                lead: lead,
                technician: technician,
                startDate: jobStartDate,
                endDate: jobEndDate
            )
            return teamService.teamLeads.first(where: { $0.id == lead.id }) ?? lead
        }
    }

    private func runPrimaryAction() {
        if let phoneText {
            Utilities.sendSMS(to: phoneText)
        } else {
            Utilities.openMapsDirections(latitude: lead.latitude, longitude: lead.longitude)
        }
    }

    private func runLeadUpdate(successMessage: String = "Team lead updated.", _ operation: @escaping () async throws -> TeamLead) {
        guard !isSaving else { return }
        isSaving = true
        statusMessage = nil

        Task {
            do {
                let updatedLead = try await operation()
                resetEditableFields(from: updatedLead)
                statusMessage = successMessage
                statusMessageIsError = false
            } catch {
                statusMessage = TeamFirebaseService.userFacingErrorMessage(for: error)
                statusMessageIsError = true
            }
            isSaving = false
        }
    }

    private func resetEditableFields(from lead: TeamLead) {
        editableLeadId = lead.id
        editName = lead.name
        editPhone = lead.phone ?? ""
        editEmail = lead.email ?? ""
        editAddress = lead.address
        editServiceCategory = lead.serviceCategory ?? ""
        editPrice = lead.price > 0 ? numberEditText(lead.price) : ""
        editEstimatedValue = lead.estimatedValue > 0 ? numberEditText(lead.estimatedValue) : ""
        editTags = lead.tags.joined(separator: ", ")
        editNotes = lead.notes
    }

    private func decimalValue(_ text: String) -> Double {
        let sanitized = text
            .replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: ",", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return Double(sanitized) ?? 0
    }

    private func numberEditText(_ value: Double) -> String {
        value.rounded() == value ? String(Int(value)) : String(value)
    }

    private func copyField(title: String, value: String) {
        guard let copyValue = copyableValue(value) else { return }
        UIPasteboard.general.string = copyValue
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        UIAccessibility.post(notification: .announcement, argument: "\(title) copied")

        copyToastDismissTask?.cancel()
        withAnimation(.easeInOut(duration: 0.18)) {
            copiedFieldName = title
        }

        copyToastDismissTask = Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.18)) {
                    copiedFieldName = nil
                }
            }
        }
    }

    private func copyableValue(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != "Not provided", trimmed != "Not set", trimmed != "None", trimmed != "Unknown" else {
            return nil
        }
        return trimmed
    }

    private func displayName(for member: TeamMember?, fallback: String) -> String {
        member?.displayName ?? fallback
    }

    private func displayName(forUserId userId: String) -> String {
        teamService.teamMembers.first { $0.userId == userId }?.displayName ?? "Unassigned"
    }

    private func dateText(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .shortened)
    }

    private func moneyText(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = Locale.current.currency?.identifier ?? "USD"
        formatter.maximumFractionDigits = value.rounded() == value ? 0 : 2
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }
}

private struct TeamLeadDetailSection<Content: View>: View {
    let title: String
    let systemImage: String?
    @ViewBuilder let content: Content

    init(_ title: String, systemImage: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.systemImage = systemImage
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.obsidianAction)
                        .foregroundColor(Color.electricViolet)
                        .frame(width: 24)
                }

                Text(title)
                    .font(systemImage == nil ? .obsidianCallout : .themeTitle)
                    .foregroundColor(Color.textPrimary)

                Spacer()
            }

            VStack(spacing: systemImage == nil ? 0 : 16) {
                content
            }
            .padding(.horizontal, systemImage == nil ? 12 : 20)
            .padding(.vertical, systemImage == nil ? 6 : 20)
            .background(Color.obsidianSurface)
            .clipShape(RoundedRectangle(cornerRadius: systemImage == nil ? 14 : 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: systemImage == nil ? 14 : 16, style: .continuous)
                    .stroke(systemImage == nil ? Color.obsidianBorder.opacity(0.4) : Color.obsidianBorder, lineWidth: systemImage == nil ? 1 : 0.5)
            )
            .shadow(color: systemImage == nil ? Color.clear : Color.black.opacity(0.08), radius: systemImage == nil ? 0 : 8, x: 0, y: systemImage == nil ? 0 : 2)
        }
    }
}

private struct TeamLeadDetailFieldRow: View {
    let title: String
    let value: String
    let onCopy: (String, String) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            TeamLeadDetailFieldText(title: title, value: value)
            Spacer(minLength: 10)
            Image(systemName: "doc.on.doc")
                .font(.nano)
                .foregroundColor(Color.textMuted)
                .opacity(copyable ? 1 : 0)
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .contextMenu {
            if copyable {
                Button {
                    onCopy(title, value)
                } label: {
                    Label("Copy \(title)", systemImage: "doc.on.doc")
                }
            }
        }
        .accessibilityHint(copyable ? "Long press to copy \(title.lowercased())" : "")
    }

    private var copyable: Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty
            && trimmed != "Not provided"
            && trimmed != "Not set"
            && trimmed != "None"
            && trimmed != "Unknown"
    }
}

private struct TeamLeadDetailFieldText: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.nano)
                .foregroundColor(Color.textMuted)
                .textCase(.uppercase)
            Text(value)
                .font(.micro)
                .foregroundColor(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct TeamLeadDetailEditField: View {
    let title: String
    @Binding var text: String
    let icon: String
    var keyboardType: UIKeyboardType = .default

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundColor(Color.electricViolet)
                    .frame(width: 20)

                Text(title)
                    .font(.obsidianFootnote)
                    .foregroundColor(Color.textPrimary)
            }

            TextField(title, text: $text)
                .keyboardType(keyboardType)
                .textInputAutocapitalization(keyboardType == .emailAddress ? .never : .sentences)
                .autocorrectionDisabled(keyboardType == .emailAddress)
                .font(.obsidianCallout)
                .foregroundColor(Color.textPrimary)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.obsidianSurface)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(Color.obsidianBorder.opacity(0.5), lineWidth: 0.5)
                        )
                )
        }
    }
}

private struct TeamLeadDetailEditTextArea: View {
    let title: String
    @Binding var text: String
    let icon: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundColor(Color.electricViolet)
                    .frame(width: 20)

                Text(title)
                    .font(.obsidianFootnote)
                    .foregroundColor(Color.textPrimary)
            }

            TextEditor(text: $text)
                .font(.obsidianCallout)
                .foregroundColor(Color.textPrimary)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 104)
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.obsidianSurface)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(Color.obsidianBorder.opacity(0.5), lineWidth: 0.5)
                        )
                )
        }
    }
}

private struct TeamLeadDetailDateField: View {
    let title: String
    @Binding var selection: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "calendar.badge.clock")
                    .foregroundColor(Color.electricViolet)
                    .frame(width: 20)

                Text(title)
                    .font(.obsidianFootnote)
                    .foregroundColor(Color.textPrimary)
            }

            DatePicker(title, selection: $selection, displayedComponents: [.date, .hourAndMinute])
                .labelsHidden()
                .tint(Color.electricViolet)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.obsidianSurface)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(Color.obsidianBorder.opacity(0.5), lineWidth: 0.5)
                        )
                )
        }
    }
}

private struct TeamLeadDetailStepperField: View {
    let title: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    let suffix: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "clock.fill")
                    .foregroundColor(Color.electricViolet)
                    .frame(width: 20)

                Text(title)
                    .font(.obsidianFootnote)
                    .foregroundColor(Color.textPrimary)
            }

            Stepper(value: $value, in: range) {
                Text("\(value) \(suffix)")
                    .font(.obsidianFootnote)
                    .foregroundColor(Color.textPrimary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.obsidianSurface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color.obsidianBorder.opacity(0.5), lineWidth: 0.5)
                    )
            )
        }
    }
}

private struct TeamLeadDetailInlineNotice: View {
    let text: String
    let icon: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.obsidianFootnote)
                .foregroundColor(Color.electricViolet)
                .frame(width: 20)

            Text(text)
                .font(.obsidianFootnote)
                .foregroundColor(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.obsidianSurface)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.obsidianBorder.opacity(0.5), lineWidth: 0.5)
                )
        )
    }
}

private struct TeamLeadDetailPill: View {
    let title: String
    let systemImage: String
    let color: Color

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.nano)
            .foregroundColor(color)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(color.opacity(0.12))
            )
    }
}

private struct TeamLeadStatusChip: View {
    let status: TeamLeadStatus
    let isSelected: Bool
    let isDisabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: status.teamIconName)
                    .font(.nano)
                Text(status.teamDisplayName)
                    .font(.micro)
                    .lineLimit(1)
            }
            .foregroundColor(isSelected ? .white : status.teamColor)
            .padding(.horizontal, 11)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(isSelected ? status.teamColor : status.teamColor.opacity(0.12))
            )
            .overlay(
                Capsule()
                    .stroke(status.teamColor.opacity(isSelected ? 0 : 0.35), lineWidth: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(isDisabled || isSelected)
        .opacity(isDisabled && !isSelected ? 0.55 : 1)
        .accessibilityIdentifier("teamLeadStatusChip_\(status.rawValue)")
        .accessibilityLabel("Set status to \(status.teamDisplayName)")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

private struct TeamLeadDetailActionButton: View {
    let title: String
    let systemImage: String
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.obsidianFootnote)
                Text(title)
                    .font(.nano)
                    .lineLimit(1)
            }
            .foregroundColor(isEnabled ? Color.electricViolet : Color.textMuted)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 11)
            .background(Color.obsidianSurface)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.obsidianBorder.opacity(0.4), lineWidth: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(!isEnabled)
        .accessibilityIdentifier("teamLeadDetailAction\(title)")
    }
}

private struct TeamLeadDetailBookingRow: View {
    let booking: TeamBooking
    let assignedName: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                Image(systemName: "calendar.badge.clock")
                    .foregroundColor(Color.electricViolet)
                Text(booking.title)
                    .font(.micro)
                    .foregroundColor(Color.textPrimary)
                Spacer()
                Text(booking.status.rawValue.capitalized)
                    .font(.nano)
                    .foregroundColor(Color.textMuted)
            }

            Text("Approx. arrival \(booking.startDate.formatted(date: .abbreviated, time: .shortened)) - \(booking.endDate.formatted(date: .omitted, time: .shortened))")
                .font(.nano)
                .foregroundColor(Color.textSecondary)

            Text(booking.location.isEmpty ? "No location" : booking.location)
                .font(.nano)
                .foregroundColor(Color.textMuted)

            Text("Assigned to \(assignedName)")
                .font(.nano)
                .foregroundColor(Color.textMuted)
        }
        .padding(.vertical, 9)
    }
}

private struct TeamLeadDetailAlertRow: View {
    let alert: TeamOwnerNotification

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(alert.title)
                    .font(.micro)
                    .foregroundColor(Color.textPrimary)
                Spacer()
                Text(alert.readAt == nil ? "Unread" : "Read")
                    .font(.nano)
                    .foregroundColor(alert.readAt == nil ? Color.statusInterested : Color.textMuted)
            }
            Text(alert.message)
                .font(.nano)
                .foregroundColor(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(alert.createdAt.formatted(date: .abbreviated, time: .shortened))
                .font(.nano)
                .foregroundColor(Color.textMuted)
        }
        .padding(.vertical, 9)
    }
}

private struct TeamLeadDetailActivityRow: View {
    let entry: TeamActivityLogEntry

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: iconName)
                .font(.nano)
                .foregroundColor(Color.electricViolet)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.summary)
                    .font(.micro)
                    .foregroundColor(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(entry.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.nano)
                    .foregroundColor(Color.textMuted)
            }
        }
        .padding(.vertical, 9)
    }

    private var iconName: String {
        switch entry.kind {
        case .leadHighPriority:
            return "star.fill"
        case .leadAssigned, .bookingAssigned:
            return "person.crop.circle.badge.checkmark"
        case .leadStatusUpdated, .repStatusReply, .bookingStatusUpdated:
            return "bubble.left.and.bubble.right.fill"
        case .leadCreated:
            return "mappin.circle.fill"
        default:
            return "clock.fill"
        }
    }
}

private struct TeamLeadDetailNotice: View {
    let message: String
    let isError: Bool

    var body: some View {
        Label(message, systemImage: isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
            .font(.obsidianFootnote)
            .foregroundColor(isError ? Color.statusNotInterested : Color.statusInterested)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.obsidianSurface)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.obsidianBorder.opacity(0.35), lineWidth: 1)
            )
    }
}

struct TeamToolbarDoneButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.obsidianCaption)

                Text("Done")
                    .font(.obsidianFootnote)
                    .fontWeight(.semibold)
            }
            .foregroundColor(.white)
            .padding(.horizontal, 12)
            .frame(minHeight: 44)
            .background(
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [Color.electricViolet, Color.electricVioletDeep],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay(
                Capsule()
                    .stroke(Color.obsidianBorder.opacity(0.45), lineWidth: 0.5)
            )
            .shadow(color: Color.electricViolet.opacity(0.22), radius: 4, x: 0, y: 2)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Done")
    }
}
