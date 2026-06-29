import Foundation
import CoreLocation
import FirebaseAuth
import FirebaseCore
import FirebaseFirestore

struct TeamCachedMembershipSnapshot: Codable {
    var team: TeamWorkspace
    var member: TeamMember
    var savedAt: Date

    func isFresh(now: Date = Date(), maxAge: TimeInterval) -> Bool {
        now.timeIntervalSince(savedAt) <= maxAge
    }
}

enum TeamCachedMembershipLocalStore {
    static func save(_ snapshot: TeamCachedMembershipSnapshot, to userDefaults: UserDefaults, key: String) throws {
        let data = try JSONEncoder().encode(snapshot)
        userDefaults.set(data, forKey: key)
    }

    static func loadSnapshot(from userDefaults: UserDefaults, key: String) throws -> TeamCachedMembershipSnapshot? {
        guard let data = userDefaults.data(forKey: key) else { return nil }
        return try JSONDecoder().decode(TeamCachedMembershipSnapshot.self, from: data)
    }

    static func loadFreshSnapshot(
        from userDefaults: UserDefaults,
        key: String,
        now: Date = Date(),
        maxAge: TimeInterval
    ) throws -> TeamCachedMembershipSnapshot? {
        guard let snapshot = try loadSnapshot(from: userDefaults, key: key) else { return nil }
        return snapshot.isFresh(now: now, maxAge: maxAge) ? snapshot : nil
    }
}

struct TeamCurrentTeamLoadRequest: Equatable {
    var displayName: String?
    var email: String?
}

enum TeamCurrentTeamLoadCoalescingPolicy {
    static func queuedRequest(
        current: TeamCurrentTeamLoadRequest?,
        incoming: TeamCurrentTeamLoadRequest
    ) -> TeamCurrentTeamLoadRequest {
        incoming
    }
}

enum TeamFirestoreMergePayloadValue {
    static func nullable<T>(_ value: T?) -> Any {
        value ?? NSNull()
    }

    static func omittedWhenNil<T>(_ value: T?) -> Any {
        value as Any
    }

    static func isNilOptional(_ value: Any) -> Bool {
        let mirror = Mirror(reflecting: value)
        return mirror.displayStyle == .optional && mirror.children.isEmpty
    }
}

enum TeamFirestoreRESTProbeLogPolicy {
    static func bodySnippet(_ body: String, maxLength: Int = 300) -> String {
        let normalized = body
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.count > maxLength else { return normalized }

        let endIndex = normalized.index(normalized.startIndex, offsetBy: maxLength)
        return String(normalized[..<endIndex]) + "..."
    }

    static func summary(label: String, statusCode: Int, body: String, publicProbe: Bool) -> String {
        var message = "\(label) status: \(statusCode)"
        if publicProbe, statusCode == 403 {
            message += " (expected if Firestore rules block public reads)"
        }

        let snippet = bodySnippet(body)
        if !snippet.isEmpty {
            message += " body: \(snippet)"
        }

        return message
    }
}

@MainActor
final class TeamFirebaseService: ObservableObject {
    static let shared = TeamFirebaseService()

    @Published private(set) var activeTeam: TeamWorkspace?
    @Published private(set) var currentMember: TeamMember?
    @Published private(set) var teamMembers: [TeamMember] = []
    @Published private(set) var teamLeads: [TeamLead] = []
    @Published private(set) var teamBookings: [TeamBooking] = []
    @Published private(set) var dutySessions: [TeamDutySession] = []
    @Published private(set) var dutyLocationPoints: [TeamDutyLocationPoint] = []
    @Published private(set) var ownerNotifications: [TeamOwnerNotification] = []
    @Published private(set) var activityLog: [TeamActivityLogEntry] = []
    @Published private(set) var activeDutySession: TeamDutySession?
    @Published private(set) var syncWriteState: TeamSyncWriteState = .idle
    @Published private(set) var isLoading = false
    @Published var lastErrorMessage: String?

    private static let cachedMembershipKey = "teamFirebase.cachedMembership.v1"
    private static let cachedMembershipMaxAge: TimeInterval = 14 * 24 * 60 * 60

    private let db: Firestore
    private var teamListenerRegistrations: [ListenerRegistration] = []
    private var hasPreparedFirestoreNetwork = false
    private var queuedCurrentTeamLoadRequest: TeamCurrentTeamLoadRequest?

    private init() {
        FirebaseBootstrap.configureIfNeeded()
        db = Firestore.firestore()
        FirebaseEmulatorConfiguration.applyIfNeeded(firestore: db)
        restoreCachedMembershipIfAvailable()
    }

    nonisolated static let removedTeamAccessMessage = "You no longer have access to this team. Ask the owner for a new invite if needed."
    nonisolated static let teamOfflineMessage = "Team is offline. Showing saved team data until the connection returns."
    nonisolated static let teamSetupOfflineMessage = "Team is offline. Connect to the internet to create or join a team."

    nonisolated static func userFacingErrorMessage(for error: Error) -> String {
        if isPermissionDeniedError(error) {
            return "Team permissions need updating. Refresh Team or sign in again."
        }
        if isOfflineError(error) {
            return teamOfflineMessage
        }
        return error.localizedDescription
    }

    nonisolated static func isStaleNoTeamSetupMessage(_ message: String) -> Bool {
        message.localizedCaseInsensitiveContains("team permissions need updating")
            || message.localizedCaseInsensitiveContains("no active team")
            || message.localizedCaseInsensitiveContains("missing or insufficient permissions")
    }

    nonisolated static func isPermissionDeniedError(_ error: Error) -> Bool {
        let message = error.localizedDescription
        return message.localizedCaseInsensitiveContains("Missing or insufficient permissions")
            || message.localizedCaseInsensitiveContains("permission_denied")
    }

    nonisolated static func isOfflineError(_ error: Error) -> Bool {
        let nsError = error as NSError
        let message = error.localizedDescription
        return nsError.domain == NSURLErrorDomain
            || message.localizedCaseInsensitiveContains("client is offline")
            || message.localizedCaseInsensitiveContains("connection appears to be offline")
            || message.localizedCaseInsensitiveContains("network connection was lost")
            || message.localizedCaseInsensitiveContains("not connected to the internet")
    }

    nonisolated static func shouldClearMemberSessionAfterPermissionError(
        error: Error,
        profileRole: TeamRole?,
        cachedRole: TeamRole?
    ) -> Bool {
        guard isPermissionDeniedError(error) else { return false }
        return profileRole == .member || cachedRole == .member
    }

    func clearStaleNoTeamSetupErrors() {
        if let lastErrorMessage,
           Self.isStaleNoTeamSetupMessage(lastErrorMessage) {
            self.lastErrorMessage = nil
        }

        if case .failed(let message) = syncWriteState,
           Self.isStaleNoTeamSetupMessage(message) {
            syncWriteState = .idle
        }
    }

    func loadCurrentTeam(displayName: String? = nil, email: String? = nil) async {
        let request = TeamCurrentTeamLoadRequest(displayName: displayName, email: email)
        guard !isLoading else {
            queuedCurrentTeamLoadRequest = TeamCurrentTeamLoadCoalescingPolicy.queuedRequest(
                current: queuedCurrentTeamLoadRequest,
                incoming: request
            )
            return
        }

        var requestToLoad: TeamCurrentTeamLoadRequest? = request
        while let currentRequest = requestToLoad {
            queuedCurrentTeamLoadRequest = nil
            await performCurrentTeamLoad(request: currentRequest)
            requestToLoad = queuedCurrentTeamLoadRequest
        }
    }

    private func performCurrentTeamLoad(request: TeamCurrentTeamLoadRequest) async {
        isLoading = true
        lastErrorMessage = nil
        defer { isLoading = false }

        do {
            try await prepareFirestoreForTeamUse(force: true)
            let user = try requireFirebaseUser()

            let profile = try await teamProfileRef(userId: user.uid).getDocument()
            guard let teamId = profile.data()?[TeamFirebaseSchema.Field.teamId] as? String,
                  !teamId.isEmpty else {
                clearLocalTeam(removeCachedMembership: true)
                return
            }
            let profileRole = (profile.data()?[TeamFirebaseSchema.Field.role] as? String)
                .flatMap(TeamRole.init(rawValue:))

            let team: TeamWorkspace
            let member: TeamMember
            do {
                team = try await loadTeam(teamId: teamId)
                member = try await loadMember(teamId: teamId, userId: user.uid)
            } catch {
                if Self.shouldClearMemberSessionAfterPermissionError(
                    error: error,
                    profileRole: profileRole,
                    cachedRole: currentMember?.role
                ) {
                    await handleRevokedTeamAccess(userId: user.uid)
                    return
                }
                throw error
            }

            guard member.status == .active else {
                await handleRevokedTeamAccess(userId: user.uid)
                return
            }

            stopTeamRealtimeListeners()
            activeTeam = team
            currentMember = member
            if member.role == .owner {
                teamMembers = await loadOptionalTeamValue(context: "members", fallback: teamMembers.isEmpty ? [member] : teamMembers) {
                    try await loadMembers(teamId: teamId)
                }
            } else {
                teamMembers = await loadOptionalTeamValue(context: "owner member", fallback: [member]) {
                    let owner = try await loadMember(teamId: teamId, userId: team.ownerUserId)
                    return TeamMemberRoster.normalized(owner.userId == member.userId ? [member] : [owner, member])
                }
            }
            teamLeads = await loadOptionalTeamValue(context: "team leads", fallback: teamLeads) {
                try await loadTeamLeads(team: team, member: member)
            }
            teamBookings = await loadOptionalTeamValue(context: "team bookings", fallback: teamBookings) {
                try await loadTeamBookings(team: team, member: member)
            }
            dutySessions = await loadOptionalTeamValue(context: "duty sessions", fallback: dutySessions) {
                try await loadDutySessions(team: team, member: member)
            }
            dutyLocationPoints = await loadOptionalTeamValue(context: "duty location points", fallback: dutyLocationPoints) {
                try await loadDutyLocationPoints(team: team, member: member)
            }
            if member.role == .owner {
                ownerNotifications = await loadOptionalTeamValue(context: "owner notifications", fallback: ownerNotifications) {
                    try await loadOwnerNotifications(team: team)
                }
            } else {
                ownerNotifications = []
            }
            activityLog = await loadOptionalTeamValue(context: "activity log", fallback: activityLog) {
                try await loadActivityLog(team: team, member: member)
            }
            updateActiveDutySession(for: member.userId)
            cacheMembership(team: team, member: member)
            startTeamRealtimeListeners(team: team, member: member)
        } catch TeamFirebaseServiceError.notAuthenticated {
            restoreCachedMembershipIfAvailable()
        } catch {
            if Self.isOfflineError(error), activeTeam != nil, currentMember != nil {
                hasPreparedFirestoreNetwork = false
                #if DEBUG
                await debugLogFirestoreRESTProbe()
                #endif
                print("⚠️ Team refresh failed while offline; keeping cached Team workspace visible.")
            } else {
                lastErrorMessage = Self.userFacingErrorMessage(for: error)
            }
        }
    }

    func createTeam(name: String, displayName: String?, email: String?) async throws {
        try await prepareFirestoreForTeamUse()
        let user = try await requireFreshFirebaseUser()

        let existingProfile = try await getServerDocument(teamProfileRef(userId: user.uid))
        if existingProfile.exists {
            throw TeamFirebaseServiceError.alreadyInTeam
        }

        let now = Date()
        let team = TeamWorkspace.newOwnerTeam(
            id: UUID().uuidString,
            name: Self.nilIfBlank(name) ?? "My Team",
            ownerUserId: user.uid,
            now: now
        )
        let owner = TeamMember.owner(
            teamId: team.id,
            userId: user.uid,
            displayName: Self.nilIfBlank(displayName) ?? Self.nilIfBlank(user.displayName) ?? "Team Owner",
            email: Self.nilIfBlank(email) ?? user.email,
            joinedAt: now
        )

        let batch = db.batch()
        batch.setData(teamData(team), forDocument: teamRef(team.id))
        batch.setData(memberData(owner, updatedAt: now), forDocument: memberRef(teamId: team.id, userId: user.uid))
        batch.setData(profileData(teamId: team.id, role: owner.role, updatedAt: now), forDocument: teamProfileRef(userId: user.uid), merge: true)
        addActivityLog(
            to: batch,
            teamId: team.id,
            actor: owner,
            kind: .teamCreated,
            subjectId: team.id,
            subjectTitle: team.name,
            targetUserId: owner.userId,
            createdAt: now
        )
        try await commitTeamBatch(batch, pendingWriteCount: 4, allowsLocalQueueFallback: false)

        activeTeam = team
        currentMember = owner
        teamMembers = [owner]
        teamLeads = []
        teamBookings = []
        dutySessions = []
        dutyLocationPoints = []
        ownerNotifications = []
        activityLog = []
        activeDutySession = nil
        syncWriteState = .idle
        cacheMembership(team: team, member: owner)
    }

