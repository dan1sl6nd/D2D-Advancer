# Hybrid Team Workspaces Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the first hybrid team-workspace layer for D2D Advancer: Firebase-backed team records, assignment privacy, invite rules, Team-plan gating, owner instructions, and manual duty-session location sharing.

**Architecture:** Keep personal leads/bookings on the existing local/iCloud path. Add separate Firebase DTOs and services for team workspaces so owner/member permissions, one-team membership, invite expiry, assigned-only visibility, and active-hours GPS retention can be enforced independently from personal Core Data records. Surface the feature through a focused Team screen in More before deeper tab-level replacement.

**Tech Stack:** Swift, SwiftUI, Swift Testing, FirebaseAuth, FirebaseFirestore, CoreLocation, existing D2D Advancer services and styling.

---

### Task 1: Team Domain Rules

**Files:**
- Create: `D2D Advancer/TeamWorkspaceModels.swift`
- Create: `D2D AdvancerTests/TeamWorkspaceTests.swift`

- [ ] **Step 1: Write failing tests for plan state, invites, permissions, and retention**

```swift
import Testing
import Foundation
@testable import D2D_Advancer

struct TeamWorkspaceTests {
    @Test func activePlanAllowsWritesButGraceIsReadOnly() {
        #expect(TeamPlanStatus.active.allowsTeamRead)
        #expect(TeamPlanStatus.active.allowsTeamWrite)
        #expect(TeamPlanStatus.grace.allowsTeamRead)
        #expect(!TeamPlanStatus.grace.allowsTeamWrite)
        #expect(!TeamPlanStatus.paused.allowsTeamRead)
        #expect(!TeamPlanStatus.paused.allowsTeamWrite)
    }

    @Test func inviteMustBeUnusedUnrevokedUnexpiredAndTeamNotFull() {
        let invite = TeamInvite(
            id: "invite-1",
            teamId: "team-1",
            createdByUserId: "owner-1",
            createdAt: Date(timeIntervalSince1970: 1_000),
            expiresAt: Date(timeIntervalSince1970: 2_000)
        )

        #expect(invite.acceptanceState(now: Date(timeIntervalSince1970: 1_500), activeMemberCount: 2, memberLimit: 3) == .valid)
        #expect(invite.acceptanceState(now: Date(timeIntervalSince1970: 2_500), activeMemberCount: 2, memberLimit: 3) == .expired)
        #expect(invite.acceptanceState(now: Date(timeIntervalSince1970: 1_500), activeMemberCount: 3, memberLimit: 3) == .teamFull)

        var consumed = invite
        consumed.consumedAt = Date(timeIntervalSince1970: 1_600)
        #expect(consumed.acceptanceState(now: Date(timeIntervalSince1970: 1_700), activeMemberCount: 2, memberLimit: 3) == .consumed)

        var revoked = invite
        revoked.revokedAt = Date(timeIntervalSince1970: 1_600)
        #expect(revoked.acceptanceState(now: Date(timeIntervalSince1970: 1_700), activeMemberCount: 2, memberLimit: 3) == .revoked)
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
}
```

- [ ] **Step 2: Run tests to verify they fail because types are missing**

Run: `xcodebuild test -project "D2D Advancer.xcodeproj" -scheme "D2D Advancer" -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:D2D_AdvancerTests/TeamWorkspaceTests`

Expected: FAIL with missing `TeamPlanStatus`, `TeamInvite`, `TeamLead`, `TeamAccessPolicy`, or `TeamDutySession`.

- [ ] **Step 3: Add team domain models and policy helpers**

