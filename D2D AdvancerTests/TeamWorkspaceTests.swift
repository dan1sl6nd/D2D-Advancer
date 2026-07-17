import Testing
import Foundation
@testable import D2D_Advancer

struct TeamWorkspaceTests {
    @Test func teamRoleContextRoutesTechniciansToJobs() {
        let summary = TeamWorkspaceSurfaceSummary(
            role: .member,
            currentMemberWorkType: .technician,
            teamName: "Field Team",
            workspaces: [],
            teamLeadCount: 0,
            importantLeadCount: 0,
            activeRepCount: 0,
            upcomingBookingCount: 3,
            unreadNotificationCount: 0
        )

        let context = TeamRoleContext(summary: summary)

        #expect(context.defaultTabIndex == MainAppTab.work.rawValue)
        #expect(context.defaultWorkSection == .schedule)
        #expect(context.workTabTitle == "Jobs")
        #expect(context.workScheduleSectionTitle == "Jobs")
        #expect(context.appointmentScreenTitle == "Today's Jobs")
        #expect(context.workspaceMenuTitle == "Job Workspace")
    }

    @Test func teamRoleContextRoutesSalesRepsToTheirLeads() {
        let summary = TeamWorkspaceSurfaceSummary(
            role: .member,
            currentMemberWorkType: .salesRep,
            teamName: "Field Team",
            workspaces: [],
            teamLeadCount: 4,
            importantLeadCount: 1,
            activeRepCount: 1,
            upcomingBookingCount: 0,
            unreadNotificationCount: 0
        )

        let context = TeamRoleContext(summary: summary)

        #expect(context.defaultTabIndex == 1)
        #expect(context.leadsTabTitle == "Mine")
        #expect(context.leadScreenTitle == "My Leads")
        #expect(context.workspaceMenuTitle == "My Team")
    }

    @Test func teamRoleContextKeepsOwnersMapFirst() {
        let summary = TeamWorkspaceSurfaceSummary(
            role: .owner,
            currentMemberWorkType: .owner,
            teamName: "Field Team",
            workspaces: [],
            teamLeadCount: 8,
            importantLeadCount: 2,
            activeRepCount: 1,
            upcomingBookingCount: 2,
            unreadNotificationCount: 1
        )

        let context = TeamRoleContext(summary: summary)

        #expect(context.defaultTabIndex == 0)
        #expect(context.leadsTabTitle == "Leads")
        #expect(context.appointmentScreenTitle == "Schedule")
        #expect(context.workspaceMenuTitle == "Team Admin")
    }

    @Test func activePlanAllowsWritesButGraceIsReadOnly() {
        #expect(TeamPlanStatus.active.allowsTeamRead)
        #expect(TeamPlanStatus.active.allowsTeamWrite)
        #expect(TeamPlanStatus.grace.allowsTeamRead)
        #expect(!TeamPlanStatus.grace.allowsTeamWrite)
        #expect(!TeamPlanStatus.paused.allowsTeamRead)
        #expect(!TeamPlanStatus.paused.allowsTeamWrite)
    }