    func createInvite(workType: TeamMemberWorkType = .salesRep) async throws -> TeamInvite {
        try await prepareFirestoreForTeamUse()
        let user = try await requireFreshFirebaseUser()
        guard let team = activeTeam, let member = currentMember else {
            throw TeamFirebaseServiceError.noActiveTeam
        }
        guard member.userId == user.uid, member.role == .owner else {
            throw TeamFirebaseServiceError.ownerOnly
        }
        guard team.planStatus.allowsTeamWrite else {
            throw TeamFirebaseServiceError.writeBlocked
        }
        guard teamMembers.filter({ $0.status == .active }).count < team.memberLimit else {
            throw TeamFirebaseServiceError.teamFull
        }

        let now = Date()
        let invite = TeamInvite(
            code: try await generateUniqueInviteCode(),
            teamId: team.id,
            expiresAt: now.addingTimeInterval(TeamFirebaseSchema.inviteExpirationInterval)
        )
        let pendingMember = TeamMember.rep(
            teamId: team.id,
            userId: "\(TeamFirebaseSchema.pendingRepUserPrefix)-\(invite.code)",
            displayName: "Pending Rep",
            email: nil,
            acceptedInviteId: invite.code,
            workType: workType,
            joinedAt: now
        )

        let batch = db.batch()
        batch.setData(inviteData(invite, team: team, createdByUserId: user.uid, createdAt: now), forDocument: inviteRef(invite.code))
        batch.setData(memberData(pendingMember, updatedAt: now), forDocument: memberRef(teamId: team.id, userId: pendingMember.userId))
        addActivityLog(
            to: batch,
            teamId: team.id,
            actor: member,
            kind: .inviteCreated,
            subjectId: invite.code,
            subjectTitle: "invite \(invite.displayCode)",
            targetUserId: pendingMember.userId,
            createdAt: now
        )
        try await commitTeamBatch(batch, pendingWriteCount: 3)

        teamMembers = TeamMemberRoster.upserting(pendingMember, into: teamMembers)
        return invite
    }

    func joinTeam(inviteCode: String, displayName: String?, email: String?) async throws {
        try await prepareFirestoreForTeamUse()
        let user = try await requireFreshFirebaseUser()
        let code = inviteCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !code.isEmpty else { throw TeamFirebaseServiceError.invalidInvite }

        let inviteSnapshot = try await inviteRef(code).getDocument()
        guard let inviteData = inviteSnapshot.data(),
              let teamId = inviteData[TeamFirebaseSchema.Field.teamId] as? String,
              let status = inviteData[TeamFirebaseSchema.Field.status] as? String,
              status == TeamFirebaseSchema.InviteStatus.pending,
              let expiresAt = Self.dateValue(inviteData[TeamFirebaseSchema.Field.expiresAt]),
              expiresAt > Date() else {
            throw TeamFirebaseServiceError.invalidInvite
        }
        let invitePlanStatus = (inviteData[TeamFirebaseSchema.Field.planStatus] as? String)
            .flatMap(TeamPlanStatus.init(rawValue:))
        guard invitePlanStatus?.allowsTeamWrite ?? true else {
            throw TeamFirebaseServiceError.writeBlocked
        }

        let existingProfile = try await teamProfileRef(userId: user.uid).getDocument()
        if existingProfile.exists {
            throw TeamFirebaseServiceError.alreadyInTeam
        }

        let now = Date()
        let pendingUserId = "\(TeamFirebaseSchema.pendingRepUserPrefix)-\(code)"
        let pendingMemberSnapshot = try? await memberRef(teamId: teamId, userId: pendingUserId).getDocument()
        let pendingMember = pendingMemberSnapshot
            .flatMap { snapshot in snapshot.data().flatMap { decodeMember(id: snapshot.documentID, data: $0) } }
        let member = TeamMember.rep(
            teamId: teamId,
            userId: user.uid,
            displayName: Self.nilIfBlank(displayName) ?? Self.nilIfBlank(user.displayName) ?? "Team Rep",
            email: Self.nilIfBlank(email) ?? user.email,
            acceptedInviteId: code,
            workType: pendingMember?.workType ?? .salesRep,
            joinedAt: now
        )

        let batch = db.batch()
        batch.deleteDocument(memberRef(teamId: teamId, userId: pendingUserId))
        batch.setData(memberData(member, updatedAt: now), forDocument: memberRef(teamId: teamId, userId: user.uid))
        batch.setData([
            TeamFirebaseSchema.Field.status: TeamFirebaseSchema.InviteStatus.accepted,
            TeamFirebaseSchema.Field.acceptedByUserId: user.uid,
            TeamFirebaseSchema.Field.acceptedAt: Timestamp(date: now)
        ], forDocument: inviteRef(code), merge: true)
        batch.setData(profileData(teamId: teamId, role: member.role, updatedAt: now), forDocument: teamProfileRef(userId: user.uid), merge: true)
        addActivityLog(
            to: batch,
            teamId: teamId,
            actor: member,
            kind: .inviteAccepted,
            subjectId: code,
            subjectTitle: "invite accepted",
            targetUserId: member.userId,
            createdAt: now
        )
        try await commitTeamBatch(batch, pendingWriteCount: 5)

        await loadCurrentTeam(displayName: displayName, email: email)
    }

    func cancelPendingInvite(for member: TeamMember) async throws {
        try await prepareFirestoreForTeamUse()
        let user = try requireFirebaseUser()
        guard let currentMember, currentMember.userId == user.uid else {
            throw TeamFirebaseServiceError.noActiveTeam
        }
        guard TeamAccessPolicy.canCancelPendingInvite(role: currentMember.role, member: member) else {
            throw TeamFirebaseServiceError.ownerOnly
        }
        guard activeTeam?.planStatus.allowsTeamWrite == true else {
            throw TeamFirebaseServiceError.writeBlocked
        }
        guard let inviteId = member.acceptedInviteId else {
            throw TeamFirebaseServiceError.invalidInvite
        }

        let now = Date()
        let batch = db.batch()
        batch.setData([
            TeamFirebaseSchema.Field.status: TeamFirebaseSchema.InviteStatus.cancelled,
            TeamFirebaseSchema.Field.updatedAt: Timestamp(date: now)
        ], forDocument: inviteRef(inviteId), merge: true)
        batch.deleteDocument(memberRef(teamId: member.teamId, userId: member.userId))
        addActivityLog(
            to: batch,
            teamId: member.teamId,
            actor: currentMember,
            kind: .inviteCancelled,
            subjectId: inviteId,
            subjectTitle: "invite \(inviteId.uppercased())",
            targetUserId: member.userId,
            createdAt: now
        )
        try await commitTeamBatch(batch, pendingWriteCount: 3)

        teamMembers.removeAll { $0.id == member.id }
    }

    func refreshTeamData() async {
        await loadCurrentTeam()
    }

    @discardableResult
    func createRepLead(
        name: String,
        address: String,
        phone: String? = nil,
        email: String? = nil,
        coordinate: TeamCoordinate,
        status: TeamLeadStatus = .notContacted,
        notes: String = "",
        serviceCategory: String? = nil,
        price: Double = 0,
        estimatedValue: Double = 0,
        isHighPriority: Bool = false,
        highPriorityReason: String? = nil,
        now: Date = Date()
    ) async throws -> TeamLead {
        try await prepareFirestoreForTeamUse()
        let user = try requireFirebaseUser()
        guard let team = activeTeam, let member = currentMember else {
            throw TeamFirebaseServiceError.noActiveTeam
        }

        var lead = TeamLead.newRepLead(
            teamId: team.id,
            creatorUserId: user.uid,
            name: Self.nilIfBlank(name) ?? "New Lead",
            address: Self.nilIfBlank(address) ?? "No address",
            coordinate: coordinate,
            now: now
        )
        lead.phone = Self.nilIfBlank(phone)
        lead.email = Self.nilIfBlank(email)
        lead.status = status
        lead.notes = notes
        lead.serviceCategory = Self.nilIfBlank(serviceCategory)
        lead.price = price
        lead.estimatedValue = estimatedValue
        lead.isHighPriority = isHighPriority
        lead.highPriorityReason = Self.nilIfBlank(highPriorityReason)

        guard TeamAccessPolicy.canCreateRepLead(
            userId: user.uid,
            role: member.role,
            planStatus: team.planStatus,
            assignedToUserId: lead.assignedToUserId
        ) else {
            throw TeamFirebaseServiceError.writeBlocked
        }

        let events = TeamNotificationPolicy.ownerLeadEvents(before: nil, after: lead)
        let batch = db.batch()
        batch.setData(leadData(lead), forDocument: leadRef(teamId: team.id, leadId: lead.id))
        addOwnerNotifications(to: batch, team: team, lead: lead, events: events, createdAt: now)
        addActivityLog(
            to: batch,
            teamId: team.id,
            actor: member,
            kind: .leadCreated,
            subjectId: lead.id,
            subjectTitle: lead.name,
            targetUserId: lead.assignedToUserId,
            createdAt: now
        )
        try await commitTeamBatch(batch, pendingWriteCount: events.count + 2)

        teamLeads.removeAll { $0.id == lead.id }
        teamLeads.append(lead)
        return lead
    }

    @discardableResult
    func createOwnerTechnicianJobLead(
        name: String,
        address: String,
        phone: String? = nil,
        email: String? = nil,
        coordinate: TeamCoordinate,
        notes: String = "",
        serviceCategory: String? = nil,
        price: Double = 0,
        technician: TeamMember,
        startDate: Date,
        endDate: Date,
        now: Date = Date()
    ) async throws -> TeamBooking {
        try await prepareFirestoreForTeamUse()
        let user = try requireFirebaseUser()
        guard let team = activeTeam, let member = currentMember, member.userId == user.uid else {
            throw TeamFirebaseServiceError.noActiveTeam
        }

        var lead = TeamLead.newRepLead(
            teamId: team.id,
            creatorUserId: user.uid,
            name: Self.nilIfBlank(name) ?? "New Lead",
            address: Self.nilIfBlank(address) ?? "No address",
            coordinate: coordinate,
            now: now
        )
        lead.phone = Self.nilIfBlank(phone)
        lead.email = Self.nilIfBlank(email)
        lead.status = .converted
        lead.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        lead.serviceCategory = Self.nilIfBlank(serviceCategory)
        lead.price = max(0, price)
        lead.estimatedValue = max(0, price)
        lead.assignedToUserId = member.userId
        lead.createdByUserId = member.userId
        lead.updatedByUserId = member.userId

        guard TeamLeadDispatchPolicy.canDispatchLeadToTechnician(
            actor: member,
            team: team,
            technician: technician,
            lead: lead
        ) else {
            throw TeamFirebaseServiceError.writeBlocked
        }

        let booking = TeamLeadDispatchPolicy.booking(
            from: lead,
            to: technician,
            by: member,
            startDate: startDate,
            endDate: endDate,
            now: now
        )

        let batch = db.batch()
        batch.setData(leadData(lead), forDocument: leadRef(teamId: team.id, leadId: lead.id))
        batch.setData(bookingData(booking), forDocument: bookingRef(teamId: team.id, bookingId: booking.id), merge: true)
        addActivityLog(
            to: batch,
            teamId: team.id,
            actor: member,
            kind: .leadCreated,
            subjectId: lead.id,
            subjectTitle: lead.name,
            targetUserId: member.userId,
            createdAt: now
        )
        addActivityLog(
            to: batch,
            teamId: team.id,
            actor: member,
            kind: .bookingAssigned,
            subjectId: booking.id,
            subjectTitle: booking.title,
            targetUserId: technician.userId,
            createdAt: now
        )
        try await commitTeamBatch(batch, pendingWriteCount: 4)

        teamLeads.removeAll { $0.id == lead.id }
        teamLeads.append(lead)
        if let bookingIndex = teamBookings.firstIndex(where: { $0.id == booking.id }) {
            teamBookings[bookingIndex] = booking
        } else {
            teamBookings.append(booking)
        }
        return booking
    }

    @discardableResult
    func updateTeamLead(
        leadId: String,
        status: TeamLeadStatus? = nil,
        isHighPriority: Bool? = nil,
        highPriorityReason: String? = nil,
        repStatusNote: String? = nil,
        editableFields: TeamLeadEditableFields? = nil,
        now: Date = Date()
    ) async throws -> TeamLead {
        try await prepareFirestoreForTeamUse()
        let user = try requireFirebaseUser()
        guard let team = activeTeam, let member = currentMember else {
            throw TeamFirebaseServiceError.noActiveTeam
        }

        let snapshot = try await leadRef(teamId: team.id, leadId: leadId).getDocument()
        guard let data = snapshot.data(), let before = decodeLead(id: snapshot.documentID, data: data) else {
            throw TeamFirebaseServiceError.noActiveTeam
        }
        guard TeamAccessPolicy.canWriteAssignedRecord(
            userId: user.uid,
            role: member.role,
            planStatus: team.planStatus,
            assignedToUserId: before.assignedToUserId
        ) else {
            throw TeamFirebaseServiceError.writeBlocked
        }

        var after = before
        if let status {
            after.status = status
        }
        if let isHighPriority {
            after.isHighPriority = isHighPriority
        }
        if let highPriorityReason {
            after.highPriorityReason = Self.nilIfBlank(highPriorityReason)
        }
        if let repStatusNote {
            after.notes = Self.nilIfBlank(repStatusNote) ?? after.notes
        }
        if let editableFields {
            after = editableFields.applying(to: after, updatedByUserId: user.uid, now: now)
        }
        after.updatedByUserId = user.uid
        after.updatedAt = now

        let events = TeamNotificationPolicy.ownerLeadEvents(before: before, after: after)
        let batch = db.batch()
        batch.setData(leadData(after), forDocument: leadRef(teamId: team.id, leadId: leadId), merge: true)
        addOwnerNotifications(to: batch, team: team, lead: after, events: events, createdAt: now)
        if before.status != after.status {
            addActivityLog(
                to: batch,
                teamId: team.id,
                actor: member,
                kind: .leadStatusUpdated,
                subjectId: after.id,
                subjectTitle: after.name,
                targetUserId: after.assignedToUserId,
                createdAt: now
            )
        }
        if before.isHighPriority != true && after.isHighPriority {
            addActivityLog(
                to: batch,
                teamId: team.id,
                actor: member,
                kind: .leadHighPriority,
                subjectId: after.id,
                subjectTitle: after.name,
                targetUserId: after.assignedToUserId,
                createdAt: now
            )
        }
        if repStatusNote != nil {
            addActivityLog(
                to: batch,
                teamId: team.id,
                actor: member,
                kind: .repStatusReply,
                subjectId: after.id,
                subjectTitle: after.name,
                targetUserId: after.assignedToUserId,
                createdAt: now
            )
        }
        if editableFields != nil {
            addActivityLog(
                to: batch,
                teamId: team.id,
                actor: member,
                kind: .leadStatusUpdated,
                subjectId: after.id,
                subjectTitle: "\(after.name) details",
                targetUserId: after.assignedToUserId,
                createdAt: now
            )
        }
        try await commitTeamBatch(batch, pendingWriteCount: events.count + 1)

        if let index = teamLeads.firstIndex(where: { $0.id == after.id }) {
            teamLeads[index] = after
        } else {
            teamLeads.append(after)
        }
        return after
    }