```swift
import Foundation

enum TeamRole: String, Codable, CaseIterable, Sendable {
    case owner
    case member
}

enum TeamMemberStatus: String, Codable, CaseIterable, Sendable {
    case active
    case removed
}

enum TeamPlanStatus: String, Codable, CaseIterable, Sendable {
    case active
    case grace
    case paused

    var allowsTeamRead: Bool { self == .active || self == .grace }
    var allowsTeamWrite: Bool { self == .active }
}

enum TeamInviteAcceptanceState: String, Codable, Equatable, Sendable {
    case valid
    case expired
    case revoked
    case consumed
    case teamFull
}

struct TeamCoordinate: Codable, Equatable, Sendable {
    var latitude: Double
    var longitude: Double
}

struct TeamWorkspace: Identifiable, Codable, Equatable, Sendable {
    var id: String
    var name: String
    var ownerUserId: String
    var createdAt: Date
    var updatedAt: Date
    var planStatus: TeamPlanStatus
    var planExpiresAt: Date?
    var graceEndsAt: Date?
    var memberLimit: Int
}

struct TeamMember: Identifiable, Codable, Equatable, Sendable {
    var id: String { userId }
    var teamId: String
    var userId: String
    var displayName: String
    var email: String?
    var role: TeamRole
    var status: TeamMemberStatus
    var joinedAt: Date
    var removedAt: Date?
}

struct TeamInvite: Identifiable, Codable, Equatable, Sendable {
    var id: String
    var teamId: String
    var createdByUserId: String
    var defaultRole: TeamRole = .member
    var createdAt: Date
    var expiresAt: Date
    var revokedAt: Date?
    var consumedAt: Date?
    var acceptedByUserId: String?

    func acceptanceState(now: Date, activeMemberCount: Int, memberLimit: Int) -> TeamInviteAcceptanceState {
        if revokedAt != nil { return .revoked }
        if consumedAt != nil { return .consumed }
        if now > expiresAt { return .expired }
        if activeMemberCount >= memberLimit { return .teamFull }
        return .valid
    }
}

enum TeamLeadStatus: String, Codable, CaseIterable, Sendable {
    case notContacted = "not_contacted"
    case contacted
    case interested
    case followUp = "follow_up"
    case booked
    case converted
    case notInterested = "not_interested"
}

struct TeamLead: Identifiable, Codable, Equatable, Sendable {
    var id: String
    var teamId: String
    var name: String
    var address: String
    var phone: String?
    var email: String?
    var latitude: Double
    var longitude: Double
    var status: TeamLeadStatus
    var notes: String = ""
    var serviceCategory: String?
    var price: Double = 0
    var estimatedValue: Double = 0
    var tags: [String] = []
    var assignedToUserId: String
    var createdByUserId: String
    var updatedByUserId: String
    var createdAt: Date
    var updatedAt: Date
    var isHighPriority: Bool = false
    var highPriorityReason: String?

    static func newRepLead(
        teamId: String,
        creatorUserId: String,
        name: String,
        address: String,
        coordinate: TeamCoordinate,
        now: Date = Date()
    ) -> TeamLead {
        TeamLead(
            id: UUID().uuidString,
            teamId: teamId,
            name: name,
            address: address,
            phone: nil,
            email: nil,
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            status: .notContacted,
            assignedToUserId: creatorUserId,
            createdByUserId: creatorUserId,
            updatedByUserId: creatorUserId,
            createdAt: now,
            updatedAt: now
        )
    }
}

enum TeamBookingStatus: String, Codable, CaseIterable, Sendable {
    case scheduled
    case confirmed
    case completed
    case cancelled
    case rescheduled
}

struct TeamBooking: Identifiable, Codable, Equatable, Sendable {
    var id: String
    var teamId: String
    var leadId: String
    var assignedToUserId: String
    var title: String
    var notes: String
    var startDate: Date
    var endDate: Date
    var location: String
    var status: TeamBookingStatus
    var createdByUserId: String
    var updatedByUserId: String
    var createdAt: Date
    var updatedAt: Date

    var isFutureEditable: Bool {
        status != .completed && status != .cancelled
    }
}

enum OwnerInstructionStatus: String, Codable, CaseIterable, Sendable {
    case none
    case done
    case customerNotHome = "customer_not_home"
    case needsOwnerFollowUp = "needs_owner_follow_up"
    case couldNotComplete = "could_not_complete"
}

struct OwnerInstruction: Identifiable, Codable, Equatable, Sendable {
    var id: String
    var teamId: String
    var leadId: String
    var assignedToUserId: String
    var text: String
    var createdByUserId: String
    var updatedByUserId: String
    var createdAt: Date
    var updatedAt: Date
    var repStatus: OwnerInstructionStatus
    var repNote: String?
    var repRespondedAt: Date?
}

enum TeamDutySessionStatus: String, Codable, CaseIterable, Sendable {
    case active
    case ended
}

struct TeamDutySession: Identifiable, Codable, Equatable, Sendable {
    static let retentionInterval: TimeInterval = 30 * 24 * 60 * 60

    var id: String
    var teamId: String
    var repUserId: String
    var startedAt: Date
    var endedAt: Date?
    var status: TeamDutySessionStatus
    var lastLocationAt: Date?
    var distanceMeters: Double
    var createdAt: Date
    var deleteAfter: Date?

    static func ended(
        id: String,
        teamId: String,
        repUserId: String,
        startedAt: Date,
        endedAt: Date,
        distanceMeters: Double
    ) -> TeamDutySession {
        TeamDutySession(
            id: id,
            teamId: teamId,
            repUserId: repUserId,
            startedAt: startedAt,
            endedAt: endedAt,
            status: .ended,
            lastLocationAt: endedAt,
            distanceMeters: distanceMeters,
            createdAt: startedAt,
            deleteAfter: endedAt.addingTimeInterval(retentionInterval)
        )
    }
}

struct TeamDutyLocationPoint: Identifiable, Codable, Equatable, Sendable {
    static let retentionInterval: TimeInterval = 30 * 24 * 60 * 60

    var id: String
    var teamId: String
    var sessionId: String
    var repUserId: String
    var latitude: Double
    var longitude: Double
    var horizontalAccuracy: Double
    var recordedAt: Date
    var deleteAfter: Date

    init(
        id: String = UUID().uuidString,
        teamId: String,
        sessionId: String,
        repUserId: String,
        coordinate: TeamCoordinate,
        horizontalAccuracy: Double,
        recordedAt: Date = Date()
    ) {
        self.id = id
        self.teamId = teamId
        self.sessionId = sessionId
        self.repUserId = repUserId
        self.latitude = coordinate.latitude
        self.longitude = coordinate.longitude
        self.horizontalAccuracy = horizontalAccuracy
        self.recordedAt = recordedAt
        self.deleteAfter = recordedAt.addingTimeInterval(Self.retentionInterval)
    }
}

enum TeamAccessPolicy {
    static func canReadLead(userId: String, role: TeamRole, planStatus: TeamPlanStatus, lead: TeamLead) -> Bool {
        guard planStatus.allowsTeamRead else { return false }
        if role == .owner { return true }
        return lead.assignedToUserId == userId
    }

    static func canWriteAssignedRecord(userId: String, role: TeamRole, planStatus: TeamPlanStatus, assignedToUserId: String) -> Bool {
        guard planStatus.allowsTeamWrite else { return false }
        if role == .owner { return true }
        return assignedToUserId == userId
    }

    static func canCreateRepLead(userId: String, role: TeamRole, planStatus: TeamPlanStatus, assignedToUserId: String) -> Bool {
        guard planStatus.allowsTeamWrite else { return false }
        if role == .owner { return true }
        return assignedToUserId == userId
    }

    static func canViewDutySession(userId: String, role: TeamRole, planStatus: TeamPlanStatus, session: TeamDutySession) -> Bool {
        guard planStatus.allowsTeamRead else { return false }
        if role == .owner { return true }
        return session.repUserId == userId
    }
}
```

