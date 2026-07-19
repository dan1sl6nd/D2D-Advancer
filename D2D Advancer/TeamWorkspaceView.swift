import SwiftUI
import UIKit
import AuthenticationServices
import CoreLocation

struct TeamWorkspaceView: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var userAccountManager = FirebaseUserAccountManager.shared
    @ObservedObject private var firebaseService = FirebaseService.shared
    @ObservedObject private var appleSignInManager = AppleSignInManager.shared
    @ObservedObject private var teamService = TeamFirebaseService.shared
    @ObservedObject private var paywallManager = PaywallManager.shared
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
    @State private var createdInviteWorkType: TeamMemberWorkType?
    @State private var isWorking = false
    @State private var isUploadingDutyLocation = false
    @State private var lastTeamLocationUploadAt: Date?
    @State private var lastTeamLocationUploadCoordinate: TeamCoordinate?
    @State private var memberPendingRemoval: TeamMember?
    @State private var showingRemoveMemberConfirmation = false
    @State private var showingLeaveTeamConfirmation = false
    @State private var showingCloseTeamConfirmation = false
    @State private var statusMessage: String?
    @State private var statusMessageIsError = false
    @State private var pendingInviteWorkType: TeamMemberWorkType = .salesRep
    @State private var scrollResetToken = 0
    @FocusState private var focusedInput: TeamInput?

    private let scrollTopAnchor = "teamWorkspaceScrollTop"

    private enum TeamInput: Hashable {
        case accountEmail
        case accountPassword
        case accountDisplayName
        case teamName
        case inviteCode
    }

    var body: some View {
        VStack(spacing: 0) {
            if let team = teamService.activeTeam,
               teamService.currentMember?.role == .owner,
               canUseTeamWorkspace {
                ownerPinnedInvitePanel(team: team)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
            }
            if let team = teamService.activeTeam,
               let member = teamService.currentMember,
               member.role != .owner,
               canUseTeamWorkspace {
                workerPinnedDutyPanel(team: team, member: member)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
            }

            ScrollViewReader { scrollProxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        Color.clear
                            .frame(height: 0)
                            .id(scrollTopAnchor)

                        if canUseTeamWorkspace, teamService.activeTeam != nil {
                            introCard
                        }

                        primaryStatusNotice

                        #if DEBUG
                        if FirebaseEmulatorConfiguration.isEnabled {
                            statusCard("Firebase emulator mode active: \(FirebaseEmulatorConfiguration.activeHostDescription)")
                        }
                        #endif

                        if shouldShowInitialLoadingCard {
                            loadingCard("Loading team workspace...")
                        }

                        if !canUseTeamWorkspace {
                            appleSignInRequiredCard
                        } else if let team = teamService.activeTeam, let member = teamService.currentMember {
                            planStateCard(team, member: member)
                            if member.role == .owner {
                                ownerSummary(team: team)
                                memberListCard(team: team)
                                ownerDuplicateWarningsCard
                                activityLogCard
                            } else {
                                activityLogCard
                            }
                        } else {
                            setupTeamCard
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 28)
                }
                .id(teamService.activeTeam?.id ?? "team-setup")
                .scrollDismissesKeyboard(.immediately)
                .onChange(of: teamService.activeTeam?.id) { _, _ in
                    scrollTeamWorkspaceToTop(scrollProxy)
                }
                .onChange(of: teamService.currentMember?.role) { _, _ in
                    scrollTeamWorkspaceToTop(scrollProxy)
                }
                .onChange(of: teamService.currentMember?.id) { _, _ in
                    scrollTeamWorkspaceToTop(scrollProxy)
                }
                .onChange(of: scrollResetToken) { _, _ in
                    scrollTeamWorkspaceToTop(scrollProxy)
                }
            }
        }
        .background(Color.obsidianBackground(for: colorScheme).ignoresSafeArea())
        .obsidianPushedNavigation("Team", backButtonAccessibilityIdentifier: "teamWorkspaceBackButton")
        .toolbar(.hidden, for: .tabBar)
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
    }

    private func scrollTeamWorkspaceToTop(_ proxy: ScrollViewProxy) {
        DispatchQueue.main.async {
            proxy.scrollTo(scrollTopAnchor, anchor: .top)
        }
    }

    private var introCard: some View {
        return TeamInfoCard {
            Label("Team Workspace", systemImage: "person.3.fill")
                .font(.obsidianCallout)
                .foregroundColor(Color.textPrimary)

            Text(teamIntroText)
                .font(.obsidianFootnote)
                .foregroundColor(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var teamIntroText: String {
        if teamService.currentMember?.role == .owner {
            return "Team setup, invites, seats, duty sharing, and owner controls. Daily lead and job work stays in Map, Leads, and Work."
        }
        if teamService.currentMember?.isTechnician == true {
            return "Use this screen for team access and duty sharing. Your daily service work is in Work."
        }
        if teamService.currentMember?.isSalesRep == true {
            return "Use this screen for team access and duty sharing. Your daily sales work is in My Leads."
        }
        return "Create or join a team. Personal leads stay private unless you create or assign work inside Team."
    }

    @ViewBuilder
    private var primaryStatusNotice: some View {
        if let errorMessage = visibleUserAuthErrorMessage {
            statusCard(errorMessage, color: Color.statusNotInterested)
        } else if let errorMessage = visibleAppleAuthErrorMessage {
            statusCard(errorMessage, color: Color.statusNotInterested)
        } else if let statusMessage = visibleStatusMessage {
            statusCard(
                statusMessage,
                color: statusMessageIsError ? Color.statusNotInterested : Color.statusInterested
            )
        } else if canUseTeamWorkspace,
                  !teamService.teamOperationsControl.teamWritesEnabled {
            statusCard(
                teamService.teamOperationsControl.displayMessage,
                color: Color.statusNotHome
            )
        } else if canUseTeamWorkspace,
                  teamService.teamUsageControl.level != .normal {
            teamUsageSafeguardCard(teamService.teamUsageControl)
        } else if let syncHealth = visibleTeamSyncHealthSnapshot {
            teamSyncHealthCard(syncHealth)
        }
    }

    private func planStateCard(_ team: TeamWorkspace, member: TeamMember) -> some View {
        let effectivePlanStatus = team.effectivePlanStatus()

        return TeamInfoCard {
            Text(team.name)
                .font(.obsidianCallout)
                .foregroundColor(Color.textPrimary)

            Label(planStateText(effectivePlanStatus), systemImage: planStateIcon(effectivePlanStatus))
                .font(.obsidianFootnote)
                .foregroundColor(planStateColor(effectivePlanStatus))

            Divider()
                .overlay(Color.obsidianBorder.opacity(0.6))

            if member.role == .owner {
                Text("Close the workspace to remove worker access and cancel pending invites.")
                    .font(.micro)
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
                Text("Leave this workspace and remove team access from this account.")
                    .font(.micro)
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
    }

    private func ownerPinnedInvitePanel(team: TeamWorkspace) -> some View {
        TeamInfoCard {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Label("Invite Worker", systemImage: "number.square.fill")
                    .font(.obsidianCallout)
                    .foregroundColor(Color.textPrimary)

                Spacer(minLength: 8)

                Text("\(activeMemberCount)/\(team.memberLimit) seats")
                    .font(.micro)
                    .foregroundColor(Color.textMuted)
            }

            if let createdInvite {
                createdInvitePanel(
                    invite: createdInvite,
                    workType: createdInviteWorkType ?? pendingInviteWorkType
                )
            }

            if activeMemberCount >= team.memberLimit {
                Text("All included seats are in use. Remove a worker or cancel a pending invite before creating another code.")
                    .font(.obsidianFootnote)
                    .foregroundColor(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                inviteWorkerTypeSelector(disabled: inviteCreationDisabled(for: team))

                teamActionButton(
                    title: createdInvite == nil ? "Create Invite Code" : "Create Another Code",
                    icon: createdInvite == nil ? "number.square.fill" : "plus.square.fill",
                    disabled: inviteCreationDisabled(for: team),
                    accessibilityIdentifier: "teamCreateInviteButton"
                ) {
                    createInvite()
                }
            }
        }
    }

    private func workerPinnedDutyPanel(team: TeamWorkspace, member: TeamMember) -> some View {
        TeamInfoCard {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Label("Duty Sharing", systemImage: "location.fill")
                    .font(.obsidianCallout)
                    .foregroundColor(Color.textPrimary)

                Spacer(minLength: 8)

                Text(teamService.activeDutySession == nil ? "Off" : "On")
                    .font(.micro)
                    .foregroundColor(teamService.activeDutySession == nil ? Color.textMuted : Color.statusInterested)
            }

            dutySharingButton(
                member: member,
                team: team,
                onTitle: "Go On Duty",
                offTitle: "Go Off Duty",
                accessibilityIdentifier: "teamDutyToggleButton"
            )

            Text("Owner sees your live dot and active-hours route only while you are on duty.")
                .font(.obsidianFootnote)
                .foregroundColor(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func ownerSummary(team: TeamWorkspace) -> some View {
        TeamInfoCard {
            Text("Team Administration")
                .font(.obsidianCallout)
                .foregroundColor(Color.textPrimary)

            statRow("Sales reps", "\(activeSalesReps.count)")
            statRow("Technicians", "\(activeTechnicians.count)")
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

            Text("Lead review, dispatch, live locations, and daily work stay in Map, Leads, and Work. This screen only manages access and privacy.")
                .font(.obsidianFootnote)
                .foregroundColor(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func inviteCreationDisabled(for team: TeamWorkspace) -> Bool {
        activeMemberCount >= team.memberLimit
            || !team.effectivePlanStatus().allowsTeamWrite
            || !teamService.teamOperationsControl.teamWritesEnabled
            || !teamService.teamUsageControl.allowsCreate(in: TeamFirebaseSchema.Collection.members)
            || isWorking
            || teamService.isLoading
    }

    private func inviteWorkerTypeSelector(disabled: Bool) -> some View {
        HStack(spacing: 10) {
            inviteWorkerTypeButton(.salesRep, disabled: disabled)
            inviteWorkerTypeButton(.technician, disabled: disabled)
        }
        .padding(4)
        .background(Color.obsidianSurface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.obsidianBorder.opacity(0.55), lineWidth: 0.5)
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("teamInviteWorkerTypePicker")
    }

    private func inviteWorkerTypeButton(_ workType: TeamMemberWorkType, disabled: Bool) -> some View {
        let isSelected = pendingInviteWorkType == workType

        return Button {
            pendingInviteWorkType = workType
        } label: {
            Label(workType.title, systemImage: workType == .technician ? "wrench.and.screwdriver.fill" : "person.2.fill")
                .font(.obsidianFootnote)
                .fontWeight(.semibold)
                .foregroundColor(isSelected ? Color.obsidianBlack : Color.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
        }
        .buttonStyle(PlainButtonStyle())
        .frame(maxWidth: .infinity, minHeight: 48)
        .background(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(isSelected ? Color.statusNotHome : Color.clear)
        )
        .contentShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        .disabled(disabled)
        .opacity(disabled ? 0.55 : 1)
        .accessibilityIdentifier(workType == .technician ? "teamInviteWorkerTypeTechnicianButton" : "teamInviteWorkerTypeSalesRepButton")
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

    private func teamUsageSafeguardCard(_ control: TeamUsageControl) -> some View {
        let isLimited = !control.allowsWrite()
        let tint = isLimited ? Color.statusNotInterested : Color.statusNotHome

        return TeamInfoCard {
            Label(
                isLimited ? "Team updates paused briefly" : "Team usage is elevated",
                systemImage: isLimited ? "pause.circle.fill" : "gauge.with.dots.needle.67percent"
            )
            .font(.obsidianCallout)
            .foregroundColor(tint)

            Text(control.displayMessage)
                .font(.obsidianFootnote)
                .foregroundColor(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            ProgressView(value: max(control.dailyUsageFraction, control.velocityUsageFraction))
                .tint(tint)

            if !control.blockedCollections.isEmpty {
                Text("New \(usageCapacityLabels(control.blockedCollections)) are paused at the workspace capacity. Existing records can still be edited or removed.")
                    .font(.micro)
                    .foregroundColor(Color.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func usageCapacityLabels(_ collections: Set<String>) -> String {
        collections.sorted().map { collection in
            switch collection {
            case TeamFirebaseSchema.Collection.leads:
                return "leads"
            case TeamFirebaseSchema.Collection.bookings:
                return "bookings"
            case TeamFirebaseSchema.Collection.dutyLocationPoints:
                return "GPS route points"
            case TeamFirebaseSchema.Collection.activityLog:
                return "activity entries"
            case TeamFirebaseSchema.Collection.ownerNotifications:
                return "owner alerts"
            default:
                return "Team records"
            }
        }.joined(separator: ", ")
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
                ObsidianCompactIconButton(
                    icon: "xmark",
                    accessibilityLabel: "Cancel pending invite",
                    accentColor: Color.statusNotInterested,
                    size: 36
                ) {
                    cancelPendingInvite(member)
                }
                .disabled(isWorking || teamService.isLoading)
                .opacity(isWorking || teamService.isLoading ? 0.55 : 1)
            } else if let team = teamService.activeTeam,
                      let currentMember = teamService.currentMember,
                      TeamAccessPolicy.canRemoveMember(actor: currentMember, team: team, member: member) {
                ObsidianCompactIconButton(
                    icon: "person.crop.circle.badge.minus",
                    accessibilityLabel: "Remove \(member.displayName)",
                    accentColor: Color.statusNotInterested,
                    size: 36
                ) {
                    confirmRemoveMember(member)
                }
                .disabled(isWorking || teamService.isLoading)
                .opacity(isWorking || teamService.isLoading ? 0.55 : 1)
            } else {
                Text(memberStatusText(member))
                    .font(.micro)
                    .foregroundColor(memberStatusColor(member))
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
                    .submitLabel(.next)
                    .onSubmit { focusedInput = .accountPassword }
                    .teamTextField()
                    .accessibilityIdentifier("teamAccountEmailField")

                Text("Password")
                    .font(.micro)
                    .foregroundColor(Color.textMuted)
                TextField("Password", text: $teamAccountPassword)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focusedInput, equals: .accountPassword)
                    .submitLabel(isCreatingTeamAccount ? .next : .done)
                    .onSubmit {
                        focusedInput = isCreatingTeamAccount ? .accountDisplayName : nil
                    }
                    .teamTextField()
                    .accessibilityIdentifier("teamAccountPasswordField")

                if isCreatingTeamAccount {
                    Text("Name")
                        .font(.micro)
                        .foregroundColor(Color.textMuted)
                    TextField("Rep name", text: $teamAccountDisplayName)
                        .focused($focusedInput, equals: .accountDisplayName)
                        .submitLabel(.done)
                        .onSubmit { focusedInput = nil }
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
                        .submitLabel(.done)
                        .onSubmit { focusedInput = nil }
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
                        .submitLabel(.done)
                        .onSubmit { focusedInput = nil }
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
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.statusNotHome.opacity(0.10))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
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
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.obsidianElevated)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.obsidianBorder.opacity(0.45), lineWidth: 0.5)
                    )
            )
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

    private func teamSyncHealthCard(_ snapshot: TeamSyncHealthSnapshot) -> some View {
        TeamInfoCard {
            HStack(alignment: .center, spacing: 12) {
                ObsidianIconTile(
                    icon: teamSyncHealthIcon(snapshot.level),
                    tint: teamSyncHealthColor(snapshot.level),
                    size: 38
                )

                VStack(alignment: .leading, spacing: 3) {
                    Text(snapshot.title)
                        .font(.obsidianCallout)
                        .foregroundColor(Color.textPrimary)

                    Text(snapshot.detail)
                        .font(.obsidianFootnote)
                        .foregroundColor(Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                if let actionTitle = snapshot.actionTitle {
                    ObsidianCompactIconButton(
                        icon: "arrow.clockwise",
                        accessibilityLabel: actionTitle,
                        accentColor: Color.electricViolet,
                        backgroundColor: Color.electricViolet.opacity(0.12),
                        foregroundColor: Color.electricViolet,
                        borderColor: Color.electricViolet.opacity(0.2),
                        accessibilityIdentifier: "teamSyncHealthRefreshButton"
                    ) {
                        Task { await teamService.refreshTeamData() }
                    }
                }
            }
        }
    }

    private func teamSyncHealthColor(_ level: TeamSyncHealthLevel) -> Color {
        switch level {
        case .ready:
            return Color.statusInterested
        case .refreshing, .saving:
            return Color.statusNotHome
        case .offline:
            return Color.textSecondary
        case .blocked:
            return Color.statusNotInterested
        case .setup:
            return Color.electricViolet
        }
    }

    private func teamSyncHealthIcon(_ level: TeamSyncHealthLevel) -> String {
        switch level {
        case .ready:
            return "checkmark.seal.fill"
        case .refreshing:
            return "arrow.triangle.2.circlepath"
        case .saving:
            return "cloud.fill"
        case .offline:
            return "wifi.slash"
        case .blocked:
            return "exclamationmark.triangle.fill"
        case .setup:
            return "person.crop.circle.badge.checkmark"
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
                .frame(maxWidth: .infinity, minHeight: 50)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
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
        let canStartDuty = TeamAccessPolicy.canStartDutySession(planStatus: team.effectivePlanStatus(), role: member.role)
            && member.status == .active
            && teamService.teamOperationsControl.teamWritesEnabled
            && teamService.teamUsageControl.allowsWrite()
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
        guard canUseTeamWorkspace else { return nil }
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

    private var visibleTeamSyncHealthSnapshot: TeamSyncHealthSnapshot? {
        let snapshot = TeamSyncHealthPolicy.snapshot(
            isAuthenticated: canUseTeamWorkspace,
            hasActiveTeam: teamService.activeTeam != nil,
            hasCurrentMember: teamService.currentMember != nil,
            isLoading: teamService.isLoading && !shouldShowInitialLoadingCard,
            isWorking: isWorking,
            syncWriteState: teamService.syncWriteState,
            lastErrorMessage: teamService.lastErrorMessage,
            lastSuccessfulSyncAt: teamService.lastSuccessfulTeamSyncAt
        )

        guard let snapshot else { return nil }
        if isShowingTeamSetup && snapshot.level == .setup {
            return nil
        }
        if shouldShowInitialLoadingCard && snapshot.level == .refreshing {
            return nil
        }
        return snapshot
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

    private func createTeam() {
        guard !isWorking else { return }
        isWorking = true
        statusMessage = nil
        statusMessageIsError = false

        Task {
            do {
                try await teamService.createTeam(
                    name: teamName,
                    displayName: userAccountManager.currentUserDisplayName,
                    email: userAccountManager.currentUserEmail
                )
                statusMessage = "Team created."
                scrollResetToken += 1
            } catch TeamFirebaseServiceError.teamPlanRequired {
                paywallManager.showTeamPaywall()
            } catch {
                statusMessage = TeamFirebaseService.userFacingErrorMessage(for: error)
                statusMessageIsError = true
            }
            isWorking = false
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
        runTeamAction(successMessage: "Joined team.", scrollToTopOnSuccess: true) {
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

    private func runTeamAction(
        successMessage: String,
        scrollToTopOnSuccess: Bool = false,
        action: @escaping () async throws -> Void
    ) {
        isWorking = true
        statusMessage = nil
        statusMessageIsError = false

        Task {
            do {
                try await action()
                statusMessage = successMessage
                statusMessageIsError = false
                if scrollToTopOnSuccess {
                    scrollResetToken += 1
                }
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
            usageLevel: teamService.teamUsageControl.level,
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

    private func canUpdateMemberWorkType(_ member: TeamMember) -> Bool {
        guard let team = teamService.activeTeam,
              let currentMember = teamService.currentMember else { return false }
        return currentMember.role == .owner
            && currentMember.status == .active
            && team.effectivePlanStatus().allowsTeamWrite
            && teamService.teamOperationsControl.teamWritesEnabled
            && teamService.teamUsageControl.allowsWrite()
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
            teamInlineMenuIcon("person.text.rectangle.fill", tint: Color.electricViolet)
        }
        .accessibilityLabel("Change worker type")
    }

    private func teamInlineMenuIcon(_ icon: String, tint: Color) -> some View {
        Image(systemName: icon)
            .font(.obsidianCallout)
            .fontWeight(.semibold)
            .foregroundColor(tint)
            .frame(width: 44, height: 44)
            .background(tint.opacity(0.12))
            .clipShape(Circle())
            .overlay(
                Circle()
                    .stroke(tint.opacity(0.2), lineWidth: 0.5)
            )
    }

    private func memberStatusText(_ member: TeamMember) -> String {
        if member.isPendingInvite { return "Pending" }
        return member.status == .active ? "Active" : "Removed"
    }

    private func memberStatusColor(_ member: TeamMember) -> Color {
        if member.isPendingInvite { return Color.statusNotHome }
        return member.status == .active ? Color.statusInterested : Color.statusNotInterested
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
        case .leadStatusUpdated, .leadFollowUpRecorded, .repStatusReply, .bookingStatusUpdated:
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

    private func updateMemberWorkType(_ member: TeamMember, workType: TeamMemberWorkType) {
        runTeamAction(successMessage: "\(member.displayName) is now a \(workType.title).") {
            try await teamService.updateMemberWorkType(member, workType: workType)
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
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.obsidianElevated)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
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
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.obsidianSurface)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.obsidianBorder.opacity(0.55), lineWidth: 0.5)
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