    @discardableResult
    func assignTeamLead(_ lead: TeamLead, to target: TeamMember, now: Date = Date()) async throws -> TeamLead {
        try await prepareFirestoreForTeamUse()
        let user = try requireFirebaseUser()
        guard let team = activeTeam, let member = currentMember, member.userId == user.uid else {
            throw TeamFirebaseServiceError.noActiveTeam
        }

        let snapshot = try await leadRef(teamId: team.id, leadId: lead.id).getDocument()
        guard let data = snapshot.data(), let before = decodeLead(id: snapshot.documentID, data: data) else {
            throw TeamFirebaseServiceError.noActiveTeam
        }
        guard TeamAssignmentPolicy.canAssignLead(actor: member, team: team, target: target, lead: before) else {
            throw TeamFirebaseServiceError.writeBlocked
        }

        let after = TeamAssignmentPolicy.assign(before, to: target, by: member, now: now)
        let batch = db.batch()
        batch.setData(leadData(after), forDocument: leadRef(teamId: team.id, leadId: lead.id), merge: true)
        addActivityLog(
            to: batch,
            teamId: team.id,
            actor: member,
            kind: .leadAssigned,
            subjectId: after.id,
            subjectTitle: after.name,
            targetUserId: target.userId,
            createdAt: now
        )
        try await commitTeamBatch(batch, pendingWriteCount: 2)

        if let index = teamLeads.firstIndex(where: { $0.id == after.id }) {
            teamLeads[index] = after
        }
        return after
    }

    @discardableResult
    func dispatchTeamLeadToTechnicianJob(
        lead: TeamLead,
        technician: TeamMember,
        startDate: Date,
        endDate: Date,
        now: Date = Date()
    ) async throws -> TeamBooking {
        try await prepareFirestoreForTeamUse()
        let user = try requireFirebaseUser()
        guard let team = activeTeam, let member = currentMember, member.userId == user.uid else {
            throw TeamFirebaseServiceError.noActiveTeam
        }

        let snapshot = try await leadRef(teamId: team.id, leadId: lead.id).getDocument()
        guard let data = snapshot.data(), let before = decodeLead(id: snapshot.documentID, data: data) else {
            throw TeamFirebaseServiceError.noActiveTeam
        }
        guard TeamLeadDispatchPolicy.canDispatchLeadToTechnician(
            actor: member,
            team: team,
            technician: technician,
            lead: before
        ) else {
            throw TeamFirebaseServiceError.writeBlocked
        }

        let soldLead = TeamLeadDispatchPolicy.soldLead(before, by: member, now: now)
        let booking = TeamLeadDispatchPolicy.booking(
            from: soldLead,
            to: technician,
            by: member,
            startDate: startDate,
            endDate: endDate,
            now: now
        )
        let events = TeamNotificationPolicy.ownerLeadEvents(before: before, after: soldLead)

        let batch = db.batch()
        batch.setData(leadData(soldLead), forDocument: leadRef(teamId: team.id, leadId: soldLead.id), merge: true)
        batch.setData(bookingData(booking), forDocument: bookingRef(teamId: team.id, bookingId: booking.id), merge: true)
        addOwnerNotifications(to: batch, team: team, lead: soldLead, events: events, createdAt: now)
        if before.status != soldLead.status {
            addActivityLog(
                to: batch,
                teamId: team.id,
                actor: member,
                kind: .leadStatusUpdated,
                subjectId: soldLead.id,
                subjectTitle: soldLead.name,
                targetUserId: soldLead.assignedToUserId,
                createdAt: now
            )
        }
        addActivityLog(
            to: batch,
            teamId: team.id,
            actor: member,
            kind: .bookingAssigned,
            subjectId: booking.id,
            subjectTitle: booking.title,
            targetUserId: technician.userId,
            createdAt: now
        )
        try await commitTeamBatch(batch, pendingWriteCount: events.count + 3)

        if let leadIndex = teamLeads.firstIndex(where: { $0.id == soldLead.id }) {
            teamLeads[leadIndex] = soldLead
        } else {
            teamLeads.append(soldLead)
        }
        if let bookingIndex = teamBookings.firstIndex(where: { $0.id == booking.id }) {
            teamBookings[bookingIndex] = booking
        } else {
            teamBookings.append(booking)
        }
        return booking
    }

    @discardableResult
    func assignTeamBooking(_ booking: TeamBooking, to target: TeamMember, now: Date = Date()) async throws -> TeamBooking {
        try await prepareFirestoreForTeamUse()
        let user = try requireFirebaseUser()
        guard let team = activeTeam, let member = currentMember, member.userId == user.uid else {
            throw TeamFirebaseServiceError.noActiveTeam
        }

        let snapshot = try await bookingRef(teamId: team.id, bookingId: booking.id).getDocument()
        guard let data = snapshot.data(), let before = decodeBooking(id: snapshot.documentID, data: data) else {
            throw TeamFirebaseServiceError.noActiveTeam
        }
        guard TeamAssignmentPolicy.canAssignBooking(actor: member, team: team, target: target, booking: before) else {
            throw TeamFirebaseServiceError.writeBlocked
        }

        let after = TeamAssignmentPolicy.assign(before, to: target, by: member, now: now)
        let batch = db.batch()
        batch.setData(bookingData(after), forDocument: bookingRef(teamId: team.id, bookingId: booking.id), merge: true)
        addActivityLog(
            to: batch,
            teamId: team.id,
            actor: member,
            kind: .bookingAssigned,
            subjectId: after.id,
            subjectTitle: after.title,
            targetUserId: target.userId,
            createdAt: now
        )
        try await commitTeamBatch(batch, pendingWriteCount: 2)

        if let index = teamBookings.firstIndex(where: { $0.id == after.id }) {
            teamBookings[index] = after
        }
        return after
    }

    @discardableResult
    func sendAppointmentToTeamBooking(_ appointment: Appointment, to target: TeamMember, now: Date = Date()) async throws -> TeamBooking {
        try await prepareFirestoreForTeamUse()
        let user = try requireFirebaseUser()
        guard let team = activeTeam, let member = currentMember, member.userId == user.uid else {
            throw TeamFirebaseServiceError.noActiveTeam
        }

        let booking = TeamBooking(
            id: appointment.id.uuidString,
            teamId: team.id,
            leadId: appointment.leadId?.uuidString ?? appointment.id.uuidString,
            assignedToUserId: target.userId,
            title: Self.nilIfBlank(appointment.title) ?? "Scheduled Job",
            notes: appointment.notes,
            startDate: appointment.startDate,
            endDate: appointment.endDate,
            location: Self.nilIfBlank(appointment.location) ?? "No location",
            status: bookingStatus(for: appointment.status),
            createdByUserId: member.userId,
            updatedByUserId: member.userId,
            createdAt: now,
            updatedAt: now
        )
        guard TeamAssignmentPolicy.canAssignBooking(actor: member, team: team, target: target, booking: booking) else {
            throw TeamFirebaseServiceError.writeBlocked
        }

        let batch = db.batch()
        batch.setData(bookingData(booking), forDocument: bookingRef(teamId: team.id, bookingId: booking.id), merge: true)
        addActivityLog(
            to: batch,
            teamId: team.id,
            actor: member,
            kind: .bookingAssigned,
            subjectId: booking.id,
            subjectTitle: booking.title,
            targetUserId: target.userId,
            createdAt: now
        )
        try await commitTeamBatch(batch, pendingWriteCount: 2)

        if let index = teamBookings.firstIndex(where: { $0.id == booking.id }) {
            teamBookings[index] = booking
        } else {
            teamBookings.append(booking)
        }
        return booking
    }

    @discardableResult
    func updateTeamBookingStatus(_ booking: TeamBooking, status: TeamBookingStatus, now: Date = Date()) async throws -> TeamBooking {
        try await prepareFirestoreForTeamUse()
        let user = try requireFirebaseUser()
        guard let team = activeTeam, let member = currentMember, member.userId == user.uid else {
            throw TeamFirebaseServiceError.noActiveTeam
        }

        let snapshot = try await bookingRef(teamId: team.id, bookingId: booking.id).getDocument()
        guard let data = snapshot.data(), var updated = decodeBooking(id: snapshot.documentID, data: data) else {
            throw TeamFirebaseServiceError.noActiveTeam
        }
        guard TeamAccessPolicy.canWriteAssignedRecord(
            userId: user.uid,
            role: member.role,
            planStatus: team.planStatus,
            assignedToUserId: updated.assignedToUserId
        ) else {
            throw TeamFirebaseServiceError.writeBlocked
        }

        updated.status = status
        updated.updatedByUserId = member.userId
        updated.updatedAt = now

        let batch = db.batch()
        batch.setData(bookingData(updated), forDocument: bookingRef(teamId: team.id, bookingId: booking.id), merge: true)
        addActivityLog(
            to: batch,
            teamId: team.id,
            actor: member,
            kind: .bookingStatusUpdated,
            subjectId: updated.id,
            subjectTitle: "\(updated.title) \(status.displayName.lowercased())",
            targetUserId: updated.assignedToUserId,
            createdAt: now
        )
        try await commitTeamBatch(batch, pendingWriteCount: 2)

        if let index = teamBookings.firstIndex(where: { $0.id == updated.id }) {
            teamBookings[index] = updated
        } else {
            teamBookings.append(updated)
        }
        return updated
    }

    @discardableResult
    func submitRepStatusReply(
        lead: TeamLead,
        status: OwnerInstructionStatus,
        note: String?,
        now: Date = Date()
    ) async throws -> TeamLead {
        try await prepareFirestoreForTeamUse()
        let user = try requireFirebaseUser()
        guard let team = activeTeam, let member = currentMember, member.userId == user.uid else {
            throw TeamFirebaseServiceError.noActiveTeam
        }
        guard TeamRepReplyPolicy.canReply(
            userId: user.uid,
            role: member.role,
            planStatus: team.planStatus,
            assignedToUserId: lead.assignedToUserId
        ) else {
            throw TeamFirebaseServiceError.writeBlocked
        }

        let cleanNote = TeamRepReplyPolicy.sanitizedNote(note) ?? repReplyTitle(status)
        let mappedStatus = leadStatus(for: status)
        let snapshot = try await leadRef(teamId: team.id, leadId: lead.id).getDocument()
        guard let data = snapshot.data(), let before = decodeLead(id: snapshot.documentID, data: data) else {
            throw TeamFirebaseServiceError.noActiveTeam
        }

        var after = before
        if let mappedStatus {
            after.status = mappedStatus
        }
        after.notes = cleanNote
        after.updatedByUserId = user.uid
        after.updatedAt = now

        let events = TeamNotificationPolicy.ownerLeadEvents(before: before, after: after)
        let batch = db.batch()
        batch.setData(leadData(after), forDocument: leadRef(teamId: team.id, leadId: lead.id), merge: true)
        addOwnerNotifications(to: batch, team: team, lead: after, events: events, createdAt: now)
        addActivityLog(
            to: batch,
            teamId: team.id,
            actor: member,
            kind: .repStatusReply,
            subjectId: after.id,
            subjectTitle: cleanNote,
            targetUserId: member.userId,
            createdAt: now
        )
        try await commitTeamBatch(batch, pendingWriteCount: events.count + 2)

        if let index = teamLeads.firstIndex(where: { $0.id == after.id }) {
            teamLeads[index] = after
        }
        return after
    }

    func markOwnerNotificationRead(_ notification: TeamOwnerNotification, now: Date = Date()) async throws {
        try await prepareFirestoreForTeamUse()
        let user = try requireFirebaseUser()
        guard let team = activeTeam, let member = currentMember, member.userId == user.uid, member.role == .owner else {
            throw TeamFirebaseServiceError.ownerOnly
        }
        guard team.planStatus.allowsTeamWrite else {
            throw TeamFirebaseServiceError.writeBlocked
        }

        let read = TeamOwnerNotification.markedRead(notification, at: now)
        try await setTeamData([
            TeamFirebaseSchema.Field.readAt: Timestamp(date: now)
        ], forDocument: ownerNotificationRef(teamId: team.id, notificationId: notification.id), merge: true)

        let activityLogBatch = db.batch()
        addActivityLog(
            to: activityLogBatch,
            teamId: team.id,
            actor: member,
            kind: .ownerAlertRead,
            subjectId: notification.id,
            subjectTitle: notification.title,
            targetUserId: notification.assignedToUserId,
            createdAt: now
        )
        commitOptionalTeamBatch(activityLogBatch, context: "owner alert read activity log")

        if let index = ownerNotifications.firstIndex(where: { $0.id == read.id }) {
            ownerNotifications[index] = read
        }
    }