- [ ] **Step 4: Run tests to verify domain rules pass**

Run: `xcodebuild test -project "D2D Advancer.xcodeproj" -scheme "D2D Advancer" -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:D2D_AdvancerTests/TeamWorkspaceTests`

Expected: PASS for `TeamWorkspaceTests`.

- [ ] **Step 5: Commit**

```bash
git add "D2D Advancer/TeamWorkspaceModels.swift" "D2D AdvancerTests/TeamWorkspaceTests.swift"
git commit -m "feat(team): add workspace domain rules"
```

### Task 2: Team Firebase Payloads and Service Boundary

**Files:**
- Create: `D2D Advancer/TeamFirestorePayloads.swift`
- Create: `D2D Advancer/TeamFirebaseService.swift`
- Modify: `D2D AdvancerTests/TeamWorkspaceTests.swift`

- [ ] **Step 1: Write failing tests for Firestore payloads and important-notification transitions**

Add these tests to `TeamWorkspaceTests`:

```swift
@Test func teamLeadFirestorePayloadPreservesAssignmentBoundary() {
    let lead = TeamLead.newRepLead(
        teamId: "team-1",
        creatorUserId: "rep-1",
        name: "Lead",
        address: "100 Main St",
        coordinate: TeamCoordinate(latitude: 43, longitude: -79),
        now: Date(timeIntervalSince1970: 1_000)
    )

    let payload = lead.firestoreData
    #expect(payload["teamId"] as? String == "team-1")
    #expect(payload["createdByUserId"] as? String == "rep-1")
    #expect(payload["assignedToUserId"] as? String == "rep-1")
    #expect(payload["status"] as? String == TeamLeadStatus.notContacted.rawValue)
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
```

- [ ] **Step 2: Run tests to verify missing payload and notification helpers fail**

Run: `xcodebuild test -project "D2D Advancer.xcodeproj" -scheme "D2D Advancer" -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:D2D_AdvancerTests/TeamWorkspaceTests`

Expected: FAIL with missing `firestoreData` and `TeamNotificationPolicy`.

- [ ] **Step 3: Add Firestore payload mappers and notification policy**

```swift
import Foundation

extension TeamWorkspace {
    var firestoreData: [String: Any] {
        [
            "name": name,
            "ownerUserId": ownerUserId,
            "createdAt": createdAt,
            "updatedAt": updatedAt,
            "planStatus": planStatus.rawValue,
            "planExpiresAt": planExpiresAt as Any,
            "graceEndsAt": graceEndsAt as Any,
            "memberLimit": memberLimit
        ]
    }
}

extension TeamInvite {
    var firestoreData: [String: Any] {
        [
            "teamId": teamId,
            "createdByUserId": createdByUserId,
            "defaultRole": defaultRole.rawValue,
            "createdAt": createdAt,
            "expiresAt": expiresAt,
            "revokedAt": revokedAt as Any,
            "consumedAt": consumedAt as Any,
            "acceptedByUserId": acceptedByUserId as Any
        ]
    }
}

extension TeamLead {
    var firestoreData: [String: Any] {
        [
            "teamId": teamId,
            "name": name,
            "address": address,
            "phone": phone as Any,
            "email": email as Any,
            "latitude": latitude,
            "longitude": longitude,
            "status": status.rawValue,
            "notes": notes,
            "serviceCategory": serviceCategory as Any,
            "price": price,
            "estimatedValue": estimatedValue,
            "tags": tags,
            "assignedToUserId": assignedToUserId,
            "createdByUserId": createdByUserId,
            "updatedByUserId": updatedByUserId,
            "createdAt": createdAt,
            "updatedAt": updatedAt,
            "isHighPriority": isHighPriority,
            "highPriorityReason": highPriorityReason as Any
        ]
    }
}

enum TeamOwnerLeadEvent: String, Equatable, Sendable {
    case interested
    case followUp
    case booked
    case converted
    case highPriority
}

enum TeamNotificationPolicy {
    static func ownerLeadEvents(before: TeamLead?, after: TeamLead) -> [TeamOwnerLeadEvent] {
        var events: [TeamOwnerLeadEvent] = []

        if before?.status != after.status {
            switch after.status {
            case .interested:
                events.append(.interested)
            case .followUp:
                events.append(.followUp)
            case .booked:
                events.append(.booked)
            case .converted:
                events.append(.converted)
            default:
                break
            }
        }

        if before?.isHighPriority != true && after.isHighPriority {
            events.append(.highPriority)
        }

        return events
    }
}
```