    @Test func currentTeamLoadCoalescingKeepsLatestQueuedRequest() {
        let first = TeamCurrentTeamLoadRequest(displayName: "Owner", email: "owner@example.com")
        let latest = TeamCurrentTeamLoadRequest(displayName: "Rep", email: "rep@example.com")

        #expect(
            TeamCurrentTeamLoadCoalescingPolicy.queuedRequest(current: nil, incoming: first) == first
        )
        #expect(
            TeamCurrentTeamLoadCoalescingPolicy.queuedRequest(current: first, incoming: latest) == latest
        )
    }

    @Test func currentTeamLoadReusesHealthyRealtimeListenersAcrossTabs() {
        #expect(TeamCurrentTeamLoadPolicy.shouldReuseActiveListeners(
            forceRefresh: false,
            hasActiveTeam: true,
            hasCurrentMember: true,
            listenerCount: 8
        ))
        #expect(!TeamCurrentTeamLoadPolicy.shouldReuseActiveListeners(
            forceRefresh: true,
            hasActiveTeam: true,
            hasCurrentMember: true,
            listenerCount: 8
        ))
        #expect(!TeamCurrentTeamLoadPolicy.shouldReuseActiveListeners(
            forceRefresh: false,
            hasActiveTeam: true,
            hasCurrentMember: true,
            listenerCount: 0
        ))
    }

    @Test func teamFirestoreMergePayloadUsesExplicitNullsForClearedFields() {
        #expect(TeamFirestoreMergePayloadValue.nullable(nil as String?) is NSNull)
        #expect(TeamFirestoreMergePayloadValue.nullable(nil as Double?) is NSNull)
        #expect(TeamFirestoreMergePayloadValue.nullable(nil as Date?) is NSNull)
        #expect(TeamFirestoreMergePayloadValue.nullable("rep@example.com") as? String == "rep@example.com")
        #expect(TeamFirestoreMergePayloadValue.nullable(125.0) as? Double == 125.0)
    }

    @Test func firestoreRESTProbeLogLabelsPublicRulesDenialsAsExpected() {
        let summary = TeamFirestoreRESTProbeLogPolicy.summary(
            label: "Firestore public REST probe",
            statusCode: 403,
            body: #"{"error":{"message":"Missing or insufficient permissions."}}"#,
            publicProbe: true
        )

        #expect(summary.contains("status: 403"))
        #expect(summary.contains("expected if Firestore rules block public reads"))
        #expect(summary.contains("Missing or insufficient permissions"))
    }

    @Test func firestoreRESTProbeLogDoesNotHideAuthenticatedForbiddenResponses() {
        let summary = TeamFirestoreRESTProbeLogPolicy.summary(
            label: "Firestore authenticated REST probe",
            statusCode: 403,
            body: #"{"error":{"message":"App Check token required."}}"#,
            publicProbe: false
        )

        #expect(summary.contains("status: 403"))
        #expect(!summary.contains("expected if Firestore rules block public reads"))
        #expect(summary.contains("App Check token required"))
    }

    @Test func teamRuleRestrictedPayloadsDoNotAddNullFieldsForLegacyDocuments() {
        let omittedString = TeamFirestoreMergePayloadValue.omittedWhenNil(nil as String?)
        let omittedDouble = TeamFirestoreMergePayloadValue.omittedWhenNil(nil as Double?)
        let omittedDate = TeamFirestoreMergePayloadValue.omittedWhenNil(nil as Date?)

        #expect(TeamFirestoreMergePayloadValue.isNilOptional(omittedString))
        #expect(TeamFirestoreMergePayloadValue.isNilOptional(omittedDouble))
        #expect(TeamFirestoreMergePayloadValue.isNilOptional(omittedDate))
        #expect(!TeamFirestoreMergePayloadValue.isNilOptional(TeamFirestoreMergePayloadValue.nullable(nil as String?)))
        #expect(TeamFirestoreMergePayloadValue.omittedWhenNil("rep@example.com") as? String == "rep@example.com")
    }

    @Test func ownerTeamDefaultsToIncludedThreeSeats() {
        let now = Date(timeIntervalSince1970: 1_000)
        let team = TeamWorkspace.newOwnerTeam(
            id: "team-1",
            name: "Daniel's Team",
            ownerUserId: "owner-1",
            now: now
        )

        #expect(team.id == "team-1")
        #expect(team.name == "Daniel's Team")
        #expect(team.ownerUserId == "owner-1")
        #expect(team.planStatus == .active)
        #expect(team.effectivePlanStatus() == .active)
        #expect(team.memberLimit == 3)
        #expect(team.createdAt == now)
        #expect(team.updatedAt == now)
    }

    @Test("Team plan dates adopt legacy workspaces and enforce grace locally")
    func effectiveTeamPlanStatusMigration() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        var team = TeamWorkspace.newOwnerTeam(
            id: "team-plan-migration",
            name: "Legacy Team",
            ownerUserId: "owner",
            now: now.addingTimeInterval(-1_000)
        )

        #expect(team.effectivePlanStatus(now: now) == .active)

        team.planExpiresAt = now.addingTimeInterval(-60)
        team.graceEndsAt = now.addingTimeInterval(60)
        #expect(team.effectivePlanStatus(now: now) == .grace)

        team.graceEndsAt = now.addingTimeInterval(-1)
        #expect(team.effectivePlanStatus(now: now) == .paused)

        team.planStatus = .paused
        team.planExpiresAt = now.addingTimeInterval(60)
        #expect(team.effectivePlanStatus(now: now) == .paused)
    }

    @Test("Team purchases use a stable account token without changing legacy plan recognition")
    func teamPurchaseAccountTokenMigration() {
        let ownerToken = PaywallManager.teamAppAccountToken(for: "owner-1")
        #expect(ownerToken == PaywallManager.teamAppAccountToken(for: "owner-1"))
        #expect(ownerToken != PaywallManager.teamAppAccountToken(for: "owner-2"))
        #expect(ownerToken == UUID(uuidString: "5dea72f7-ed61-55f2-b315-9dfefbbffd78"))
        #expect(PaywallManager.SubscriptionPlan.teamMonthly.isTeamPlan)
        #expect(PaywallManager.SubscriptionPlan.teamYearly.isTeamPlan)
        #expect(!PaywallManager.SubscriptionPlan.weekly.isTeamPlan)
        #expect(!PaywallManager.SubscriptionPlan.yearly.isTeamPlan)

        #expect(SubscriptionProductCatalog.recognizes("com.d2dadvancer.weekly"))
        #expect(SubscriptionProductCatalog.recognizes("com.d2dadvancer.yearly"))
        #expect(SubscriptionProductCatalog.recognizes("com.d2dadvancer.monthly"))
        #expect(SubscriptionProductCatalog.recognizes("com.d2dadvancer.team.monthly"))
        #expect(SubscriptionProductCatalog.recognizes("com.d2dadvancer.team.yearly"))
        #expect(SubscriptionProductCatalog.recognizes("com.d2dadvancer.solo.monthly"))
        #expect(SubscriptionProductCatalog.recognizes("com.d2dadvancer.solo.yearly"))
        #expect(SubscriptionProductCatalog.recognizes("com.d2dadvancer.team3.monthly"))
        #expect(SubscriptionProductCatalog.recognizes("com.d2dadvancer.team3.yearly"))
        #expect(!SubscriptionProductCatalog.recognizes("com.d2dadvancer.unknown"))
        #expect(SubscriptionProductCatalog.team == [
            "com.d2dadvancer.team.monthly",
            "com.d2dadvancer.team.yearly",
            "com.d2dadvancer.team3.monthly",
            "com.d2dadvancer.team3.yearly"
        ])
    }

    @Test func ownerAndRepMemberRecordsUseExpectedRolesAndInviteLink() {
        let joinedAt = Date(timeIntervalSince1970: 2_000)
        let owner = TeamMember.owner(
            teamId: "team-1",
            userId: "owner-1",
            displayName: "Daniel",
            email: "owner@example.com",
            joinedAt: joinedAt
        )
        let rep = TeamMember.rep(
            teamId: "team-1",
            userId: "rep-1",
            displayName: "Mike",
            email: nil,
            acceptedInviteId: "ABC12345",
            joinedAt: joinedAt
        )

        #expect(owner.role == .owner)
        #expect(owner.status == .active)
        #expect(owner.workType == .owner)
        #expect(owner.displayRoleTitle == "Owner")
        #expect(owner.acceptedInviteId == nil)
        #expect(rep.role == .member)
        #expect(rep.status == .active)
        #expect(rep.workType == .salesRep)
        #expect(rep.isSalesRep)
        #expect(!rep.isTechnician)
        #expect(rep.displayRoleTitle == "Sales Rep")
        #expect(rep.acceptedInviteId == "ABC12345")
    }

    @Test func pendingInviteMemberIsDetectableAndCancellableByOwner() {
        let pending = TeamMember.rep(
            teamId: "team-1",
            userId: "\(TeamFirebaseSchema.pendingRepUserPrefix)-invite-1",
            displayName: "Pending Rep",
            email: nil,
            acceptedInviteId: "invite-1",
            joinedAt: Date(timeIntervalSince1970: 2_000)
        )
        let accepted = TeamMember.rep(
            teamId: "team-1",
            userId: "real-rep-1",
            displayName: "Mike",
            email: nil,
            acceptedInviteId: "invite-2",
            joinedAt: Date(timeIntervalSince1970: 3_000)
        )

        #expect(pending.isPendingInvite)
        #expect(TeamAccessPolicy.canCancelPendingInvite(role: .owner, member: pending))
        #expect(!accepted.isPendingInvite)
        #expect(!TeamAccessPolicy.canCancelPendingInvite(role: .owner, member: accepted))
        #expect(!TeamAccessPolicy.canCancelPendingInvite(role: .member, member: pending))
    }

    @Test func pendingInviteRosterDeduplicatesOptimisticLocalAndRealtimeRows() {
        let now = Date(timeIntervalSince1970: 2_000)
        let owner = TeamMember.owner(
            teamId: "team-1",
            userId: "owner-1",
            displayName: "Owner",
            email: nil,
            joinedAt: now
        )
        let pending = TeamMember.rep(
            teamId: "team-1",
            userId: "\(TeamFirebaseSchema.pendingRepUserPrefix)-AB12CD34",
            displayName: "Pending Rep",
            email: nil,
            acceptedInviteId: "AB12CD34",
            joinedAt: now.addingTimeInterval(10)
        )

        let normalized = TeamMemberRoster.normalized([pending, owner, pending])

        #expect(normalized.map(\.userId) == [owner.userId, pending.userId])
        #expect(TeamMemberRoster.activeSeatCount([pending, owner, pending]) == 2)
        #expect(pending.pendingInviteDisplayCode == "AB12CD34")
    }

    @Test func teamWorkspaceRequiresAuthenticatedBackendIdentity() {
        #expect(TeamAuthPolicy.canUseTeamWorkspace(isFirebaseAuthenticated: true))
        #expect(!TeamAuthPolicy.canUseTeamWorkspace(isFirebaseAuthenticated: false))
    }

    @Test func teamWorkspaceUsesAppleVisibleIdentityWithFirebaseBackend() {
        #expect(TeamAuthPolicy.visibleIdentityProvider == .apple)
        #expect(TeamAuthPolicy.backendIdentityProvider == .firebase)
        #expect(TeamAuthPolicy.signInButtonTitle == "Continue with Apple")
        #expect(TeamAuthPolicy.signInRequiredTitle == "Apple Sign-In Required")
    }

    @Test func teamCachedMembershipLocalStoreDistinguishesValidExpiredAndCorruptData() throws {
        let suiteName = "TeamCachedMembershipLocalStoreTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let key = "team_cached_membership_test"
        let now = Date(timeIntervalSince1970: 50_000)
        let team = TeamWorkspace.newOwnerTeam(
            id: "team-cache",
            name: "Cached Team",
            ownerUserId: "owner-cache",
            now: now
        )
        let member = TeamMember.owner(
            teamId: team.id,
            userId: team.ownerUserId,
            displayName: "Owner",
            email: "owner@example.com",
            joinedAt: now
        )
        let snapshot = TeamCachedMembershipSnapshot(team: team, member: member, savedAt: now)

        #expect(try TeamCachedMembershipLocalStore.loadFreshSnapshot(
            from: defaults,
            key: key,
            now: now,
            maxAge: 14 * 24 * 60 * 60
        ) == nil)

        try TeamCachedMembershipLocalStore.save(snapshot, to: defaults, key: key)
        let loaded = try #require(try TeamCachedMembershipLocalStore.loadFreshSnapshot(
            from: defaults,
            key: key,
            now: now.addingTimeInterval(60),
            maxAge: 14 * 24 * 60 * 60
        ))
        #expect(loaded.team.id == team.id)
        #expect(loaded.member.userId == member.userId)

        #expect(try TeamCachedMembershipLocalStore.loadFreshSnapshot(
            from: defaults,
            key: key,
            now: now.addingTimeInterval(15 * 24 * 60 * 60),
            maxAge: 14 * 24 * 60 * 60
        ) == nil)

        defaults.set(Data("not-json".utf8), forKey: key)
        #expect(throws: Error.self) {
            try TeamCachedMembershipLocalStore.loadFreshSnapshot(
                from: defaults,
                key: key,
                now: now,
                maxAge: 14 * 24 * 60 * 60
            )
        }
    }

    @Test func firebaseTeamInvitesUseSingleUseCodesAndAssignedRecords() {
        #expect(TeamFirebaseSchema.inviteDelivery == .firebaseInviteCode)
        #expect(TeamFirebaseSchema.sharePrivacyModel == .assignedFirebaseRecords)
        #expect(TeamFirebaseSchema.inviteExpirationInterval == 7 * 24 * 60 * 60)
    }

    @Test func firebaseInviteDisplaysUppercaseCode() {
        let invite = TeamInvite(
            code: "ab12cd34",
            teamId: "team-1",
            expiresAt: Date(timeIntervalSince1970: 1_000)
        )

        #expect(invite.id == "ab12cd34")
        #expect(invite.displayCode == "AB12CD34")
    }

    @Test func memberCanReadOnlyAssignedLeadWhenPlanIsReadable() {
        let lead = TeamLead(
            id: "lead-1",
            teamId: "team-1",
            name: "Assigned Lead",
            address: "100 Main St",
            phone: nil,
            email: nil,
            latitude: 43,
            longitude: -79,
            status: .interested,
            assignedToUserId: "rep-1",
            createdByUserId: "rep-1",
            updatedByUserId: "rep-1",
            createdAt: Date(timeIntervalSince1970: 1_000),
            updatedAt: Date(timeIntervalSince1970: 1_000)
        )

        #expect(TeamAccessPolicy.canReadLead(userId: "owner-1", role: .owner, planStatus: .active, lead: lead))
        #expect(TeamAccessPolicy.canReadLead(userId: "rep-1", role: .member, planStatus: .active, lead: lead))
        #expect(!TeamAccessPolicy.canReadLead(userId: "rep-2", role: .member, planStatus: .active, lead: lead))
        #expect(!TeamAccessPolicy.canReadLead(userId: "rep-1", role: .member, planStatus: .paused, lead: lead))
    }

    @Test func placeholderOwnerAndRepsKeepAssignedWorkPrivate() {
        let team = TeamWorkspace.newOwnerTeam(
            id: "team-placeholder",
            name: "Placeholder Team",
            ownerUserId: "owner-placeholder",
            now: Date(timeIntervalSince1970: 1_000)
        )
        let repA = TeamMember.rep(
            teamId: team.id,
            userId: "rep-a-placeholder",
            displayName: "Rep A",
            email: nil,
            acceptedInviteId: "invite-a"
        )
        let repB = TeamMember.rep(
            teamId: team.id,
            userId: "rep-b-placeholder",
            displayName: "Rep B",
            email: nil,
            acceptedInviteId: "invite-b"
        )

        let repALead = TeamLead.newRepLead(
            teamId: team.id,
            creatorUserId: repA.userId,
            name: "Rep A Lead",
            address: "10 King St",
            coordinate: TeamCoordinate(latitude: 43.65, longitude: -79.38)
        )
        let repBLead = TeamLead.newRepLead(
            teamId: team.id,
            creatorUserId: repB.userId,
            name: "Rep B Lead",
            address: "20 Queen St",
            coordinate: TeamCoordinate(latitude: 43.66, longitude: -79.39)
        )

        #expect(TeamAccessPolicy.canReadLead(userId: team.ownerUserId, role: .owner, planStatus: team.planStatus, lead: repALead))
        #expect(TeamAccessPolicy.canReadLead(userId: team.ownerUserId, role: .owner, planStatus: team.planStatus, lead: repBLead))
        #expect(TeamAccessPolicy.canReadLead(userId: repA.userId, role: .member, planStatus: team.planStatus, lead: repALead))
        #expect(!TeamAccessPolicy.canReadLead(userId: repA.userId, role: .member, planStatus: team.planStatus, lead: repBLead))
        #expect(TeamAccessPolicy.canReadLead(userId: repB.userId, role: .member, planStatus: team.planStatus, lead: repBLead))
        #expect(!TeamAccessPolicy.canReadLead(userId: repB.userId, role: .member, planStatus: team.planStatus, lead: repALead))
    }

    @Test func placeholderRepBookingsAndLocationGraphsStayAssignedOnly() {
        let now = Date(timeIntervalSince1970: 4_000)
        let ownerUserId = "owner-placeholder"
        let repAUserId = "rep-a-placeholder"
        let repBUserId = "rep-b-placeholder"
        let repABooking = TeamBooking(
            id: "booking-a",
            teamId: "team-placeholder",
            leadId: "lead-a",
            assignedToUserId: repAUserId,
            title: "Rep A Booking",
            notes: "",
            startDate: now,
            endDate: now.addingTimeInterval(3_600),
            location: "10 King St",
            status: .scheduled,
            createdByUserId: ownerUserId,
            updatedByUserId: ownerUserId,
            createdAt: now,
            updatedAt: now
        )
        let repASession = TeamDutySession.ended(
            id: "session-a",
            teamId: "team-placeholder",
            repUserId: repAUserId,
            startedAt: now,
            endedAt: now.addingTimeInterval(7_200),
            distanceMeters: 1_800
        )

        #expect(TeamAccessPolicy.canWriteAssignedRecord(userId: ownerUserId, role: .owner, planStatus: .active, assignedToUserId: repABooking.assignedToUserId))
        #expect(TeamAccessPolicy.canWriteAssignedRecord(userId: repAUserId, role: .member, planStatus: .active, assignedToUserId: repABooking.assignedToUserId))
        #expect(!TeamAccessPolicy.canWriteAssignedRecord(userId: repBUserId, role: .member, planStatus: .active, assignedToUserId: repABooking.assignedToUserId))
        #expect(TeamAccessPolicy.canViewDutySession(userId: ownerUserId, role: .owner, planStatus: .active, session: repASession))
        #expect(TeamAccessPolicy.canViewDutySession(userId: repAUserId, role: .member, planStatus: .active, session: repASession))
        #expect(!TeamAccessPolicy.canViewDutySession(userId: repBUserId, role: .member, planStatus: .active, session: repASession))
    }

    @Test func repsCanViewOwnerDutyLocationButNotOtherReps() {
        let now = Date(timeIntervalSince1970: 4_500)
        let ownerSession = TeamDutySession(
            id: "owner-session",
            teamId: "team-placeholder",
            repUserId: "owner-placeholder",
            startedAt: now,
            endedAt: nil,
            status: .active,
            lastLocationAt: now,
            distanceMeters: 0,
            createdAt: now,
            deleteAfter: nil
        )
        let otherRepSession = TeamDutySession(
            id: "rep-b-session",
            teamId: "team-placeholder",
            repUserId: "rep-b-placeholder",
            startedAt: now,
            endedAt: nil,
            status: .active,
            lastLocationAt: now,
            distanceMeters: 0,
            createdAt: now,
            deleteAfter: nil
        )

        #expect(TeamAccessPolicy.canViewDutySession(
            userId: "rep-a-placeholder",
            role: .member,
            planStatus: .active,
            session: ownerSession,
            ownerUserId: "owner-placeholder"
        ))
        #expect(!TeamAccessPolicy.canViewDutySession(
            userId: "rep-a-placeholder",
            role: .member,
            planStatus: .active,
            session: otherRepSession,
            ownerUserId: "owner-placeholder"
        ))
        #expect(!TeamAccessPolicy.canViewDutySession(
            userId: "rep-a-placeholder",
            role: .member,
            planStatus: .paused,
            session: ownerSession,
            ownerUserId: "owner-placeholder"
        ))
    }

    @Test func repCreatedLeadIsAssignedToRepAtCreation() {
        let lead = TeamLead.newRepLead(
            teamId: "team-1",
            creatorUserId: "rep-1",
            name: "New Lead",
            address: "200 Queen St",
            coordinate: TeamCoordinate(latitude: 43.6532, longitude: -79.3832),
            now: Date(timeIntervalSince1970: 3_000)
        )

        #expect(lead.createdByUserId == "rep-1")
        #expect(lead.assignedToUserId == "rep-1")
        #expect(lead.updatedByUserId == "rep-1")
        #expect(lead.createdAt == Date(timeIntervalSince1970: 3_000))
    }

    @Test func dutySessionDeleteDateIsThirtyDaysAfterEnd() {
        let endedAt = Date(timeIntervalSince1970: 10_000)
        let session = TeamDutySession.ended(
            id: "session-1",
            teamId: "team-1",
            repUserId: "rep-1",
            startedAt: Date(timeIntervalSince1970: 8_000),
            endedAt: endedAt,
            distanceMeters: 1200
        )

        #expect(session.deleteAfter == endedAt.addingTimeInterval(30 * 24 * 60 * 60))
    }

    @Test func ownerImportantNotificationFiresOnlyForImportantTransitions() {
        let before = TeamLead.newRepLead(
            teamId: "team-1",
            creatorUserId: "rep-1",
            name: "Lead",
            address: "100 Main St",
            coordinate: TeamCoordinate(latitude: 43, longitude: -79),
            now: Date(timeIntervalSince1970: 1_000)
        )
        var highPriority = before
        highPriority.isHighPriority = true
        highPriority.highPriorityReason = "Ready to book"

        #expect(TeamNotificationPolicy.ownerLeadEvents(before: before, after: highPriority) == [.highPriority])

        var editedAgain = highPriority
        editedAgain.notes = "Extra note"
        #expect(TeamNotificationPolicy.ownerLeadEvents(before: highPriority, after: editedAgain).isEmpty)

        var converted = editedAgain
        converted.status = .converted
        #expect(TeamNotificationPolicy.ownerLeadEvents(before: editedAgain, after: converted) == [.converted])
    }

    @Test func repCreatedImportantLeadNotifiesOwnerImmediately() {
        var interested = TeamLead.newRepLead(
            teamId: "team-1",
            creatorUserId: "rep-1",
            name: "Interested Lead",
            address: "120 Main St",
            coordinate: TeamCoordinate(latitude: 43, longitude: -79),
            now: Date(timeIntervalSince1970: 2_000)
        )
        interested.status = .interested

        var highPriority = interested
        highPriority.isHighPriority = true
        highPriority.highPriorityReason = "Large job"

        #expect(TeamNotificationPolicy.ownerLeadEvents(before: nil, after: interested) == [.interested])
        #expect(TeamNotificationPolicy.ownerLeadEvents(before: nil, after: highPriority) == [.interested, .highPriority])
        #expect(TeamOwnerLeadEvent.highPriority.ownerTitle == "Rep marked a lead high priority")
        #expect(TeamFirebaseSchema.Collection.ownerNotifications == "ownerNotifications")
    }

    @Test func dutyLocationPointDeleteDateIsThirtyDaysAfterRecordedAt() {
        let recordedAt = Date(timeIntervalSince1970: 5_000)
        let point = TeamDutyLocationPoint(
            teamId: "team-1",
            sessionId: "session-1",
            repUserId: "rep-1",
            coordinate: TeamCoordinate(latitude: 43, longitude: -79),
            horizontalAccuracy: 12,
            recordedAt: recordedAt
        )

        #expect(point.deleteAfter == recordedAt.addingTimeInterval(30 * 24 * 60 * 60))
    }

    @Test func onlyActivePlanCanStartDutySession() {
        #expect(TeamAccessPolicy.canStartDutySession(planStatus: .active, role: .member))
        #expect(TeamAccessPolicy.canStartDutySession(planStatus: .active, role: .owner))
        #expect(!TeamAccessPolicy.canStartDutySession(planStatus: .grace, role: .member))
        #expect(!TeamAccessPolicy.canStartDutySession(planStatus: .paused, role: .member))
    }

    @Test func ownerRepWorkspacesShowAssignedWorkAndOnlyActiveLiveLocations() {
        let now = Date(timeIntervalSince1970: 20_000)
        let owner = TeamMember.owner(
            teamId: "team-visual",
            userId: "owner-1",
            displayName: "Owner",
            email: nil,
            joinedAt: now
        )
        let repA = TeamMember.rep(
            teamId: "team-visual",
            userId: "rep-a",
            displayName: "Mike",
            email: nil,
            acceptedInviteId: "INVITEA",
            joinedAt: now
        )
        let repB = TeamMember.rep(
            teamId: "team-visual",
            userId: "rep-b",
            displayName: "Sarah",
            email: nil,
            acceptedInviteId: "INVITEB",
            joinedAt: now.addingTimeInterval(10)
        )
        let pending = TeamMember.rep(
            teamId: "team-visual",
            userId: "\(TeamFirebaseSchema.pendingRepUserPrefix)-INVITEC",
            displayName: "Pending Rep",
            email: nil,
            acceptedInviteId: "INVITEC",
            joinedAt: now.addingTimeInterval(20)
        )

        var repALead = TeamLead.newRepLead(
            teamId: "team-visual",
            creatorUserId: repA.userId,
            name: "High Value Home",
            address: "10 King St",
            coordinate: TeamCoordinate(latitude: 43.6501, longitude: -79.3801),
            now: now
        )
        repALead.isHighPriority = true
        repALead.updatedAt = now.addingTimeInterval(60)
        let repBLead = TeamLead.newRepLead(
            teamId: "team-visual",
            creatorUserId: repB.userId,
            name: "Booked Home",
            address: "20 Queen St",
            coordinate: TeamCoordinate(latitude: 43.651, longitude: -79.381),
            now: now
        )
        let repABooking = TeamBooking(
            id: "booking-a",
            teamId: "team-visual",
            leadId: repALead.id,
            assignedToUserId: repA.userId,
            title: "Window Cleaning",
            notes: "",
            startDate: now.addingTimeInterval(3_600),
            endDate: now.addingTimeInterval(5_400),
            location: "10 King St",
            status: .scheduled,
            createdByUserId: owner.userId,
            updatedByUserId: owner.userId,
            createdAt: now,
            updatedAt: now
        )
        let repAActiveSession = TeamDutySession(
            id: "session-a",
            teamId: "team-visual",
            repUserId: repA.userId,
            startedAt: now,
            endedAt: nil,
            status: .active,
            lastLocationAt: now.addingTimeInterval(120),
            distanceMeters: 250,
            createdAt: now,
            deleteAfter: nil
        )
        let repBEndedSession = TeamDutySession.ended(
            id: "session-b",
            teamId: "team-visual",
            repUserId: repB.userId,
            startedAt: now,
            endedAt: now.addingTimeInterval(300),
            distanceMeters: 700
        )
        let oldPoint = TeamDutyLocationPoint(
            teamId: "team-visual",
            sessionId: repAActiveSession.id,
            repUserId: repA.userId,
            coordinate: TeamCoordinate(latitude: 43.6502, longitude: -79.3802),
            horizontalAccuracy: 8,
            recordedAt: now.addingTimeInterval(30)
        )
        let latestPoint = TeamDutyLocationPoint(
            teamId: "team-visual",
            sessionId: repAActiveSession.id,
            repUserId: repA.userId,
            coordinate: TeamCoordinate(latitude: 43.6508, longitude: -79.3808),
            horizontalAccuracy: 7,
            recordedAt: now.addingTimeInterval(120)
        )
        let endedSessionPoint = TeamDutyLocationPoint(
            teamId: "team-visual",
            sessionId: repBEndedSession.id,
            repUserId: repB.userId,
            coordinate: TeamCoordinate(latitude: 43.66, longitude: -79.39),
            horizontalAccuracy: 9,
            recordedAt: now.addingTimeInterval(200)
        )

        let workspaces = TeamRepWorkspace.makeOwnerWorkspaces(
            members: [owner, repB, pending, repA],
            leads: [repBLead, repALead],
            bookings: [repABooking],
            dutySessions: [repBEndedSession, repAActiveSession],
            dutyLocationPoints: [latestPoint, endedSessionPoint, oldPoint]
        )

        #expect(workspaces.map(\.member.userId) == [repA.userId, repB.userId])
        #expect(workspaces[0].assignedLeads.map(\.id) == [repALead.id])
        #expect(workspaces[0].assignedBookings.map(\.id) == [repABooking.id])
        #expect(workspaces[0].activeSession?.id == repAActiveSession.id)
        #expect(workspaces[0].liveLocation?.id == latestPoint.id)
        #expect(workspaces[0].routePoints.map(\.id) == [oldPoint.id, latestPoint.id])
        #expect(workspaces[0].mapItemCount == 3)
        #expect(workspaces[1].assignedLeads.map(\.id) == [repBLead.id])
        #expect(workspaces[1].activeSession == nil)
        #expect(workspaces[1].liveLocation == nil)
        #expect(workspaces[1].routePoints.map(\.id) == [endedSessionPoint.id])
    }

    @Test func locationSharingPolicyUploadsFirstMovedOrHeartbeatPointsWithoutBursting() {
        let now = Date(timeIntervalSince1970: 30_000)
        let first = TeamCoordinate(latitude: 43.6500, longitude: -79.3800)
        let tinyMove = TeamCoordinate(latitude: 43.65001, longitude: -79.38001)
        let meaningfulMove = TeamCoordinate(latitude: 43.6504, longitude: -79.3804)

        #expect(TeamLocationSharingPolicy.shouldUploadLocation(
            lastUploadAt: nil,
            lastCoordinate: nil,
            newCoordinate: first,
            now: now
        ))
        #expect(!TeamLocationSharingPolicy.shouldUploadLocation(
            lastUploadAt: now.addingTimeInterval(-10),
            lastCoordinate: first,
            newCoordinate: tinyMove,
            now: now
        ))
        #expect(!TeamLocationSharingPolicy.shouldUploadLocation(
            lastUploadAt: now.addingTimeInterval(-10),
            lastCoordinate: first,
            newCoordinate: meaningfulMove,
            now: now
        ))
        #expect(!TeamLocationSharingPolicy.shouldUploadLocation(
            lastUploadAt: now.addingTimeInterval(-45),
            lastCoordinate: first,
            newCoordinate: tinyMove,
            now: now
        ))
        #expect(TeamLocationSharingPolicy.shouldUploadLocation(
            lastUploadAt: now.addingTimeInterval(-45),
            lastCoordinate: first,
            newCoordinate: meaningfulMove,
            now: now
        ))
        #expect(TeamLocationSharingPolicy.shouldUploadLocation(
            lastUploadAt: now.addingTimeInterval(-130),
            lastCoordinate: first,
            newCoordinate: tinyMove,
            now: now
        ))
        #expect(!TeamLocationSharingPolicy.shouldUploadLocation(
            lastUploadAt: now.addingTimeInterval(-130),
            lastCoordinate: first,
            newCoordinate: meaningfulMove,
            usageLevel: .warning,
            now: now
        ))
    }

    @Test func localWriteLimiterStopsBurstsAndRecoversAfterItsWindow() {
        let now = Date(timeIntervalSince1970: 31_000)
        var limiter = TeamLocalWriteLimiter(window: 60, maximumUnits: 5)

        #expect(limiter.retryDelayIfBlocked(units: 3, now: now) == nil)
        #expect(limiter.retryDelayIfBlocked(units: 2, now: now.addingTimeInterval(1)) == nil)
        #expect(limiter.retryDelayIfBlocked(units: 1, now: now.addingTimeInterval(2)) == 58)
        #expect(limiter.retryDelayIfBlocked(units: 5, now: now.addingTimeInterval(61)) == nil)
    }

    @Test func teamUsageControlRecoversFromCooldownButKeepsCollectionCapacity() {
        let now = Date(timeIntervalSince1970: 32_000)
        var control = TeamUsageControl.normal
        control.level = .limited
        control.writesAllowed = false
        control.limitedUntil = now.addingTimeInterval(60)
        control.blockedCollections = [TeamFirebaseSchema.Collection.leads]

        #expect(!control.allowsWrite(now: now))
        #expect(control.allowsWrite(now: now.addingTimeInterval(61)))
        #expect(!control.allowsCreate(
            in: TeamFirebaseSchema.Collection.leads,
            now: now.addingTimeInterval(61)
        ))
        #expect(control.allowsCreate(
            in: TeamFirebaseSchema.Collection.bookings,
            now: now.addingTimeInterval(61)
        ))
    }

    @Test func ownerSurfaceSummaryRollsTeamWorkIntoMainScreens() {
        let now = Date(timeIntervalSince1970: 40_000)
        let team = TeamWorkspace.newOwnerTeam(
            id: "team-main-surface",
            name: "Main Surface Team",
            ownerUserId: "owner-1",
            now: now
        )
        let owner = TeamMember.owner(
            teamId: team.id,
            userId: "owner-1",
            displayName: "Owner",
            email: nil,
            joinedAt: now
        )
        let rep = TeamMember.rep(
            teamId: team.id,
            userId: "rep-1",
            displayName: "Mike",
            email: nil,
            acceptedInviteId: "INVITE1",
            joinedAt: now
        )
        var interestedLead = TeamLead.newRepLead(
            teamId: team.id,
            creatorUserId: rep.userId,
            name: "Interested Home",
            address: "10 King St",
            coordinate: TeamCoordinate(latitude: 43.65, longitude: -79.38),
            now: now
        )
        interestedLead.status = .interested
        var highPriorityLead = TeamLead.newRepLead(
            teamId: team.id,
            creatorUserId: rep.userId,
            name: "High Priority Home",
            address: "20 Queen St",
            coordinate: TeamCoordinate(latitude: 43.66, longitude: -79.39),
            now: now.addingTimeInterval(60)
        )
        highPriorityLead.isHighPriority = true
        let booking = TeamBooking(
            id: "booking-1",
            teamId: team.id,
            leadId: highPriorityLead.id,
            assignedToUserId: rep.userId,
            title: "Window Cleaning",
            notes: "",
            startDate: now.addingTimeInterval(3_600),
            endDate: now.addingTimeInterval(5_400),
            location: "20 Queen St",
            status: .scheduled,
            createdByUserId: owner.userId,
            updatedByUserId: owner.userId,
            createdAt: now,
            updatedAt: now
        )
        let activeSession = TeamDutySession(
            id: "session-1",
            teamId: team.id,
            repUserId: rep.userId,
            startedAt: now,
            endedAt: nil,
            status: .active,
            lastLocationAt: now.addingTimeInterval(120),
            distanceMeters: 300,
            createdAt: now,
            deleteAfter: nil
        )
        let notification = TeamOwnerNotification(
            id: "notification-1",
            teamId: team.id,
            leadId: highPriorityLead.id,
            assignedToUserId: rep.userId,
            createdByUserId: rep.userId,
            event: .highPriority,
            title: TeamOwnerLeadEvent.highPriority.ownerTitle,
            message: "Mike marked High Priority Home high priority.",
            createdAt: now,
            readAt: nil
        )

        let summary = TeamWorkspaceSurfaceSummary.make(
            team: team,
            currentMember: owner,
            members: [owner, rep],
            leads: [interestedLead, highPriorityLead],
            bookings: [booking],
            dutySessions: [activeSession],
            dutyLocationPoints: [
                TeamDutyLocationPoint(
                    teamId: team.id,
                    sessionId: activeSession.id,
                    repUserId: rep.userId,
                    coordinate: TeamCoordinate(latitude: 43.6502, longitude: -79.3802),
                    horizontalAccuracy: 8,
                    recordedAt: now.addingTimeInterval(120)
                )
            ],
            ownerNotifications: [notification],
            now: now
        )

        #expect(summary?.role == .owner)
        #expect(summary?.workspaces.count == 1)
        #expect(summary?.activeRepCount == 1)
        #expect(summary?.teamLeadCount == 2)
        #expect(summary?.importantLeadCount == 2)
        #expect(summary?.upcomingBookingCount == 1)
        #expect(summary?.unreadNotificationCount == 1)
        #expect(summary?.shouldShowMapShortcut == true)
        #expect(summary?.headline == "1 active worker")
    }

    @Test func closedTeamLeadsDoNotInflateOwnerAttentionOrHotClusterCounts() throws {
        let now = Date(timeIntervalSince1970: 40_500)
        let team = TeamWorkspace.newOwnerTeam(
            id: "team-closed-attention",
            name: "Closed Attention",
            ownerUserId: "owner-1",
            now: now
        )
        let owner = TeamMember.owner(
            teamId: team.id,
            userId: "owner-1",
            displayName: "Owner",
            email: nil,
            joinedAt: now
        )
        let rep = TeamMember.rep(
            teamId: team.id,
            userId: "rep-1",
            displayName: "Mike",
            email: nil,
            acceptedInviteId: "INVITE1",
            joinedAt: now
        )

        var interestedLead = TeamLead.newRepLead(
            teamId: team.id,
            creatorUserId: rep.userId,
            name: "Interested",
            address: "10 King St",
            coordinate: TeamCoordinate(latitude: 43.65, longitude: -79.38),
            now: now
        )
        interestedLead.status = .interested

        var convertedLead = TeamLead.newRepLead(
            teamId: team.id,
            creatorUserId: rep.userId,
            name: "Converted",
            address: "20 Queen St",
            coordinate: TeamCoordinate(latitude: 43.6501, longitude: -79.3801),
            now: now.addingTimeInterval(10)
        )
        convertedLead.status = .converted
        convertedLead.isHighPriority = true
        convertedLead.price = 900

        var rejectedLead = TeamLead.newRepLead(
            teamId: team.id,
            creatorUserId: rep.userId,
            name: "Rejected",
            address: "30 Queen St",
            coordinate: TeamCoordinate(latitude: 43.6502, longitude: -79.3802),
            now: now.addingTimeInterval(20)
        )
        rejectedLead.status = .notInterested
        rejectedLead.isHighPriority = true

        let leads = [interestedLead, convertedLead, rejectedLead]
        let summary = try #require(
            TeamWorkspaceSurfaceSummary.make(
                team: team,
                currentMember: owner,
                members: [owner, rep],
                leads: leads,
                bookings: [],
                dutySessions: [],
                dutyLocationPoints: [],
                ownerNotifications: [],
                now: now
            )
        )
        let today = TeamTodayWorkSummary.make(
            currentMember: owner,
            leads: leads,
            bookings: [],
            dutySessions: [],
            now: now
        )
        let closedCluster = TeamLeadClusterSummary(
            items: [convertedLead, rejectedLead].map {
                TeamLeadClusterItem(lead: $0, repName: rep.displayName)
            }
        )

        #expect(summary.importantLeadCount == 1)
        #expect(summary.badgeCount == 1)
        #expect(today.importantLeadCount == 1)
        #expect(!closedCluster.isImportant)
        #expect(closedCluster.highPriorityCount == 0)
        #expect(closedCluster.hotLeadCount == 0)
    }

    @Test func ownerEmptyTeamStillShowsMapShortcut() {
        let now = Date(timeIntervalSince1970: 49_000)
        let team = TeamWorkspace.newOwnerTeam(
            id: "team-empty-map",
            name: "Empty Map Team",
            ownerUserId: "owner-1",
            now: now
        )
        let owner = TeamMember.owner(
            teamId: team.id,
            userId: "owner-1",
            displayName: "Owner",
            email: nil,
            joinedAt: now
        )

        let summary = TeamWorkspaceSurfaceSummary.make(
            team: team,
            currentMember: owner,
            members: [owner],
            leads: [],
            bookings: [],
            dutySessions: [],
            dutyLocationPoints: [],
            ownerNotifications: [],
            now: now
        )

        #expect(summary?.headline == "0 workers")
        #expect(summary?.detailLine == "No urgent team activity")
        #expect(summary?.hasMapContent == false)
        #expect(summary?.hasUrgentActivity == false)
        #expect(summary?.shouldShowMapShortcut == true)
    }

    @Test func ownerMapShortcutSummaryKeepsWorkerAndUrgentCountsWithoutFullWorkspacePayload() {
        let now = Date(timeIntervalSince1970: 49_500)
        let team = TeamWorkspace.newOwnerTeam(
            id: "team-shortcut-map",
            name: "Shortcut Team",
            ownerUserId: "owner-1",
            now: now
        )
        let owner = TeamMember.owner(teamId: team.id, userId: "owner-1", displayName: "Owner", email: nil, joinedAt: now)
        let repA = TeamMember.rep(teamId: team.id, userId: "rep-a", displayName: "Rep A", email: nil, acceptedInviteId: "invite-a", joinedAt: now)
        let repB = TeamMember.rep(teamId: team.id, userId: "rep-b", displayName: "Rep B", email: nil, acceptedInviteId: "invite-b", joinedAt: now)

        var interestedLead = TeamLead.newRepLead(
            teamId: team.id,
            creatorUserId: repA.userId,
            name: "Interested",
            address: "10 King St",
            coordinate: TeamCoordinate(latitude: 43.65, longitude: -79.38),
            now: now
        )
        interestedLead.status = .interested

        let activeSession = TeamDutySession(
            id: "session-a",
            teamId: team.id,
            repUserId: repA.userId,
            startedAt: now,
            endedAt: nil,
            status: .active,
            lastLocationAt: now,
            distanceMeters: 0,
            createdAt: now,
            deleteAfter: nil
        )

        let summary = TeamWorkspaceSurfaceSummary.makeShortcut(
            team: team,
            currentMember: owner,
            members: [owner, repA, repB],
            leads: [interestedLead],
            bookings: [],
            dutySessions: [activeSession],
            ownerNotifications: [],
            now: now
        )

        #expect(summary?.headline == "1 active worker")
        #expect(summary?.workspaces.count == 2)
        #expect(summary?.importantLeadCount == 1)
        #expect(summary?.activeRepCount == 1)
        #expect(summary?.detailLine == "1 important")
        #expect(summary?.workspaces.allSatisfy { $0.assignedLeads.isEmpty && $0.routePoints.isEmpty } == true)
    }

    @Test func memberSurfaceSummaryOnlyShowsAssignedWork() {
        let now = Date(timeIntervalSince1970: 50_000)
        let team = TeamWorkspace.newOwnerTeam(
            id: "team-rep-surface",
            name: "Rep Surface Team",
            ownerUserId: "owner-1",
            now: now
        )
        let rep = TeamMember.rep(
            teamId: team.id,
            userId: "rep-1",
            displayName: "Mike",
            email: nil,
            acceptedInviteId: "INVITE1",
            joinedAt: now
        )
        var assigned = TeamLead.newRepLead(
            teamId: team.id,
            creatorUserId: rep.userId,
            name: "Assigned Home",
            address: "10 King St",
            coordinate: TeamCoordinate(latitude: 43.65, longitude: -79.38),
            now: now
        )
        assigned.status = .booked

        let summary = TeamWorkspaceSurfaceSummary.make(
            team: team,
            currentMember: rep,
            members: [rep],
            leads: [assigned],
            bookings: [],
            dutySessions: [],
            dutyLocationPoints: [],
            ownerNotifications: [],
            now: now
        )

        #expect(summary?.role == .member)
        #expect(summary?.workspaces.count == 1)
        #expect(summary?.activeRepCount == 0)
        #expect(summary?.teamLeadCount == 1)
        #expect(summary?.importantLeadCount == 1)
        #expect(summary?.unreadNotificationCount == 0)
        #expect(summary?.shouldShowMapShortcut == true)
        #expect(summary?.headline == "1 assigned lead")
    }

    @Test func technicianSurfaceSummaryShowsAssignedJobsInsteadOfSalesLeads() {
        let now = Date(timeIntervalSince1970: 55_000)
        let team = TeamWorkspace.newOwnerTeam(
            id: "team-tech-surface",
            name: "Tech Surface Team",
            ownerUserId: "owner-1",
            now: now
        )
        let technician = TeamMember.rep(
            teamId: team.id,
            userId: "tech-1",
            displayName: "Alex",
            email: nil,
            acceptedInviteId: "TECH1",
            workType: .technician,
            joinedAt: now
        )
        let booking = TeamBooking(
            id: "job-1",
            teamId: team.id,
            leadId: "lead-1",
            assignedToUserId: technician.userId,
            title: "Service Job",
            notes: "",
            startDate: now.addingTimeInterval(3_600),
            endDate: now.addingTimeInterval(5_400),
            location: "10 King St",
            status: .scheduled,
            createdByUserId: team.ownerUserId,
            updatedByUserId: team.ownerUserId,
            createdAt: now,
            updatedAt: now
        )

        let summary = TeamWorkspaceSurfaceSummary.make(
            team: team,
            currentMember: technician,
            members: [technician],
            leads: [],
            bookings: [booking],
            dutySessions: [],
            dutyLocationPoints: [],
            ownerNotifications: [],
            now: now
        )

        #expect(technician.isTechnician)
        #expect(technician.displayRoleTitle == "Technician")
        #expect(summary?.role == .member)
        #expect(summary?.currentMemberWorkType == .technician)
        #expect(summary?.teamLeadCount == 0)
        #expect(summary?.upcomingBookingCount == 1)
        #expect(summary?.headline == "1 assigned job")
    }

    @Test func ownerCanAssignLeadsOnlyToSalesRepsAndJobsToActiveWorkers() {
        let now = Date(timeIntervalSince1970: 60_000)
        let team = TeamWorkspace.newOwnerTeam(id: "team-ops", name: "Ops", ownerUserId: "owner-1", now: now)
        let owner = TeamMember.owner(teamId: team.id, userId: "owner-1", displayName: "Owner", email: nil, joinedAt: now)
        let rep = TeamMember.rep(teamId: team.id, userId: "rep-1", displayName: "Mike", email: nil, acceptedInviteId: "INVITE1", joinedAt: now)
        let technician = TeamMember.rep(teamId: team.id, userId: "tech-1", displayName: "Alex", email: nil, acceptedInviteId: "INVITET", workType: .technician, joinedAt: now)
        var removedRep = TeamMember.rep(teamId: team.id, userId: "rep-2", displayName: "Sarah", email: nil, acceptedInviteId: "INVITE2", joinedAt: now)
        removedRep.status = .removed

        let lead = TeamLead.newRepLead(
            teamId: team.id,
            creatorUserId: rep.userId,
            name: "Original Lead",
            address: "10 King St",
            coordinate: TeamCoordinate(latitude: 43.65, longitude: -79.38),
            now: now
        )
        let booking = TeamBooking(
            id: "booking-1",
            teamId: team.id,
            leadId: lead.id,
            assignedToUserId: rep.userId,
            title: "Window Cleaning",
            notes: "",
            startDate: now.addingTimeInterval(3_600),
            endDate: now.addingTimeInterval(5_400),
            location: lead.address,
            status: .scheduled,
            createdByUserId: owner.userId,
            updatedByUserId: owner.userId,
            createdAt: now,
            updatedAt: now
        )

        #expect(TeamAssignmentPolicy.canAssignLead(actor: owner, team: team, target: rep, lead: lead))
        #expect(!TeamAssignmentPolicy.canAssignLead(actor: owner, team: team, target: technician, lead: lead))
        #expect(!TeamAssignmentPolicy.canAssignLead(actor: rep, team: team, target: removedRep, lead: lead))
        #expect(!TeamAssignmentPolicy.canAssignLead(actor: owner, team: team, target: removedRep, lead: lead))
        #expect(TeamAssignmentPolicy.canAssignBooking(actor: owner, team: team, target: rep, booking: booking))
        #expect(TeamAssignmentPolicy.canAssignBooking(actor: owner, team: team, target: technician, booking: booking))
        #expect(!TeamAssignmentPolicy.canAssignBooking(actor: owner, team: team, target: removedRep, booking: booking))

        let assignedLead = TeamAssignmentPolicy.assign(lead, to: rep, by: owner, now: now.addingTimeInterval(10))
        let assignedBooking = TeamAssignmentPolicy.assign(booking, to: technician, by: owner, now: now.addingTimeInterval(10))
        #expect(assignedLead.assignedToUserId == rep.userId)
        #expect(assignedLead.updatedByUserId == owner.userId)
        #expect(assignedBooking.assignedToUserId == technician.userId)
        #expect(assignedBooking.updatedByUserId == owner.userId)
    }

    @Test func ownerCanEditTeamLeadFieldsAndDispatchSoldLeadToTechnician() {
        let now = Date(timeIntervalSince1970: 60_500)
        let team = TeamWorkspace.newOwnerTeam(id: "team-dispatch", name: "Dispatch", ownerUserId: "owner-1", now: now)
        let owner = TeamMember.owner(teamId: team.id, userId: "owner-1", displayName: "Owner", email: nil, joinedAt: now)
        let technician = TeamMember.rep(
            teamId: team.id,
            userId: "tech-1",
            displayName: "Alex",
            email: nil,
            acceptedInviteId: "TECH1",
            workType: .technician,
            joinedAt: now
        )
        var lead = TeamLead.newRepLead(
            teamId: team.id,
            creatorUserId: "rep-1",
            name: "Old Name",
            address: "10 King St",
            coordinate: TeamCoordinate(latitude: 43.65, longitude: -79.38),
            now: now
        )
        lead.status = .interested

        let fields = TeamLeadEditableFields(
            name: "  Hula  ",
            address: "4908 Forest Hill Dr",
            phone: " 555-1212 ",
            email: " customer@example.com ",
            notes: " Sold exterior package ",
            serviceCategory: " Window Cleaning ",
            price: 350,
            estimatedValue: 500,
            tags: [" sold ", "", " exterior "]
        )
        let edited = fields.applying(to: lead, updatedByUserId: owner.userId, now: now.addingTimeInterval(10))
        let sold = TeamLeadDispatchPolicy.soldLead(edited, by: owner, now: now.addingTimeInterval(20))
        let booking = TeamLeadDispatchPolicy.booking(
            from: sold,
            to: technician,
            by: owner,
            startDate: now.addingTimeInterval(3_600),
            endDate: now.addingTimeInterval(7_200),
            now: now.addingTimeInterval(20)
        )

        #expect(edited.name == "Hula")
        #expect(edited.phone == "555-1212")
        #expect(edited.email == "customer@example.com")
        #expect(edited.serviceCategory == "Window Cleaning")
        #expect(edited.tags == ["sold", "exterior"])
        #expect(TeamLeadDispatchPolicy.canDispatchLeadToTechnician(actor: owner, team: team, technician: technician, lead: edited))
        #expect(sold.status == .converted)
        #expect(booking.id == "\(lead.id)-job")
        #expect(booking.leadId == lead.id)
        #expect(booking.assignedToUserId == technician.userId)
        #expect(booking.title == "Window Cleaning - Hula")
        #expect(booking.location == "4908 Forest Hill Dr")
        #expect(booking.customerName == "Hula")
        #expect(booking.customerPhone == "555-1212")
        #expect(booking.customerEmail == "customer@example.com")
        #expect(booking.serviceCategory == "Window Cleaning")
        #expect(booking.quotedPrice == 350)
        #expect(booking.latitude == 43.65)
        #expect(booking.longitude == -79.38)
        #expect(booking.arrivalWindowMinutes == 30)
        #expect(booking.customerDisplayName == "Hula")
        #expect(booking.notes.contains("Phone: 555-1212"))
    }

    @Test func teamWritesAreBlockedInGraceAndPausedAcrossOperations() {
        let now = Date(timeIntervalSince1970: 61_000)
        let team = TeamWorkspace.newOwnerTeam(id: "team-readonly", name: "Read Only", ownerUserId: "owner-1", now: now)
        let owner = TeamMember.owner(teamId: team.id, userId: "owner-1", displayName: "Owner", email: nil, joinedAt: now)
        let rep = TeamMember.rep(teamId: team.id, userId: "rep-1", displayName: "Mike", email: nil, acceptedInviteId: "INVITE1", joinedAt: now)
        let lead = TeamLead.newRepLead(teamId: team.id, creatorUserId: rep.userId, name: "Lead", address: "10 King St", coordinate: TeamCoordinate(latitude: 43.65, longitude: -79.38), now: now)

        var graceTeam = team
        graceTeam.planStatus = .grace
        var pausedTeam = team
        pausedTeam.planStatus = .paused

        #expect(!TeamAssignmentPolicy.canAssignLead(actor: owner, team: graceTeam, target: rep, lead: lead))
        #expect(!TeamAssignmentPolicy.canAssignLead(actor: owner, team: pausedTeam, target: rep, lead: lead))
        #expect(!TeamAccessPolicy.canRemoveMember(actor: owner, team: graceTeam, member: rep))
        #expect(!TeamRepReplyPolicy.canReply(userId: rep.userId, role: rep.role, planStatus: .grace, assignedToUserId: rep.userId))
    }

    @Test func repStatusReplyIsShortAssignedAndSanitized() {
        let short = TeamRepReplyPolicy.sanitizedNote("  Needs owner follow-up.  ")
        let tooLong = String(repeating: "x", count: TeamRepReplyPolicy.maxNoteCharacters + 1)

        #expect(short == "Needs owner follow-up.")
        #expect(TeamRepReplyPolicy.sanitizedNote("") == nil)
        #expect(TeamRepReplyPolicy.sanitizedNote(tooLong) == nil)
        #expect(TeamRepReplyPolicy.canReply(userId: "rep-1", role: .member, planStatus: .active, assignedToUserId: "rep-1"))
        #expect(!TeamRepReplyPolicy.canReply(userId: "rep-2", role: .member, planStatus: .active, assignedToUserId: "rep-1"))
        #expect(!TeamRepReplyPolicy.canReply(userId: "owner-1", role: .owner, planStatus: .active, assignedToUserId: "rep-1"))
    }

    @Test func activityLogSummarizesCriticalTeamActions() {
        let now = Date(timeIntervalSince1970: 62_000)
        let lead = TeamLead.newRepLead(teamId: "team-activity", creatorUserId: "rep-1", name: "High Value Home", address: "10 King St", coordinate: TeamCoordinate(latitude: 43.65, longitude: -79.38), now: now)

        let created = TeamActivityLogEntry.make(
            teamId: lead.teamId,
            actorUserId: "rep-1",
            actorDisplayName: "Mike",
            kind: .leadCreated,
            subjectId: lead.id,
            subjectTitle: lead.name,
            targetUserId: lead.assignedToUserId,
            createdAt: now
        )
        let assigned = TeamActivityLogEntry.make(
            teamId: lead.teamId,
            actorUserId: "owner-1",
            actorDisplayName: "Owner",
            kind: .leadAssigned,
            subjectId: lead.id,
            subjectTitle: lead.name,
            targetUserId: "rep-2",
            createdAt: now.addingTimeInterval(10)
        )
        let jobUpdated = TeamActivityLogEntry.make(
            teamId: lead.teamId,
            actorUserId: "tech-1",
            actorDisplayName: "Alex",
            kind: .bookingStatusUpdated,
            subjectId: "job-1",
            subjectTitle: "Service Job completed",
            targetUserId: "tech-1",
            createdAt: now.addingTimeInterval(20)
        )
        let leftTeam = TeamActivityLogEntry.make(
            teamId: lead.teamId,
            actorUserId: "rep-1",
            actorDisplayName: "Mike",
            kind: .memberLeft,
            subjectId: "rep-1",
            subjectTitle: "Team",
            targetUserId: "rep-1",
            createdAt: now.addingTimeInterval(30)
        )
        let closedTeam = TeamActivityLogEntry.make(
            teamId: lead.teamId,
            actorUserId: "owner-1",
            actorDisplayName: "Owner",
            kind: .teamClosed,
            subjectId: lead.teamId,
            subjectTitle: "Team",
            targetUserId: "owner-1",
            createdAt: now.addingTimeInterval(40)
        )

        #expect(created.summary == "Mike created lead High Value Home")
        #expect(assigned.summary == "Owner assigned lead High Value Home")
        #expect(jobUpdated.summary == "Alex updated job Service Job completed")
        #expect(leftTeam.summary == "Mike left team Team")
        #expect(closedTeam.summary == "Owner closed team Team")
        #expect(created.targetUserId == "rep-1")
        #expect(assigned.kind == .leadAssigned)
        #expect(jobUpdated.kind == .bookingStatusUpdated)
    }

    @Test func duplicateDetectorFindsPhoneAddressAndNearbyMatches() {
        let now = Date(timeIntervalSince1970: 63_000)
        var existingByPhone = TeamLead.newRepLead(teamId: "team-dupes", creatorUserId: "rep-1", name: "Phone Match", address: "1 First St", coordinate: TeamCoordinate(latitude: 43.6500, longitude: -79.3800), now: now)
        existingByPhone.phone = "(416) 555-1212"
        let existingByAddress = TeamLead.newRepLead(teamId: "team-dupes", creatorUserId: "rep-1", name: "Address Match", address: "22 Queen Street West", coordinate: TeamCoordinate(latitude: 43.6510, longitude: -79.3810), now: now)
        let existingNearby = TeamLead.newRepLead(teamId: "team-dupes", creatorUserId: "rep-1", name: "Nearby Match", address: "Unknown", coordinate: TeamCoordinate(latitude: 43.6520, longitude: -79.3820), now: now)
        let unrelated = TeamLead.newRepLead(teamId: "team-dupes", creatorUserId: "rep-1", name: "Unrelated", address: "99 Far St", coordinate: TeamCoordinate(latitude: 44.0, longitude: -80.0), now: now)

        var newLead = TeamLead.newRepLead(teamId: "team-dupes", creatorUserId: "rep-2", name: "New", address: "22 queen st. west", coordinate: TeamCoordinate(latitude: 43.65208, longitude: -79.38208), now: now)
        newLead.phone = "4165551212"

        let matches = TeamDuplicateLeadDetector.candidates(
            for: newLead,
            existingLeads: [existingByPhone, existingByAddress, existingNearby, unrelated]
        )

        #expect(matches.map(\.existingLead.id).contains(existingByPhone.id))
        #expect(matches.map(\.existingLead.id).contains(existingByAddress.id))
        #expect(matches.map(\.existingLead.id).contains(existingNearby.id))
        #expect(!matches.map(\.existingLead.id).contains(unrelated.id))
        #expect(matches.first?.reason == .samePhone)

        let warnings = TeamDuplicateLeadDetector.warnings(for: [existingByPhone, existingByAddress, existingNearby, unrelated, newLead])
        #expect(warnings.contains {
            Set([$0.lead.id, $0.candidate.existingLead.id]) == Set([newLead.id, existingByPhone.id])
        })
        #expect(warnings.filter { $0.lead.id == newLead.id || $0.candidate.existingLead.id == newLead.id }.count == 3)
    }

    @Test func todayWorkSummaryKeepsOwnerAndRepScopesSeparate() {
        let calendar = Calendar(identifier: .gregorian)
        let today = Date(timeIntervalSince1970: 64_000)
        let tomorrow = today.addingTimeInterval(86_400)
        let owner = TeamMember.owner(teamId: "team-today", userId: "owner-1", displayName: "Owner", email: nil, joinedAt: today)
        let repA = TeamMember.rep(teamId: "team-today", userId: "rep-a", displayName: "Mike", email: nil, acceptedInviteId: "INVITEA", joinedAt: today)
        let repB = TeamMember.rep(teamId: "team-today", userId: "rep-b", displayName: "Sarah", email: nil, acceptedInviteId: "INVITEB", joinedAt: today)
        var repALead = TeamLead.newRepLead(teamId: "team-today", creatorUserId: repA.userId, name: "Rep A", address: "10 King St", coordinate: TeamCoordinate(latitude: 43.65, longitude: -79.38), now: today)
        repALead.isHighPriority = true
        let repBLead = TeamLead.newRepLead(teamId: "team-today", creatorUserId: repB.userId, name: "Rep B", address: "20 Queen St", coordinate: TeamCoordinate(latitude: 43.66, longitude: -79.39), now: today)
        let todayBooking = TeamBooking(id: "booking-today", teamId: "team-today", leadId: repALead.id, assignedToUserId: repA.userId, title: "Today", notes: "", startDate: today, endDate: today.addingTimeInterval(3_600), location: repALead.address, status: .scheduled, createdByUserId: owner.userId, updatedByUserId: owner.userId, createdAt: today, updatedAt: today)
        let tomorrowBooking = TeamBooking(id: "booking-tomorrow", teamId: "team-today", leadId: repBLead.id, assignedToUserId: repB.userId, title: "Tomorrow", notes: "", startDate: tomorrow, endDate: tomorrow.addingTimeInterval(3_600), location: repBLead.address, status: .scheduled, createdByUserId: owner.userId, updatedByUserId: owner.userId, createdAt: today, updatedAt: today)

        let ownerSummary = TeamTodayWorkSummary.make(currentMember: owner, leads: [repALead, repBLead], bookings: [todayBooking, tomorrowBooking], dutySessions: [], now: today, calendar: calendar)
        let repSummary = TeamTodayWorkSummary.make(currentMember: repA, leads: [repALead, repBLead], bookings: [todayBooking, tomorrowBooking], dutySessions: [], now: today, calendar: calendar)

        #expect(ownerSummary.leadCount == 2)
        #expect(ownerSummary.bookingCount == 1)
        #expect(ownerSummary.importantLeadCount == 1)
        #expect(repSummary.leadCount == 1)
        #expect(repSummary.bookingCount == 1)
        #expect(repSummary.memberUserId == repA.userId)
    }

    @Test func ownerCanRemoveActiveRepButNotSelfOrPendingInvite() {
        let now = Date(timeIntervalSince1970: 65_000)
        let team = TeamWorkspace.newOwnerTeam(id: "team-remove", name: "Remove", ownerUserId: "owner-1", now: now)
        let owner = TeamMember.owner(teamId: team.id, userId: "owner-1", displayName: "Owner", email: nil, joinedAt: now)
        let rep = TeamMember.rep(teamId: team.id, userId: "rep-1", displayName: "Mike", email: nil, acceptedInviteId: "INVITE1", joinedAt: now)
        let pending = TeamMember.rep(teamId: team.id, userId: "\(TeamFirebaseSchema.pendingRepUserPrefix)-INVITE2", displayName: "Pending Rep", email: nil, acceptedInviteId: "INVITE2", joinedAt: now)

        #expect(TeamAccessPolicy.canRemoveMember(actor: owner, team: team, member: rep))
        #expect(!TeamAccessPolicy.canRemoveMember(actor: rep, team: team, member: owner))
        #expect(!TeamAccessPolicy.canRemoveMember(actor: owner, team: team, member: owner))
        #expect(!TeamAccessPolicy.canRemoveMember(actor: owner, team: team, member: pending))
        #expect(TeamAccessPolicy.canLeaveTeam(member: rep, team: team))
        #expect(!TeamAccessPolicy.canLeaveTeam(member: owner, team: team))
        #expect(!TeamAccessPolicy.canLeaveTeam(member: pending, team: team))
        #expect(TeamAccessPolicy.canCloseTeam(owner: owner, team: team))
        #expect(!TeamAccessPolicy.canCloseTeam(owner: rep, team: team))

        let removed = TeamMember.removed(rep, removedAt: now.addingTimeInterval(10))
        #expect(removed.status == .removed)
        #expect(removed.removedAt == now.addingTimeInterval(10))
    }

    @Test func ownerAlertReadAndSyncPendingStatesHaveDisplayText() {
        let now = Date(timeIntervalSince1970: 66_000)
        let notification = TeamOwnerNotification(
            id: "notification-1",
            teamId: "team-alert",
            leadId: "lead-1",
            assignedToUserId: "rep-1",
            createdByUserId: "rep-1",
            event: .interested,
            title: TeamOwnerLeadEvent.interested.ownerTitle,
            message: "Interested Home",
            createdAt: now,
            readAt: nil
        )

        let read = TeamOwnerNotification.markedRead(notification, at: now.addingTimeInterval(20))
        #expect(read.readAt == now.addingTimeInterval(20))
        #expect(TeamSyncWriteState.idle.displayText == "Synced")
        #expect(TeamSyncWriteState.pending(localWriteCount: 2).displayText == "Saving 2 team edits...")
        #expect(TeamSyncWriteState.failed("Network unavailable").displayText == "Network unavailable")

        let permissionError = NSError(
            domain: "FIRFirestoreErrorDomain",
            code: 7,
            userInfo: [NSLocalizedDescriptionKey: "Missing or insufficient permissions."]
        )
        #expect(
            TeamFirebaseService.userFacingErrorMessage(for: permissionError)
                == "Team access needs refresh. Refresh Team or sign in again."
        )

        let firestoreOfflineError = NSError(
            domain: "FIRFirestoreErrorDomain",
            code: 14,
            userInfo: [NSLocalizedDescriptionKey: "Failed to get document because the client is offline."]
        )
        #expect(TeamFirebaseService.isOfflineError(firestoreOfflineError))
        #expect(
            TeamFirebaseService.userFacingErrorMessage(for: firestoreOfflineError)
                == TeamFirebaseService.teamOfflineMessage
        )
        #expect(
            TeamFirebaseService.teamSetupOfflineMessage
                == "Offline. Connect to the internet to create or join a team."
        )
        #expect(TeamFirebaseService.isOfflineMessage(TeamFirebaseService.teamOfflineMessage))
        #expect(TeamFirebaseService.isPermissionMessage("Missing or insufficient permissions."))

        #expect(
            TeamFirebaseServiceError.serverConfirmationTimedOut.errorDescription
                == "Team could not be confirmed. Check your connection and try again."
        )
    }

    @Test func teamSyncHealthPolicySummarizesReadySavingOfflineAndBlockedStates() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)

        let ready = TeamSyncHealthPolicy.snapshot(
            isAuthenticated: true,
            hasActiveTeam: true,
            hasCurrentMember: true,
            isLoading: false,
            isWorking: false,
            syncWriteState: .idle,
            lastErrorMessage: nil,
            lastSuccessfulSyncAt: now.addingTimeInterval(-90),
            now: now
        )
        #expect(ready?.level == .ready)
        #expect(ready?.title == "Team online")
        #expect(ready?.detail == "Last synced 1 min ago.")

        let saving = TeamSyncHealthPolicy.snapshot(
            isAuthenticated: true,
            hasActiveTeam: true,
            hasCurrentMember: true,
            isLoading: false,
            isWorking: false,
            syncWriteState: .pending(localWriteCount: 2),
            lastErrorMessage: nil,
            lastSuccessfulSyncAt: nil,
            now: now
        )
        #expect(saving?.level == .saving)
        #expect(saving?.title == "Saving 2 team edits...")

        let offline = TeamSyncHealthPolicy.snapshot(
            isAuthenticated: true,
            hasActiveTeam: true,
            hasCurrentMember: true,
            isLoading: false,
            isWorking: false,
            syncWriteState: .failed(TeamFirebaseService.teamOfflineMessage),
            lastErrorMessage: nil,
            lastSuccessfulSyncAt: nil,
            now: now
        )
        #expect(offline?.level == .offline)
        #expect(offline?.actionTitle == "Refresh Team")

        let blocked = TeamSyncHealthPolicy.snapshot(
            isAuthenticated: true,
            hasActiveTeam: true,
            hasCurrentMember: true,
            isLoading: false,
            isWorking: false,
            syncWriteState: .failed("Missing or insufficient permissions."),
            lastErrorMessage: nil,
            lastSuccessfulSyncAt: nil,
            now: now
        )
        #expect(blocked?.level == .blocked)
        #expect(blocked?.title == "Team access needs refresh")
    }

    @Test func removedRepPermissionErrorClearsMemberSessionButNotOwnerSession() {
        let permissionError = NSError(
            domain: "FIRFirestoreErrorDomain",
            code: 7,
            userInfo: [NSLocalizedDescriptionKey: "Missing or insufficient permissions."]
        )
        let networkError = NSError(
            domain: NSURLErrorDomain,
            code: NSURLErrorNotConnectedToInternet,
            userInfo: [NSLocalizedDescriptionKey: "The Internet connection appears to be offline."]
        )

        #expect(TeamFirebaseService.removedTeamAccessMessage == "You no longer have access to this team. Ask the owner for a new invite if needed.")
        #expect(TeamFirebaseService.shouldClearMemberSessionAfterPermissionError(error: permissionError, profileRole: .member, cachedRole: nil))
        #expect(TeamFirebaseService.shouldClearMemberSessionAfterPermissionError(error: permissionError, profileRole: nil, cachedRole: .member))
        #expect(!TeamFirebaseService.shouldClearMemberSessionAfterPermissionError(error: permissionError, profileRole: .owner, cachedRole: .owner))
        #expect(!TeamFirebaseService.shouldClearMemberSessionAfterPermissionError(error: permissionError, profileRole: nil, cachedRole: nil))
        #expect(!TeamFirebaseService.shouldClearMemberSessionAfterPermissionError(error: networkError, profileRole: .member, cachedRole: .member))
    }

    @Test func teamOperationsControlDefaultsToEnabledAndExplainsPausedWrites() {
        #expect(TeamOperationsControl.enabled.teamWritesEnabled)
        #expect(
            TeamOperationsControl(teamWritesEnabled: false, message: nil).displayMessage
                == TeamOperationsControl.defaultPausedMessage
        )
        #expect(
            TeamOperationsControl(teamWritesEnabled: false, message: "  Usage review in progress.  ").displayMessage
                == "Usage review in progress."
        )
        #expect(
            TeamFirebaseServiceError.operationsPaused("Usage review in progress.").errorDescription
                == "Usage review in progress."
        )
    }
}