    func removeMember(_ memberToRemove: TeamMember, now: Date = Date()) async throws {
        try await prepareFirestoreForTeamUse()
        let user = try requireFirebaseUser()
        guard let team = activeTeam, let member = currentMember, member.userId == user.uid else {
            throw TeamFirebaseServiceError.noActiveTeam
        }
        guard TeamAccessPolicy.canRemoveMember(actor: member, team: team, member: memberToRemove) else {
            throw TeamFirebaseServiceError.writeBlocked
        }

        let removed = TeamMember.removed(memberToRemove, removedAt: now)
        let batch = db.batch()
        batch.setData(memberData(removed, updatedAt: now), forDocument: memberRef(teamId: team.id, userId: memberToRemove.userId), merge: true)
        addActivityLog(
            to: batch,
            teamId: team.id,
            actor: member,
            kind: .memberRemoved,
            subjectId: memberToRemove.userId,
            subjectTitle: memberToRemove.displayName,
            targetUserId: memberToRemove.userId,
            createdAt: now
        )
        try await commitTeamBatch(batch, pendingWriteCount: 2)

        if let index = teamMembers.firstIndex(where: { $0.id == removed.id }) {
            teamMembers[index] = removed
        }
    }

    func leaveCurrentTeam(now: Date = Date()) async throws {
        try await prepareFirestoreForTeamUse()
        let user = try requireFirebaseUser()
        guard let team = activeTeam, let member = currentMember, member.userId == user.uid else {
            throw TeamFirebaseServiceError.noActiveTeam
        }
        guard TeamAccessPolicy.canLeaveTeam(member: member, team: team) else {
            throw TeamFirebaseServiceError.writeBlocked
        }

        let removed = TeamMember.removed(member, removedAt: now)
        let batch = db.batch()
        var pendingWriteCount = 3

        if let session = activeDutySession, session.repUserId == user.uid {
            let ended = TeamDutySession.ended(
                id: session.id,
                teamId: session.teamId,
                repUserId: session.repUserId,
                startedAt: session.startedAt,
                endedAt: now,
                distanceMeters: session.distanceMeters
            )
            batch.setData(
                dutySessionData(ended),
                forDocument: dutySessionRef(teamId: session.teamId, sessionId: session.id),
                merge: true
            )
            pendingWriteCount += 1
        }

        batch.setData(memberData(removed, updatedAt: now), forDocument: memberRef(teamId: team.id, userId: member.userId), merge: true)
        batch.deleteDocument(teamProfileRef(userId: user.uid))
        addActivityLog(
            to: batch,
            teamId: team.id,
            actor: member,
            kind: .memberLeft,
            subjectId: member.userId,
            subjectTitle: team.name,
            targetUserId: member.userId,
            createdAt: now
        )
        try await commitTeamBatch(batch, pendingWriteCount: pendingWriteCount)

        clearLocalTeam(removeCachedMembership: true)
    }

    func closeCurrentTeam(now: Date = Date()) async throws {
        try await prepareFirestoreForTeamUse()
        let user = try requireFirebaseUser()
        guard var team = activeTeam, let member = currentMember, member.userId == user.uid else {
            throw TeamFirebaseServiceError.noActiveTeam
        }
        guard TeamAccessPolicy.canCloseTeam(owner: member, team: team) else {
            throw TeamFirebaseServiceError.writeBlocked
        }

        let members = try await loadMembers(teamId: team.id)
        team.planStatus = .paused
        team.updatedAt = now

        let batch = db.batch()
        var pendingWriteCount = 3

        batch.setData(teamData(team), forDocument: teamRef(team.id), merge: true)
        batch.deleteDocument(teamProfileRef(userId: user.uid))

        for teamMember in members {
            let removed = TeamMember.removed(teamMember, removedAt: now)
            batch.setData(memberData(removed, updatedAt: now), forDocument: memberRef(teamId: team.id, userId: teamMember.userId), merge: true)
            pendingWriteCount += 1

            if teamMember.isPendingInvite, let inviteCode = teamMember.acceptedInviteId {
                batch.deleteDocument(inviteRef(inviteCode))
                pendingWriteCount += 1
            }
        }

        var activeSessionsById = Dictionary(
            uniqueKeysWithValues: dutySessions
                .filter { $0.teamId == team.id && $0.status == .active }
                .map { ($0.id, $0) }
        )
        if let activeDutySession,
           activeDutySession.teamId == team.id,
           activeDutySession.status == .active {
            activeSessionsById[activeDutySession.id] = activeDutySession
        }

        for session in activeSessionsById.values {
            let ended = TeamDutySession.ended(
                id: session.id,
                teamId: session.teamId,
                repUserId: session.repUserId,
                startedAt: session.startedAt,
                endedAt: now,
                distanceMeters: session.distanceMeters
            )
            batch.setData(
                dutySessionData(ended),
                forDocument: dutySessionRef(teamId: session.teamId, sessionId: session.id),
                merge: true
            )
            pendingWriteCount += 1
        }

        addActivityLog(
            to: batch,
            teamId: team.id,
            actor: member,
            kind: .teamClosed,
            subjectId: team.id,
            subjectTitle: team.name,
            targetUserId: member.userId,
            createdAt: now
        )
        try await commitTeamBatch(batch, pendingWriteCount: pendingWriteCount)

        clearLocalTeam(removeCachedMembership: true)
    }

    func updateMemberWorkType(_ memberToUpdate: TeamMember, workType: TeamMemberWorkType, now: Date = Date()) async throws {
        try await prepareFirestoreForTeamUse()
        let user = try requireFirebaseUser()
        guard let team = activeTeam, let member = currentMember, member.userId == user.uid else {
            throw TeamFirebaseServiceError.noActiveTeam
        }
        guard member.role == .owner,
              member.status == .active,
              memberToUpdate.role == .member,
              memberToUpdate.status == .active,
              !memberToUpdate.isPendingInvite,
              team.planStatus.allowsTeamWrite else {
            throw TeamFirebaseServiceError.writeBlocked
        }

        var updated = memberToUpdate
        updated.workType = workType
        try await setTeamData(memberData(updated, updatedAt: now), forDocument: memberRef(teamId: team.id, userId: memberToUpdate.userId), merge: true)

        if let index = teamMembers.firstIndex(where: { $0.id == updated.id }) {
            teamMembers[index] = updated
        }
    }

    func duplicateCandidates(for lead: TeamLead) -> [TeamDuplicateLeadCandidate] {
        TeamDuplicateLeadDetector.candidates(for: lead, existingLeads: teamLeads)
    }

    func duplicateLeadWarnings() -> [TeamDuplicateLeadWarning] {
        TeamDuplicateLeadDetector.warnings(for: teamLeads)
    }

    func todayWorkSummary(now: Date = Date()) -> TeamTodayWorkSummary? {
        guard let currentMember else { return nil }
        return TeamTodayWorkSummary.make(
            currentMember: currentMember,
            leads: teamLeads,
            bookings: teamBookings,
            dutySessions: dutySessions,
            now: now
        )
    }

    func startDuty(member: TeamMember, now: Date = Date()) async throws {
        try await prepareFirestoreForTeamUse()
        let user = try requireFirebaseUser()
        guard let team = activeTeam else { throw TeamFirebaseServiceError.noActiveTeam }
        guard user.uid == member.userId else { throw TeamFirebaseServiceError.noActiveTeam }
        guard TeamAccessPolicy.canStartDutySession(planStatus: team.planStatus, role: member.role) else {
            throw TeamFirebaseServiceError.writeBlocked
        }

        let session = TeamDutySession(
            id: UUID().uuidString,
            teamId: team.id,
            repUserId: member.userId,
            startedAt: now,
            endedAt: nil,
            status: .active,
            lastLocationAt: nil,
            distanceMeters: 0,
            createdAt: now,
            deleteAfter: nil
        )

        let batch = db.batch()
        batch.setData(dutySessionData(session), forDocument: dutySessionRef(teamId: team.id, sessionId: session.id), merge: true)
        addActivityLog(
            to: batch,
            teamId: team.id,
            actor: member,
            kind: .dutyStarted,
            subjectId: session.id,
            subjectTitle: "duty",
            targetUserId: member.userId,
            createdAt: now
        )
        try await commitTeamBatch(batch, pendingWriteCount: 2)
        activeDutySession = session
        dutySessions.append(session)
    }

    func recordCurrentLocation(_ location: CLLocation, member: TeamMember, now: Date = Date()) async throws {
        try await prepareFirestoreForTeamUse()
        let user = try requireFirebaseUser()
        guard let team = activeTeam, var session = activeDutySession else {
            throw TeamFirebaseServiceError.noActiveTeam
        }
        guard user.uid == member.userId,
              session.repUserId == member.userId,
              session.status == .active else {
            throw TeamFirebaseServiceError.noActiveTeam
        }
        guard team.planStatus.allowsTeamWrite else {
            throw TeamFirebaseServiceError.writeBlocked
        }

        let coordinate = TeamCoordinate(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude
        )
        let point = TeamDutyLocationPoint(
            teamId: team.id,
            sessionId: session.id,
            repUserId: member.userId,
            coordinate: coordinate,
            horizontalAccuracy: location.horizontalAccuracy,
            recordedAt: now
        )
        let previousPoint = dutyLocationPoints
            .filter { $0.sessionId == session.id && $0.repUserId == member.userId }
            .sorted { $0.recordedAt < $1.recordedAt }
            .last

        if let previousPoint {
            let previousLocation = CLLocation(latitude: previousPoint.latitude, longitude: previousPoint.longitude)
            session.distanceMeters += previousLocation.distance(from: location)
        }
        session.lastLocationAt = now

        let batch = db.batch()
        batch.setData(
            dutyLocationPointData(point),
            forDocument: dutyLocationPointRef(teamId: team.id, pointId: point.id)
        )
        batch.setData(
            dutySessionData(session),
            forDocument: dutySessionRef(teamId: team.id, sessionId: session.id),
            merge: true
        )
        try await commitTeamBatch(batch, pendingWriteCount: 2)

        activeDutySession = session
        upsertDutySession(session)
        dutyLocationPoints.append(point)
    }

    func endDuty(now: Date = Date()) async throws {
        try await prepareFirestoreForTeamUse()
        let user = try requireFirebaseUser()
        guard let session = activeDutySession, session.repUserId == user.uid else {
            throw TeamFirebaseServiceError.noActiveTeam
        }

        let ended = TeamDutySession.ended(
            id: session.id,
            teamId: session.teamId,
            repUserId: session.repUserId,
            startedAt: session.startedAt,
            endedAt: now,
            distanceMeters: session.distanceMeters
        )

        let member = currentMember ?? TeamMember.rep(
            teamId: session.teamId,
            userId: session.repUserId,
            displayName: "Rep",
            email: nil,
            acceptedInviteId: ""
        )
        let batch = db.batch()
        batch.setData(dutySessionData(ended), forDocument: dutySessionRef(teamId: session.teamId, sessionId: session.id), merge: true)
        addActivityLog(
            to: batch,
            teamId: session.teamId,
            actor: member,
            kind: .dutyEnded,
            subjectId: session.id,
            subjectTitle: "duty",
            targetUserId: session.repUserId,
            createdAt: now
        )
        try await commitTeamBatch(batch, pendingWriteCount: 2)
        activeDutySession = nil
        if let index = dutySessions.firstIndex(where: { $0.id == session.id }) {
            dutySessions[index] = ended
        }
    }
}

enum TeamFirebaseServiceError: LocalizedError {
    case alreadyInTeam
    case firebaseSessionExpired
    case invalidInvite
    case noActiveTeam
    case notAuthenticated
    case ownerOnly
    case serverConfirmationTimedOut
    case teamFull
    case writeBlocked

    var errorDescription: String? {
        switch self {
        case .alreadyInTeam:
            return "This Apple sign-in is already in a team."
        case .firebaseSessionExpired:
            return "Team sign-in expired. Continue with Apple again to reconnect Team."
        case .invalidInvite:
            return "This invite code is invalid, expired, or already used."
        case .noActiveTeam:
            return "No active team was found for this account."
        case .notAuthenticated:
            return "Sign in with Apple to use Team."
        case .ownerOnly:
            return "Only the team owner can do that."
        case .serverConfirmationTimedOut:
            return "Team could not be confirmed with the cloud. Check your connection and try again."
        case .teamFull:
            return "The included team seats are full."
        case .writeBlocked:
            return "Team edits are currently read-only."
        }
    }
}

private extension TeamFirebaseService {
#if DEBUG
    func debugLogFirestoreRESTProbe() async {
        guard let options = FirebaseApp.app()?.options,
              let projectID = options.projectID,
              let apiKey = options.apiKey else {
            print("🧪 Firestore REST probe skipped: Firebase options unavailable")
            return
        }

        var components = URLComponents()
        components.scheme = "https"
        components.host = "firestore.googleapis.com"
        components.path = "/v1/projects/\(projectID)/databases/(default)/documents/teams"
        components.queryItems = [URLQueryItem(name: "key", value: apiKey)]

        guard let url = components.url else {
            print("🧪 Firestore REST probe skipped: invalid URL")
            return
        }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            let body = String(data: data, encoding: .utf8) ?? ""
            print("🧪 \(TeamFirestoreRESTProbeLogPolicy.summary(label: "Firestore public REST probe", statusCode: statusCode, body: body, publicProbe: true))")
        } catch {
            print("🧪 Firestore public REST probe failed before HTTP response: \(error.localizedDescription)")
        }

        guard let user = Auth.auth().currentUser else {
            print("🧪 Firestore auth REST probe skipped: no Firebase Auth user")
            return
        }