- [ ] **Step 4: Add Firebase service boundary**

```swift
import Foundation
import FirebaseAuth
import FirebaseFirestore

@MainActor
final class TeamFirebaseService: ObservableObject {
    static let shared = TeamFirebaseService()

    @Published private(set) var activeTeam: TeamWorkspace?
    @Published private(set) var currentMember: TeamMember?
    @Published private(set) var teamLeads: [TeamLead] = []
    @Published private(set) var teamBookings: [TeamBooking] = []
    @Published private(set) var dutySessions: [TeamDutySession] = []
    @Published private(set) var isLoading = false
    @Published private(set) var lastErrorMessage: String?

    private let db = Firestore.firestore()
    private var listeners: [ListenerRegistration] = []

    private init() {}

    var currentUserId: String? {
        Auth.auth().currentUser?.uid
    }

    func stopListening() {
        listeners.forEach { $0.remove() }
        listeners.removeAll()
    }

    func startListening(team: TeamWorkspace, member: TeamMember) {
        stopListening()
        activeTeam = team
        currentMember = member
        listenForLeads(team: team, member: member)
        listenForBookings(team: team, member: member)
        listenForDutySessions(team: team, member: member)
    }

    func createRepLead(name: String, address: String, coordinate: TeamCoordinate) async throws {
        guard let team = activeTeam, let member = currentMember else { throw TeamServiceError.noActiveTeam }
        guard member.role == .member else { throw TeamServiceError.ownerMustUseAssignmentFlow }
        guard TeamAccessPolicy.canCreateRepLead(userId: member.userId, role: member.role, planStatus: team.planStatus, assignedToUserId: member.userId) else {
            throw TeamServiceError.writeBlocked
        }

        let lead = TeamLead.newRepLead(
            teamId: team.id,
            creatorUserId: member.userId,
            name: name,
            address: address,
            coordinate: coordinate
        )
        try await db.collection("teams").document(team.id).collection("leads").document(lead.id).setData(lead.firestoreData)
    }

    private func listenForLeads(team: TeamWorkspace, member: TeamMember) {
        var query: Query = db.collection("teams").document(team.id).collection("leads")
        if member.role == .member {
            query = query.whereField("assignedToUserId", isEqualTo: member.userId)
        }

        let listener = query.addSnapshotListener { [weak self] snapshot, error in
            Task { @MainActor in
                if let error {
                    self?.lastErrorMessage = error.localizedDescription
                    return
                }
                self?.teamLeads = snapshot?.documents.compactMap { TeamFirestoreDecoder.teamLead(from: $0.data(), id: $0.documentID) } ?? []
            }
        }
        listeners.append(listener)
    }

    private func listenForBookings(team: TeamWorkspace, member: TeamMember) {
        var query: Query = db.collection("teams").document(team.id).collection("bookings")
        if member.role == .member {
            query = query.whereField("assignedToUserId", isEqualTo: member.userId)
        }

        let listener = query.addSnapshotListener { [weak self] snapshot, error in
            Task { @MainActor in
                if let error {
                    self?.lastErrorMessage = error.localizedDescription
                    return
                }
                self?.teamBookings = snapshot?.documents.compactMap { TeamFirestoreDecoder.teamBooking(from: $0.data(), id: $0.documentID) } ?? []
            }
        }
        listeners.append(listener)
    }

    private func listenForDutySessions(team: TeamWorkspace, member: TeamMember) {
        var query: Query = db.collection("teams").document(team.id).collection("dutySessions")
        if member.role == .member {
            query = query.whereField("repUserId", isEqualTo: member.userId)
        }

        let listener = query.addSnapshotListener { [weak self] snapshot, error in
            Task { @MainActor in
                if let error {
                    self?.lastErrorMessage = error.localizedDescription
                    return
                }
                self?.dutySessions = snapshot?.documents.compactMap { TeamFirestoreDecoder.dutySession(from: $0.data(), id: $0.documentID) } ?? []
            }
        }
        listeners.append(listener)
    }
}

enum TeamServiceError: LocalizedError {
    case noActiveTeam
    case ownerMustUseAssignmentFlow
    case writeBlocked

    var errorDescription: String? {
        switch self {
        case .noActiveTeam: return "No active team workspace is loaded."
        case .ownerMustUseAssignmentFlow: return "Owners assign leads through the owner workflow."
        case .writeBlocked: return "Team workspace is read-only or paused."
        }
    }
}

enum TeamFirestoreDecoder {
    static func teamLead(from data: [String: Any], id: String) -> TeamLead? {
        guard let teamId = data["teamId"] as? String,
              let name = data["name"] as? String,
              let address = data["address"] as? String,
              let latitude = data["latitude"] as? Double,
              let longitude = data["longitude"] as? Double,
              let rawStatus = data["status"] as? String,
              let status = TeamLeadStatus(rawValue: rawStatus),
              let assignedToUserId = data["assignedToUserId"] as? String,
              let createdByUserId = data["createdByUserId"] as? String,
              let updatedByUserId = data["updatedByUserId"] as? String else { return nil }

        return TeamLead(
            id: id,
            teamId: teamId,
            name: name,
            address: address,
            phone: data["phone"] as? String,
            email: data["email"] as? String,
            latitude: latitude,
            longitude: longitude,
            status: status,
            notes: data["notes"] as? String ?? "",
            serviceCategory: data["serviceCategory"] as? String,
            price: data["price"] as? Double ?? 0,
            estimatedValue: data["estimatedValue"] as? Double ?? 0,
            tags: data["tags"] as? [String] ?? [],
            assignedToUserId: assignedToUserId,
            createdByUserId: createdByUserId,
            updatedByUserId: updatedByUserId,
            createdAt: data["createdAt"] as? Date ?? Date.distantPast,
            updatedAt: data["updatedAt"] as? Date ?? Date.distantPast,
            isHighPriority: data["isHighPriority"] as? Bool ?? false,
            highPriorityReason: data["highPriorityReason"] as? String
        )
    }

    static func teamBooking(from data: [String: Any], id: String) -> TeamBooking? {
        guard let teamId = data["teamId"] as? String,
              let leadId = data["leadId"] as? String,
              let assignedToUserId = data["assignedToUserId"] as? String,
              let title = data["title"] as? String,
              let rawStatus = data["status"] as? String,
              let status = TeamBookingStatus(rawValue: rawStatus) else { return nil }

        return TeamBooking(
            id: id,
            teamId: teamId,
            leadId: leadId,
            assignedToUserId: assignedToUserId,
            title: title,
            notes: data["notes"] as? String ?? "",
            startDate: data["startDate"] as? Date ?? Date.distantPast,
            endDate: data["endDate"] as? Date ?? Date.distantPast,
            location: data["location"] as? String ?? "",
            status: status,
            createdByUserId: data["createdByUserId"] as? String ?? "",
            updatedByUserId: data["updatedByUserId"] as? String ?? "",
            createdAt: data["createdAt"] as? Date ?? Date.distantPast,
            updatedAt: data["updatedAt"] as? Date ?? Date.distantPast
        )
    }

    static func dutySession(from data: [String: Any], id: String) -> TeamDutySession? {
        guard let teamId = data["teamId"] as? String,
              let repUserId = data["repUserId"] as? String,
              let rawStatus = data["status"] as? String,
              let status = TeamDutySessionStatus(rawValue: rawStatus) else { return nil }

        return TeamDutySession(
            id: id,
            teamId: teamId,
            repUserId: repUserId,
            startedAt: data["startedAt"] as? Date ?? Date.distantPast,
            endedAt: data["endedAt"] as? Date,
            status: status,
            lastLocationAt: data["lastLocationAt"] as? Date,
            distanceMeters: data["distanceMeters"] as? Double ?? 0,
            createdAt: data["createdAt"] as? Date ?? Date.distantPast,
            deleteAfter: data["deleteAfter"] as? Date
        )
    }
}
```

