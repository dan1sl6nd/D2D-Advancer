import SwiftUI
import UIKit
import AuthenticationServices
import CoreLocation

struct TeamWorkspaceView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var userAccountManager = FirebaseUserAccountManager.shared
    @ObservedObject private var appleSignInManager = AppleSignInManager.shared
    @ObservedObject private var teamService = TeamFirebaseService.shared
    @ObservedObject private var locationManager = LocationManager.shared
    @State private var teamName = "My Team"
    @State private var inviteCode = ""
    #if DEBUG
    @State private var teamAccountEmail = ""
    @State private var teamAccountPassword = ""
    @State private var teamAccountDisplayName = ""
    @State private var isCreatingTeamAccount = false
    #endif
    @State private var createdInvite: TeamInvite?
    @State private var isWorking = false
    @State private var isUploadingDutyLocation = false
    @State private var selectedRepUserId: String?
    @State private var lastTeamLocationUploadAt: Date?
    @State private var lastTeamLocationUploadCoordinate: TeamCoordinate?
    @State private var memberPendingRemoval: TeamMember?
    @State private var showingRemoveMemberConfirmation = false
    @State private var statusMessage: String?
    @State private var statusMessageIsError = false
    @FocusState private var focusedInput: TeamInput?

    private enum TeamInput: Hashable {
        case accountEmail
        case accountPassword
        case accountDisplayName
        case teamName
        case inviteCode
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

                        if let statusMessage {
                            statusCard(
                                statusMessage,
                                color: statusMessageIsError ? Color.statusNotInterested : Color.statusInterested
                            )
                        }

                        #if DEBUG
                        if FirebaseEmulatorConfiguration.isEnabled {
                            statusCard("Firebase emulator mode active")
                        }
                        #endif

                        if let errorMessage = teamService.lastErrorMessage {
                            statusCard(errorMessage, color: Color.statusNotInterested)
                        }

                        if let syncMessage = teamSyncStatusMessage {
                            statusCard(syncMessage, color: teamSyncStatusColor)
                        }

                        if case let .failed(errorMessage) = userAccountManager.authStatus {
                            statusCard(errorMessage, color: Color.statusNotInterested)
                        }

                        if case let .failed(errorMessage) = appleSignInManager.authStatus {
                            statusCard(errorMessage, color: Color.statusNotInterested)
                        }

                        if teamService.isLoading || isWorking {
                            loadingCard
                        }

                        if !TeamAuthPolicy.canUseTeamWorkspace(isFirebaseAuthenticated: userAccountManager.isLoggedIn) {
                            appleSignInRequiredCard
                        } else if let team = teamService.activeTeam, let member = teamService.currentMember {
                            planStateCard(team)
                            if member.role == .owner {
                                ownerNotificationsCard
                                ownerSummary(team: team)
                                ownerDuplicateWarningsCard
                                ownerFieldMapCard
                                ownerRepWorkCard
                                inviteManagementCard(team: team)
                                activityLogCard
                                memberListCard(team: team)
                            } else {
                                repSummary(team: team, member: member)
                                activityLogCard
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
        .onChange(of: userAccountManager.isLoggedIn) { _, isLoggedIn in
            Task { await loadTeam() }
        }
        .onReceive(locationManager.$location.compactMap { $0 }) { location in
            publishDutyLocationIfNeeded(location)
        }
        .alert("Remove Rep?", isPresented: $showingRemoveMemberConfirmation, presenting: memberPendingRemoval) { member in
            Button("Remove", role: .destructive) {
                removeMember(member)
            }
            Button("Cancel", role: .cancel) {}
        } message: { member in
            Text("\(member.displayName) will lose team access and the seat will be freed.")
        }
    }

    private var introCard: some View {
        TeamInfoCard {
            Label("Team Workspace", systemImage: "person.3.fill")
                .font(.obsidianCallout)
                .foregroundColor(Color.textPrimary)

            Text("Personal leads stay private. Sign in with Apple for team identity. Reps only receive assigned leads, bookings, and their own active-hours GPS graph.")
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
                statRow("Today bookings", "\(todaySummary.bookingCount)")
                statRow("Important work", "\(todaySummary.importantLeadCount)")
            }
            statRow("Team leads", "\(teamService.teamLeads.count)")
            statRow("Bookings", "\(teamService.teamBookings.count)")
            statRow("Active reps", "\(teamService.dutySessions.filter { $0.status == .active }.count)")
            statRow("Seats used", "\(activeMemberCount)/\(team.memberLimit)")

            Text("Generate one invite code per rep. Each code reserves one seat until the rep joins or you cancel the pending invite.")
                .font(.obsidianFootnote)
                .foregroundColor(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
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
                Text("Active reps will appear here after they join the team.")
                    .font(.obsidianFootnote)
                    .foregroundColor(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                TeamFieldMapView(
                    workspaces: ownerRepWorkspaces,
                    selectedRepUserId: $selectedRepUserId
                )
                .frame(height: 270)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.obsidianBorder.opacity(0.35), lineWidth: 0.5)
                )
                .accessibilityIdentifier("teamFieldMapView")

                HStack(spacing: 12) {
                    mapLegendItem("Live rep", color: .blue, icon: "location.fill")
                    mapLegendItem("Lead", color: .orange, icon: "mappin.circle.fill")
                    mapLegendItem("Route", color: .blue, icon: "point.topleft.down.curvedto.point.bottomright.up")
                }
            }
        }
    }

    private var ownerRepWorkCard: some View {
        TeamInfoCard {
            Text("Rep Work")
                .font(.obsidianCallout)
                .foregroundColor(Color.textPrimary)

            if ownerRepWorkspaces.isEmpty {
                Text("Accepted reps will appear here with their assigned leads, bookings, live status, and active-hours route history.")
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

    private func inviteManagementCard(team: TeamWorkspace) -> some View {
        TeamInfoCard {
            Text("Invite Rep")
                .font(.obsidianCallout)
                .foregroundColor(Color.textPrimary)

            Text(activeMemberCount >= team.memberLimit ? "The included team seats are full." : "Create an invite code and send it to one rep. The code expires after 7 days and can be used once.")
                .font(.obsidianFootnote)
                .foregroundColor(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            if let createdInvite {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Invite code")
                        .font(.micro)
                        .foregroundColor(Color.textMuted)
                    Text(createdInvite.displayCode)
                        .font(.system(.title3, design: .monospaced).weight(.semibold))
                        .foregroundColor(Color.textPrimary)
                    Text("Expires \(createdInvite.expiresAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.micro)
                        .foregroundColor(Color.textMuted)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.obsidianElevated)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color.obsidianBorder.opacity(0.4), lineWidth: 0.5)
                        )
                )
            }

            teamActionButton(
                title: "Create Invite Code",
                icon: "number.square.fill",
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

            if teamService.teamMembers.isEmpty {
                Text("Members will appear here after the team loads.")
                    .font(.obsidianFootnote)
                    .foregroundColor(Color.textSecondary)
            } else {
                ForEach(teamService.teamMembers) { member in
                    HStack(spacing: 12) {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(member.role == .owner ? Color.electricViolet : Color.statusInterested)
                            .frame(width: 34, height: 34)
                            .overlay(
                                Image(systemName: member.role == .owner ? "crown.fill" : "person.fill")
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
            }
        }
    }

    private func repSummary(team: TeamWorkspace, member: TeamMember) -> some View {
        let workspace = TeamRepWorkspace.makeMemberWorkspace(
            member: member,
            leads: teamService.teamLeads,
            bookings: teamService.teamBookings,
            dutySessions: teamService.dutySessions,
            dutyLocationPoints: teamService.dutyLocationPoints
        )

        return TeamInfoCard {
            Text("My Team Work")
                .font(.obsidianCallout)
                .foregroundColor(Color.textPrimary)

            if let todaySummary = teamService.todayWorkSummary() {
                statRow("Today bookings", "\(todaySummary.bookingCount)")
                statRow("Important work", "\(todaySummary.importantLeadCount)")
            }
            statRow("Assigned leads", "\(teamService.teamLeads.count)")
            statRow("Assigned bookings", "\(teamService.teamBookings.count)")

            Button {
                Task {
                    if teamService.activeDutySession == nil {
                        locationManager.startLocationUpdates()
                        locationManager.requestImmediateLocation()
                        try? await teamService.startDuty(member: member)
                        if let location = locationManager.location {
                            publishDutyLocationIfNeeded(location, force: true)
                        }
                    } else {
                        try? await teamService.endDuty()
                        lastTeamLocationUploadAt = nil
                        lastTeamLocationUploadCoordinate = nil
                    }
                }
            } label: {
                Label(teamService.activeDutySession == nil ? "Go On Duty" : "Go Off Duty", systemImage: teamService.activeDutySession == nil ? "location.fill" : "location.slash.fill")
                    .frame(maxWidth: .infinity)
                    .font(.obsidianCallout)
                    .foregroundColor(.white)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.electricViolet)
                            .shadow(color: Color.electricViolet.opacity(0.3), radius: 4, x: 0, y: 2)
                    )
            }
            .buttonStyle(PlainButtonStyle())
            .accessibilityIdentifier("teamDutyToggleButton")
            .disabled(!team.planStatus.allowsTeamWrite)
            .opacity(team.planStatus.allowsTeamWrite ? 1 : 0.45)

            Text("Your active-hours route is visible to the owner while you are on duty. Your live dot disappears when you go off duty.")
                .font(.obsidianFootnote)
                .foregroundColor(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            TeamFieldMapView(
                workspaces: [workspace],
                selectedRepUserId: constantRepSelection(member.userId)
            )
            .frame(height: 220)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.obsidianBorder.opacity(0.35), lineWidth: 0.5)
            )
            .accessibilityIdentifier("teamRepMapView")

            ForEach(workspace.assignedLeads.prefix(4)) { lead in
                VStack(alignment: .leading, spacing: 8) {
                    teamLeadRow(lead)
                    repQuickReplyRow(lead: lead, team: team)
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
                SecureField("Password", text: $teamAccountPassword)
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
            Text("Create or Accept Team")
                .font(.obsidianCallout)
                .foregroundColor(Color.textPrimary)

            Text("Create the included Team plan as the owner. Reps join by signing in with Apple and entering your invite code.")
                .font(.obsidianFootnote)
                .foregroundColor(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 8) {
                Text("Team name")
                    .font(.micro)
                    .foregroundColor(Color.textMuted)
                TextField("My Team", text: $teamName)
                    .focused($focusedInput, equals: .teamName)
                    .teamTextField()
                    .accessibilityIdentifier("teamNameField")
                teamActionButton(
                    title: "Create Team",
                    icon: "person.3.fill",
                    accessibilityIdentifier: "teamCreateTeamButton"
                ) {
                    createTeam()
                }
            }

            Divider()
                .overlay(Color.obsidianBorder)

            VStack(alignment: .leading, spacing: 8) {
                Text("Joining as a rep?")
                    .font(.micro)
                    .foregroundColor(Color.textMuted)
                TextField("Invite code", text: $inviteCode)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .focused($focusedInput, equals: .inviteCode)
                    .teamTextField()
                    .accessibilityIdentifier("teamInviteCodeField")
                teamActionButton(
                    title: "Join Team",
                    icon: "person.badge.plus",
                    accessibilityIdentifier: "teamJoinTeamButton"
                ) {
                    joinTeam()
                }
            }
        }
    }

    private var loadingCard: some View {
        TeamInfoCard {
            HStack(spacing: 12) {
                ProgressView()
                    .tint(Color.electricViolet)
                Text("Updating team workspace...")
                    .font(.obsidianFootnote)
                    .foregroundColor(Color.textSecondary)
            }
        }
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

    private var activeMemberCount: Int {
        teamService.teamMembers.filter { $0.status == .active }.count
    }

    private var activeAssignableReps: [TeamMember] {
        teamService.teamMembers
            .filter { $0.role == .member && $0.status == .active && !$0.isPendingInvite }
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
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

    private var filteredOwnerRepWorkspaces: [TeamRepWorkspace] {
        guard let selectedRepUserId else { return ownerRepWorkspaces }
        return ownerRepWorkspaces.filter { $0.member.userId == selectedRepUserId }
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

    private func repWorkspaceRow(_ workspace: TeamRepWorkspace) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                selectedRepUserId = workspace.member.userId
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
                        Text("\(workspace.assignedLeads.count) leads")
                            .font(.micro)
                            .foregroundColor(Color.textSecondary)
                        Text("\(workspace.assignedBookings.count) bookings")
                            .font(.micro)
                            .foregroundColor(Color.textMuted)
                    }
                }
            }
            .buttonStyle(PlainButtonStyle())
            .accessibilityLabel("Show \(workspace.member.displayName) on map")

            if workspace.assignedLeads.isEmpty {
                Text("No assigned team leads yet.")
                    .font(.micro)
                    .foregroundColor(Color.textMuted)
            } else {
                ForEach(workspace.assignedLeads.prefix(3)) { lead in
                    teamLeadRow(lead, allowAssignment: true)
                }
            }

            if !workspace.assignedBookings.isEmpty {
                ForEach(workspace.assignedBookings.prefix(2)) { booking in
                    teamBookingRow(booking, allowAssignment: true)
                }
            }

            Divider()
                .overlay(Color.obsidianBorder.opacity(0.5))
        }
    }

    private func teamLeadRow(_ lead: TeamLead, allowAssignment: Bool = false) -> some View {
        HStack(spacing: 10) {
            Image(systemName: lead.isHighPriority ? "star.fill" : leadStatusIcon(lead.status))
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
    }

    private func teamBookingRow(_ booking: TeamBooking, allowAssignment: Bool = false) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "calendar.badge.clock")
                .foregroundColor(Color.electricViolet)
            VStack(alignment: .leading, spacing: 2) {
                Text(booking.title)
                    .font(.micro)
                    .foregroundColor(Color.textSecondary)
                    .lineLimit(1)
                Text(booking.startDate.formatted(date: .omitted, time: .shortened))
                    .font(.nano)
                    .foregroundColor(Color.textMuted)
            }
            Spacer()
            if allowAssignment {
                bookingAssignmentMenu(booking)
            }
        }
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
            ForEach(activeAssignableReps) { rep in
                Button(rep.displayName) {
                    assignBooking(booking, to: rep)
                }
                .disabled(rep.userId == booking.assignedToUserId)
            }
        } label: {
            Image(systemName: "person.crop.circle.badge.checkmark")
                .font(.micro)
                .foregroundColor(Color.electricViolet)
                .frame(width: 26, height: 26)
        }
        .disabled(activeAssignableReps.isEmpty || teamService.activeTeam?.planStatus.allowsTeamWrite != true)
        .accessibilityLabel("Assign booking")
    }

    private func repQuickReplyRow(lead: TeamLead, team: TeamWorkspace) -> some View {
        HStack(spacing: 8) {
            repReplyButton("Done", status: .done, lead: lead, team: team)
            repReplyButton("Not home", status: .customerNotHome, lead: lead, team: team)
            repReplyButton("Owner follow-up", status: .needsOwnerFollowUp, lead: lead, team: team)
        }
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

    private func constantRepSelection(_ userId: String) -> Binding<String?> {
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
        isWorking = true
        statusMessage = nil
        statusMessageIsError = false

        Task {
            do {
                createdInvite = try await teamService.createInvite()
                statusMessage = "Invite code created."
                statusMessageIsError = false
            } catch {
                statusMessage = error.localizedDescription
                statusMessageIsError = true
            }
            isWorking = false
        }
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
                statusMessage = error.localizedDescription
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
    }

    private func publishDutyLocationIfNeeded(_ location: CLLocation, force: Bool = false) {
        guard let member = teamService.currentMember,
              member.role == .member,
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
                statusMessage = error.localizedDescription
                statusMessageIsError = true
            }
            isUploadingDutyLocation = false
        }
    }

    private func memberSubtitle(_ member: TeamMember) -> String {
        if member.isPendingInvite { return "Pending Invite" }
        return member.role == .owner ? "Owner" : "Rep"
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
        case .memberRemoved:
            return "person.crop.circle.badge.minus"
        case .leadCreated:
            return "mappin.circle.fill"
        case .leadAssigned, .bookingAssigned:
            return "person.crop.circle.badge.checkmark"
        case .leadStatusUpdated, .repStatusReply:
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
        runTeamAction(successMessage: "Booking assigned to \(rep.displayName).") {
            try await teamService.assignTeamBooking(booking, to: rep)
        }
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
    NavigationView {
        TeamWorkspaceView()
    }
}