        let idToken: String
        do {
            do {
                idToken = try await firebaseIDToken(for: user, forceRefresh: false)
            } catch {
                print("🧪 Firestore auth REST probe could not read cached Firebase ID token: \(error.localizedDescription)")
                idToken = try await firebaseIDToken(for: user, forceRefresh: true)
                print("🧪 Firestore auth REST probe recovered with refreshed Firebase ID token")
            }
        } catch {
            print("🧪 Firestore auth REST probe failed before HTTP request: Firebase ID token unavailable (\(error.localizedDescription))")
            return
        }

        var authComponents = URLComponents()
        authComponents.scheme = "https"
        authComponents.host = "firestore.googleapis.com"
        authComponents.path = "/v1/projects/\(projectID)/databases/(default)/documents/users/\(user.uid)/teamProfile/\(TeamFirebaseSchema.currentTeamProfileDocumentId)"
        authComponents.queryItems = [URLQueryItem(name: "key", value: apiKey)]

        guard let authURL = authComponents.url else {
            print("🧪 Firestore auth REST probe skipped: invalid URL")
            return
        }

        do {
            var request = URLRequest(url: authURL)
            request.setValue("Bearer \(idToken)", forHTTPHeaderField: "Authorization")
            let (data, response) = try await URLSession.shared.data(for: request)
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            let body = String(data: data, encoding: .utf8) ?? ""
            print("🧪 \(TeamFirestoreRESTProbeLogPolicy.summary(label: "Firestore authenticated REST probe", statusCode: statusCode, body: body, publicProbe: false))")
        } catch {
            print("🧪 Firestore auth REST probe failed before HTTP response: \(error.localizedDescription)")
        }
    }
#endif

    static let teamWriteAckWaitLimit: TimeInterval = 8
    static let teamServerConfirmationWaitLimit: TimeInterval = 20

    func prepareFirestoreForTeamUse(force: Bool = false) async throws {
        guard force || !hasPreparedFirestoreNetwork else { return }
        do {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                db.enableNetwork { error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume()
                    }
                }
            }
            hasPreparedFirestoreNetwork = true
        } catch {
            hasPreparedFirestoreNetwork = false
            throw error
        }
    }

    func getServerDocument(_ document: DocumentReference) async throws -> DocumentSnapshot {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<DocumentSnapshot, Error>) in
            let completion = TeamDocumentCompletionBox(continuation: continuation)
            let timeout = DispatchWorkItem {
                completion.resume(throwing: TeamFirebaseServiceError.serverConfirmationTimedOut)
            }
            completion.setTimeoutWorkItem(timeout)
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.teamServerConfirmationWaitLimit, execute: timeout)
            document.getDocument(source: .server) { snapshot, error in
                if let error {
                    completion.resume(throwing: error)
                } else if let snapshot {
                    completion.resume(returning: snapshot)
                } else {
                    completion.resume(throwing: TeamFirebaseServiceError.serverConfirmationTimedOut)
                }
            }
        }
    }

    static func nilIfBlank(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }

    func bookingStatus(for appointmentStatus: Appointment.AppointmentStatus) -> TeamBookingStatus {
        switch appointmentStatus {
        case .scheduled:
            return .scheduled
        case .confirmed:
            return .confirmed
        case .completed:
            return .completed
        case .cancelled:
            return .cancelled
        case .rescheduled:
            return .rescheduled
        }
    }

    private func cacheMembership(team: TeamWorkspace, member: TeamMember) {
        let cached = TeamCachedMembershipSnapshot(team: team, member: member, savedAt: Date())
        do {
            try TeamCachedMembershipLocalStore.save(cached, to: .standard, key: Self.cachedMembershipKey)
            UserDefaults.standard.synchronize()
        } catch {
            let message = "Team cache could not be saved: \(error.localizedDescription)"
            lastErrorMessage = message
            print("⚠️ \(message)")
        }
    }

    private func restoreCachedMembershipIfAvailable() {
        guard activeTeam == nil || currentMember == nil else { return }
        let cached: TeamCachedMembershipSnapshot?
        do {
            cached = try TeamCachedMembershipLocalStore.loadFreshSnapshot(
                from: .standard,
                key: Self.cachedMembershipKey,
                maxAge: Self.cachedMembershipMaxAge
            )
        } catch {
            let message = "Saved Team cache could not be loaded: \(error.localizedDescription)"
            lastErrorMessage = message
            UserDefaults.standard.removeObject(forKey: Self.cachedMembershipKey)
            print("⚠️ \(message)")
            return
        }
        guard let cached else { return }

        activeTeam = cached.team
        currentMember = cached.member
        teamMembers = cached.member.role == .owner ? [cached.member] : [cached.member]
        teamLeads = []
        teamBookings = []
        dutySessions = []
        dutyLocationPoints = []
        ownerNotifications = []
        activityLog = []
        activeDutySession = nil
    }

    func requireFirebaseUser() throws -> User {
        guard let user = Auth.auth().currentUser else {
            throw TeamFirebaseServiceError.notAuthenticated
        }
        return user
    }

    func requireFreshFirebaseUser() async throws -> User {
        let user = try requireFirebaseUser()
        do {
            _ = try await firebaseIDToken(for: user, forceRefresh: true)
            return user
        } catch {
            hasPreparedFirestoreNetwork = false
            print("⚠️ Firebase Team session token refresh failed: \(error.localizedDescription)")
            try? Auth.auth().signOut()
            throw TeamFirebaseServiceError.firebaseSessionExpired
        }
    }

    func firebaseIDToken(for user: User, forceRefresh: Bool) async throws -> String {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
            user.getIDTokenForcingRefresh(forceRefresh) { token, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let token {
                    continuation.resume(returning: token)
                } else {
                    continuation.resume(throwing: TeamFirebaseServiceError.notAuthenticated)
                }
            }
        }
    }

    func clearLocalTeam(removeCachedMembership: Bool = false) {
        stopTeamRealtimeListeners()
        activeTeam = nil
        currentMember = nil
        teamMembers = []
        teamLeads = []
        teamBookings = []
        dutySessions = []
        dutyLocationPoints = []
        ownerNotifications = []
        activityLog = []
        activeDutySession = nil
        syncWriteState = .idle
        if removeCachedMembership {
            UserDefaults.standard.removeObject(forKey: Self.cachedMembershipKey)
            UserDefaults.standard.synchronize()
        }
    }

    func handleRevokedTeamAccess(userId: String) async {
        do {
            try await teamProfileRef(userId: userId).delete()
        } catch {
            print("⚠️ Team profile cleanup failed after access revocation: \(Self.userFacingErrorMessage(for: error))")
        }

        clearLocalTeam(removeCachedMembership: true)
        lastErrorMessage = Self.removedTeamAccessMessage
    }

    func stopTeamRealtimeListeners() {
        teamListenerRegistrations.forEach { $0.remove() }
        teamListenerRegistrations = []
    }

    func startTeamRealtimeListeners(team: TeamWorkspace, member: TeamMember) {
        stopTeamRealtimeListeners()

        if member.role == .owner {
            teamListenerRegistrations.append(
                teamRef(team.id)
                    .collection(TeamFirebaseSchema.Collection.members)
                    .addSnapshotListener { [weak self] snapshot, error in
                        Task { @MainActor in
                            guard let self else { return }
                            if let error {
                                self.handleRealtimeListenerError(error, context: "members")
                                return
                            }
                            self.teamMembers = TeamMemberRoster.normalized(snapshot?.documents
                                .compactMap { self.decodeMember(id: $0.documentID, data: $0.data()) }
                                ?? [])
                        }
                    }
            )
        }

        teamListenerRegistrations.append(
            teamLeadsQuery(team: team, member: member)
                .addSnapshotListener { [weak self] snapshot, error in
                    Task { @MainActor in
                        guard let self else { return }
                        if let error {
                            self.handleRealtimeListenerError(error, context: "team leads")
                            return
                        }
                        self.teamLeads = snapshot?.documents
                            .compactMap { self.decodeLead(id: $0.documentID, data: $0.data()) } ?? []
                    }
                }
        )

        teamListenerRegistrations.append(
            teamBookingsQuery(team: team, member: member)
                .addSnapshotListener { [weak self] snapshot, error in
                    Task { @MainActor in
                        guard let self else { return }
                        if let error {
                            self.handleRealtimeListenerError(error, context: "team bookings")
                            return
                        }
                        self.teamBookings = snapshot?.documents
                            .compactMap { self.decodeBooking(id: $0.documentID, data: $0.data()) } ?? []
                    }
                }
        )

        if member.role == .owner {
            listenDutySessions(
                query: dutySessionsQuery(team: team, member: member),
                replacingUserIds: nil,
                currentUserId: member.userId
            )
            listenDutyLocationPoints(
                query: dutyLocationPointsQuery(team: team, member: member),
                replacingUserIds: nil
            )
        } else {
            listenDutySessions(
                query: dutySessionsForUserQuery(team: team, userId: member.userId),
                replacingUserIds: [member.userId],
                currentUserId: member.userId
            )
            listenDutyLocationPoints(
                query: dutyLocationPointsForUserQuery(team: team, userId: member.userId),
                replacingUserIds: [member.userId]
            )

            if team.ownerUserId != member.userId {
                listenDutySessions(
                    query: dutySessionsForUserQuery(team: team, userId: team.ownerUserId),
                    replacingUserIds: [team.ownerUserId],
                    currentUserId: member.userId
                )
                listenDutyLocationPoints(
                    query: dutyLocationPointsForUserQuery(team: team, userId: team.ownerUserId),
                    replacingUserIds: [team.ownerUserId]
                )
            }
        }

        if member.role == .owner {
            teamListenerRegistrations.append(
                teamRef(team.id)
                    .collection(TeamFirebaseSchema.Collection.ownerNotifications)
                    .addSnapshotListener { [weak self] snapshot, error in
                        Task { @MainActor in
                            guard let self else { return }
                            if let error {
                                self.handleRealtimeListenerError(error, context: "owner notifications")
                                return
                            }
                            self.ownerNotifications = snapshot?.documents
                                .compactMap { self.decodeOwnerNotification(id: $0.documentID, data: $0.data()) }
                                .sorted { $0.createdAt > $1.createdAt } ?? []
                        }
                    }
            )
        }

        teamListenerRegistrations.append(
            activityLogQuery(team: team, member: member)
                .addSnapshotListener { [weak self] snapshot, error in
                    Task { @MainActor in
                        guard let self else { return }
                        if let error {
                            self.handleRealtimeListenerError(error, context: "activity log")
                            return
                        }
                        self.activityLog = snapshot?.documents
                            .compactMap { self.decodeActivityLogEntry(id: $0.documentID, data: $0.data()) }
                            .sorted { $0.createdAt > $1.createdAt } ?? []
                    }
                }
        )
    }

    func generateUniqueInviteCode() async throws -> String {
        for _ in 0..<5 {
            let code = UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(8).uppercased()
            let codeString = String(code)
            let codeExists = try await inviteRef(codeString).getDocument().exists
            if !codeExists {
                return codeString
            }
        }
        throw TeamFirebaseServiceError.invalidInvite
    }

    func loadTeam(teamId: String) async throws -> TeamWorkspace {
        let snapshot = try await teamRef(teamId).getDocument()
        guard let data = snapshot.data(), let team = decodeTeam(id: snapshot.documentID, data: data) else {
            throw TeamFirebaseServiceError.noActiveTeam
        }
        return team
    }

    func loadMember(teamId: String, userId: String) async throws -> TeamMember {
        let snapshot = try await memberRef(teamId: teamId, userId: userId).getDocument()
        guard let data = snapshot.data(), let member = decodeMember(id: snapshot.documentID, data: data) else {
            throw TeamFirebaseServiceError.noActiveTeam
        }
        return member
    }

    func loadMembers(teamId: String) async throws -> [TeamMember] {
        let snapshot = try await teamRef(teamId)
            .collection(TeamFirebaseSchema.Collection.members)
            .getDocuments()

        return TeamMemberRoster.normalized(
            snapshot.documents.compactMap { decodeMember(id: $0.documentID, data: $0.data()) }
        )
    }

    func loadTeamLeads(team: TeamWorkspace, member: TeamMember) async throws -> [TeamLead] {
        let snapshot = try await teamLeadsQuery(team: team, member: member).getDocuments()
        return snapshot.documents.compactMap { decodeLead(id: $0.documentID, data: $0.data()) }
    }

    func loadTeamBookings(team: TeamWorkspace, member: TeamMember) async throws -> [TeamBooking] {
        let snapshot = try await teamBookingsQuery(team: team, member: member).getDocuments()
        return snapshot.documents.compactMap { decodeBooking(id: $0.documentID, data: $0.data()) }
    }

    func loadDutySessions(team: TeamWorkspace, member: TeamMember) async throws -> [TeamDutySession] {
        if member.role == .owner {
            let snapshot = try await dutySessionsQuery(team: team, member: member).getDocuments()
            return snapshot.documents.compactMap { decodeDutySession(id: $0.documentID, data: $0.data()) }
        }

        var sessions = try await loadDutySessionsForUser(team: team, userId: member.userId)
        if team.ownerUserId != member.userId {
            sessions.append(contentsOf: try await loadDutySessionsForUser(team: team, userId: team.ownerUserId))
        }
        return sessions.sorted { ($0.endedAt ?? $0.startedAt) > ($1.endedAt ?? $1.startedAt) }
    }

    func loadDutyLocationPoints(team: TeamWorkspace, member: TeamMember) async throws -> [TeamDutyLocationPoint] {
        if member.role == .owner {
            let snapshot = try await dutyLocationPointsQuery(team: team, member: member).getDocuments()
            return snapshot.documents
                .compactMap { decodeDutyLocationPoint(id: $0.documentID, data: $0.data()) }
                .sorted { $0.recordedAt < $1.recordedAt }
        }

        var points = try await loadDutyLocationPointsForUser(team: team, userId: member.userId)
        if team.ownerUserId != member.userId {
            points.append(contentsOf: try await loadDutyLocationPointsForUser(team: team, userId: team.ownerUserId))
        }
        return points.sorted { $0.recordedAt < $1.recordedAt }
    }

    func loadDutySessionsForUser(team: TeamWorkspace, userId: String) async throws -> [TeamDutySession] {
        let snapshot = try await dutySessionsForUserQuery(team: team, userId: userId).getDocuments()
        return snapshot.documents.compactMap { decodeDutySession(id: $0.documentID, data: $0.data()) }
    }

    func loadDutyLocationPointsForUser(team: TeamWorkspace, userId: String) async throws -> [TeamDutyLocationPoint] {
        let snapshot = try await dutyLocationPointsForUserQuery(team: team, userId: userId).getDocuments()
        return snapshot.documents.compactMap { decodeDutyLocationPoint(id: $0.documentID, data: $0.data()) }
    }

    func loadOwnerNotifications(team: TeamWorkspace) async throws -> [TeamOwnerNotification] {
        let snapshot = try await teamRef(team.id)
            .collection(TeamFirebaseSchema.Collection.ownerNotifications)
            .getDocuments()

        return snapshot.documents
            .compactMap { decodeOwnerNotification(id: $0.documentID, data: $0.data()) }
            .sorted { $0.createdAt > $1.createdAt }
    }

    func loadActivityLog(team: TeamWorkspace, member: TeamMember) async throws -> [TeamActivityLogEntry] {
        let snapshot = try await activityLogQuery(team: team, member: member).getDocuments()
        return snapshot.documents
            .compactMap { decodeActivityLogEntry(id: $0.documentID, data: $0.data()) }
            .sorted { $0.createdAt > $1.createdAt }
    }

    func teamLeadsQuery(team: TeamWorkspace, member: TeamMember) -> Query {
        let collection = teamRef(team.id).collection(TeamFirebaseSchema.Collection.leads)
        if member.role == .owner { return collection }
        return collection.whereField(TeamFirebaseSchema.Field.assignedToUserId, isEqualTo: member.userId)
    }

    func teamBookingsQuery(team: TeamWorkspace, member: TeamMember) -> Query {
        let collection = teamRef(team.id).collection(TeamFirebaseSchema.Collection.bookings)
        if member.role == .owner { return collection }
        return collection.whereField(TeamFirebaseSchema.Field.assignedToUserId, isEqualTo: member.userId)
    }

    func dutySessionsQuery(team: TeamWorkspace, member: TeamMember) -> Query {
        let collection = teamRef(team.id).collection(TeamFirebaseSchema.Collection.dutySessions)
        if member.role == .owner { return collection }
        return dutySessionsForUserQuery(team: team, userId: member.userId)
    }

    func dutyLocationPointsQuery(team: TeamWorkspace, member: TeamMember) -> Query {
        let collection = teamRef(team.id).collection(TeamFirebaseSchema.Collection.dutyLocationPoints)
        if member.role == .owner { return collection }
        return dutyLocationPointsForUserQuery(team: team, userId: member.userId)
    }

    func dutySessionsForUserQuery(team: TeamWorkspace, userId: String) -> Query {
        teamRef(team.id)
            .collection(TeamFirebaseSchema.Collection.dutySessions)
            .whereField(TeamFirebaseSchema.Field.repUserId, isEqualTo: userId)
    }

    func dutyLocationPointsForUserQuery(team: TeamWorkspace, userId: String) -> Query {
        teamRef(team.id)
            .collection(TeamFirebaseSchema.Collection.dutyLocationPoints)
            .whereField(TeamFirebaseSchema.Field.repUserId, isEqualTo: userId)
    }

    func activityLogQuery(team: TeamWorkspace, member: TeamMember) -> Query {
        let collection = teamRef(team.id).collection(TeamFirebaseSchema.Collection.activityLog)
        if member.role == .owner { return collection }
        return collection.whereField(TeamFirebaseSchema.Field.targetUserId, isEqualTo: member.userId)
    }
}