- [ ] **Step 5: Run tests**

Run: `xcodebuild test -project "D2D Advancer.xcodeproj" -scheme "D2D Advancer" -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:D2D_AdvancerTests/TeamWorkspaceTests`

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add "D2D Advancer/TeamFirestorePayloads.swift" "D2D Advancer/TeamFirebaseService.swift" "D2D AdvancerTests/TeamWorkspaceTests.swift"
git commit -m "feat(team): add Firebase service boundary"
```

### Task 3: Firestore Rules for Team Access

**Files:**
- Modify: `firestore.rules`

- [ ] **Step 1: Replace rules with user-private plus team-scoped rules**

```rules
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    function signedIn() {
      return request.auth != null;
    }

    function isSelf(userId) {
      return signedIn() && request.auth.uid == userId;
    }

    function teamDoc(teamId) {
      return get(/databases/$(database)/documents/teams/$(teamId));
    }

    function memberDoc(teamId) {
      return get(/databases/$(database)/documents/teams/$(teamId)/members/$(request.auth.uid));
    }

    function isActiveMember(teamId) {
      return signedIn()
        && exists(/databases/$(database)/documents/teams/$(teamId)/members/$(request.auth.uid))
        && memberDoc(teamId).data.status == "active";
    }

    function memberRole(teamId) {
      return memberDoc(teamId).data.role;
    }

    function planStatus(teamId) {
      return teamDoc(teamId).data.planStatus;
    }

    function canReadTeam(teamId) {
      return isActiveMember(teamId)
        && (planStatus(teamId) == "active" || planStatus(teamId) == "grace");
    }

    function canWriteTeam(teamId) {
      return isActiveMember(teamId) && planStatus(teamId) == "active";
    }

    function isOwner(teamId) {
      return isActiveMember(teamId) && memberRole(teamId) == "owner";
    }

    function isAssigned(resourceData) {
      return resourceData.assignedToUserId == request.auth.uid;
    }

    match /users/{userId} {
      allow read, write: if isSelf(userId);

      match /leads/{leadId} {
        allow read, write: if isSelf(userId);
      }

      match /checkIns/{checkInId} {
        allow read, write: if isSelf(userId);
      }

      match /appointments/{appointmentId} {
        allow read, write: if isSelf(userId);
      }
    }

    match /teamInvites/{inviteId} {
      allow read: if signedIn();
      allow create: if signedIn()
        && request.resource.data.createdByUserId == request.auth.uid
        && isOwner(request.resource.data.teamId)
        && canWriteTeam(request.resource.data.teamId);
      allow update: if signedIn()
        && isOwner(resource.data.teamId)
        && canWriteTeam(resource.data.teamId);
      allow delete: if false;
    }

    match /teams/{teamId} {
      allow read: if canReadTeam(teamId);
      allow create: if signedIn()
        && request.resource.data.ownerUserId == request.auth.uid
        && request.resource.data.planStatus == "active"
        && request.resource.data.memberLimit == 3;
      allow update: if isOwner(teamId) && canWriteTeam(teamId);
      allow delete: if false;

      match /members/{userId} {
        allow read: if canReadTeam(teamId);
        allow create: if signedIn()
          && (isOwner(teamId) || userId == request.auth.uid);
        allow update: if isOwner(teamId) && canWriteTeam(teamId);
        allow delete: if false;
      }

      match /leads/{leadId} {
        allow read: if canReadTeam(teamId)
          && (isOwner(teamId) || isAssigned(resource.data));
        allow create: if canWriteTeam(teamId)
          && request.resource.data.teamId == teamId
          && (isOwner(teamId) || request.resource.data.assignedToUserId == request.auth.uid)
          && request.resource.data.createdByUserId == request.auth.uid;
        allow update: if canWriteTeam(teamId)
          && (isOwner(teamId) || isAssigned(resource.data))
          && (!("assignedToUserId" in request.resource.data.diff(resource.data).changedKeys()) || isOwner(teamId));
        allow delete: if isOwner(teamId) && canWriteTeam(teamId);
      }

      match /bookings/{bookingId} {
        allow read: if canReadTeam(teamId)
          && (isOwner(teamId) || isAssigned(resource.data));
        allow create: if canWriteTeam(teamId)
          && request.resource.data.teamId == teamId
          && (isOwner(teamId) || request.resource.data.assignedToUserId == request.auth.uid)
          && request.resource.data.createdByUserId == request.auth.uid;
        allow update: if canWriteTeam(teamId)
          && (isOwner(teamId) || isAssigned(resource.data))
          && (!("assignedToUserId" in request.resource.data.diff(resource.data).changedKeys()) || isOwner(teamId));
        allow delete: if isOwner(teamId) && canWriteTeam(teamId);
      }

      match /ownerInstructions/{instructionId} {
        allow read: if canReadTeam(teamId)
          && (isOwner(teamId) || isAssigned(resource.data));
        allow create, update: if isOwner(teamId) && canWriteTeam(teamId);
        allow delete: if isOwner(teamId) && canWriteTeam(teamId);
      }

      match /dutySessions/{sessionId} {
        allow read: if canReadTeam(teamId)
          && (isOwner(teamId) || resource.data.repUserId == request.auth.uid);
        allow create: if canWriteTeam(teamId)
          && request.resource.data.teamId == teamId
          && request.resource.data.repUserId == request.auth.uid;
        allow update: if canWriteTeam(teamId)
          && resource.data.repUserId == request.auth.uid;
        allow delete: if false;

        match /points/{pointId} {
          allow read: if canReadTeam(teamId)
            && (isOwner(teamId) || resource.data.repUserId == request.auth.uid);
          allow create: if canWriteTeam(teamId)
            && request.resource.data.teamId == teamId
            && request.resource.data.sessionId == sessionId
            && request.resource.data.repUserId == request.auth.uid;
          allow update, delete: if false;
        }
      }

      match /activityLog/{activityId} {
        allow read: if canReadTeam(teamId)
          && (isOwner(teamId) || resource.data.actorUserId == request.auth.uid || resource.data.targetUserId == request.auth.uid);
        allow create: if canWriteTeam(teamId)
          && request.resource.data.actorUserId == request.auth.uid;
        allow update, delete: if false;
      }
    }

    match /{document=**} {
      allow read, write: if false;
    }
  }
}
```

- [ ] **Step 2: Sanity-check rules syntax locally**

Run: `firebase deploy --only firestore:rules --dry-run`

Expected: PASS or a clear local Firebase CLI error. If Firebase CLI is unavailable, record that rule syntax was reviewed but not deployed.

- [ ] **Step 3: Commit**

```bash
git add firestore.rules
git commit -m "feat(team): add Firestore team access rules"
```

### Task 4: Duty Session Manager

**Files:**
- Create: `D2D Advancer/TeamDutySessionManager.swift`
- Modify: `D2D AdvancerTests/TeamWorkspaceTests.swift`

- [ ] **Step 1: Write failing tests for duty write gating and point retention**

Add:

```swift
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
    #expect(TeamDutySessionManager.canStartDutySession(planStatus: .active, role: .member))
    #expect(!TeamDutySessionManager.canStartDutySession(planStatus: .grace, role: .member))
    #expect(!TeamDutySessionManager.canStartDutySession(planStatus: .paused, role: .member))
    #expect(!TeamDutySessionManager.canStartDutySession(planStatus: .active, role: .owner))
}
```

- [ ] **Step 2: Run tests to verify missing manager fails**

Run: `xcodebuild test -project "D2D Advancer.xcodeproj" -scheme "D2D Advancer" -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:D2D_AdvancerTests/TeamWorkspaceTests`

Expected: FAIL with missing `TeamDutySessionManager`.

- [ ] **Step 3: Implement duty manager**

```swift
import Foundation
import CoreLocation
import FirebaseFirestore

