import SwiftUI
import UIKit
import AuthenticationServices
import CoreLocation

struct TeamWorkspaceView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var userAccountManager = FirebaseUserAccountManager.shared
    @ObservedObject private var firebaseService = FirebaseService.shared
    @ObservedObject private var appleSignInManager = AppleSignInManager.shared
    @ObservedObject private var teamService = TeamFirebaseService.shared
    @ObservedObject private var locationManager = LocationManager.shared
    @ObservedObject private var appointmentManager = AppointmentManager.shared
    @State private var teamName = "My Team"
    @State private var inviteCode = ""
    #if DEBUG
    @State private var teamAccountEmail = ""
    @State private var teamAccountPassword = ""
    @State private var teamAccountDisplayName = ""
    @State private var isCreatingTeamAccount = false
    #endif
    @State private var createdInvite: TeamInvite?
    @State private var createdInviteWorkType: TeamMemberWorkType?
    @State private var isWorking = false
    @State private var isUploadingDutyLocation = false
    @State private var selectedRepUserId: String?
    @State private var selectedTeamLead: TeamLead?
    @State private var selectedRepWorkspace: TeamRepWorkspace?
    @State private var ownerLeadQueueFilter: OwnerLeadQueueFilter = .important
    @State private var ownerLeadQueueExpanded = false
    @State private var lastTeamLocationUploadAt: Date?
    @State private var lastTeamLocationUploadCoordinate: TeamCoordinate?
    @State private var memberPendingRemoval: TeamMember?
    @State private var showingRemoveMemberConfirmation = false
    @State private var showingLeaveTeamConfirmation = false
    @State private var showingCloseTeamConfirmation = false
    @State private var statusMessage: String?
    @State private var statusMessageIsError = false
    @State private var pendingInviteWorkType: TeamMemberWorkType = .salesRep
    @FocusState private var focusedInput: TeamInput?

    private enum TeamInput: Hashable {
        case accountEmail
        case accountPassword
        case accountDisplayName
        case teamName
        case inviteCode
    }

    private enum OwnerLeadQueueFilter: String, CaseIterable {
        case important = "Important"
        case open = "Open"
        case all = "All"
    }

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                Rectangle()
                    .fill(Color.obsidianBlack)
                    .frame(height: topChromeHeight(for: geometry))
                teamHeader

                ScrollView {
                    LazyVStack(spacing: 12) {
                        introCard

                        if let statusMessage = visibleStatusMessage {
                            statusCard(
                                statusMessage,
                                color: statusMessageIsError ? Color.statusNotInterested : Color.statusInterested
                            )
                        }

                        #if DEBUG
                        if FirebaseEmulatorConfiguration.isEnabled {
                            statusCard("Firebase emulator mode active: \(FirebaseEmulatorConfiguration.activeHostDescription)")
                        }
                        #endif

                        if let errorMessage = visibleTeamErrorMessage {
                            statusCard(errorMessage, color: Color.statusNotInterested)
                        }

                        if let syncMessage = visibleTeamSyncStatusMessage {
                            statusCard(syncMessage, color: teamSyncStatusColor)
                        }

                        if let passiveStatusMessage = passiveTeamStatusMessage {
                            statusCard(passiveStatusMessage, color: Color.statusNotHome)
                        }

                        if let errorMessage = visibleUserAuthErrorMessage {
                            statusCard(errorMessage, color: Color.statusNotInterested)
                        }

                        if let errorMessage = visibleAppleAuthErrorMessage {
                            statusCard(errorMessage, color: Color.statusNotInterested)
                        }

                        if shouldShowInitialLoadingCard {
                            loadingCard("Loading team workspace...")
                        }

                        if !canUseTeamWorkspace {
                            appleSignInRequiredCard
                        } else if let team = teamService.activeTeam, let member = teamService.currentMember {
                            planStateCard(team)
                            if member.role == .owner {
                                inviteManagementCard(team: team)
                                ownerNotificationsCard
                                ownerLeadQueueCard
                                ownerSummary(team: team)
                                ownerTechnicianJobsCard
                                ownerDuplicateWarningsCard
                                ownerFieldMapCard
                                ownerRepWorkCard
                                activityLogCard
                                memberListCard(team: team)
                                teamAccessCard(team: team, member: member)
                            } else {
                                repSummary(team: team, member: member)
                                activityLogCard
                                teamAccessCard(team: team, member: member)
                            }
                        } else {
                            setupTeamCard
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                }
                .scrollDismissesKeyboard(.immediately)
            }
        }
        .background(Color.obsidianBlack.ignoresSafeArea())
        .navigationBarHidden(true)
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    focusedInput = nil
                }
                .accessibilityIdentifier("teamKeyboardDoneButton")
            }
        }
        .ignoresSafeArea(.all, edges: .top)
        .task {
            await loadTeam()
        }
        .onChange(of: userAccountManager.isLoggedIn) { _, _ in
            Task { await loadTeam() }
        }
        .onChange(of: firebaseService.isAuthenticated) { _, _ in
            Task { await loadTeam() }
        }
        .onReceive(locationManager.$location.compactMap { $0 }) { location in
            publishDutyLocationIfNeeded(location)
        }
        .alert("Remove Team Member?", isPresented: $showingRemoveMemberConfirmation, presenting: memberPendingRemoval) { member in
            Button("Remove", role: .destructive) {
                removeMember(member)
            }
            Button("Cancel", role: .cancel) {}
        } message: { member in
            Text("\(member.displayName) will lose team access and the seat will be freed.")
        }
        .alert("Leave Team?", isPresented: $showingLeaveTeamConfirmation) {
            Button("Leave Team", role: .destructive) {
                leaveTeam()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You will lose access to assigned leads, jobs, Team map, and live sharing. Your seat will be freed for another worker.")
        }
        .alert("Close Team Workspace?", isPresented: $showingCloseTeamConfirmation) {
            Button("Close Team", role: .destructive) {
                closeTeam()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This pauses the Team Workspace, removes worker access, cancels pending invites, and returns this account to the create or join screen.")
        }
        .sheet(item: $selectedTeamLead) { lead in
            TeamLeadDetailSheet(initialLead: lead)
        }
        .sheet(item: $selectedRepWorkspace) { workspace in
            TeamRepDetailSheet(initialWorkspace: workspace)
        }
    }

    private var introCard: some View {
        TeamInfoCard {
            Label("Team Workspace", systemImage: "person.3.fill")
                .font(.obsidianCallout)
                .foregroundColor(Color.textPrimary)

            Text("Personal leads stay private. Sales reps receive assigned leads and jobs. Technicians receive assigned service jobs, navigation, status updates, and their own active-hours GPS graph.")
                .font(.obsidianFootnote)
                .foregroundColor(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func topChromeHeight(for geometry: GeometryProxy) -> CGFloat {
        max(geometry.safeAreaInsets.top, 54)
    }

    private func planStateCard(_ team: TeamWorkspace) -> some View {
        TeamInfoCard {
            Text(team.name)
                .font(.obsidianCallout)
                .foregroundColor(Color.textPrimary)

            Label(planStateText(team.planStatus), systemImage: planStateIcon(team.planStatus))
                .font(.obsidianFootnote)
                .foregroundColor(planStateColor(team.planStatus))
        }
    }

    private func ownerSummary(team: TeamWorkspace) -> some View {
        TeamInfoCard {
            Text("Owner Controls")
                .font(.obsidianCallout)
                .foregroundColor(Color.textPrimary)

            if let todaySummary = teamService.todayWorkSummary() {
                statRow("Today jobs", "\(todaySummary.bookingCount)")
                statRow("Important work", "\(todaySummary.importantLeadCount)")
            }
            statRow("Team leads", "\(teamService.teamLeads.count)")
            statRow("Jobs", "\(teamService.teamBookings.count)")
            statRow("Sales reps", "\(activeSalesReps.count)")
            statRow("Technicians", "\(activeTechnicians.count)")
            statRow("On duty", "\(ownerRepWorkspaces.filter(\.isOnDuty).count)")
            statRow("Seats used", "\(activeMemberCount)/\(team.memberLimit)")
            if let member = teamService.currentMember {
                statRow("Owner sharing", teamService.activeDutySession == nil ? "Off" : "On")

                dutySharingButton(
                    member: member,
                    team: team,
                    onTitle: "Share My Location",
                    offTitle: "Stop Sharing Location",
                    accessibilityIdentifier: "teamOwnerLocationToggleButton"
                )

                Text("Team workers can see your live dot only while this is on. Your owner route history is kept for active hours and expires after 30 days.")
                    .font(.obsidianFootnote)
                    .foregroundColor(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text("Generate one invite code per worker. Each code reserves one seat until the worker joins or you cancel the pending invite.")
                .font(.obsidianFootnote)
                .foregroundColor(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var ownerLeadQueueCard: some View {
        TeamInfoCard {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Lead Queue")
                        .font(.obsidianCallout)
                        .foregroundColor(Color.textPrimary)

                    Text(ownerLeadQueueSubtitle)
                        .font(.obsidianFootnote)
                        .foregroundColor(Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                Button {
                    Task { await teamService.refreshTeamData() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.obsidianFootnote)
                        .foregroundColor(Color.electricViolet)
                        .frame(width: 34, height: 34)
                }
                .buttonStyle(PlainButtonStyle())
                .accessibilityLabel("Refresh team leads")
            }

            ownerLeadQueueFilterStrip

            if let selectedRepUserId,
               let repName = teamService.teamMembers.first(where: { $0.userId == selectedRepUserId })?.displayName {
                HStack(spacing: 8) {
                    Text("Showing \(repName)")
                        .font(.micro)
                        .foregroundColor(Color.textSecondary)
                    Button("Clear") {
                        self.selectedRepUserId = nil
                    }
                    .font(.micro)
                    .foregroundColor(Color.electricViolet)
                    .buttonStyle(PlainButtonStyle())
                    Spacer()
                }
            }

            if ownerLeadQueueRows.isEmpty {
                Text("No team leads match this view.")
                    .font(.obsidianFootnote)
                    .foregroundColor(Color.textMuted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 6)
            } else {
                VStack(spacing: 0) {
                    ForEach(ownerLeadQueueRows) { lead in
                        ownerLeadQueueRow(lead)

                        if lead.id != ownerLeadQueueRows.last?.id {
                            Divider()
                                .overlay(Color.obsidianBorder.opacity(0.5))
                        }
                    }
                }
            }

            if ownerFilteredLeads.count > ownerLeadQueueRows.count {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        ownerLeadQueueExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(ownerLeadQueueExpanded ? "Show less" : "Show \(ownerFilteredLeads.count - ownerLeadQueueRows.count) more")
                        Image(systemName: ownerLeadQueueExpanded ? "chevron.up" : "chevron.down")
                    }
                    .font(.obsidianFootnote)
                    .foregroundColor(Color.electricViolet)
                }
                .buttonStyle(PlainButtonStyle())
                .accessibilityIdentifier("teamLeadQueueShowMoreButton")
            }
        }
        .accessibilityIdentifier("teamLeadQueueCard")
    }

    private var ownerLeadQueueFilterStrip: some View {
        HStack(spacing: 8) {
            ForEach(OwnerLeadQueueFilter.allCases, id: \.self) { filter in
                Button {
                    ownerLeadQueueFilter = filter
                    ownerLeadQueueExpanded = false
                } label: {
                    Text(filter.rawValue)
                        .font(.micro)
                        .foregroundColor(ownerLeadQueueFilter == filter ? .white : Color.textSecondary)
                        .lineLimit(1)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            Capsule()
                                .fill(ownerLeadQueueFilter == filter ? Color.electricViolet : Color.obsidianElevated)
                                .overlay(
                                    Capsule()
                                        .stroke(Color.obsidianBorder.opacity(0.4), lineWidth: 0.5)
                                )
                        )
                }
                .buttonStyle(PlainButtonStyle())
                .accessibilityLabel("Show \(filter.rawValue.lowercased()) team leads")
            }

            Spacer(minLength: 0)
        }
    }

    private func ownerLeadQueueRow(_ lead: TeamLead) -> some View {
        let isActionableHighPriority = TeamLeadAttentionPolicy.isActionableHighPriority(lead)

        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: isActionableHighPriority ? "star.fill" : leadStatusIcon(lead.status))
                    .font(.obsidianFootnote)
                    .foregroundColor(isActionableHighPriority ? Color.statusInterested : leadStatusColor(lead.status))
                    .frame(width: 22, height: 22)

                VStack(alignment: .leading, spacing: 3) {
                    Text(lead.name)
                        .font(.obsidianFootnote)
                        .foregroundColor(Color.textPrimary)
                        .lineLimit(1)

                    Text(lead.address)
                        .font(.micro)
                        .foregroundColor(Color.textMuted)
                        .lineLimit(2)

                    HStack(spacing: 6) {
                        ownerLeadQueuePill(ownerName(for: lead), color: Color.electricViolet)
                        ownerLeadQueuePill(leadStatusText(lead.status), color: leadStatusColor(lead.status))
                        if isActionableHighPriority {
                            ownerLeadQueuePill("High", color: Color.statusInterested)
                        }
                    }
                }

                Spacer()

                leadAssignmentMenu(lead)
            }
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .onTapGesture {
            selectedTeamLead = lead
        }
        .accessibilityIdentifier("teamOwnerLeadQueueRow")
    }

    private func ownerLeadQueuePill(_ title: String, color: Color) -> some View {
        Text(title)
            .font(.nano)
            .foregroundColor(color)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(color.opacity(0.12))
            )
    }

    private var ownerFieldMapCard: some View {
        TeamInfoCard {
            HStack {
                Text("Field Map")
                    .font(.obsidianCallout)
                    .foregroundColor(Color.textPrimary)

                Spacer()

                Button {
                    Task { await teamService.refreshTeamData() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.obsidianFootnote)
                        .foregroundColor(Color.electricViolet)
                        .frame(width: 34, height: 34)
                }
                .buttonStyle(PlainButtonStyle())
                .accessibilityLabel("Refresh team map")
                .accessibilityIdentifier("teamRefreshMapButton")
            }

            repFilterChips(workspaces: ownerRepWorkspaces)

            if ownerRepWorkspaces.isEmpty {
                Text("Active workers will appear here after they join the team.")
                    .font(.obsidianFootnote)
                    .foregroundColor(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                TeamFieldMapView(
                    workspaces: ownerRepWorkspaces,
                    selectedRepUserId: $selectedRepUserId,
                    onLeadTap: { lead in
                        selectedTeamLead = lead
                    }
                )
                .frame(height: 270)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.obsidianBorder.opacity(0.35), lineWidth: 0.5)
                )
                .accessibilityIdentifier("teamFieldMapView")

                HStack(spacing: 12) {
                    mapLegendItem("Live team", color: .blue, icon: "location.fill")
                    mapLegendItem("Lead", color: .orange, icon: "mappin.circle.fill")
                    mapLegendItem("Route", color: .blue, icon: "point.topleft.down.curvedto.point.bottomright.up")
                }
            }
        }
    }

    private var ownerRepWorkCard: some View {
        TeamInfoCard {
            Text("Team Work")
                .font(.obsidianCallout)
                .foregroundColor(Color.textPrimary)

            if ownerRepWorkspaces.isEmpty {
                Text("Accepted workers will appear here with assigned leads, jobs, live status, and active-hours route history.")
                    .font(.obsidianFootnote)
                    .foregroundColor(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(filteredOwnerRepWorkspaces) { workspace in
                    repWorkspaceRow(workspace)
                }
            }
        }
    }

    private var ownerTechnicianJobsCard: some View {
        TeamInfoCard {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Technician Jobs")
                        .font(.obsidianCallout)
                        .foregroundColor(Color.textPrimary)

                    Text("Send scheduled appointments to technicians or reassign existing Team jobs.")
                        .font(.obsidianFootnote)
                        .foregroundColor(Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                Button {
                    Task { await teamService.refreshTeamData() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.obsidianFootnote)
                        .foregroundColor(Color.electricViolet)
                        .frame(width: 34, height: 34)
                }
                .buttonStyle(PlainButtonStyle())
                .accessibilityLabel("Refresh technician jobs")
            }

            if activeTechnicians.isEmpty {
                Text("Create a Technician invite before sending service jobs.")
                    .font(.obsidianFootnote)
                    .foregroundColor(Color.textMuted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
            }

            if ownerDispatchAppointments.isEmpty {
                Text("No upcoming local appointments are ready to send.")
                    .font(.obsidianFootnote)
                    .foregroundColor(Color.textMuted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
            } else {
                VStack(spacing: 0) {
                    ForEach(ownerDispatchAppointments.prefix(6)) { appointment in
                        appointmentDispatchRow(appointment)

                        if appointment.id != ownerDispatchAppointments.prefix(6).last?.id {
                            Divider()
                                .overlay(Color.obsidianBorder.opacity(0.5))
                        }
                    }
                }
            }

            if !ownerTeamJobs.isEmpty {
                Divider()
                    .overlay(Color.obsidianBorder.opacity(0.5))

                Text("Team Jobs")
                    .font(.micro)
                    .foregroundColor(Color.textMuted)
                    .textCase(.uppercase)

                ForEach(ownerTeamJobs.prefix(5)) { booking in
                    teamBookingRow(booking, allowAssignment: true)
                }
            }
        }
        .accessibilityIdentifier("teamTechnicianJobsCard")
    }

    private func inviteManagementCard(team: TeamWorkspace) -> some View {
        TeamInfoCard {
            Text("Invite Worker")
                .font(.obsidianCallout)
                .foregroundColor(Color.textPrimary)

            Text(activeMemberCount >= team.memberLimit ? "The included team seats are full." : "Create an invite code for a sales rep or technician. The code expires after 7 days and can be used once.")
                .font(.obsidianFootnote)
                .foregroundColor(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Picker("Worker type", selection: $pendingInviteWorkType) {
                Text("Sales Rep").tag(TeamMemberWorkType.salesRep)
                Text("Technician").tag(TeamMemberWorkType.technician)
            }
            .pickerStyle(.segmented)
            .disabled(activeMemberCount >= team.memberLimit || !team.planStatus.allowsTeamWrite || isWorking || teamService.isLoading)
            .accessibilityIdentifier("teamInviteWorkerTypePicker")

            if let createdInvite {
                createdInvitePanel(
                    invite: createdInvite,
                    workType: createdInviteWorkType ?? pendingInviteWorkType
                )
            }

            teamActionButton(
                title: createdInvite == nil ? "Create Invite Code" : "Create Another Code",
                icon: createdInvite == nil ? "number.square.fill" : "plus.square.fill",
                disabled: activeMemberCount >= team.memberLimit || !team.planStatus.allowsTeamWrite,
                accessibilityIdentifier: "teamCreateInviteButton"
            ) {
                createInvite()
            }
        }
    }

    private var ownerNotificationsCard: some View {
        TeamInfoCard {
            Text("Owner Alerts")
                .font(.obsidianCallout)
                .foregroundColor(Color.textPrimary)

            if teamService.ownerNotifications.isEmpty {
                Text("Rep-created leads will appear here when they become interested, booked, converted, or high priority.")
                    .font(.obsidianFootnote)
                    .foregroundColor(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(Array(teamService.ownerNotifications.prefix(5))) { notification in
                    HStack(alignment: .top, spacing: 10) {
                        VStack(alignment: .leading, spacing: 4) {
                            Label(notification.title, systemImage: ownerNotificationIcon(notification.event))
                                .font(.obsidianFootnote)
                                .foregroundColor(notification.readAt == nil ? Color.textPrimary : Color.textSecondary)
                            Text(notification.message)
                                .font(.micro)
                                .foregroundColor(Color.textMuted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer()
                        if notification.readAt == nil {
                            Button {
                                markNotificationRead(notification)
                            } label: {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.obsidianCallout)
                                    .foregroundColor(Color.statusInterested)
                            }
                            .buttonStyle(PlainButtonStyle())
                            .accessibilityLabel("Mark owner alert read")
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private var ownerDuplicateWarningsCard: some View {
        let warnings = teamService.duplicateLeadWarnings()

        return Group {
            if !warnings.isEmpty {
                TeamInfoCard {
                    Text("Duplicate Warnings")
                        .font(.obsidianCallout)
                        .foregroundColor(Color.textPrimary)

                    ForEach(Array(warnings.prefix(4))) { warning in
                        VStack(alignment: .leading, spacing: 4) {
                            Label(warning.summary, systemImage: "exclamationmark.triangle.fill")
                                .font(.obsidianFootnote)
                                .foregroundColor(Color.textPrimary)

                            Text(duplicateReasonText(warning.candidate))
                                .font(.micro)
                                .foregroundColor(Color.textMuted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .accessibilityIdentifier("teamDuplicateWarningsCard")
            }
        }
    }

    private var activityLogCard: some View {
        TeamInfoCard {
            Text("Activity Log")
                .font(.obsidianCallout)
                .foregroundColor(Color.textPrimary)

            if teamService.activityLog.isEmpty {
                Text("Team actions will appear here after reps create leads, reply, go on duty, or owner assignments change.")
                    .font(.obsidianFootnote)
                    .foregroundColor(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(Array(teamService.activityLog.prefix(6))) { entry in
                    HStack(alignment: .top, spacing: 9) {
                        Image(systemName: activityIcon(entry.kind))
                            .font(.micro)
                            .foregroundColor(Color.electricViolet)
                            .frame(width: 18)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(entry.summary)
                                .font(.micro)
                                .foregroundColor(Color.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(entry.createdAt.formatted(date: .abbreviated, time: .shortened))
                                .font(.nano)
                                .foregroundColor(Color.textMuted)
                        }
                    }
                }
            }
        }
    }

    private func memberListCard(team: TeamWorkspace) -> some View {
        TeamInfoCard {
            Text("Members")
                .font(.obsidianCallout)
                .foregroundColor(Color.textPrimary)

            if displayedTeamMembers.isEmpty {
                Text("Members will appear here after the team loads.")
                    .font(.obsidianFootnote)
                    .foregroundColor(Color.textSecondary)
            } else {
                ForEach(displayedActiveMembers) { member in
                    memberRow(member)
                }

                if !displayedPendingInvites.isEmpty {
                    Divider()
                        .overlay(Color.obsidianBorder.opacity(0.6))

                    Text("Pending Invites")
                        .font(.micro)
                        .foregroundColor(Color.textMuted)
                        .textCase(.uppercase)

                    ForEach(displayedPendingInvites) { member in
                        memberRow(member)
                    }
                }
            }
        }
    }

    private func teamAccessCard(team: TeamWorkspace, member: TeamMember) -> some View {
        TeamInfoCard {
            Text("Team Access")
                .font(.obsidianCallout)
                .foregroundColor(Color.textPrimary)

            if member.role == .owner {
                Text("Close this Team Workspace when you no longer want workers to access shared leads, jobs, map, or active-hours location history.")
                    .font(.obsidianFootnote)
                    .foregroundColor(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                teamActionButton(
                    title: "Close Team Workspace",
                    icon: "person.3.sequence.fill",
                    color: Color.statusNotInterested,
                    disabled: !TeamAccessPolicy.canCloseTeam(owner: member, team: team),
                    accessibilityIdentifier: "teamCloseWorkspaceButton"
                ) {
                    showingCloseTeamConfirmation = true
                }
            } else {
                Text("Leave the team if you no longer work in this workspace. Assigned team leads, service jobs, and live sharing access will be removed from this account.")
                    .font(.obsidianFootnote)
                    .foregroundColor(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                teamActionButton(
                    title: "Leave Team",
                    icon: "rectangle.portrait.and.arrow.right",
                    color: Color.statusNotInterested,
                    disabled: !TeamAccessPolicy.canLeaveTeam(member: member, team: team),
                    accessibilityIdentifier: "teamLeaveButton"
                ) {
                    showingLeaveTeamConfirmation = true
                }
            }
        }
        .accessibilityIdentifier("teamAccessCard")
    }

    private func memberRow(_ member: TeamMember) -> some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(memberWorkTypeColor(member))
                .frame(width: 34, height: 34)
                .overlay(
                    Image(systemName: memberWorkTypeIcon(member))
                        .font(.obsidianFootnote)
                        .foregroundColor(.white)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(member.displayName)
                    .font(.obsidianFootnote)
                    .foregroundColor(Color.textPrimary)

                Text(memberSubtitle(member))
                    .font(.micro)
                    .foregroundColor(Color.textMuted)
            }

            Spacer()

            if canUpdateMemberWorkType(member) {
                memberWorkTypeMenu(member)
            }

            if TeamAccessPolicy.canCancelPendingInvite(role: .owner, member: member) {
                Button {
                    cancelPendingInvite(member)
                } label: {
                    Label("Cancel", systemImage: "xmark.circle.fill")
                        .labelStyle(.iconOnly)
                        .font(.obsidianCallout)
                        .foregroundColor(Color.statusNotInterested)
                }
                .buttonStyle(PlainButtonStyle())
                .accessibilityLabel("Cancel pending invite")
                .disabled(isWorking || teamService.isLoading)
            } else if let team = teamService.activeTeam,
                      let currentMember = teamService.currentMember,
                      TeamAccessPolicy.canRemoveMember(actor: currentMember, team: team, member: member) {
                Button {
                    confirmRemoveMember(member)
                } label: {
                    Image(systemName: "person.crop.circle.badge.minus")
                        .font(.obsidianCallout)
                        .foregroundColor(Color.statusNotInterested)
                }
                .buttonStyle(PlainButtonStyle())
                .accessibilityLabel("Remove \(member.displayName)")
                .disabled(isWorking || teamService.isLoading)
            } else {
                Text(memberStatusText(member))
                    .font(.micro)
                    .foregroundColor(memberStatusColor(member))
            }
        }
    }

    private func repSummary(team: TeamWorkspace, member: TeamMember) -> some View {
        let visibleWorkspaces = visibleMemberWorkspaces(member: member)
        let workspace = visibleWorkspaces.first { $0.member.userId == member.userId }
            ?? TeamRepWorkspace.makeMemberWorkspace(
                member: member,
                leads: teamService.teamLeads,
                bookings: teamService.teamBookings,
                dutySessions: teamService.dutySessions,
                dutyLocationPoints: teamService.dutyLocationPoints
            )

        return TeamInfoCard {
            Text(member.isTechnician ? "My Service Jobs" : "My Team Work")
                .font(.obsidianCallout)
                .foregroundColor(Color.textPrimary)

            if let todaySummary = teamService.todayWorkSummary() {
                statRow(member.isTechnician ? "Today jobs" : "Today bookings", "\(todaySummary.bookingCount)")
                if !member.isTechnician {
                    statRow("Important work", "\(todaySummary.importantLeadCount)")
                }
            }
            if member.isTechnician {
                statRow("Assigned jobs", "\(workspace.assignedBookings.count)")
            } else {
                statRow("Assigned leads", "\(workspace.assignedLeads.count)")
                statRow("Assigned jobs", "\(workspace.assignedBookings.count)")
            }

            dutySharingButton(
                member: member,
                team: team,
                onTitle: "Go On Duty",
                offTitle: "Go Off Duty",
                accessibilityIdentifier: "teamDutyToggleButton"
            )

            Text("Your active-hours route is visible to the owner while you are on duty. Your live dot disappears when you go off duty.")
                .font(.obsidianFootnote)
                .foregroundColor(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            if visibleWorkspaces.contains(where: { $0.member.role == .owner && $0.liveLocation != nil }) {
                Text("Owner location is visible while the owner is sharing.")
                    .font(.obsidianFootnote)
                    .foregroundColor(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            TeamFieldMapView(
                workspaces: visibleWorkspaces,
                selectedRepUserId: constantRepSelection(nil),
                onLeadTap: { lead in
                    selectedTeamLead = lead
                }
            )
            .frame(height: 220)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.obsidianBorder.opacity(0.35), lineWidth: 0.5)
            )
            .accessibilityIdentifier("teamRepMapView")

            if member.isTechnician {
                if workspace.assignedBookings.isEmpty {
                    Text("No service jobs assigned yet.")
                        .font(.obsidianFootnote)
                        .foregroundColor(Color.textMuted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 6)
                } else {
                    ForEach(workspace.assignedBookings.prefix(6)) { booking in
                        VStack(alignment: .leading, spacing: 8) {
                            teamBookingRow(booking)
                            technicianJobStatusButtons(booking)
                        }
                    }
                }
            } else {
                ForEach(workspace.assignedLeads.prefix(4)) { lead in
                    VStack(alignment: .leading, spacing: 8) {
                        teamLeadRow(lead)
                        repQuickReplyRow(lead: lead, team: team)
                    }
                }
            }
        }
    }

    private var appleSignInRequiredCard: some View {
        TeamInfoCard {
            Text(TeamAuthPolicy.signInRequiredTitle)
                .font(.obsidianCallout)
                .foregroundColor(Color.textPrimary)

            Text("Use Sign in with Apple to create your team identity. Your personal iCloud leads stay private unless you assign or create work inside Team.")
                .font(.obsidianFootnote)
                .foregroundColor(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            appleTeamSignInButton

            #if DEBUG
            if FirebaseEmulatorConfiguration.isEnabled {
                emulatorAccountForm
            }
            #endif
        }
    }

    private var appleTeamSignInButton: some View {
        SignInWithAppleButton(
            .continue,
            onRequest: { request in
                appleSignInManager.configureRequest(request)
            },
            onCompletion: { result in
                appleSignInManager.handleAuthorizationCompletion(result, requireFirebaseTeamSession: true)
            }
        )
        .signInWithAppleButtonStyle(.white)
        .frame(height: 54)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityIdentifier("teamAppleSignInButton")
        .overlay(
            Group {
                if case .loading = appleSignInManager.authStatus {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.black.opacity(0.25))
                        .overlay(ProgressView().tint(.white))
                }
            }
        )
    }

    #if DEBUG
    private var emulatorAccountForm: some View {
        VStack(alignment: .leading, spacing: 12) {
            Divider()
                .overlay(Color.obsidianBorder)

            Text("Emulator Test Account")
                .font(.obsidianCallout)
                .foregroundColor(Color.textPrimary)

            Text("Automated UI tests use disposable local auth accounts because Apple Sign In cannot run against the Firebase emulator.")
                .font(.obsidianFootnote)
                .foregroundColor(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 8) {
                Text("Email")
                    .font(.micro)
                    .foregroundColor(Color.textMuted)
                TextField("rep@example.com", text: $teamAccountEmail)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focusedInput, equals: .accountEmail)
                    .teamTextField()
                    .accessibilityIdentifier("teamAccountEmailField")

                Text("Password")
                    .font(.micro)
                    .foregroundColor(Color.textMuted)
                TextField("Password", text: $teamAccountPassword)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focusedInput, equals: .accountPassword)
                    .teamTextField()
                    .accessibilityIdentifier("teamAccountPasswordField")

                if isCreatingTeamAccount {
                    Text("Name")
                        .font(.micro)
                        .foregroundColor(Color.textMuted)
                    TextField("Rep name", text: $teamAccountDisplayName)
                        .focused($focusedInput, equals: .accountDisplayName)
                        .teamTextField()
                        .accessibilityIdentifier("teamAccountDisplayNameField")
                }
            }

            teamActionButton(
                title: isCreatingTeamAccount ? "Create Test Account" : "Sign In Test Account",
                icon: isCreatingTeamAccount ? "person.badge.plus" : "person.crop.circle.badge.checkmark",
                accessibilityIdentifier: isCreatingTeamAccount ? "teamCreateAccountButton" : "teamSignInButton"
            ) {
                submitTeamAccount()
            }

            Button {
                isCreatingTeamAccount.toggle()
            } label: {
                Text(isCreatingTeamAccount ? "I already have a test account" : "Create a new test account")
                    .font(.obsidianFootnote)
                    .foregroundColor(Color.electricViolet)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .buttonStyle(PlainButtonStyle())
        }
    }
    #endif

    private var setupTeamCard: some View {
        TeamInfoCard {
            VStack(alignment: .leading, spacing: 5) {
                Label("Create or Accept Team", systemImage: "person.3.fill")
                    .font(.obsidianCallout)
                    .foregroundColor(Color.textPrimary)

                Text("Start as the owner, or join an existing crew with a single-use invite code.")
                    .font(.obsidianFootnote)
                    .foregroundColor(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            setupOptionPanel(
                title: "Create owner workspace",
                icon: "crown.fill",
                subtitle: "Use this account to manage reps, technicians, leads, jobs, and team location sharing."
            ) {
                setupField(title: "Team name", icon: "person.3.fill") {
                    TextField("My Team", text: $teamName)
                        .focused($focusedInput, equals: .teamName)
                        .teamTextField()
                        .accessibilityIdentifier("teamNameField")
                }

                setupActionButton(
                    title: "Create Team",
                    icon: "plus.circle.fill",
                    accessibilityIdentifier: "teamCreateTeamButton"
                ) {
                    createTeam()
                }
            }

            setupDivider("Or join with code")

            setupOptionPanel(
                title: "Join as worker",
                icon: "person.badge.plus",
                subtitle: "Sales reps and technicians join here after the owner sends an invite code."
            ) {
                setupField(title: "Invite code", icon: "number.square.fill") {
                    TextField("Invite code", text: $inviteCode)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .focused($focusedInput, equals: .inviteCode)
                        .teamTextField()
                        .accessibilityIdentifier("teamInviteCodeField")
                }

                setupActionButton(
                    title: "Join Team",
                    icon: "person.badge.plus",
                    accessibilityIdentifier: "teamJoinTeamButton"
                ) {
                    joinTeam()
                }
            }
        }
    }

    private func setupOptionPanel<Content: View>(
        title: String,
        icon: String,
        subtitle: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: icon)
                    .font(.obsidianFootnote)
                    .foregroundColor(Color.electricViolet)
                    .frame(width: 30, height: 30)
                    .background(
                        Circle()
                            .fill(Color.electricViolet.opacity(0.12))
                    )

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.obsidianFootnote)
                        .fontWeight(.semibold)
                        .foregroundColor(Color.textPrimary)

                    Text(subtitle)
                        .font(.micro)
                        .foregroundColor(Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            content()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.obsidianElevated.opacity(0.62))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.obsidianBorder.opacity(0.45), lineWidth: 0.5)
                )
        )
    }

    private func setupField<Content: View>(
        title: String,
        icon: String,
        @ViewBuilder field: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: icon)
                .font(.micro)
                .foregroundColor(Color.textMuted)

            field()
        }
    }

    private func setupDivider(_ title: String) -> some View {
        HStack(spacing: 10) {
            Rectangle()
                .fill(Color.obsidianBorder.opacity(0.75))
                .frame(height: 0.5)

            Text(title)
                .font(.micro)
                .foregroundColor(Color.textMuted)
                .lineLimit(1)

            Rectangle()
                .fill(Color.obsidianBorder.opacity(0.75))
                .frame(height: 0.5)
        }
        .padding(.vertical, 2)
    }

    private func setupActionButton(
        title: String,
        icon: String,
        accessibilityIdentifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.obsidianFootnote)
                    .frame(width: 26, height: 26)
                    .background(Color.white.opacity(0.16))
                    .clipShape(Circle())

                Text(title)
                    .font(.obsidianFootnote)
                    .fontWeight(.semibold)
                    .lineLimit(1)

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.micro.weight(.bold))
                    .opacity(0.75)
            }
            .foregroundColor(.white)
            .padding(.horizontal, 12)
            .frame(height: 48)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color.electricViolet, Color.electricVioletDeep],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .shadow(color: Color.electricViolet.opacity(0.22), radius: 4, x: 0, y: 2)
            )
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityIdentifier(accessibilityIdentifier)
        .disabled(isWorking || teamService.isLoading)
        .opacity(isWorking || teamService.isLoading ? 0.55 : 1)
    }

    private func loadingCard(_ message: String) -> some View {
        TeamInfoCard {
            HStack(spacing: 12) {
                ProgressView()
                    .tint(Color.electricViolet)
                Text(message)
                    .font(.obsidianFootnote)
                    .foregroundColor(Color.textSecondary)
            }
        }
    }

    private func createdInvitePanel(invite: TeamInvite, workType: TeamMemberWorkType) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Label("Invite code ready", systemImage: "checkmark.seal.fill")
                    .font(.obsidianFootnote)
                    .foregroundColor(Color.textPrimary)

                Spacer(minLength: 8)

                Text(workType.title)
                    .font(.micro)
                    .foregroundColor(Color.statusNotHome)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(
                        Capsule()
                            .fill(Color.statusNotHome.opacity(0.14))
                    )
            }

            Text(invite.displayCode)
                .font(.system(.largeTitle, design: .monospaced).weight(.heavy))
                .foregroundColor(Color.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
                .textSelection(.enabled)
                .accessibilityIdentifier("teamCreatedInviteCode")

            HStack(spacing: 10) {
                Button {
                    copyInviteCode(invite)
                } label: {
                    inviteCodeUtilityLabel(title: "Copy Code", icon: "doc.on.doc.fill")
                }
                .buttonStyle(PlainButtonStyle())
                .accessibilityIdentifier("teamCopyInviteCodeButton")

                ShareLink(item: inviteShareText(for: invite, workType: workType)) {
                    inviteCodeUtilityLabel(title: "Share", icon: "square.and.arrow.up.fill")
                }
                .buttonStyle(PlainButtonStyle())
                .accessibilityIdentifier("teamShareInviteCodeButton")
            }

            Text("Expires \(invite.expiresAt.formatted(date: .abbreviated, time: .shortened))")
                .font(.micro)
                .foregroundColor(Color.textMuted)

            Text("Reserved in Members as Pending \(workType.title) Invite until the worker joins or you cancel it.")
                .font(.micro)
                .foregroundColor(Color.textMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.statusNotHome.opacity(0.10))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.statusNotHome.opacity(0.45), lineWidth: 1)
                )
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("teamCreatedInvitePanel")
    }

    private func inviteCodeUtilityLabel(title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(.obsidianFootnote)
            .foregroundColor(Color.textPrimary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.obsidianElevated)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.obsidianBorder.opacity(0.45), lineWidth: 0.5)
                    )
            )
    }

    private var teamHeader: some View {
        HStack(spacing: 12) {
            Button(action: { dismiss() }) {
                Image(systemName: "chevron.left.circle.fill")
                    .font(.title2)
                    .foregroundColor(.textPrimary)
                    .frame(width: 34, height: 34)
            }
            .buttonStyle(PlainButtonStyle())
            .accessibilityLabel("Back to More")
            .accessibilityIdentifier("teamBackToMoreButton")

            Text("Team")
                .font(.displayMedium)
                .foregroundColor(.textPrimary)

            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 14)
        .background(Color.obsidianBlack)
    }

    private func statusCard(_ text: String, color: Color = Color.statusInterested) -> some View {
        TeamInfoCard {
            HStack(spacing: 10) {
                Image(systemName: color == Color.statusNotInterested ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                    .foregroundColor(color)
                Text(text)
                    .font(.obsidianFootnote)
                    .foregroundColor(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func teamActionButton(
        title: String,
        icon: String,
        color: Color = Color.electricViolet,
        disabled: Bool = false,
        accessibilityIdentifier: String? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.obsidianCallout)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(disabled ? Color.textMuted : color)
                        .shadow(color: color.opacity(disabled ? 0 : 0.3), radius: 4, x: 0, y: 2)
                )
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityIdentifier(accessibilityIdentifier ?? title)
        .disabled(disabled || isWorking || teamService.isLoading)
        .opacity(disabled ? 0.5 : 1)
    }

    private func dutySharingButton(
        member: TeamMember,
        team: TeamWorkspace,
        onTitle: String,
        offTitle: String,
        accessibilityIdentifier: String
    ) -> some View {
        let isOnDuty = teamService.activeDutySession != nil
        let canStartDuty = TeamAccessPolicy.canStartDutySession(planStatus: team.planStatus, role: member.role)
            && member.status == .active
        return teamActionButton(
            title: isOnDuty ? offTitle : onTitle,
            icon: isOnDuty ? "location.slash.fill" : "location.fill",
            color: isOnDuty ? Color.statusNotInterested : Color.electricViolet,
            disabled: !isOnDuty && !canStartDuty,
            accessibilityIdentifier: accessibilityIdentifier
        ) {
            toggleDutySharing(for: member)
        }
    }

    private var activeMemberCount: Int {
        TeamMemberRoster.activeSeatCount(teamService.teamMembers)
    }

    private var displayedTeamMembers: [TeamMember] {
        TeamMemberRoster.normalized(teamService.teamMembers)
    }

    private var displayedActiveMembers: [TeamMember] {
        displayedTeamMembers.filter { !$0.isPendingInvite }
    }

    private var displayedPendingInvites: [TeamMember] {
        displayedTeamMembers.filter(\.isPendingInvite)
    }

    private var activeAssignableReps: [TeamMember] {
        activeSalesReps
    }

    private var activeSalesReps: [TeamMember] {
        displayedTeamMembers
            .filter { $0.isSalesRep && $0.status == .active && !$0.isPendingInvite }
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    private var activeTechnicians: [TeamMember] {
        displayedTeamMembers
            .filter { $0.isTechnician && $0.status == .active && !$0.isPendingInvite }
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    private var activeAssignableJobWorkers: [TeamMember] {
        (activeTechnicians + activeSalesReps)
            .reduce(into: [TeamMember]()) { result, member in
                if !result.contains(where: { $0.userId == member.userId }) {
                    result.append(member)
                }
            }
    }

    private var ownerDispatchAppointments: [Appointment] {
        appointmentManager.appointments
            .filter { appointment in
                appointment.status != .cancelled
                    && appointment.status != .completed
                    && appointment.endDate >= Date().addingTimeInterval(-60 * 60)
            }
            .sorted { $0.startDate < $1.startDate }
    }

    private var ownerTeamJobs: [TeamBooking] {
        teamService.teamBookings
            .sorted {
                if $0.isFutureEditable != $1.isFutureEditable {
                    return $0.isFutureEditable && !$1.isFutureEditable
                }
                return $0.startDate < $1.startDate
            }
    }

    private var teamSyncStatusMessage: String? {
        switch teamService.syncWriteState {
        case .idle:
            return nil
        case .pending:
            return teamService.syncWriteState.displayText
        case .failed:
            return teamService.syncWriteState.displayText
        }
    }

    private var visibleStatusMessage: String? {
        guard let statusMessage else { return nil }
        if statusMessage == teamSyncStatusMessage {
            return nil
        }
        if statusMessage == teamService.lastErrorMessage {
            return nil
        }
        if isShowingTeamSetup && statusMessageIsError && isStaleSetupErrorMessage(statusMessage) {
            return nil
        }
        return statusMessage
    }

    private var visibleTeamErrorMessage: String? {
        guard let errorMessage = teamService.lastErrorMessage else { return nil }
        if errorMessage == teamSyncStatusMessage { return nil }
        if isShowingTeamSetup && isStaleSetupErrorMessage(errorMessage) {
            return nil
        }
        if isShowingTeamSetup && errorMessage == TeamFirebaseService.teamOfflineMessage {
            return hasVisibleSetupActionError ? nil : TeamFirebaseService.teamSetupOfflineMessage
        }
        return errorMessage
    }

    private var visibleTeamSyncStatusMessage: String? {
        guard let message = teamSyncStatusMessage else { return nil }
        if isShowingTeamSetup && isStaleSetupErrorMessage(message) {
            return nil
        }
        if isShowingTeamSetup && hasVisibleSetupActionError {
            return nil
        }
        if isShowingTeamSetup && message == TeamFirebaseService.teamOfflineMessage {
            return TeamFirebaseService.teamSetupOfflineMessage
        }
        return message
    }

    private var visibleUserAuthErrorMessage: String? {
        guard case let .failed(message) = userAccountManager.authStatus else { return nil }
        if isShowingTeamSetup && isStaleSetupErrorMessage(message) {
            return nil
        }
        return message
    }

    private var visibleAppleAuthErrorMessage: String? {
        guard case let .failed(message) = appleSignInManager.authStatus else { return nil }
        if isShowingTeamSetup && isStaleSetupErrorMessage(message) {
            return nil
        }
        return message
    }

    private var isShowingTeamSetup: Bool {
        canUseTeamWorkspace
            && teamService.activeTeam == nil
            && teamService.currentMember == nil
    }

    private var canUseTeamWorkspace: Bool {
        TeamAuthPolicy.canUseTeamWorkspace(isFirebaseAuthenticated: firebaseService.isAuthenticated)
    }

    private var hasVisibleSetupActionError: Bool {
        guard isShowingTeamSetup,
              statusMessageIsError,
              let statusMessage,
              !isStaleSetupErrorMessage(statusMessage) else {
            return false
        }
        return true
    }

    private func isStaleSetupErrorMessage(_ message: String) -> Bool {
        TeamFirebaseService.isStaleNoTeamSetupMessage(message)
    }

    private var shouldShowInitialLoadingCard: Bool {
        teamService.isLoading && teamService.activeTeam == nil && teamService.currentMember == nil
    }

    private var passiveTeamStatusMessage: String? {
        if teamService.isLoading && !shouldShowInitialLoadingCard {
            return "Refreshing team..."
        }
        if isWorking && teamSyncStatusMessage == nil {
            return "Saving team edit..."
        }
        return nil
    }

    private var teamSyncStatusColor: Color {
        switch teamService.syncWriteState {
        case .idle:
            return Color.statusInterested
        case .pending:
            return Color.statusNotHome
        case .failed:
            return Color.statusNotInterested
        }
    }

    private var ownerRepWorkspaces: [TeamRepWorkspace] {
        TeamRepWorkspace.makeOwnerWorkspaces(
            members: teamService.teamMembers,
            leads: teamService.teamLeads,
            bookings: teamService.teamBookings,
            dutySessions: teamService.dutySessions,
            dutyLocationPoints: teamService.dutyLocationPoints
        )
    }

    private var ownerLeadQueueSubtitle: String {
        let repScope = selectedRepUserId.flatMap { selectedId in
            teamService.teamMembers.first(where: { $0.userId == selectedId })?.displayName
        }

        let scopeText = repScope.map { "\($0)'s leads" } ?? "All reps"
        switch ownerLeadQueueFilter {
        case .important:
            return "\(scopeText) that need owner attention."
        case .open:
            return "\(scopeText) still in the active sales pipeline."
        case .all:
            return "\(scopeText), newest updates first."
        }
    }

    private var ownerFilteredLeads: [TeamLead] {
        teamService.teamLeads
            .filter { lead in
                if let selectedRepUserId, lead.assignedToUserId != selectedRepUserId {
                    return false
                }
                switch ownerLeadQueueFilter {
                case .important:
                    return TeamLeadAttentionPolicy.needsOwnerAttention(lead)
                case .open:
                    return lead.status != .converted && lead.status != .notInterested
                case .all:
                    return true
                }
            }
            .sorted { ownerLeadSort(lhs: $0, rhs: $1) }
    }

    private var ownerLeadQueueRows: [TeamLead] {
        ownerLeadQueueExpanded ? ownerFilteredLeads : Array(ownerFilteredLeads.prefix(6))
    }

    private var filteredOwnerRepWorkspaces: [TeamRepWorkspace] {
        guard let selectedRepUserId else { return ownerRepWorkspaces }
        return ownerRepWorkspaces.filter { $0.member.userId == selectedRepUserId }
    }

    private func visibleMemberWorkspaces(member: TeamMember) -> [TeamRepWorkspace] {
        TeamRepWorkspace.makeVisibleMemberWorkspaces(
            currentMember: member,
            members: teamService.teamMembers,
            leads: teamService.teamLeads,
            bookings: teamService.teamBookings,
            dutySessions: teamService.dutySessions,
            dutyLocationPoints: teamService.dutyLocationPoints
        )
    }

    private func ownerLeadSort(lhs: TeamLead, rhs: TeamLead) -> Bool {
        let lhsHighPriority = TeamLeadAttentionPolicy.isActionableHighPriority(lhs)
        let rhsHighPriority = TeamLeadAttentionPolicy.isActionableHighPriority(rhs)
        if lhsHighPriority != rhsHighPriority {
            return lhsHighPriority
        }

        let lhsRank = TeamLeadImportance.rank(lhs.status)
        let rhsRank = TeamLeadImportance.rank(rhs.status)
        if lhsRank != rhsRank {
            return lhsRank > rhsRank
        }

        return lhs.updatedAt > rhs.updatedAt
    }

    private func ownerName(for lead: TeamLead) -> String {
        teamService.teamMembers.first(where: { $0.userId == lead.assignedToUserId })?.displayName ?? "Unassigned"
    }

    private func statRow(_ title: String, _ value: String) -> some View {
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

    private func repFilterChips(workspaces: [TeamRepWorkspace]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                repFilterButton(title: "All", userId: nil, isLive: workspaces.contains { $0.isOnDuty })
                ForEach(workspaces) { workspace in
                    repFilterButton(
                        title: workspace.member.displayName,
                        userId: workspace.member.userId,
                        isLive: workspace.isOnDuty
                    )
                }
            }
        }
    }

    private func repFilterButton(title: String, userId: String?, isLive: Bool) -> some View {
        let isSelected = selectedRepUserId == userId
        return Button {
            selectedRepUserId = userId
        } label: {
            HStack(spacing: 6) {
                if isLive {
                    Circle()
                        .fill(Color.statusInterested)
                        .frame(width: 7, height: 7)
                }
                Text(title)
                    .font(.micro)
                    .foregroundColor(isSelected ? .white : Color.textSecondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(isSelected ? Color.electricViolet : Color.obsidianElevated)
                    .overlay(
                        Capsule()
                            .stroke(Color.obsidianBorder.opacity(0.4), lineWidth: 0.5)
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityLabel("Show \(title) on team map")
    }

    private func appointmentDispatchRow(_ appointment: Appointment) -> some View {
        let sentBooking = teamBooking(for: appointment)
        return HStack(alignment: .top, spacing: 10) {
            Image(systemName: appointment.displayIcon)
                .font(.micro)
                .foregroundColor(appointment.displayColor)
                .frame(width: 28, height: 28)
                .background(appointment.displayColor.opacity(0.12))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(appointment.title.isEmpty ? appointment.displayName : appointment.title)
                    .font(.micro)
                    .foregroundColor(Color.textPrimary)
                    .lineLimit(1)

                Text("\(appointment.startDate.formatted(date: .abbreviated, time: .shortened)) - \(appointment.endDate.formatted(date: .omitted, time: .shortened))")
                    .font(.nano)
                    .foregroundColor(Color.textSecondary)
                    .lineLimit(1)

                Text(appointment.location.isEmpty ? "No location" : appointment.location)
                    .font(.nano)
                    .foregroundColor(Color.textMuted)
                    .lineLimit(1)

                if let sentBooking {
                    Text("Sent to \(memberName(forUserId: sentBooking.assignedToUserId)) • \(sentBooking.status.displayName)")
                        .font(.nano)
                        .foregroundColor(Color.statusInterested)
                        .lineLimit(1)
                } else {
                    Text("Not sent to Team yet")
                        .font(.nano)
                        .foregroundColor(Color.textMuted)
                }
            }

            Spacer(minLength: 8)

            appointmentSendMenu(appointment, existingBooking: sentBooking)
        }
        .padding(.vertical, 9)
        .accessibilityIdentifier("teamAppointmentDispatchRow")
    }

    private func appointmentSendMenu(_ appointment: Appointment, existingBooking: TeamBooking?) -> some View {
        Menu {
            if activeAssignableJobWorkers.isEmpty {
                Text("No technicians or reps available")
            } else {
                ForEach(activeAssignableJobWorkers) { worker in
                    Button("\(worker.displayName) • \(worker.displayRoleTitle)") {
                        sendAppointment(appointment, to: worker)
                    }
                    .disabled(existingBooking?.assignedToUserId == worker.userId)
                }
            }
        } label: {
            Image(systemName: existingBooking == nil ? "paperplane.fill" : "arrow.triangle.2.circlepath")
                .font(.micro)
                .foregroundColor(Color.electricViolet)
                .frame(width: 30, height: 30)
        }
        .disabled(activeAssignableJobWorkers.isEmpty || teamService.activeTeam?.planStatus.allowsTeamWrite != true)
        .accessibilityLabel(existingBooking == nil ? "Send appointment to worker" : "Reassign sent job")
    }

    private func repWorkspaceRow(_ workspace: TeamRepWorkspace) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                selectedRepUserId = workspace.member.userId
                selectedRepWorkspace = workspace
            } label: {
                HStack(spacing: 12) {
                    Circle()
                        .fill(workspace.isOnDuty ? Color.statusInterested : Color.textMuted)
                        .frame(width: 10, height: 10)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(workspace.member.displayName)
                            .font(.obsidianFootnote)
                            .foregroundColor(Color.textPrimary)
                        Text(repWorkspaceSubtitle(workspace))
                            .font(.micro)
                            .foregroundColor(Color.textMuted)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 2) {
                        Text(workspace.member.isTechnician ? "\(workspace.assignedBookings.count) jobs" : "\(workspace.assignedLeads.count) leads")
                            .font(.micro)
                            .foregroundColor(Color.textSecondary)
                        Text(workspace.member.displayRoleTitle)
                            .font(.micro)
                            .foregroundColor(Color.textMuted)
                    }

                    Image(systemName: "chevron.right")
                        .font(.nano)
                        .foregroundColor(Color.textMuted)
                }
            }
            .buttonStyle(PlainButtonStyle())
            .accessibilityLabel("Open \(workspace.member.displayName)")
            .accessibilityIdentifier("teamRepDetailButton")

            if workspace.member.isTechnician {
                if workspace.assignedBookings.isEmpty {
                    Text("No assigned service jobs yet.")
                        .font(.micro)
                        .foregroundColor(Color.textMuted)
                } else {
                    ForEach(workspace.assignedBookings.prefix(4)) { booking in
                        teamBookingRow(booking, allowAssignment: true)
                    }
                }
            } else if workspace.assignedLeads.isEmpty {
                Text("No assigned team leads yet.")
                    .font(.micro)
                    .foregroundColor(Color.textMuted)
            } else {
                ForEach(workspace.assignedLeads.prefix(3)) { lead in
                    teamLeadRow(lead, allowAssignment: true)
                }

                if !workspace.assignedBookings.isEmpty {
                    ForEach(workspace.assignedBookings.prefix(2)) { booking in
                        teamBookingRow(booking, allowAssignment: true)
                    }
                }
            }

            Divider()
                .overlay(Color.obsidianBorder.opacity(0.5))
        }
    }

    private func teamLeadRow(_ lead: TeamLead, allowAssignment: Bool = false) -> some View {
        let isActionableHighPriority = TeamLeadAttentionPolicy.isActionableHighPriority(lead)

        return HStack(spacing: 10) {
            Image(systemName: isActionableHighPriority ? "star.fill" : leadStatusIcon(lead.status))
                .font(.micro)
                .foregroundColor(leadStatusColor(lead.status))
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(lead.name)
                    .font(.micro)
                    .foregroundColor(Color.textPrimary)
                    .lineLimit(1)
                Text(lead.address)
                    .font(.nano)
                    .foregroundColor(Color.textMuted)
                    .lineLimit(1)
            }

            Spacer()

            Text(leadStatusText(lead.status))
                .font(.nano)
                .foregroundColor(leadStatusColor(lead.status))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(leadStatusColor(lead.status).opacity(0.12))
                )

            if allowAssignment {
                leadAssignmentMenu(lead)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            selectedTeamLead = lead
        }
        .accessibilityIdentifier("teamLeadDetailRow")
        .accessibilityLabel("\(lead.name), \(leadStatusText(lead.status))")
    }

    private func teamBookingRow(_ booking: TeamBooking, allowAssignment: Bool = false) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "calendar.badge.clock")
                .foregroundColor(Color.electricViolet)
            VStack(alignment: .leading, spacing: 2) {
                Text(booking.title)
                    .font(.micro)
                    .foregroundColor(Color.textPrimary)
                    .lineLimit(1)
                Text("\(booking.startDate.formatted(date: .abbreviated, time: .shortened)) • \(booking.status.displayName)")
                    .font(.nano)
                    .foregroundColor(Color.textSecondary)
                Text(booking.location.isEmpty ? "No location" : booking.location)
                    .font(.nano)
                    .foregroundColor(Color.textMuted)
                    .lineLimit(1)
                Text("Assigned to \(memberName(forUserId: booking.assignedToUserId))")
                    .font(.nano)
                    .foregroundColor(Color.textMuted)
            }
            Spacer()
            jobStatusMenu(booking)
            if allowAssignment {
                bookingAssignmentMenu(booking)
            }
        }
        .padding(.vertical, 6)
    }

    private func leadAssignmentMenu(_ lead: TeamLead) -> some View {
        Menu {
            ForEach(activeAssignableReps) { rep in
                Button(rep.displayName) {
                    assignLead(lead, to: rep)
                }
                .disabled(rep.userId == lead.assignedToUserId)
            }
        } label: {
            Image(systemName: "person.crop.circle.badge.checkmark")
                .font(.micro)
                .foregroundColor(Color.electricViolet)
                .frame(width: 26, height: 26)
        }
        .disabled(activeAssignableReps.isEmpty || teamService.activeTeam?.planStatus.allowsTeamWrite != true)
        .accessibilityLabel("Assign lead")
    }

    private func bookingAssignmentMenu(_ booking: TeamBooking) -> some View {
        Menu {
            ForEach(activeAssignableJobWorkers) { worker in
                Button("\(worker.displayName) • \(worker.displayRoleTitle)") {
                    assignBooking(booking, to: worker)
                }
                .disabled(worker.userId == booking.assignedToUserId)
            }
        } label: {
            Image(systemName: "person.crop.circle.badge.checkmark")
                .font(.micro)
                .foregroundColor(Color.electricViolet)
                .frame(width: 26, height: 26)
        }
        .disabled(activeAssignableJobWorkers.isEmpty || teamService.activeTeam?.planStatus.allowsTeamWrite != true)
        .accessibilityLabel("Assign job")
    }

    private func jobStatusMenu(_ booking: TeamBooking) -> some View {
        Menu {
            ForEach(TeamBookingStatus.allCases, id: \.rawValue) { status in
                Button(status.displayName) {
                    updateBookingStatus(booking, status: status)
                }
                .disabled(status == booking.status)
            }
        } label: {
            Image(systemName: "checklist")
                .font(.micro)
                .foregroundColor(Color.statusInterested)
                .frame(width: 26, height: 26)
        }
        .disabled(!canUpdateBooking(booking))
        .accessibilityLabel("Update job status")
    }

    private func repQuickReplyRow(lead: TeamLead, team: TeamWorkspace) -> some View {
        HStack(spacing: 8) {
            repReplyButton("Done", status: .done, lead: lead, team: team)
            repReplyButton("Not home", status: .customerNotHome, lead: lead, team: team)
            repReplyButton("Owner follow-up", status: .needsOwnerFollowUp, lead: lead, team: team)
        }
    }

    private func technicianJobStatusButtons(_ booking: TeamBooking) -> some View {
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
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(
                    Capsule()
                        .fill(Color.electricViolet.opacity(canUpdateBooking(booking) ? 0.12 : 0.05))
                )
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(!canUpdateBooking(booking) || booking.status == status || isWorking || teamService.isLoading)
    }

    private func repReplyButton(_ title: String, status: OwnerInstructionStatus, lead: TeamLead, team: TeamWorkspace) -> some View {
        Button {
            submitRepReply(status: status, lead: lead)
        } label: {
            Text(title)
                .font(.nano)
                .foregroundColor(team.planStatus.allowsTeamWrite ? Color.electricViolet : Color.textMuted)
                .lineLimit(1)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(
                    Capsule()
                        .fill(Color.electricViolet.opacity(team.planStatus.allowsTeamWrite ? 0.12 : 0.05))
                )
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(!team.planStatus.allowsTeamWrite || isWorking || teamService.isLoading)
    }

    private func mapLegendItem(_ title: String, color: Color, icon: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.nano)
                .foregroundColor(color)
            Text(title)
                .font(.nano)
                .foregroundColor(Color.textMuted)
                .lineLimit(1)
        }
    }

    private func repWorkspaceSubtitle(_ workspace: TeamRepWorkspace) -> String {
        if let liveLocation = workspace.liveLocation {
            return "On duty • updated \(liveLocation.recordedAt.formatted(date: .omitted, time: .shortened))"
        }
        if let latestSession = workspace.latestSession, let endedAt = latestSession.endedAt {
            return "Off duty • last route \(endedAt.formatted(date: .abbreviated, time: .shortened))"
        }
        return "Off duty"
    }

    private func leadStatusText(_ status: TeamLeadStatus) -> String {
        switch status {
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

    private func leadStatusIcon(_ status: TeamLeadStatus) -> String {
        switch status {
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

    private func leadStatusColor(_ status: TeamLeadStatus) -> Color {
        switch status {
        case .notContacted:
            return Color.textMuted
        case .notHome:
            return Color.statusNotHome
        case .contacted:
            return Color.statusInterested
        case .interested:
            return Color.statusInterested
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

    private func constantRepSelection(_ userId: String?) -> Binding<String?> {
        Binding<String?>(
            get: { userId },
            set: { _ in }
        )
    }

    private func createTeam() {
        runTeamAction(successMessage: "Team created.") {
            try await teamService.createTeam(
                name: teamName,
                displayName: userAccountManager.currentUserDisplayName,
                email: userAccountManager.currentUserEmail
            )
        }
    }

    #if DEBUG
    private func submitTeamAccount() {
        let email = teamAccountEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        let password = teamAccountPassword
        if isCreatingTeamAccount {
            userAccountManager.signUp(
                email: email,
                password: password,
                displayName: teamAccountDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        } else {
            userAccountManager.signIn(email: email, password: password)
        }
    }
    #endif

    private func createInvite() {
        guard !isWorking && !teamService.isLoading else { return }
        isWorking = true
        statusMessage = nil
        statusMessageIsError = false

        Task {
            do {
                let inviteWorkType = pendingInviteWorkType
                createdInvite = try await teamService.createInvite(workType: inviteWorkType)
                createdInviteWorkType = inviteWorkType
                statusMessage = nil
                statusMessageIsError = false
                if let createdInvite {
                    UIAccessibility.post(notification: .announcement, argument: "Invite code \(createdInvite.displayCode) ready")
                }
            } catch {
                statusMessage = TeamFirebaseService.userFacingErrorMessage(for: error)
                statusMessageIsError = true
            }
            isWorking = false
        }
    }

    private func copyInviteCode(_ invite: TeamInvite) {
        UIPasteboard.general.string = invite.displayCode
        statusMessage = "Invite code copied."
        statusMessageIsError = false
        UIAccessibility.post(notification: .announcement, argument: "Invite code copied")
    }

    private func inviteShareText(for invite: TeamInvite, workType: TeamMemberWorkType) -> String {
        "Join my D2D Advancer team as a \(workType.title). Invite code: \(invite.displayCode). Expires \(invite.expiresAt.formatted(date: .abbreviated, time: .shortened))."
    }

    private func joinTeam() {
        runTeamAction(successMessage: "Joined team.") {
            try await teamService.joinTeam(
                inviteCode: inviteCode,
                displayName: userAccountManager.currentUserDisplayName,
                email: userAccountManager.currentUserEmail
            )
            inviteCode = ""
        }
    }

    private func cancelPendingInvite(_ member: TeamMember) {
        runTeamAction(successMessage: "Pending invite cancelled.") {
            try await teamService.cancelPendingInvite(for: member)
        }
    }

    private func runTeamAction(successMessage: String, action: @escaping () async throws -> Void) {
        isWorking = true
        statusMessage = nil
        statusMessageIsError = false

        Task {
            do {
                try await action()
                statusMessage = successMessage
                statusMessageIsError = false
            } catch {
                statusMessage = TeamFirebaseService.userFacingErrorMessage(for: error)
                statusMessageIsError = true
            }
            isWorking = false
        }
    }

    private func toggleDutySharing(for member: TeamMember) {
        isWorking = true
        statusMessage = nil
        statusMessageIsError = false

        Task {
            do {
                if teamService.activeDutySession == nil {
                    locationManager.startLocationUpdates()
                    locationManager.requestImmediateLocation()
                    try await teamService.startDuty(member: member)
                    if let location = locationManager.location {
                        publishDutyLocationIfNeeded(location, force: true)
                    }
                    statusMessage = member.role == .owner ? "Owner location sharing is on." : "You are on duty."
                } else {
                    try await teamService.endDuty()
                    lastTeamLocationUploadAt = nil
                    lastTeamLocationUploadCoordinate = nil
                    statusMessage = member.role == .owner ? "Owner location sharing is off." : "You are off duty."
                }
                statusMessageIsError = false
            } catch {
                statusMessage = TeamFirebaseService.userFacingErrorMessage(for: error)
                statusMessageIsError = true
            }
            isWorking = false
        }
    }

    private func loadTeam() async {
        await teamService.loadCurrentTeam(
            displayName: userAccountManager.currentUserDisplayName,
            email: userAccountManager.currentUserEmail
        )
        clearStaleSetupMessagesIfNeeded()
    }

    private func clearStaleSetupMessagesIfNeeded() {
        guard isShowingTeamSetup else { return }

        if let statusMessage,
           statusMessageIsError,
           isStaleSetupErrorMessage(statusMessage) {
            self.statusMessage = nil
            statusMessageIsError = false
        }

        if let errorMessage = teamService.lastErrorMessage,
           isStaleSetupErrorMessage(errorMessage) {
            teamService.lastErrorMessage = nil
        }

        teamService.clearStaleNoTeamSetupErrors()

        if case let .failed(message) = userAccountManager.authStatus,
           isStaleSetupErrorMessage(message) {
            userAccountManager.authStatus = .idle
        }

        if case let .failed(message) = appleSignInManager.authStatus,
           isStaleSetupErrorMessage(message) {
            appleSignInManager.authStatus = .idle
        }
    }

    private func publishDutyLocationIfNeeded(_ location: CLLocation, force: Bool = false) {
        guard let member = teamService.currentMember,
              teamService.activeDutySession != nil else {
            return
        }

        let coordinate = TeamCoordinate(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude
        )
        let now = Date()
        guard force || TeamLocationSharingPolicy.shouldUploadLocation(
            lastUploadAt: lastTeamLocationUploadAt,
            lastCoordinate: lastTeamLocationUploadCoordinate,
            newCoordinate: coordinate,
            now: now
        ) else {
            return
        }
        guard !isUploadingDutyLocation else { return }

        isUploadingDutyLocation = true
        Task {
            do {
                try await teamService.recordCurrentLocation(location, member: member, now: now)
                lastTeamLocationUploadAt = now
                lastTeamLocationUploadCoordinate = coordinate
            } catch {
                statusMessage = TeamFirebaseService.userFacingErrorMessage(for: error)
                statusMessageIsError = true
            }
            isUploadingDutyLocation = false
        }
    }

    private func memberSubtitle(_ member: TeamMember) -> String {
        if member.isPendingInvite {
            if let code = member.pendingInviteDisplayCode {
                return "Pending \(member.displayRoleTitle) Invite • \(code)"
            }
            return "Pending \(member.displayRoleTitle) Invite"
        }
        return member.displayRoleTitle
    }

    private func memberWorkTypeIcon(_ member: TeamMember) -> String {
        if member.role == .owner { return "crown.fill" }
        if member.isTechnician { return "wrench.and.screwdriver.fill" }
        return "person.fill"
    }

    private func memberWorkTypeColor(_ member: TeamMember) -> Color {
        if member.role == .owner { return Color.electricViolet }
        if member.isTechnician { return Color.statusNotHome }
        return Color.statusInterested
    }

    private func memberName(forUserId userId: String) -> String {
        teamService.teamMembers.first { $0.userId == userId }?.displayName ?? "Unassigned"
    }

    private func teamBooking(for appointment: Appointment) -> TeamBooking? {
        teamService.teamBookings.first { $0.id == appointment.id.uuidString }
    }

    private func canUpdateMemberWorkType(_ member: TeamMember) -> Bool {
        guard let team = teamService.activeTeam,
              let currentMember = teamService.currentMember else { return false }
        return currentMember.role == .owner
            && currentMember.status == .active
            && team.planStatus.allowsTeamWrite
            && member.role == .member
            && member.status == .active
            && !member.isPendingInvite
    }

    private func memberWorkTypeMenu(_ member: TeamMember) -> some View {
        Menu {
            Button(TeamMemberWorkType.salesRep.title) {
                updateMemberWorkType(member, workType: .salesRep)
            }
            .disabled(member.workType == .salesRep)

            Button(TeamMemberWorkType.technician.title) {
                updateMemberWorkType(member, workType: .technician)
            }
            .disabled(member.workType == .technician)
        } label: {
            Image(systemName: "person.text.rectangle.fill")
                .font(.obsidianFootnote)
                .foregroundColor(Color.electricViolet)
                .frame(width: 28, height: 28)
        }
        .accessibilityLabel("Change worker type")
    }

    private func memberStatusText(_ member: TeamMember) -> String {
        if member.isPendingInvite { return "Pending" }
        return member.status == .active ? "Active" : "Removed"
    }

    private func memberStatusColor(_ member: TeamMember) -> Color {
        if member.isPendingInvite { return Color.statusNotHome }
        return member.status == .active ? Color.statusInterested : Color.statusNotInterested
    }

    private func ownerNotificationIcon(_ event: TeamOwnerLeadEvent) -> String {
        switch event {
        case .interested:
            return "heart.fill"
        case .followUp:
            return "arrow.clockwise.circle.fill"
        case .booked:
            return "calendar.badge.checkmark"
        case .converted:
            return "checkmark.seal.fill"
        case .highPriority:
            return "exclamationmark.triangle.fill"
        }
    }

    private func activityIcon(_ kind: TeamActivityLogKind) -> String {
        switch kind {
        case .teamCreated:
            return "person.3.fill"
        case .inviteCreated, .inviteAccepted, .inviteCancelled:
            return "number.square.fill"
        case .memberLeft:
            return "rectangle.portrait.and.arrow.right"
        case .memberRemoved:
            return "person.crop.circle.badge.minus"
        case .teamClosed:
            return "person.3.sequence.fill"
        case .leadCreated:
            return "mappin.circle.fill"
        case .leadAssigned, .bookingAssigned:
            return "person.crop.circle.badge.checkmark"
        case .leadStatusUpdated, .repStatusReply, .bookingStatusUpdated:
            return "bubble.left.and.bubble.right.fill"
        case .leadHighPriority:
            return "star.fill"
        case .dutyStarted:
            return "location.fill"
        case .dutyEnded:
            return "location.slash.fill"
        case .ownerAlertRead:
            return "checkmark.circle.fill"
        }
    }

    private func duplicateReasonText(_ candidate: TeamDuplicateLeadCandidate) -> String {
        switch candidate.reason {
        case .samePhone:
            return "Same phone number as \(candidate.existingLead.name)."
        case .sameAddress:
            return "Same address as \(candidate.existingLead.name)."
        case .nearbyLocation:
            if let distance = candidate.distanceMeters {
                return "Within \(Int(distance.rounded())) meters of \(candidate.existingLead.name)."
            }
            return "Very close to \(candidate.existingLead.name)."
        }
    }

    private func planStateText(_ status: TeamPlanStatus) -> String {
        switch status {
        case .active:
            return "Team plan active"
        case .grace:
            return "Read-only grace period"
        case .paused:
            return "Team paused"
        }
    }

    private func planStateIcon(_ status: TeamPlanStatus) -> String {
        switch status {
        case .active:
            return "checkmark.seal.fill"
        case .grace:
            return "clock.badge.exclamationmark.fill"
        case .paused:
            return "pause.circle.fill"
        }
    }

    private func planStateColor(_ status: TeamPlanStatus) -> Color {
        switch status {
        case .active:
            return Color.statusInterested
        case .grace:
            return Color.statusNotHome
        case .paused:
            return Color.statusNotInterested
        }
    }

    private func assignLead(_ lead: TeamLead, to rep: TeamMember) {
        runTeamAction(successMessage: "Lead assigned to \(rep.displayName).") {
            try await teamService.assignTeamLead(lead, to: rep)
        }
    }

    private func assignBooking(_ booking: TeamBooking, to rep: TeamMember) {
        runTeamAction(successMessage: "Job assigned to \(rep.displayName).") {
            try await teamService.assignTeamBooking(booking, to: rep)
        }
    }

    private func sendAppointment(_ appointment: Appointment, to worker: TeamMember) {
        runTeamAction(successMessage: "Job sent to \(worker.displayName).") {
            try await teamService.sendAppointmentToTeamBooking(appointment, to: worker)
        }
    }

    private func updateBookingStatus(_ booking: TeamBooking, status: TeamBookingStatus) {
        runTeamAction(successMessage: "Job marked \(status.displayName.lowercased()).") {
            try await teamService.updateTeamBookingStatus(booking, status: status)
        }
    }

    private func updateMemberWorkType(_ member: TeamMember, workType: TeamMemberWorkType) {
        runTeamAction(successMessage: "\(member.displayName) is now a \(workType.title).") {
            try await teamService.updateMemberWorkType(member, workType: workType)
        }
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

    private func submitRepReply(status: OwnerInstructionStatus, lead: TeamLead) {
        runTeamAction(successMessage: "Status sent.") {
            try await teamService.submitRepStatusReply(
                lead: lead,
                status: status,
                note: nil
            )
        }
    }

    private func markNotificationRead(_ notification: TeamOwnerNotification) {
        runTeamAction(successMessage: "Alert marked read.") {
            try await teamService.markOwnerNotificationRead(notification)
        }
    }

    private func confirmRemoveMember(_ member: TeamMember) {
        memberPendingRemoval = member
        showingRemoveMemberConfirmation = true
    }

    private func removeMember(_ member: TeamMember) {
        runTeamAction(successMessage: "\(member.displayName) removed from team.") {
            try await teamService.removeMember(member)
        }
    }

    private func leaveTeam() {
        runTeamAction(successMessage: "Left team.") {
            try await teamService.leaveCurrentTeam()
        }
    }

    private func closeTeam() {
        runTeamAction(successMessage: "Team workspace closed.") {
            try await teamService.closeCurrentTeam()
        }
    }
}

private extension View {
    func teamTextField() -> some View {
        self
            .font(.obsidianFootnote)
            .foregroundColor(Color.textPrimary)
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.obsidianElevated)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.obsidianBorder.opacity(0.4), lineWidth: 0.5)
                    )
            )
    }
}

private struct TeamInfoCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.obsidianSurface)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.obsidianBorder.opacity(0.3), lineWidth: 0.5)
                )
                .shadow(color: Color.black.opacity(0.08), radius: 4, x: 0, y: 2)
        )
    }
}

#Preview {
    NavigationStack {
        TeamWorkspaceView()
    }
}