private extension TeamFirebaseService {
    func teamRef(_ teamId: String) -> DocumentReference {
        db.collection(TeamFirebaseSchema.Collection.teams).document(teamId)
    }

    func memberRef(teamId: String, userId: String) -> DocumentReference {
        teamRef(teamId).collection(TeamFirebaseSchema.Collection.members).document(userId)
    }

    func inviteRef(_ code: String) -> DocumentReference {
        db.collection(TeamFirebaseSchema.Collection.teamInvites).document(code)
    }

    func teamProfileRef(userId: String) -> DocumentReference {
        db.collection(TeamFirebaseSchema.Collection.users)
            .document(userId)
            .collection(TeamFirebaseSchema.Collection.teamProfile)
            .document(TeamFirebaseSchema.currentTeamProfileDocumentId)
    }

    func dutySessionRef(teamId: String, sessionId: String) -> DocumentReference {
        teamRef(teamId).collection(TeamFirebaseSchema.Collection.dutySessions).document(sessionId)
    }

    func dutyLocationPointRef(teamId: String, pointId: String) -> DocumentReference {
        teamRef(teamId).collection(TeamFirebaseSchema.Collection.dutyLocationPoints).document(pointId)
    }

    func leadRef(teamId: String, leadId: String) -> DocumentReference {
        teamRef(teamId).collection(TeamFirebaseSchema.Collection.leads).document(leadId)
    }

    func bookingRef(teamId: String, bookingId: String) -> DocumentReference {
        teamRef(teamId).collection(TeamFirebaseSchema.Collection.bookings).document(bookingId)
    }

    func ownerNotificationRef(teamId: String) -> DocumentReference {
        teamRef(teamId).collection(TeamFirebaseSchema.Collection.ownerNotifications).document()
    }

    func ownerNotificationRef(teamId: String, notificationId: String) -> DocumentReference {
        teamRef(teamId).collection(TeamFirebaseSchema.Collection.ownerNotifications).document(notificationId)
    }

    func activityLogRef(teamId: String) -> DocumentReference {
        teamRef(teamId).collection(TeamFirebaseSchema.Collection.activityLog).document()
    }

    func activityLogRef(teamId: String, entryId: String) -> DocumentReference {
        teamRef(teamId).collection(TeamFirebaseSchema.Collection.activityLog).document(entryId)
    }
}

private extension TeamFirebaseService {
    func loadOptionalTeamValue<T>(
        context: String,
        fallback: T,
        operation: () async throws -> T
    ) async -> T {
        do {
            return try await operation()
        } catch {
            handleNonBlockingTeamError(error, context: "initial \(context) load")
            return fallback
        }
    }

    func handleRealtimeListenerError(_ error: Error, context: String) {
        handleNonBlockingTeamError(error, context: "\(context) realtime listener")
    }

    func handleNonBlockingTeamError(_ error: Error, context: String) {
        if Self.shouldClearMemberSessionAfterPermissionError(
            error: error,
            profileRole: nil,
            cachedRole: currentMember?.role
        ) {
            let userId = currentMember?.userId ?? Auth.auth().currentUser?.uid
            if let userId {
                Task { await handleRevokedTeamAccess(userId: userId) }
            } else {
                clearLocalTeam(removeCachedMembership: true)
                lastErrorMessage = Self.removedTeamAccessMessage
            }
            return
        }

        let message = Self.userFacingErrorMessage(for: error)
        print("⚠️ Team non-blocking sync failed (\(context)): \(message)")
        if activeTeam == nil || currentMember == nil {
            lastErrorMessage = message
        }
    }

    func commitTeamBatch(
        _ batch: WriteBatch,
        pendingWriteCount: Int = 1,
        allowsLocalQueueFallback: Bool = true
    ) async throws {
        syncWriteState = .pending(localWriteCount: pendingWriteCount)
        do {
            try await performTeamWrite(allowsLocalQueueFallback: allowsLocalQueueFallback) { completion in
                batch.commit(completion: completion)
            }
            syncWriteState = .idle
        } catch {
            syncWriteState = .failed(Self.userFacingErrorMessage(for: error))
            throw error
        }
    }

    func setTeamData(_ data: [String: Any], forDocument document: DocumentReference, merge: Bool = true) async throws {
        syncWriteState = .pending(localWriteCount: 1)
        do {
            try await performTeamWrite { completion in
                document.setData(data, merge: merge, completion: completion)
            }
            syncWriteState = .idle
        } catch {
            syncWriteState = .failed(Self.userFacingErrorMessage(for: error))
            throw error
        }
    }