@MainActor
final class TeamDutySessionManager: ObservableObject {
    static let shared = TeamDutySessionManager()

    @Published private(set) var activeSession: TeamDutySession?
    @Published private(set) var isWritingLocation = false
    @Published private(set) var lastErrorMessage: String?

    private let db = Firestore.firestore()

    private init() {}

    static func canStartDutySession(planStatus: TeamPlanStatus, role: TeamRole) -> Bool {
        planStatus.allowsTeamWrite && role == .member
    }

    func startDuty(team: TeamWorkspace, member: TeamMember, now: Date = Date()) async throws {
        guard Self.canStartDutySession(planStatus: team.planStatus, role: member.role) else {
            throw TeamServiceError.writeBlocked
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

        try await db.collection("teams").document(team.id).collection("dutySessions").document(session.id).setData(session.firestoreData)
        activeSession = session
    }

    func recordCurrentLocation(_ location: CLLocation, team: TeamWorkspace, member: TeamMember, now: Date = Date()) async throws {
        guard let session = activeSession, session.status == .active else { throw TeamServiceError.noActiveTeam }
        guard team.planStatus.allowsTeamWrite else { throw TeamServiceError.writeBlocked }

        isWritingLocation = true
        defer { isWritingLocation = false }

        let point = TeamDutyLocationPoint(
            teamId: team.id,
            sessionId: session.id,
            repUserId: member.userId,
            coordinate: TeamCoordinate(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude),
            horizontalAccuracy: location.horizontalAccuracy,
            recordedAt: now
        )

        try await db
            .collection("teams").document(team.id)
            .collection("dutySessions").document(session.id)
            .collection("points").document(point.id)
            .setData(point.firestoreData)
    }

    func endDuty(team: TeamWorkspace, now: Date = Date()) async throws {
        guard let session = activeSession else { return }
        let ended = TeamDutySession.ended(
            id: session.id,
            teamId: team.id,
            repUserId: session.repUserId,
            startedAt: session.startedAt,
            endedAt: now,
            distanceMeters: session.distanceMeters
        )
        try await db.collection("teams").document(team.id).collection("dutySessions").document(session.id).setData(ended.firestoreData, merge: true)
        activeSession = nil
    }
}
```

Also add `firestoreData` extensions for `TeamDutySession` and `TeamDutyLocationPoint` in `TeamFirestorePayloads.swift`.

- [ ] **Step 4: Run tests**

Run: `xcodebuild test -project "D2D Advancer.xcodeproj" -scheme "D2D Advancer" -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:D2D_AdvancerTests/TeamWorkspaceTests`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add "D2D Advancer/TeamDutySessionManager.swift" "D2D Advancer/TeamFirestorePayloads.swift" "D2D AdvancerTests/TeamWorkspaceTests.swift"
git commit -m "feat(team): add duty session manager"
```

### Task 5: Team Workspace UI Entry Point

**Files:**
- Create: `D2D Advancer/TeamWorkspaceView.swift`
- Modify: `D2D Advancer/MoreView.swift`

- [ ] **Step 1: Add Team card in MoreView**

Insert a NavigationLink near the Cloud Storage card:

```swift
NavigationLink(destination: TeamWorkspaceView()) {
    MoreCardView(
        icon: "person.3.fill",
        iconColor: Color.electricViolet,
        title: "Team Workspace",
        subtitle: "Invite reps, share assigned leads, and manage active hours",
        showChevron: true
    )
}
.buttonStyle(PlainButtonStyle())
```

- [ ] **Step 2: Create TeamWorkspaceView**

```swift
import SwiftUI

struct TeamWorkspaceView: View {
    @ObservedObject private var teamService = TeamFirebaseService.shared
    @ObservedObject private var dutyManager = TeamDutySessionManager.shared

    var body: some View {
        NavigationView {
            ScrollView {
                LazyVStack(spacing: 14) {
                    statusCard
                    if let team = teamService.activeTeam, let member = teamService.currentMember {
                        planStateCard(team)
                        if member.role == .owner {
                            ownerSummary(team: team)
                        } else {
                            repSummary(team: team, member: member)
                        }
                    } else {
                        emptyState
                    }
                }
                .padding(16)
            }
            .background(Color.obsidianBlack.ignoresSafeArea())
            .navigationTitle("Team")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Hybrid Team Workspace", systemImage: "person.3.fill")
                .font(.headline)
                .foregroundColor(Color.textPrimary)
            Text("Personal leads stay private. Team leads, bookings, instructions, and active-hours GPS are synced through Firebase with assignment-based access.")
                .font(.subheadline)
                .foregroundColor(Color.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.obsidianCard)
        .cornerRadius(8)
    }

    private func planStateCard(_ team: TeamWorkspace) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(team.name)
                .font(.headline)
                .foregroundColor(Color.textPrimary)
            Text(team.planStatus == .active ? "Team plan active" : team.planStatus == .grace ? "Read-only grace period" : "Team paused")
                .font(.subheadline)
                .foregroundColor(team.planStatus == .active ? Color.statusConverted : Color.statusNotHome)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.obsidianCard)
        .cornerRadius(8)
    }

    private func ownerSummary(team: TeamWorkspace) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Owner Controls")
                .font(.headline)
                .foregroundColor(Color.textPrimary)
            statRow("Team leads", "\(teamService.teamLeads.count)")
            statRow("Bookings", "\(teamService.teamBookings.count)")
            statRow("Active reps", "\(teamService.dutySessions.filter { $0.status == .active }.count)")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.obsidianCard)
        .cornerRadius(8)
    }

    private func repSummary(team: TeamWorkspace, member: TeamMember) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("My Team Work")
                .font(.headline)
                .foregroundColor(Color.textPrimary)
            statRow("Assigned leads", "\(teamService.teamLeads.count)")
            statRow("Assigned bookings", "\(teamService.teamBookings.count)")

            Button(dutyManager.activeSession == nil ? "Go On Duty" : "Go Off Duty") {
                Task {
                    if dutyManager.activeSession == nil {
                        try? await dutyManager.startDuty(team: team, member: member)
                    } else {
                        try? await dutyManager.endDuty(team: team)
                    }
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(!team.planStatus.allowsTeamWrite)

            Text("Your active-hours route is visible to the owner while you are on duty. Your live dot disappears when you go off duty.")
                .font(.footnote)
                .foregroundColor(Color.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.obsidianCard)
        .cornerRadius(8)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("No team loaded")
                .font(.headline)
                .foregroundColor(Color.textPrimary)
            Text("Create or join one team to use shared assigned leads, bookings, owner instructions, and manual active-hours GPS sharing.")
                .font(.subheadline)
                .foregroundColor(Color.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.obsidianCard)
        .cornerRadius(8)
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
        .font(.subheadline)
    }
}

#Preview {
    TeamWorkspaceView()
}
```

- [ ] **Step 3: Build to verify SwiftUI compiles**

Run: `xcodebuild build -project "D2D Advancer.xcodeproj" -scheme "D2D Advancer" -destination 'platform=iOS Simulator,name=iPhone 17 Pro'`

Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add "D2D Advancer/TeamWorkspaceView.swift" "D2D Advancer/MoreView.swift"
git commit -m "feat(team): add workspace entry screen"
```

### Task 6: Final Verification

**Files:**
- Verify all changed files.

- [ ] **Step 1: Run targeted team tests**

Run: `xcodebuild test -project "D2D Advancer.xcodeproj" -scheme "D2D Advancer" -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:D2D_AdvancerTests/TeamWorkspaceTests`

Expected: PASS.

- [ ] **Step 2: Run app build**

Run: `xcodebuild build -project "D2D Advancer.xcodeproj" -scheme "D2D Advancer" -destination 'platform=iOS Simulator,name=iPhone 17 Pro'`

Expected: PASS.

- [ ] **Step 3: Review diff**

Run: `git diff --stat HEAD`

Expected: only team implementation files, tests, rules, plan, and the MoreView entrypoint are new or changed by this work. Existing unrelated dirty files remain unstaged unless they were explicitly edited for this feature.