    func performTeamWrite(
        updateSyncStateOnLateCompletion: Bool = true,
        allowsLocalQueueFallback: Bool = true,
        _ start: (@escaping @Sendable (Error?) -> Void) -> Void
    ) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let completion = TeamWriteCompletionBox(continuation: continuation) { [weak self] error in
                Task { @MainActor in
                    guard updateSyncStateOnLateCompletion else { return }
                    guard let self else { return }
                    if let error {
                        self.syncWriteState = .failed(Self.userFacingErrorMessage(for: error))
                    } else {
                        self.syncWriteState = .idle
                    }
                }
            }
            let timeout = DispatchWorkItem {
                if allowsLocalQueueFallback {
                    completion.resumeAfterLocalQueueDelay()
                } else {
                    completion.resume(with: TeamFirebaseServiceError.serverConfirmationTimedOut)
                }
            }
            completion.setTimeoutWorkItem(timeout)
            let waitLimit = allowsLocalQueueFallback ? Self.teamWriteAckWaitLimit : Self.teamServerConfirmationWaitLimit
            DispatchQueue.main.asyncAfter(deadline: .now() + waitLimit, execute: timeout)
            start { error in
                completion.resume(with: error)
            }
        }
    }

    func commitOptionalTeamBatch(_ batch: WriteBatch, context: String) {
        Task {
            do {
                try await performTeamWrite(updateSyncStateOnLateCompletion: false) { completion in
                    batch.commit(completion: completion)
                }
            } catch {
                print("⚠️ Team optional write failed (\(context)): \(Self.userFacingErrorMessage(for: error))")
            }
        }
    }

    func teamData(_ team: TeamWorkspace) -> [String: Any] {
        [
            TeamFirebaseSchema.Field.name: team.name,
            TeamFirebaseSchema.Field.ownerUserId: team.ownerUserId,
            TeamFirebaseSchema.Field.createdAt: Timestamp(date: team.createdAt),
            TeamFirebaseSchema.Field.updatedAt: Timestamp(date: team.updatedAt),
            TeamFirebaseSchema.Field.planStatus: team.planStatus.rawValue,
            TeamFirebaseSchema.Field.planExpiresAt: TeamFirestoreMergePayloadValue.omittedWhenNil(optionalTimestamp(team.planExpiresAt)),
            TeamFirebaseSchema.Field.graceEndsAt: TeamFirestoreMergePayloadValue.omittedWhenNil(optionalTimestamp(team.graceEndsAt)),
            TeamFirebaseSchema.Field.memberLimit: team.memberLimit
        ].filterNilValues()
    }

    func memberData(_ member: TeamMember, updatedAt: Date) -> [String: Any] {
        [
            TeamFirebaseSchema.Field.teamId: member.teamId,
            TeamFirebaseSchema.Field.userId: member.userId,
            TeamFirebaseSchema.Field.displayName: member.displayName,
            TeamFirebaseSchema.Field.email: TeamFirestoreMergePayloadValue.omittedWhenNil(member.email),
            TeamFirebaseSchema.Field.role: member.role.rawValue,
            TeamFirebaseSchema.Field.status: member.status.rawValue,
            TeamFirebaseSchema.Field.workType: member.workType.rawValue,
            TeamFirebaseSchema.Field.joinedAt: Timestamp(date: member.joinedAt),
            TeamFirebaseSchema.Field.removedAt: TeamFirestoreMergePayloadValue.omittedWhenNil(optionalTimestamp(member.removedAt)),
            TeamFirebaseSchema.Field.acceptedInviteId: TeamFirestoreMergePayloadValue.omittedWhenNil(member.acceptedInviteId),
            TeamFirebaseSchema.Field.updatedAt: Timestamp(date: updatedAt)
        ].filterNilValues()
    }

    func inviteData(_ invite: TeamInvite, team: TeamWorkspace, createdByUserId: String, createdAt: Date) -> [String: Any] {
        [
            TeamFirebaseSchema.Field.teamId: invite.teamId,
            TeamFirebaseSchema.Field.createdByUserId: createdByUserId,
            TeamFirebaseSchema.Field.createdAt: Timestamp(date: createdAt),
            TeamFirebaseSchema.Field.expiresAt: Timestamp(date: invite.expiresAt),
            TeamFirebaseSchema.Field.status: TeamFirebaseSchema.InviteStatus.pending,
            TeamFirebaseSchema.Field.planStatus: team.planStatus.rawValue
        ]
    }

    func profileData(teamId: String, role: TeamRole, updatedAt: Date) -> [String: Any] {
        [
            TeamFirebaseSchema.Field.teamId: teamId,
            TeamFirebaseSchema.Field.role: role.rawValue,
            TeamFirebaseSchema.Field.updatedAt: Timestamp(date: updatedAt)
        ]
    }

    func leadData(_ lead: TeamLead) -> [String: Any] {
        [
            TeamFirebaseSchema.Field.teamId: lead.teamId,
            TeamFirebaseSchema.Field.name: lead.name,
            TeamFirebaseSchema.Field.address: lead.address,
            TeamFirebaseSchema.Field.phone: TeamFirestoreMergePayloadValue.nullable(lead.phone),
            TeamFirebaseSchema.Field.email: TeamFirestoreMergePayloadValue.nullable(lead.email),
            TeamFirebaseSchema.Field.latitude: lead.latitude,
            TeamFirebaseSchema.Field.longitude: lead.longitude,
            TeamFirebaseSchema.Field.status: lead.status.rawValue,
            TeamFirebaseSchema.Field.notes: lead.notes,
            TeamFirebaseSchema.Field.serviceCategory: TeamFirestoreMergePayloadValue.nullable(lead.serviceCategory),
            TeamFirebaseSchema.Field.price: lead.price,
            TeamFirebaseSchema.Field.estimatedValue: lead.estimatedValue,
            TeamFirebaseSchema.Field.tags: lead.tags,
            TeamFirebaseSchema.Field.assignedToUserId: lead.assignedToUserId,
            TeamFirebaseSchema.Field.createdByUserId: lead.createdByUserId,
            TeamFirebaseSchema.Field.updatedByUserId: lead.updatedByUserId,
            TeamFirebaseSchema.Field.createdAt: Timestamp(date: lead.createdAt),
            TeamFirebaseSchema.Field.updatedAt: Timestamp(date: lead.updatedAt),
            TeamFirebaseSchema.Field.isHighPriority: lead.isHighPriority,
            TeamFirebaseSchema.Field.highPriorityReason: TeamFirestoreMergePayloadValue.nullable(lead.highPriorityReason)
        ].filterNilValues()
    }

    func bookingData(_ booking: TeamBooking) -> [String: Any] {
        [
            TeamFirebaseSchema.Field.teamId: booking.teamId,
            TeamFirebaseSchema.Field.leadId: booking.leadId,
            TeamFirebaseSchema.Field.assignedToUserId: booking.assignedToUserId,
            TeamFirebaseSchema.Field.title: booking.title,
            TeamFirebaseSchema.Field.notes: booking.notes,
            TeamFirebaseSchema.Field.startDate: Timestamp(date: booking.startDate),
            TeamFirebaseSchema.Field.endDate: Timestamp(date: booking.endDate),
            TeamFirebaseSchema.Field.location: booking.location,
            TeamFirebaseSchema.Field.status: booking.status.rawValue,
            TeamFirebaseSchema.Field.createdByUserId: booking.createdByUserId,
            TeamFirebaseSchema.Field.updatedByUserId: booking.updatedByUserId,
            TeamFirebaseSchema.Field.createdAt: Timestamp(date: booking.createdAt),
            TeamFirebaseSchema.Field.updatedAt: Timestamp(date: booking.updatedAt),
            TeamFirebaseSchema.Field.customerName: TeamFirestoreMergePayloadValue.nullable(booking.customerName),
            TeamFirebaseSchema.Field.customerPhone: TeamFirestoreMergePayloadValue.nullable(booking.customerPhone),
            TeamFirebaseSchema.Field.customerEmail: TeamFirestoreMergePayloadValue.nullable(booking.customerEmail),
            TeamFirebaseSchema.Field.serviceCategory: TeamFirestoreMergePayloadValue.nullable(booking.serviceCategory),
            TeamFirebaseSchema.Field.quotedPrice: TeamFirestoreMergePayloadValue.nullable(booking.quotedPrice),
            TeamFirebaseSchema.Field.latitude: TeamFirestoreMergePayloadValue.nullable(booking.latitude),
            TeamFirebaseSchema.Field.longitude: TeamFirestoreMergePayloadValue.nullable(booking.longitude),
            TeamFirebaseSchema.Field.arrivalWindowMinutes: TeamFirestoreMergePayloadValue.nullable(booking.arrivalWindowMinutes)
        ].filterNilValues()
    }

    func ownerNotificationData(
        event: TeamOwnerLeadEvent,
        team: TeamWorkspace,
        lead: TeamLead,
        createdAt: Date
    ) -> [String: Any] {
        [
            TeamFirebaseSchema.Field.teamId: team.id,
            TeamFirebaseSchema.Field.leadId: lead.id,
            TeamFirebaseSchema.Field.assignedToUserId: lead.assignedToUserId,
            TeamFirebaseSchema.Field.createdByUserId: lead.updatedByUserId,
            TeamFirebaseSchema.Field.eventType: event.rawValue,
            TeamFirebaseSchema.Field.title: event.ownerTitle,
            TeamFirebaseSchema.Field.message: ownerNotificationMessage(event: event, lead: lead),
            TeamFirebaseSchema.Field.createdAt: Timestamp(date: createdAt)
        ]
    }

    func activityLogData(_ entry: TeamActivityLogEntry) -> [String: Any] {
        [
            TeamFirebaseSchema.Field.teamId: entry.teamId,
            TeamFirebaseSchema.Field.actorUserId: entry.actorUserId,
            TeamFirebaseSchema.Field.actorDisplayName: entry.actorDisplayName,
            TeamFirebaseSchema.Field.kind: entry.kind.rawValue,
            TeamFirebaseSchema.Field.subjectId: entry.subjectId,
            TeamFirebaseSchema.Field.subjectTitle: entry.subjectTitle,
            TeamFirebaseSchema.Field.targetUserId: entry.targetUserId as Any,
            TeamFirebaseSchema.Field.summary: entry.summary,
            TeamFirebaseSchema.Field.createdAt: Timestamp(date: entry.createdAt)
        ].filterNilValues()
    }

    func addActivityLog(
        to batch: WriteBatch,
        teamId: String,
        actor: TeamMember,
        kind: TeamActivityLogKind,
        subjectId: String,
        subjectTitle: String,
        targetUserId: String?,
        createdAt: Date
    ) {
        let entry = TeamActivityLogEntry.make(
            teamId: teamId,
            actorUserId: actor.userId,
            actorDisplayName: actor.displayName,
            kind: kind,
            subjectId: subjectId,
            subjectTitle: subjectTitle,
            targetUserId: targetUserId,
            createdAt: createdAt
        )
        batch.setData(activityLogData(entry), forDocument: activityLogRef(teamId: teamId, entryId: entry.id))
    }

    func addOwnerNotifications(
        to batch: WriteBatch,
        team: TeamWorkspace,
        lead: TeamLead,
        events: [TeamOwnerLeadEvent],
        createdAt: Date
    ) {
        for event in events {
            batch.setData(
                ownerNotificationData(event: event, team: team, lead: lead, createdAt: createdAt),
                forDocument: ownerNotificationRef(teamId: team.id)
            )
        }
    }

    func listenDutySessions(query: Query, replacingUserIds: Set<String>?, currentUserId: String) {
        teamListenerRegistrations.append(
            query.addSnapshotListener { [weak self] snapshot, error in
                Task { @MainActor in
                    guard let self else { return }
                    if let error {
                        self.handleRealtimeListenerError(error, context: "duty sessions")
                        return
                    }
                    let sessions = snapshot?.documents
                        .compactMap { self.decodeDutySession(id: $0.documentID, data: $0.data()) } ?? []
                    if let replacingUserIds {
                        self.replaceDutySessions(for: replacingUserIds, with: sessions)
                    } else {
                        self.dutySessions = sessions.sorted {
                            ($0.endedAt ?? $0.startedAt) > ($1.endedAt ?? $1.startedAt)
                        }
                    }
                    self.updateActiveDutySession(for: currentUserId)
                }
            }
        )
    }

    func listenDutyLocationPoints(query: Query, replacingUserIds: Set<String>?) {
        teamListenerRegistrations.append(
            query.addSnapshotListener { [weak self] snapshot, error in
                Task { @MainActor in
                    guard let self else { return }
                    if let error {
                        self.handleRealtimeListenerError(error, context: "duty location points")
                        return
                    }
                    let points = snapshot?.documents
                        .compactMap { self.decodeDutyLocationPoint(id: $0.documentID, data: $0.data()) } ?? []
                    if let replacingUserIds {
                        self.replaceDutyLocationPoints(for: replacingUserIds, with: points)
                    } else {
                        self.dutyLocationPoints = points.sorted { $0.recordedAt < $1.recordedAt }
                    }
                }
            }
        )
    }

    func ownerNotificationMessage(event: TeamOwnerLeadEvent, lead: TeamLead) -> String {
        let base = "\(lead.name) at \(lead.address)"
        switch event {
        case .highPriority:
            if let reason = Self.nilIfBlank(lead.highPriorityReason) {
                return "\(base): \(reason)"
            }
            return "\(base) was marked high priority."
        default:
            return base
        }
    }

    func dutySessionData(_ session: TeamDutySession) -> [String: Any] {
        [
            TeamFirebaseSchema.Field.teamId: session.teamId,
            TeamFirebaseSchema.Field.repUserId: session.repUserId,
            TeamFirebaseSchema.Field.startedAt: Timestamp(date: session.startedAt),
            TeamFirebaseSchema.Field.endedAt: TeamFirestoreMergePayloadValue.omittedWhenNil(optionalTimestamp(session.endedAt)),
            TeamFirebaseSchema.Field.status: session.status.rawValue,
            TeamFirebaseSchema.Field.lastLocationAt: TeamFirestoreMergePayloadValue.omittedWhenNil(optionalTimestamp(session.lastLocationAt)),
            TeamFirebaseSchema.Field.distanceMeters: session.distanceMeters,
            TeamFirebaseSchema.Field.createdAt: Timestamp(date: session.createdAt),
            TeamFirebaseSchema.Field.deleteAfter: TeamFirestoreMergePayloadValue.omittedWhenNil(optionalTimestamp(session.deleteAfter))
        ].filterNilValues()
    }

    func dutyLocationPointData(_ point: TeamDutyLocationPoint) -> [String: Any] {
        [
            TeamFirebaseSchema.Field.teamId: point.teamId,
            TeamFirebaseSchema.Field.repUserId: point.repUserId,
            TeamFirebaseSchema.Field.sessionId: point.sessionId,
            TeamFirebaseSchema.Field.latitude: point.latitude,
            TeamFirebaseSchema.Field.longitude: point.longitude,
            TeamFirebaseSchema.Field.horizontalAccuracy: point.horizontalAccuracy,
            TeamFirebaseSchema.Field.recordedAt: Timestamp(date: point.recordedAt),
            TeamFirebaseSchema.Field.deleteAfter: Timestamp(date: point.deleteAfter)
        ]
    }

    func optionalTimestamp(_ date: Date?) -> Timestamp? {
        date.map(Timestamp.init(date:))
    }

    func upsertDutySession(_ session: TeamDutySession) {
        if let index = dutySessions.firstIndex(where: { $0.id == session.id }) {
            dutySessions[index] = session
        } else {
            dutySessions.append(session)
        }
    }

    func replaceDutySessions(for userIds: Set<String>, with sessions: [TeamDutySession]) {
        dutySessions.removeAll { userIds.contains($0.repUserId) }
        dutySessions.append(contentsOf: sessions)
        dutySessions.sort { ($0.endedAt ?? $0.startedAt) > ($1.endedAt ?? $1.startedAt) }
    }

    func replaceDutyLocationPoints(for userIds: Set<String>, with points: [TeamDutyLocationPoint]) {
        dutyLocationPoints.removeAll { userIds.contains($0.repUserId) }
        dutyLocationPoints.append(contentsOf: points)
        dutyLocationPoints.sort { $0.recordedAt < $1.recordedAt }
    }

    func updateActiveDutySession(for userId: String) {
        activeDutySession = dutySessions.first {
            $0.repUserId == userId && $0.status == .active
        }
    }
}

private final class TeamWriteCompletionBox: @unchecked Sendable {
    private let lock = NSLock()
    private let continuation: CheckedContinuation<Void, Error>
    private let lateCompletion: @Sendable (Error?) -> Void
    private var didResume = false
    private var timeoutWorkItem: DispatchWorkItem?

    init(
        continuation: CheckedContinuation<Void, Error>,
        lateCompletion: @escaping @Sendable (Error?) -> Void
    ) {
        self.continuation = continuation
        self.lateCompletion = lateCompletion
    }

    func setTimeoutWorkItem(_ timeoutWorkItem: DispatchWorkItem) {
        lock.lock()
        self.timeoutWorkItem = timeoutWorkItem
        lock.unlock()
    }

    func resumeAfterLocalQueueDelay() {
        lock.lock()
        guard !didResume else {
            lock.unlock()
            return
        }
        didResume = true
        lock.unlock()
        continuation.resume()
    }

    func resume(with error: Error?) {
        lock.lock()
        guard !didResume else {
            lock.unlock()
            lateCompletion(error)
            return
        }
        didResume = true
        let timeoutWorkItem = timeoutWorkItem
        lock.unlock()

        timeoutWorkItem?.cancel()
        if let error {
            continuation.resume(throwing: error)
        } else {
            continuation.resume()
        }
    }
}

private final class TeamDocumentCompletionBox: @unchecked Sendable {
    private let lock = NSLock()
    private let continuation: CheckedContinuation<DocumentSnapshot, Error>
    private var didResume = false
    private var timeoutWorkItem: DispatchWorkItem?

    init(continuation: CheckedContinuation<DocumentSnapshot, Error>) {
        self.continuation = continuation
    }

    func setTimeoutWorkItem(_ timeoutWorkItem: DispatchWorkItem) {
        lock.lock()
        self.timeoutWorkItem = timeoutWorkItem
        lock.unlock()
    }

    func resume(returning snapshot: DocumentSnapshot) {
        lock.lock()
        guard !didResume else {
            lock.unlock()
            return
        }
        didResume = true
        let timeoutWorkItem = timeoutWorkItem
        lock.unlock()

        timeoutWorkItem?.cancel()
        continuation.resume(returning: snapshot)
    }

    func resume(throwing error: Error) {
        lock.lock()
        guard !didResume else {
            lock.unlock()
            return
        }
        didResume = true
        let timeoutWorkItem = timeoutWorkItem
        lock.unlock()

        timeoutWorkItem?.cancel()
        continuation.resume(throwing: error)
    }
}

private extension TeamFirebaseService {
    func decodeTeam(id: String, data: [String: Any]) -> TeamWorkspace? {
        guard let name = data[TeamFirebaseSchema.Field.name] as? String,
              let ownerUserId = data[TeamFirebaseSchema.Field.ownerUserId] as? String,
              let createdAt = Self.dateValue(data[TeamFirebaseSchema.Field.createdAt]),
              let updatedAt = Self.dateValue(data[TeamFirebaseSchema.Field.updatedAt]),
              let planStatusRaw = data[TeamFirebaseSchema.Field.planStatus] as? String,
              let planStatus = TeamPlanStatus(rawValue: planStatusRaw) else {
            return nil
        }

        return TeamWorkspace(
            id: id,
            name: name,
            ownerUserId: ownerUserId,
            createdAt: createdAt,
            updatedAt: updatedAt,
            planStatus: planStatus,
            planExpiresAt: Self.dateValue(data[TeamFirebaseSchema.Field.planExpiresAt]),
            graceEndsAt: Self.dateValue(data[TeamFirebaseSchema.Field.graceEndsAt]),
            memberLimit: data[TeamFirebaseSchema.Field.memberLimit] as? Int ?? TeamWorkspace.includedMemberLimit
        )
    }

    func decodeMember(id: String, data: [String: Any]) -> TeamMember? {
        guard let teamId = data[TeamFirebaseSchema.Field.teamId] as? String,
              let displayName = data[TeamFirebaseSchema.Field.displayName] as? String,
              let roleRaw = data[TeamFirebaseSchema.Field.role] as? String,
              let role = TeamRole(rawValue: roleRaw),
              let statusRaw = data[TeamFirebaseSchema.Field.status] as? String,
              let status = TeamMemberStatus(rawValue: statusRaw),
              let joinedAt = Self.dateValue(data[TeamFirebaseSchema.Field.joinedAt]) else {
            return nil
        }
        let userId = data[TeamFirebaseSchema.Field.userId] as? String ?? id
        let workType = (data[TeamFirebaseSchema.Field.workType] as? String)
            .flatMap(TeamMemberWorkType.init(rawValue:)) ?? (role == .owner ? .owner : .salesRep)

        return TeamMember(
            teamId: teamId,
            userId: userId,
            displayName: displayName,
            email: data[TeamFirebaseSchema.Field.email] as? String,
            role: role,
            status: status,
            workType: workType,
            joinedAt: joinedAt,
            removedAt: Self.dateValue(data[TeamFirebaseSchema.Field.removedAt]),
            acceptedInviteId: data[TeamFirebaseSchema.Field.acceptedInviteId] as? String
        )
    }

    func decodeLead(id: String, data: [String: Any]) -> TeamLead? {
        guard let teamId = data[TeamFirebaseSchema.Field.teamId] as? String,
              let name = data[TeamFirebaseSchema.Field.name] as? String,
              let address = data[TeamFirebaseSchema.Field.address] as? String,
              let latitude = data[TeamFirebaseSchema.Field.latitude] as? Double,
              let longitude = data[TeamFirebaseSchema.Field.longitude] as? Double,
              let statusRaw = data[TeamFirebaseSchema.Field.status] as? String,
              let status = TeamLeadStatus(rawValue: statusRaw),
              let assignedToUserId = data[TeamFirebaseSchema.Field.assignedToUserId] as? String,
              let createdByUserId = data[TeamFirebaseSchema.Field.createdByUserId] as? String,
              let updatedByUserId = data[TeamFirebaseSchema.Field.updatedByUserId] as? String,
              let createdAt = Self.dateValue(data[TeamFirebaseSchema.Field.createdAt]),
              let updatedAt = Self.dateValue(data[TeamFirebaseSchema.Field.updatedAt]) else {
            return nil
        }

        return TeamLead(
            id: id,
            teamId: teamId,
            name: name,
            address: address,
            phone: data[TeamFirebaseSchema.Field.phone] as? String,
            email: data[TeamFirebaseSchema.Field.email] as? String,
            latitude: latitude,
            longitude: longitude,
            status: status,
            notes: data[TeamFirebaseSchema.Field.notes] as? String ?? "",
            serviceCategory: data[TeamFirebaseSchema.Field.serviceCategory] as? String,
            price: data[TeamFirebaseSchema.Field.price] as? Double ?? 0,
            estimatedValue: data[TeamFirebaseSchema.Field.estimatedValue] as? Double ?? 0,
            tags: data[TeamFirebaseSchema.Field.tags] as? [String] ?? [],
            assignedToUserId: assignedToUserId,
            createdByUserId: createdByUserId,
            updatedByUserId: updatedByUserId,
            createdAt: createdAt,
            updatedAt: updatedAt,
            isHighPriority: data[TeamFirebaseSchema.Field.isHighPriority] as? Bool ?? false,
            highPriorityReason: data[TeamFirebaseSchema.Field.highPriorityReason] as? String
        )
    }

    func decodeOwnerNotification(id: String, data: [String: Any]) -> TeamOwnerNotification? {
        guard let teamId = data[TeamFirebaseSchema.Field.teamId] as? String,
              let leadId = data[TeamFirebaseSchema.Field.leadId] as? String,
              let assignedToUserId = data[TeamFirebaseSchema.Field.assignedToUserId] as? String,
              let createdByUserId = data[TeamFirebaseSchema.Field.createdByUserId] as? String,
              let eventRaw = data[TeamFirebaseSchema.Field.eventType] as? String,
              let event = TeamOwnerLeadEvent(rawValue: eventRaw),
              let title = data[TeamFirebaseSchema.Field.title] as? String,
              let message = data[TeamFirebaseSchema.Field.message] as? String,
              let createdAt = Self.dateValue(data[TeamFirebaseSchema.Field.createdAt]) else {
            return nil
        }

        return TeamOwnerNotification(
            id: id,
            teamId: teamId,
            leadId: leadId,
            assignedToUserId: assignedToUserId,
            createdByUserId: createdByUserId,
            event: event,
            title: title,
            message: message,
            createdAt: createdAt,
            readAt: Self.dateValue(data[TeamFirebaseSchema.Field.readAt])
        )
    }

    func decodeActivityLogEntry(id: String, data: [String: Any]) -> TeamActivityLogEntry? {
        guard let teamId = data[TeamFirebaseSchema.Field.teamId] as? String,
              let actorUserId = data[TeamFirebaseSchema.Field.actorUserId] as? String,
              let actorDisplayName = data[TeamFirebaseSchema.Field.actorDisplayName] as? String,
              let kindRaw = data[TeamFirebaseSchema.Field.kind] as? String,
              let kind = TeamActivityLogKind(rawValue: kindRaw),
              let subjectId = data[TeamFirebaseSchema.Field.subjectId] as? String,
              let subjectTitle = data[TeamFirebaseSchema.Field.subjectTitle] as? String,
              let summary = data[TeamFirebaseSchema.Field.summary] as? String,
              let createdAt = Self.dateValue(data[TeamFirebaseSchema.Field.createdAt]) else {
            return nil
        }

        return TeamActivityLogEntry(
            id: id,
            teamId: teamId,
            actorUserId: actorUserId,
            actorDisplayName: actorDisplayName,
            kind: kind,
            subjectId: subjectId,
            subjectTitle: subjectTitle,
            targetUserId: data[TeamFirebaseSchema.Field.targetUserId] as? String,
            summary: summary,
            createdAt: createdAt
        )
    }

    func decodeBooking(id: String, data: [String: Any]) -> TeamBooking? {
        guard let teamId = data[TeamFirebaseSchema.Field.teamId] as? String,
              let leadId = data[TeamFirebaseSchema.Field.leadId] as? String,
              let assignedToUserId = data[TeamFirebaseSchema.Field.assignedToUserId] as? String,
              let title = data[TeamFirebaseSchema.Field.title] as? String,
              let startDate = Self.dateValue(data[TeamFirebaseSchema.Field.startDate]),
              let endDate = Self.dateValue(data[TeamFirebaseSchema.Field.endDate]),
              let location = data[TeamFirebaseSchema.Field.location] as? String,
              let statusRaw = data[TeamFirebaseSchema.Field.status] as? String,
              let status = TeamBookingStatus(rawValue: statusRaw),
              let createdByUserId = data[TeamFirebaseSchema.Field.createdByUserId] as? String,
              let updatedByUserId = data[TeamFirebaseSchema.Field.updatedByUserId] as? String,
              let createdAt = Self.dateValue(data[TeamFirebaseSchema.Field.createdAt]),
              let updatedAt = Self.dateValue(data[TeamFirebaseSchema.Field.updatedAt]) else {
            return nil
        }

        return TeamBooking(
            id: id,
            teamId: teamId,
            leadId: leadId,
            assignedToUserId: assignedToUserId,
            title: title,
            notes: data[TeamFirebaseSchema.Field.notes] as? String ?? "",
            startDate: startDate,
            endDate: endDate,
            location: location,
            status: status,
            createdByUserId: createdByUserId,
            updatedByUserId: updatedByUserId,
            createdAt: createdAt,
            updatedAt: updatedAt,
            customerName: data[TeamFirebaseSchema.Field.customerName] as? String,
            customerPhone: data[TeamFirebaseSchema.Field.customerPhone] as? String,
            customerEmail: data[TeamFirebaseSchema.Field.customerEmail] as? String,
            serviceCategory: data[TeamFirebaseSchema.Field.serviceCategory] as? String,
            quotedPrice: data[TeamFirebaseSchema.Field.quotedPrice] as? Double,
            latitude: data[TeamFirebaseSchema.Field.latitude] as? Double,
            longitude: data[TeamFirebaseSchema.Field.longitude] as? Double,
            arrivalWindowMinutes: data[TeamFirebaseSchema.Field.arrivalWindowMinutes] as? Int
        )
    }

    func decodeDutySession(id: String, data: [String: Any]) -> TeamDutySession? {
        guard let teamId = data[TeamFirebaseSchema.Field.teamId] as? String,
              let repUserId = data[TeamFirebaseSchema.Field.repUserId] as? String,
              let startedAt = Self.dateValue(data[TeamFirebaseSchema.Field.startedAt]),
              let statusRaw = data[TeamFirebaseSchema.Field.status] as? String,
              let status = TeamDutySessionStatus(rawValue: statusRaw),
              let createdAt = Self.dateValue(data[TeamFirebaseSchema.Field.createdAt]) else {
            return nil
        }

        return TeamDutySession(
            id: id,
            teamId: teamId,
            repUserId: repUserId,
            startedAt: startedAt,
            endedAt: Self.dateValue(data[TeamFirebaseSchema.Field.endedAt]),
            status: status,
            lastLocationAt: Self.dateValue(data[TeamFirebaseSchema.Field.lastLocationAt]),
            distanceMeters: data[TeamFirebaseSchema.Field.distanceMeters] as? Double ?? 0,
            createdAt: createdAt,
            deleteAfter: Self.dateValue(data[TeamFirebaseSchema.Field.deleteAfter])
        )
    }

    func decodeDutyLocationPoint(id: String, data: [String: Any]) -> TeamDutyLocationPoint? {
        guard let teamId = data[TeamFirebaseSchema.Field.teamId] as? String,
              let sessionId = data[TeamFirebaseSchema.Field.sessionId] as? String,
              let repUserId = data[TeamFirebaseSchema.Field.repUserId] as? String,
              let latitude = data[TeamFirebaseSchema.Field.latitude] as? Double,
              let longitude = data[TeamFirebaseSchema.Field.longitude] as? Double,
              let horizontalAccuracy = data[TeamFirebaseSchema.Field.horizontalAccuracy] as? Double,
              let recordedAt = Self.dateValue(data[TeamFirebaseSchema.Field.recordedAt]) else {
            return nil
        }

        return TeamDutyLocationPoint(
            id: id,
            teamId: teamId,
            sessionId: sessionId,
            repUserId: repUserId,
            coordinate: TeamCoordinate(latitude: latitude, longitude: longitude),
            horizontalAccuracy: horizontalAccuracy,
            recordedAt: recordedAt
        )
    }

    func repReplyTitle(_ status: OwnerInstructionStatus) -> String {
        switch status {
        case .none:
            return "Done"
        case .done:
            return "Done"
        case .customerNotHome:
            return "Customer not home"
        case .needsOwnerFollowUp:
            return "Needs owner follow-up"
        case .couldNotComplete:
            return "Could not complete"
        }
    }

    func leadStatus(for ownerInstructionStatus: OwnerInstructionStatus) -> TeamLeadStatus? {
        switch ownerInstructionStatus {
        case .customerNotHome:
            return .notHome
        case .needsOwnerFollowUp:
            return .followUp
        case .done, .couldNotComplete, .none:
            return nil
        }
    }

    static func dateValue(_ value: Any?) -> Date? {
        if let timestamp = value as? Timestamp {
            return timestamp.dateValue()
        }
        if let date = value as? Date {
            return date
        }
        if let interval = value as? TimeInterval {
            return Date(timeIntervalSince1970: interval)
        }
        return nil
    }
}

extension TeamFirebaseService {
    func clearTeamSessionForSignOut() {
        clearLocalTeam(removeCachedMembership: true)
    }
}

private extension Dictionary where Key == String, Value == Any {
    func filterNilValues() -> [String: Any] {
        filter { !TeamFirestoreMergePayloadValue.isNilOptional($0.value) }
    }
}
