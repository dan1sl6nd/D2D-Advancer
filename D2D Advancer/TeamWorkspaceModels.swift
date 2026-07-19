import Foundation

enum TeamRole: String, Codable, CaseIterable, Sendable {
    case owner
    case member
}

enum TeamMemberStatus: String, Codable, CaseIterable, Sendable {
    case active
    case removed
}

enum TeamMemberWorkType: String, Codable, CaseIterable, Hashable, Sendable {
    case owner
    case salesRep = "sales_rep"
    case technician

    var title: String {
        switch self {
        case .owner:
            return "Owner"
        case .salesRep:
            return "Sales Rep"
        case .technician:
            return "Technician"
        }
    }
}

enum TeamPlanStatus: String, Codable, CaseIterable, Sendable {
    case active
    case grace
    case paused

    var allowsTeamRead: Bool {
        self == .active || self == .grace
    }

    var allowsTeamWrite: Bool {
        self == .active
    }
}

enum TeamVisibleIdentityProvider: Equatable, Sendable {
    case apple
}

enum TeamBackendIdentityProvider: Equatable, Sendable {
    case firebase
}

enum TeamAuthPolicy {
    static let visibleIdentityProvider: TeamVisibleIdentityProvider = .apple
    static let backendIdentityProvider: TeamBackendIdentityProvider = .firebase
    static let signInButtonTitle = "Continue with Apple"
    static let signInRequiredTitle = "Apple Sign-In Required"

    static func canUseTeamWorkspace(isFirebaseAuthenticated: Bool) -> Bool {
        isFirebaseAuthenticated
    }
}

enum TeamInviteDelivery: Equatable, Sendable {
    case appleShareLink
    case firebaseInviteCode
}

enum TeamSharePrivacyModel: Equatable, Sendable {
    case perRepWorkspace
    case assignedFirebaseRecords
}

struct TeamInvite: Identifiable, Codable, Equatable, Sendable {
    var id: String { code }
    var code: String
    var teamId: String
    var expiresAt: Date

    var displayCode: String {
        code.uppercased()
    }
}

enum TeamFirebaseSchema {
    enum Collection {
        static let teams = "teams"
        static let teamInvites = "teamInvites"
        static let users = "users"
        static let members = "members"
        static let leads = "leads"
        static let bookings = "bookings"
        static let dutySessions = "dutySessions"
        static let dutyLocationPoints = "dutyLocationPoints"
        static let ownerNotifications = "ownerNotifications"
        static let ownerInstructions = "ownerInstructions"
        static let activityLog = "activityLog"
        static let teamProfile = "teamProfile"
        static let serviceControls = "serviceControls"
        static let teamUsageControls = "teamUsageControls"
    }

    enum Field {
        static let acceptedAt = "acceptedAt"
        static let acceptedByUserId = "acceptedByUserId"
        static let acceptedInviteId = "acceptedInviteId"
        static let address = "address"
        static let actorDisplayName = "actorDisplayName"
        static let actorUserId = "actorUserId"
        static let arrivalWindowMinutes = "arrivalWindowMinutes"
        static let assignedToUserId = "assignedToUserId"
        static let createdAt = "createdAt"
        static let createdByUserId = "createdByUserId"
        static let customerEmail = "customerEmail"
        static let customerName = "customerName"
        static let customerPhone = "customerPhone"
        static let displayName = "displayName"
        static let distanceMeters = "distanceMeters"
        static let email = "email"
        static let endDate = "endDate"
        static let endedAt = "endedAt"
        static let estimatedValue = "estimatedValue"
        static let eventType = "eventType"
        static let expiresAt = "expiresAt"
        static let followUpDate = "followUpDate"
        static let graceEndsAt = "graceEndsAt"
        static let highPriorityReason = "highPriorityReason"
        static let horizontalAccuracy = "horizontalAccuracy"
        static let isHighPriority = "isHighPriority"
        static let joinedAt = "joinedAt"
        static let lastLocationAt = "lastLocationAt"
        static let lastContactedAt = "lastContactedAt"
        static let lastContactSummary = "lastContactSummary"
        static let leadId = "leadId"
        static let latitude = "latitude"
        static let location = "location"
        static let longitude = "longitude"
        static let memberLimit = "memberLimit"
        static let message = "message"
        static let name = "name"
        static let notes = "notes"
        static let ownerUserId = "ownerUserId"
        static let planExpiresAt = "planExpiresAt"
        static let planStatus = "planStatus"
        static let phone = "phone"
        static let price = "price"
        static let quotedPrice = "quotedPrice"
        static let recordedAt = "recordedAt"
        static let removedAt = "removedAt"
        static let repUserId = "repUserId"
        static let role = "role"
        static let serviceCategory = "serviceCategory"
        static let sessionId = "sessionId"
        static let startDate = "startDate"
        static let startedAt = "startedAt"
        static let status = "status"
        static let tags = "tags"
        static let teamId = "teamId"
        static let title = "title"
        static let updatedAt = "updatedAt"
        static let updatedByUserId = "updatedByUserId"
        static let userId = "userId"
        static let workType = "workType"
        static let deleteAfter = "deleteAfter"
        static let readAt = "readAt"
        static let repNote = "repNote"
        static let repRespondedAt = "repRespondedAt"
        static let repStatus = "repStatus"
        static let subjectId = "subjectId"
        static let subjectTitle = "subjectTitle"
        static let targetUserId = "targetUserId"
        static let kind = "kind"
        static let summary = "summary"
        static let teamWritesEnabled = "teamWritesEnabled"
        static let reason = "reason"
        static let source = "source"
        static let pausedAt = "pausedAt"
        static let level = "level"
        static let writesAllowed = "writesAllowed"
        static let limitedUntil = "limitedUntil"
        static let blockedCollections = "blockedCollections"
        static let dailyWrites = "dailyWrites"
        static let dailyWriteLimit = "dailyWriteLimit"
        static let velocityWrites = "velocityWrites"
        static let velocityWriteLimit = "velocityWriteLimit"
        static let velocityWindowMinutes = "velocityWindowMinutes"
        static let activeRecords = "activeRecords"
        static let recordLimits = "recordLimits"
    }

    enum InviteStatus {
        static let pending = "pending"
        static let accepted = "accepted"
        static let cancelled = "cancelled"
    }

    static let currentTeamProfileDocumentId = "current"
    static let teamOperationsControlDocumentId = "teamOperations"
    static let pendingRepUserPrefix = "pending-rep"
    static let inviteExpirationInterval: TimeInterval = 7 * 24 * 60 * 60
    static let inviteDelivery: TeamInviteDelivery = .firebaseInviteCode
    static let sharePrivacyModel: TeamSharePrivacyModel = .assignedFirebaseRecords
}

struct TeamOperationsControl: Equatable, Sendable {
    static let defaultPausedMessage = "Team edits are temporarily paused while usage is checked. Existing team data remains available."
    static let enabled = TeamOperationsControl(teamWritesEnabled: true, message: nil)

    var teamWritesEnabled: Bool
    var message: String?

    var displayMessage: String {
        guard let message = message?.trimmingCharacters(in: .whitespacesAndNewlines),
              !message.isEmpty else {
            return Self.defaultPausedMessage
        }
        return message
    }
}

enum TeamUsageLevel: String, Codable, CaseIterable, Sendable {
    case normal
    case warning
    case limited
}

struct TeamUsageControl: Equatable, Sendable {
    static let defaultLimitedMessage = "Team updates are temporarily limited because usage increased unusually fast. Existing data remains available."
    static let normal = TeamUsageControl(
        level: .normal,
        writesAllowed: true,
        limitedUntil: nil,
        blockedCollections: [],
        dailyWrites: 0,
        dailyWriteLimit: 5_000,
        velocityWrites: 0,
        velocityWriteLimit: 300,
        velocityWindowMinutes: 15,
        activeRecords: [:],
        recordLimits: [:],
        message: nil
    )

    var level: TeamUsageLevel
    var writesAllowed: Bool
    var limitedUntil: Date?
    var blockedCollections: Set<String>
    var dailyWrites: Int
    var dailyWriteLimit: Int
    var velocityWrites: Int
    var velocityWriteLimit: Int
    var velocityWindowMinutes: Int
    var activeRecords: [String: Int]
    var recordLimits: [String: Int]
    var message: String?

    func allowsWrite(now: Date = Date()) -> Bool {
        writesAllowed || limitedUntil.map { $0 <= now } == true
    }

    func allowsCreate(in collection: String, now: Date = Date()) -> Bool {
        allowsWrite(now: now) && !blockedCollections.contains(collection)
    }

    var displayMessage: String {
        guard let message = message?.trimmingCharacters(in: .whitespacesAndNewlines),
              !message.isEmpty else {
            return Self.defaultLimitedMessage
        }
        return message
    }

    var dailyUsageFraction: Double {
        guard dailyWriteLimit > 0 else { return 0 }
        return min(1, Double(dailyWrites) / Double(dailyWriteLimit))
    }

    var velocityUsageFraction: Double {
        guard velocityWriteLimit > 0 else { return 0 }
        return min(1, Double(velocityWrites) / Double(velocityWriteLimit))
    }
}

struct TeamLocalWriteSample: Equatable, Sendable {
    var date: Date
    var units: Int
}

struct TeamLocalWriteLimiter: Equatable, Sendable {
    static let defaultWindow: TimeInterval = 15 * 60
    static let defaultMaximumUnits = 150

    var window: TimeInterval = Self.defaultWindow
    var maximumUnits: Int = Self.defaultMaximumUnits
    private(set) var samples: [TeamLocalWriteSample] = []

    mutating func retryDelayIfBlocked(units: Int, now: Date = Date()) -> TimeInterval? {
        samples.removeAll { now.timeIntervalSince($0.date) >= window }
        let requestedUnits = max(1, units)
        let usedUnits = samples.reduce(0) { $0 + $1.units }
        guard usedUnits + requestedUnits <= maximumUnits else {
            guard let oldestDate = samples.first?.date else { return window }
            return max(1, window - now.timeIntervalSince(oldestDate))
        }
        samples.append(TeamLocalWriteSample(date: now, units: requestedUnits))
        return nil
    }

    mutating func reset() {
        samples = []
    }
}

struct TeamCoordinate: Codable, Equatable, Sendable {
    var latitude: Double
    var longitude: Double
}

struct TeamWorkspace: Identifiable, Codable, Equatable, Sendable {
    static let includedMemberLimit = 3

    var id: String
    var name: String
    var ownerUserId: String
    var createdAt: Date
    var updatedAt: Date
    var planStatus: TeamPlanStatus
    var planExpiresAt: Date?
    var graceEndsAt: Date?
    var memberLimit: Int

    func effectivePlanStatus(now: Date = Date()) -> TeamPlanStatus {
        guard planStatus != .paused else { return .paused }

        if planStatus == .grace {
            guard let graceEndsAt else { return .grace }
            return graceEndsAt > now ? .grace : .paused
        }

        guard let planExpiresAt else {
            // Existing workspaces predate server-verified billing metadata and
            // remain grandfathered instead of being invalidated during migration.
            return .active
        }
        if planExpiresAt > now {
            return .active
        }
        if let graceEndsAt, graceEndsAt > now {
            return .grace
        }
        return .paused
    }

    static func newOwnerTeam(
        id: String,
        name: String,
        ownerUserId: String,
        now: Date = Date()
    ) -> TeamWorkspace {
        TeamWorkspace(
            id: id,
            name: name,
            ownerUserId: ownerUserId,
            createdAt: now,
            updatedAt: now,
            planStatus: .active,
            planExpiresAt: nil,
            graceEndsAt: nil,
            memberLimit: includedMemberLimit
        )
    }
}

struct TeamMember: Identifiable, Codable, Equatable, Sendable {
    var id: String { userId }
    var teamId: String
    var userId: String
    var displayName: String
    var email: String?
    var role: TeamRole
    var status: TeamMemberStatus
    var workType: TeamMemberWorkType = .salesRep
    var joinedAt: Date
    var removedAt: Date?
    var acceptedInviteId: String? = nil

    var isPendingInvite: Bool {
        userId.hasPrefix(TeamFirebaseSchema.pendingRepUserPrefix)
    }

    var pendingInviteDisplayCode: String? {
        guard isPendingInvite else { return nil }
        return acceptedInviteId?.uppercased()
    }

    var isSalesRep: Bool {
        role == .member && workType == .salesRep
    }

    var isTechnician: Bool {
        role == .member && workType == .technician
    }

    var displayRoleTitle: String {
        role == .owner ? TeamMemberWorkType.owner.title : workType.title
    }

    static func owner(
        teamId: String,
        userId: String,
        displayName: String,
        email: String?,
        joinedAt: Date = Date()
    ) -> TeamMember {
        TeamMember(
            teamId: teamId,
            userId: userId,
            displayName: displayName,
            email: email,
            role: .owner,
            status: .active,
            workType: .owner,
            joinedAt: joinedAt,
            removedAt: nil,
            acceptedInviteId: nil
        )
    }

    static func rep(
        teamId: String,
        userId: String,
        displayName: String,
        email: String?,
        acceptedInviteId: String,
        workType: TeamMemberWorkType = .salesRep,
        joinedAt: Date = Date()
    ) -> TeamMember {
        TeamMember(
            teamId: teamId,
            userId: userId,
            displayName: displayName,
            email: email,
            role: .member,
            status: .active,
            workType: workType,
            joinedAt: joinedAt,
            removedAt: nil,
            acceptedInviteId: acceptedInviteId
        )
    }
}

extension TeamMember {
    static func removed(_ member: TeamMember, removedAt: Date) -> TeamMember {
        var removedMember = member
        removedMember.status = .removed
        removedMember.removedAt = removedAt
        return removedMember
    }
}

enum TeamMemberRoster {
    static func normalized(_ members: [TeamMember]) -> [TeamMember] {
        var membersByUserId: [String: TeamMember] = [:]
        for member in members {
            if let existing = membersByUserId[member.userId] {
                membersByUserId[member.userId] = preferred(existing, member)
            } else {
                membersByUserId[member.userId] = member
            }
        }

        return membersByUserId.values.sorted(by: sort)
    }

    static func upserting(_ member: TeamMember, into members: [TeamMember]) -> [TeamMember] {
        normalized(members + [member])
    }

    static func activeSeatCount(_ members: [TeamMember]) -> Int {
        normalized(members).filter { $0.status == .active }.count
    }

    private static func preferred(_ lhs: TeamMember, _ rhs: TeamMember) -> TeamMember {
        if lhs.status != rhs.status {
            return lhs.status == .active ? lhs : rhs
        }
        return lhs.joinedAt >= rhs.joinedAt ? lhs : rhs
    }

    private static func sort(lhs: TeamMember, rhs: TeamMember) -> Bool {
        if lhs.role != rhs.role { return lhs.role == .owner }
        if lhs.joinedAt != rhs.joinedAt { return lhs.joinedAt < rhs.joinedAt }
        return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
    }
}

enum TeamLeadStatus: String, Codable, CaseIterable, Sendable {
    case notContacted = "not_contacted"
    case notHome = "not_home"
    // Compatibility-only values written by older Team builds.
    case contacted
    case interested
    case followUp = "follow_up"
    case booked
    case converted
    case notInterested = "not_interested"

    static var allCases: [TeamLeadStatus] {
        [.notContacted, .notHome, .interested, .converted, .notInterested]
    }

    static func persistedValue(_ rawValue: String) -> TeamLeadStatus? {
        if let exact = TeamLeadStatus(rawValue: rawValue) {
            return exact
        }

        let normalized = rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: " ", with: "_")
        switch normalized {
        case "new", "cold", "not_contacted", "notcontacted": return .notContacted
        case "away", "later", "no_answer", "not_home", "nothome": return .notHome
        case "contacted": return .contacted
        case "interested", "prospect": return .interested
        case "follow_up", "followup": return .followUp
        case "booked": return .booked
        case "sold", "closed", "won": return .converted
        case "converted": return .converted
        case "pass", "lost", "not_interested", "notinterested": return .notInterested
        default: return nil
        }
    }

    /// The five-state sales pipeline used by current UI and all new writes.
    var workflowStatus: TeamLeadStatus {
        switch self {
        case .contacted:
            return .notContacted
        case .followUp, .booked:
            return .interested
        case .notContacted, .notHome, .interested, .converted, .notInterested:
            return self
        }
    }

    var persistedWorkflowRawValue: String {
        workflowStatus.rawValue
    }

    var isTerminalWorkflowStatus: Bool {
        workflowStatus == .converted || workflowStatus == .notInterested
    }

    var allowsFollowUpWorkflow: Bool {
        !isTerminalWorkflowStatus
    }
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
    var followUpDate: Date? = nil
    var lastContactedAt: Date? = nil
    var lastContactSummary: String? = nil

    var workflowStatus: TeamLeadStatus {
        status.workflowStatus
    }

    var isDispatchReady: Bool {
        workflowStatus == .converted || status == .booked || price > 0
    }

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

struct TeamLeadEditableFields: Equatable, Sendable {
    var name: String
    var address: String
    var phone: String
    var email: String
    var notes: String
    var serviceCategory: String
    var price: Double
    var estimatedValue: Double
    var tags: [String]

    static func from(_ lead: TeamLead) -> TeamLeadEditableFields {
        TeamLeadEditableFields(
            name: lead.name,
            address: lead.address,
            phone: lead.phone ?? "",
            email: lead.email ?? "",
            notes: lead.notes,
            serviceCategory: lead.serviceCategory ?? "",
            price: lead.price,
            estimatedValue: lead.estimatedValue,
            tags: lead.tags
        )
    }

    func applying(to lead: TeamLead, updatedByUserId: String, now: Date = Date()) -> TeamLead {
        var updated = lead
        updated.status = lead.workflowStatus
        updated.name = normalizedRequired(name, fallback: "New Lead")
        updated.address = normalizedRequired(address, fallback: "No address")
        updated.phone = normalizedOptional(phone)
        updated.email = normalizedOptional(email)
        updated.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.serviceCategory = normalizedOptional(serviceCategory)
        updated.price = max(0, price)
        updated.estimatedValue = max(0, estimatedValue)
        updated.tags = tags
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        updated.updatedByUserId = updatedByUserId
        updated.updatedAt = now
        return updated
    }

    private func normalizedOptional(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func normalizedRequired(_ value: String, fallback: String) -> String {
        normalizedOptional(value) ?? fallback
    }
}

enum TeamBookingStatus: String, Codable, CaseIterable, Sendable {
    case scheduled
    case confirmed
    case enRoute = "en_route"
    case inProgress = "in_progress"
    case completed
    case needsOwnerFollowUp = "needs_owner_follow_up"
    case cancelled
    case rescheduled

    var displayName: String {
        switch self {
        case .scheduled:
            return "Scheduled"
        case .confirmed:
            return "Confirmed"
        case .enRoute:
            return "On the way"
        case .inProgress:
            return "Started"
        case .completed:
            return "Completed"
        case .needsOwnerFollowUp:
            return "Needs follow-up"
        case .cancelled:
            return "Cancelled"
        case .rescheduled:
            return "Rescheduled"
        }
    }
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
    var customerName: String? = nil
    var customerPhone: String? = nil
    var customerEmail: String? = nil
    var serviceCategory: String? = nil
    var quotedPrice: Double? = nil
    var latitude: Double? = nil
    var longitude: Double? = nil
    var arrivalWindowMinutes: Int? = nil

    var isFutureEditable: Bool {
        status != .completed && status != .cancelled
    }

    var customerDisplayName: String {
        if let trimmedName = customerName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !trimmedName.isEmpty {
            return trimmedName
        }
        return title
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

struct TeamOwnerNotification: Identifiable, Codable, Equatable, Sendable {
    static let retentionInterval: TimeInterval = 60 * 24 * 60 * 60

    var id: String
    var teamId: String
    var leadId: String
    var assignedToUserId: String
    var createdByUserId: String
    var event: TeamOwnerLeadEvent
    var title: String
    var message: String
    var createdAt: Date
    var readAt: Date?
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

    var coordinate: TeamCoordinate {
        TeamCoordinate(latitude: latitude, longitude: longitude)
    }
}

struct TeamRepWorkspace: Identifiable, Equatable, Sendable {
    var id: String { member.userId }

    var member: TeamMember
    var assignedLeads: [TeamLead]
    var assignedBookings: [TeamBooking]
    var activeSession: TeamDutySession?
    var latestSession: TeamDutySession?
    var liveLocation: TeamDutyLocationPoint?
    var routePoints: [TeamDutyLocationPoint]

    var isOnDuty: Bool {
        activeSession != nil
    }

    var mapItemCount: Int {
        assignedLeads.count + assignedBookings.count + (liveLocation == nil ? 0 : 1)
    }

    static func makeOwnerWorkspaces(
        members: [TeamMember],
        leads: [TeamLead],
        bookings: [TeamBooking],
        dutySessions: [TeamDutySession],
        dutyLocationPoints: [TeamDutyLocationPoint]
    ) -> [TeamRepWorkspace] {
        let reps = TeamMemberRoster.normalized(members)
            .filter { $0.role == .member && $0.status == .active && !$0.isPendingInvite }
            .sorted { lhs, rhs in
                if lhs.joinedAt != rhs.joinedAt { return lhs.joinedAt < rhs.joinedAt }
                return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
            }

        let leadsByRep = Dictionary(grouping: leads, by: \.assignedToUserId)
        let bookingsByRep = Dictionary(grouping: bookings, by: \.assignedToUserId)
        let sessionsByRep = Dictionary(grouping: dutySessions, by: \.repUserId)
        let pointsBySession = Dictionary(grouping: dutyLocationPoints, by: \.sessionId)

        return reps.map { rep in
            makeWorkspace(
                member: rep,
                leads: leadsByRep[rep.userId] ?? [],
                bookings: bookingsByRep[rep.userId] ?? [],
                sessions: sessionsByRep[rep.userId] ?? [],
                pointsBySession: pointsBySession
            )
        }
    }

    static func makeMemberWorkspace(
        member: TeamMember,
        leads: [TeamLead],
        bookings: [TeamBooking],
        dutySessions: [TeamDutySession],
        dutyLocationPoints: [TeamDutyLocationPoint]
    ) -> TeamRepWorkspace {
        makeWorkspace(
            member: member,
            leads: leads,
            bookings: bookings,
            sessions: dutySessions.filter { $0.repUserId == member.userId },
            pointsBySession: Dictionary(grouping: dutyLocationPoints.filter { $0.repUserId == member.userId }, by: \.sessionId)
        )
    }

    static func makeVisibleMemberWorkspaces(
        currentMember: TeamMember,
        members: [TeamMember],
        leads: [TeamLead],
        bookings: [TeamBooking],
        dutySessions: [TeamDutySession],
        dutyLocationPoints: [TeamDutyLocationPoint]
    ) -> [TeamRepWorkspace] {
        var workspaces = [
            makeMemberWorkspace(
                member: currentMember,
                leads: leads.filter { $0.assignedToUserId == currentMember.userId },
                bookings: bookings.filter { $0.assignedToUserId == currentMember.userId },
                dutySessions: dutySessions,
                dutyLocationPoints: dutyLocationPoints
            )
        ]

        if let owner = members.first(where: { $0.role == .owner && $0.status == .active }),
           owner.userId != currentMember.userId {
            let ownerWorkspace = makeMemberWorkspace(
                member: owner,
                leads: [],
                bookings: [],
                dutySessions: dutySessions,
                dutyLocationPoints: dutyLocationPoints
            )
            if ownerWorkspace.latestSession != nil {
                workspaces.insert(ownerWorkspace, at: 0)
            }
        }

        return workspaces
    }

    private static func makeWorkspace(
        member: TeamMember,
        leads: [TeamLead],
        bookings: [TeamBooking],
        sessions: [TeamDutySession],
        pointsBySession: [String: [TeamDutyLocationPoint]]
    ) -> TeamRepWorkspace {
        let activeSession = sessions
            .filter { $0.status == .active }
            .sorted { $0.startedAt > $1.startedAt }
            .first
        let latestSession = activeSession ?? sessions
            .sorted {
                ($0.endedAt ?? $0.startedAt) > ($1.endedAt ?? $1.startedAt)
            }
            .first
        let routePoints = latestSession
            .map { pointsBySession[$0.id] ?? [] }?
            .sorted { $0.recordedAt < $1.recordedAt } ?? []
        let liveLocation = activeSession == nil ? nil : routePoints.last

        return TeamRepWorkspace(
            member: member,
            assignedLeads: sortedOwnerLeads(leads),
            assignedBookings: bookings.sorted { $0.startDate < $1.startDate },
            activeSession: activeSession,
            latestSession: latestSession,
            liveLocation: liveLocation,
            routePoints: routePoints
        )
    }

    private static func sortedOwnerLeads(_ leads: [TeamLead]) -> [TeamLead] {
        leads.sorted { lhs, rhs in
            if lhs.isHighPriority != rhs.isHighPriority {
                return lhs.isHighPriority && !rhs.isHighPriority
            }
            let lhsRank = TeamLeadImportance.rank(lhs.status)
            let rhsRank = TeamLeadImportance.rank(rhs.status)
            if lhsRank != rhsRank { return lhsRank > rhsRank }
            return lhs.updatedAt > rhs.updatedAt
        }
    }
}

struct TeamWorkspaceSurfaceSummary: Equatable, Identifiable, Sendable {
    var role: TeamRole
    var currentMemberWorkType: TeamMemberWorkType?
    var teamName: String
    var workspaces: [TeamRepWorkspace]
    var teamLeadCount: Int
    var importantLeadCount: Int
    var activeRepCount: Int
    var upcomingBookingCount: Int
    var unreadNotificationCount: Int

    var id: String {
        "\(role.rawValue):\(teamName)"
    }

    var hasMapContent: Bool {
        workspaces.contains { !$0.assignedLeads.isEmpty || $0.liveLocation != nil || !$0.routePoints.isEmpty }
    }

    var hasUrgentActivity: Bool {
        importantLeadCount > 0 || upcomingBookingCount > 0 || unreadNotificationCount > 0
    }

    var shouldShowMapShortcut: Bool {
        true
    }

    var headline: String {
        switch role {
        case .owner:
            if activeRepCount > 0 {
                return "\(activeRepCount) active \(Self.plural("worker", activeRepCount))"
            }
            let workerCount = workspaces.count
            return "\(workerCount) \(Self.plural("worker", workerCount))"
        case .member:
            if currentMemberWorkType == .technician {
                return "\(upcomingBookingCount) assigned \(Self.plural("job", upcomingBookingCount))"
            }
            return "\(teamLeadCount) assigned \(Self.plural("lead", teamLeadCount))"
        }
    }

    var detailLine: String {
        var parts: [String] = []
        if importantLeadCount > 0 {
            parts.append("\(importantLeadCount) important")
        }
        if upcomingBookingCount > 0 {
            let workLabel = currentMemberWorkType == .technician ? "job" : "booking"
            parts.append("\(upcomingBookingCount) \(Self.plural(workLabel, upcomingBookingCount))")
        }
        if unreadNotificationCount > 0 {
            parts.append("\(unreadNotificationCount) \(Self.plural("alert", unreadNotificationCount))")
        }
        if parts.isEmpty {
            parts.append(role == .owner ? "No urgent team activity" : "No urgent assigned work")
        }
        return parts.joined(separator: " • ")
    }

    var badgeCount: Int {
        unreadNotificationCount + importantLeadCount
    }

    static func make(
        team: TeamWorkspace?,
        currentMember: TeamMember?,
        members: [TeamMember],
        leads: [TeamLead],
        bookings: [TeamBooking],
        dutySessions: [TeamDutySession],
        dutyLocationPoints: [TeamDutyLocationPoint],
        ownerNotifications: [TeamOwnerNotification],
        now: Date = Date()
    ) -> TeamWorkspaceSurfaceSummary? {
        guard let team, let currentMember, team.effectivePlanStatus(now: now).allowsTeamRead else { return nil }

        switch currentMember.role {
        case .owner:
            let workspaces = TeamRepWorkspace.makeOwnerWorkspaces(
                members: members,
                leads: leads,
                bookings: bookings,
                dutySessions: dutySessions,
                dutyLocationPoints: dutyLocationPoints
            )
            return TeamWorkspaceSurfaceSummary(
                role: .owner,
                currentMemberWorkType: .owner,
                teamName: team.name,
                workspaces: workspaces,
                teamLeadCount: leads.count,
                importantLeadCount: leads.filter(Self.isImportantLead).count,
                activeRepCount: workspaces.filter(\.isOnDuty).count,
                upcomingBookingCount: bookings.filter { Self.isUpcomingBooking($0, now: now) }.count,
                unreadNotificationCount: ownerNotifications.filter { $0.readAt == nil }.count
            )
        case .member:
            let assignedLeads = leads.filter { $0.assignedToUserId == currentMember.userId }
            let assignedBookings = bookings.filter { $0.assignedToUserId == currentMember.userId }
            let workspaces = TeamRepWorkspace.makeVisibleMemberWorkspaces(
                currentMember: currentMember,
                members: members,
                leads: leads,
                bookings: bookings,
                dutySessions: dutySessions,
                dutyLocationPoints: dutyLocationPoints
            )
            return TeamWorkspaceSurfaceSummary(
                role: .member,
                currentMemberWorkType: currentMember.workType,
                teamName: team.name,
                workspaces: workspaces,
                teamLeadCount: assignedLeads.count,
                importantLeadCount: assignedLeads.filter(Self.isImportantLead).count,
                activeRepCount: workspaces.filter(\.isOnDuty).count,
                upcomingBookingCount: assignedBookings.filter { Self.isUpcomingBooking($0, now: now) }.count,
                unreadNotificationCount: 0
            )
        }
    }

    static func makeShortcut(
        team: TeamWorkspace?,
        currentMember: TeamMember?,
        members: [TeamMember],
        leads: [TeamLead],
        bookings: [TeamBooking],
        dutySessions: [TeamDutySession],
        ownerNotifications: [TeamOwnerNotification],
        now: Date = Date()
    ) -> TeamWorkspaceSurfaceSummary? {
        guard let team, let currentMember, team.effectivePlanStatus(now: now).allowsTeamRead else { return nil }

        let activeMembers = TeamMemberRoster.normalized(members)
            .filter { $0.role == .member && $0.status == .active && !$0.isPendingInvite }
        let activeMemberIds = Set(activeMembers.map(\.userId))
        let activeDutyRepCount = Set(
            dutySessions
                .filter { $0.status == .active && activeMemberIds.contains($0.repUserId) }
                .map(\.repUserId)
        ).count
        let lightweightOwnerWorkspaces = activeMembers.map { member in
            TeamRepWorkspace(
                member: member,
                assignedLeads: [],
                assignedBookings: [],
                activeSession: nil,
                latestSession: nil,
                liveLocation: nil,
                routePoints: []
            )
        }

        switch currentMember.role {
        case .owner:
            return TeamWorkspaceSurfaceSummary(
                role: .owner,
                currentMemberWorkType: .owner,
                teamName: team.name,
                workspaces: lightweightOwnerWorkspaces,
                teamLeadCount: leads.count,
                importantLeadCount: leads.lazy.filter(Self.isImportantLead).count,
                activeRepCount: activeDutyRepCount,
                upcomingBookingCount: bookings.lazy.filter { Self.isUpcomingBooking($0, now: now) }.count,
                unreadNotificationCount: ownerNotifications.lazy.filter { $0.readAt == nil }.count
            )
        case .member:
            let assignedLeads = leads.lazy.filter { $0.assignedToUserId == currentMember.userId }
            let assignedBookings = bookings.lazy.filter { $0.assignedToUserId == currentMember.userId }
            return TeamWorkspaceSurfaceSummary(
                role: .member,
                currentMemberWorkType: currentMember.workType,
                teamName: team.name,
                workspaces: [],
                teamLeadCount: assignedLeads.count,
                importantLeadCount: assignedLeads.filter(Self.isImportantLead).count,
                activeRepCount: activeDutyRepCount,
                upcomingBookingCount: assignedBookings.filter { Self.isUpcomingBooking($0, now: now) }.count,
                unreadNotificationCount: 0
            )
        }
    }

    private static func isImportantLead(_ lead: TeamLead) -> Bool {
        TeamLeadAttentionPolicy.needsOwnerAttention(lead)
    }

    private static func isUpcomingBooking(_ booking: TeamBooking, now: Date) -> Bool {
        booking.isFutureEditable && booking.startDate >= now
    }

    private static func plural(_ singular: String, _ count: Int) -> String {
        count == 1 ? singular : "\(singular)s"
    }
}

enum TeamLeadImportance {
    static func rank(_ status: TeamLeadStatus) -> Int {
        switch status.workflowStatus {
        case .converted:
            return 5
        case .interested:
            return 3
        case .notContacted, .notHome, .notInterested:
            return 0
        case .contacted, .followUp, .booked:
            return 0
        }
    }
}

enum TeamLeadAttentionPolicy {
    static func needsOwnerAttention(_ lead: TeamLead) -> Bool {
        guard isOpenForOwnerAttention(lead.status) else { return false }
        return lead.isHighPriority || statusNeedsOwnerAttention(lead.status)
    }

    static func isActionableHighPriority(_ lead: TeamLead) -> Bool {
        lead.isHighPriority && isOpenForOwnerAttention(lead.status)
    }

    static func canMarkHighPriority(_ lead: TeamLead) -> Bool {
        isOpenForOwnerAttention(lead.status)
    }

    private static func isOpenForOwnerAttention(_ status: TeamLeadStatus) -> Bool {
        !status.isTerminalWorkflowStatus
    }

    private static func statusNeedsOwnerAttention(_ status: TeamLeadStatus) -> Bool {
        status.workflowStatus == .interested
    }
}

enum TeamLocationSharingPolicy {
    static let minimumUploadInterval: TimeInterval = 30
    static let maximumUploadInterval: TimeInterval = 2 * 60
    static let minimumDistanceMeters: Double = 50
    static let sessionHeartbeatInterval: TimeInterval = 5 * 60

    static func shouldUploadLocation(
        lastUploadAt: Date?,
        lastCoordinate: TeamCoordinate?,
        newCoordinate: TeamCoordinate,
        usageLevel: TeamUsageLevel = .normal,
        now: Date = Date()
    ) -> Bool {
        guard let lastUploadAt, let lastCoordinate else { return true }
        let elapsed = now.timeIntervalSince(lastUploadAt)
        let isElevatedUsage = usageLevel != .normal
        let minimumInterval = isElevatedUsage ? 45.0 : minimumUploadInterval
        let maximumInterval = isElevatedUsage ? 3 * 60.0 : maximumUploadInterval
        let minimumDistance = isElevatedUsage ? 75.0 : minimumDistanceMeters

        guard elapsed >= minimumInterval else { return false }
        return elapsed >= maximumInterval
            || distanceMeters(from: lastCoordinate, to: newCoordinate) >= minimumDistance
    }

    private static func distanceMeters(from start: TeamCoordinate, to end: TeamCoordinate) -> Double {
        let earthRadiusMeters = 6_371_000.0
        let startLatitude = start.latitude * .pi / 180
        let endLatitude = end.latitude * .pi / 180
        let latitudeDelta = (end.latitude - start.latitude) * .pi / 180
        let longitudeDelta = (end.longitude - start.longitude) * .pi / 180

        let a = sin(latitudeDelta / 2) * sin(latitudeDelta / 2)
            + cos(startLatitude) * cos(endLatitude)
            * sin(longitudeDelta / 2) * sin(longitudeDelta / 2)
        let c = 2 * atan2(sqrt(a), sqrt(1 - a))
        return earthRadiusMeters * c
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

    static func canViewDutySession(
        userId: String,
        role: TeamRole,
        planStatus: TeamPlanStatus,
        session: TeamDutySession,
        ownerUserId: String? = nil
    ) -> Bool {
        guard planStatus.allowsTeamRead else { return false }
        if role == .owner { return true }
        return session.repUserId == userId || session.repUserId == ownerUserId
    }

    static func canStartDutySession(planStatus: TeamPlanStatus, role: TeamRole) -> Bool {
        planStatus.allowsTeamWrite && (role == .owner || role == .member)
    }

    static func canCancelPendingInvite(role: TeamRole, member: TeamMember) -> Bool {
        role == .owner && member.role == .member && member.isPendingInvite
    }

    static func canRemoveMember(actor: TeamMember, team: TeamWorkspace, member: TeamMember) -> Bool {
        guard team.effectivePlanStatus().allowsTeamWrite else { return false }
        guard actor.teamId == team.id, member.teamId == team.id else { return false }
        guard actor.role == .owner, actor.status == .active else { return false }
        guard member.role == .member, member.status == .active, !member.isPendingInvite else { return false }
        return actor.userId != member.userId
    }

    static func canLeaveTeam(member: TeamMember, team: TeamWorkspace) -> Bool {
        member.teamId == team.id
            && member.role == .member
            && member.status == .active
            && !member.isPendingInvite
    }

    static func canCloseTeam(owner: TeamMember, team: TeamWorkspace) -> Bool {
        owner.teamId == team.id
            && owner.userId == team.ownerUserId
            && owner.role == .owner
            && owner.status == .active
    }
}

enum TeamAssignmentPolicy {
    static func canAssignLead(actor: TeamMember, team: TeamWorkspace, target: TeamMember, lead: TeamLead) -> Bool {
        guard target.isSalesRep else { return false }
        return canAssign(
            actor: actor,
            team: team,
            target: target,
            assignedRecordTeamId: lead.teamId
        )
    }

    static func canAssignBooking(actor: TeamMember, team: TeamWorkspace, target: TeamMember, booking: TeamBooking) -> Bool {
        canAssign(
            actor: actor,
            team: team,
            target: target,
            assignedRecordTeamId: booking.teamId
        )
    }

    static func assign(_ lead: TeamLead, to target: TeamMember, by actor: TeamMember, now: Date = Date()) -> TeamLead {
        var updated = lead
        updated.status = lead.workflowStatus
        updated.assignedToUserId = target.userId
        updated.updatedByUserId = actor.userId
        updated.updatedAt = now
        return updated
    }

    static func assign(_ booking: TeamBooking, to target: TeamMember, by actor: TeamMember, now: Date = Date()) -> TeamBooking {
        var updated = booking
        updated.assignedToUserId = target.userId
        updated.updatedByUserId = actor.userId
        updated.updatedAt = now
        return updated
    }

    private static func canAssign(
        actor: TeamMember,
        team: TeamWorkspace,
        target: TeamMember,
        assignedRecordTeamId: String
    ) -> Bool {
        guard team.effectivePlanStatus().allowsTeamWrite else { return false }
        guard actor.teamId == team.id, target.teamId == team.id, assignedRecordTeamId == team.id else { return false }
        guard actor.role == .owner, actor.status == .active else { return false }
        guard target.role == .member, target.status == .active, !target.isPendingInvite else { return false }
        return true
    }
}

enum TeamLeadDispatchPolicy {
    static let defaultDuration: TimeInterval = 2 * 60 * 60

    static func canDispatchLeadToTechnician(
        actor: TeamMember,
        team: TeamWorkspace,
        technician: TeamMember,
        lead: TeamLead
    ) -> Bool {
        guard team.effectivePlanStatus().allowsTeamWrite else { return false }
        guard actor.teamId == team.id, technician.teamId == team.id, lead.teamId == team.id else { return false }
        guard actor.role == .owner, actor.status == .active else { return false }
        return technician.isTechnician && technician.status == .active && !technician.isPendingInvite
    }

    static func soldLead(_ lead: TeamLead, by actor: TeamMember, now: Date = Date()) -> TeamLead {
        var updated = lead
        updated.status = .converted
        updated.updatedByUserId = actor.userId
        updated.updatedAt = now
        return updated
    }

    static func booking(
        from lead: TeamLead,
        to technician: TeamMember,
        by actor: TeamMember,
        startDate: Date,
        endDate: Date,
        now: Date = Date()
    ) -> TeamBooking {
        let safeEndDate = endDate > startDate ? endDate : startDate.addingTimeInterval(defaultDuration)
        return TeamBooking(
            id: "\(lead.id)-job",
            teamId: lead.teamId,
            leadId: lead.id,
            assignedToUserId: technician.userId,
            title: jobTitle(for: lead),
            notes: jobNotes(for: lead),
            startDate: startDate,
            endDate: safeEndDate,
            location: lead.address,
            status: .scheduled,
            createdByUserId: actor.userId,
            updatedByUserId: actor.userId,
            createdAt: now,
            updatedAt: now,
            customerName: lead.name,
            customerPhone: normalizedOptional(lead.phone),
            customerEmail: normalizedOptional(lead.email),
            serviceCategory: normalizedOptional(lead.serviceCategory),
            quotedPrice: lead.price > 0 ? lead.price : nil,
            latitude: lead.latitude,
            longitude: lead.longitude,
            arrivalWindowMinutes: 30
        )
    }

    private static func jobTitle(for lead: TeamLead) -> String {
        let service = lead.serviceCategory?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let service, !service.isEmpty {
            return "\(service) - \(lead.name)"
        }
        return "Service Job - \(lead.name)"
    }

    private static func jobNotes(for lead: TeamLead) -> String {
        var lines: [String] = []
        if let phone = lead.phone, !phone.isEmpty { lines.append("Phone: \(phone)") }
        if let email = lead.email, !email.isEmpty { lines.append("Email: \(email)") }
        if lead.price > 0 { lines.append("Sold price: \(lead.price)") }
        if !lead.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append("Lead notes: \(lead.notes)")
        }
        return lines.joined(separator: "\n")
    }

    private static func normalizedOptional(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }
}

enum TeamRepReplyPolicy {
    static let maxNoteCharacters = 80

    static func canReply(userId: String, role: TeamRole, planStatus: TeamPlanStatus, assignedToUserId: String) -> Bool {
        planStatus.allowsTeamWrite && role == .member && assignedToUserId == userId
    }

    static func sanitizedNote(_ note: String?) -> String? {
        guard let note else { return nil }
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= maxNoteCharacters else { return nil }
        return trimmed
    }
}

enum TeamActivityLogKind: String, Codable, CaseIterable, Sendable {
    case teamCreated = "team_created"
    case inviteCreated = "invite_created"
    case inviteAccepted = "invite_accepted"
    case inviteCancelled = "invite_cancelled"
    case memberLeft = "member_left"
    case memberRemoved = "member_removed"
    case teamClosed = "team_closed"
    case leadCreated = "lead_created"
    case leadAssigned = "lead_assigned"
    case bookingAssigned = "booking_assigned"
    case bookingStatusUpdated = "booking_status_updated"
    case leadStatusUpdated = "lead_status_updated"
    case leadHighPriority = "lead_high_priority"
    case leadFollowUpRecorded = "lead_follow_up_recorded"
    case repStatusReply = "rep_status_reply"
    case dutyStarted = "duty_started"
    case dutyEnded = "duty_ended"
    case ownerAlertRead = "owner_alert_read"

    var actionPhrase: String {
        switch self {
        case .teamCreated:
            return "created team"
        case .inviteCreated:
            return "created invite"
        case .inviteAccepted:
            return "accepted invite"
        case .inviteCancelled:
            return "cancelled invite"
        case .memberLeft:
            return "left team"
        case .memberRemoved:
            return "removed worker"
        case .teamClosed:
            return "closed team"
        case .leadCreated:
            return "created lead"
        case .leadAssigned:
            return "assigned lead"
        case .bookingAssigned:
            return "assigned job"
        case .bookingStatusUpdated:
            return "updated job"
        case .leadStatusUpdated:
            return "updated lead"
        case .leadHighPriority:
            return "marked high priority"
        case .leadFollowUpRecorded:
            return "recorded follow-up for"
        case .repStatusReply:
            return "replied"
        case .dutyStarted:
            return "went on duty"
        case .dutyEnded:
            return "went off duty"
        case .ownerAlertRead:
            return "read alert"
        }
    }
}

struct TeamActivityLogEntry: Identifiable, Codable, Equatable, Sendable {
    static let retentionInterval: TimeInterval = 90 * 24 * 60 * 60

    var id: String
    var teamId: String
    var actorUserId: String
    var actorDisplayName: String
    var kind: TeamActivityLogKind
    var subjectId: String
    var subjectTitle: String
    var targetUserId: String?
    var summary: String
    var createdAt: Date

    static func make(
        id: String = UUID().uuidString,
        teamId: String,
        actorUserId: String,
        actorDisplayName: String,
        kind: TeamActivityLogKind,
        subjectId: String,
        subjectTitle: String,
        targetUserId: String? = nil,
        createdAt: Date = Date()
    ) -> TeamActivityLogEntry {
        TeamActivityLogEntry(
            id: id,
            teamId: teamId,
            actorUserId: actorUserId,
            actorDisplayName: actorDisplayName,
            kind: kind,
            subjectId: subjectId,
            subjectTitle: subjectTitle,
            targetUserId: targetUserId,
            summary: "\(actorDisplayName) \(kind.actionPhrase) \(subjectTitle)",
            createdAt: createdAt
        )
    }
}

enum TeamDuplicateLeadReason: String, Codable, CaseIterable, Sendable {
    case samePhone
    case sameAddress
    case nearbyLocation

    var priority: Int {
        switch self {
        case .samePhone:
            return 3
        case .sameAddress:
            return 2
        case .nearbyLocation:
            return 1
        }
    }
}

struct TeamDuplicateLeadCandidate: Identifiable, Codable, Equatable, Sendable {
    var id: String { "\(existingLead.id)-\(reason.rawValue)" }
    var existingLead: TeamLead
    var reason: TeamDuplicateLeadReason
    var distanceMeters: Double?
}

struct TeamDuplicateLeadWarning: Identifiable, Codable, Equatable, Sendable {
    var id: String { "\(lead.id)-\(candidate.id)" }
    var lead: TeamLead
    var candidate: TeamDuplicateLeadCandidate

    var summary: String {
        "\(lead.name) may duplicate \(candidate.existingLead.name)"
    }
}

enum TeamDuplicateLeadDetector {
    static let nearbyDuplicateDistanceMeters = 25.0

    static func candidates(for newLead: TeamLead, existingLeads: [TeamLead]) -> [TeamDuplicateLeadCandidate] {
        var candidatesByLeadId: [String: TeamDuplicateLeadCandidate] = [:]
        let newPhone = normalizedPhone(newLead.phone)
        let newAddress = normalizedAddress(newLead.address)
        let newCoordinate = TeamCoordinate(latitude: newLead.latitude, longitude: newLead.longitude)

        for existingLead in existingLeads where existingLead.id != newLead.id && existingLead.teamId == newLead.teamId {
            let existingPhone = normalizedPhone(existingLead.phone)
            let existingAddress = normalizedAddress(existingLead.address)
            let distance = distanceMeters(
                from: newCoordinate,
                to: TeamCoordinate(latitude: existingLead.latitude, longitude: existingLead.longitude)
            )

            let match: TeamDuplicateLeadCandidate?
            if let newPhone, let existingPhone, newPhone == existingPhone {
                match = TeamDuplicateLeadCandidate(existingLead: existingLead, reason: .samePhone, distanceMeters: distance)
            } else if !newAddress.isEmpty, newAddress == existingAddress {
                match = TeamDuplicateLeadCandidate(existingLead: existingLead, reason: .sameAddress, distanceMeters: distance)
            } else if distance <= nearbyDuplicateDistanceMeters {
                match = TeamDuplicateLeadCandidate(existingLead: existingLead, reason: .nearbyLocation, distanceMeters: distance)
            } else {
                match = nil
            }

            guard let match else { continue }
            if let existing = candidatesByLeadId[existingLead.id] {
                if match.reason.priority > existing.reason.priority {
                    candidatesByLeadId[existingLead.id] = match
                }
            } else {
                candidatesByLeadId[existingLead.id] = match
            }
        }

        return candidatesByLeadId.values.sorted { lhs, rhs in
            if lhs.reason.priority != rhs.reason.priority {
                return lhs.reason.priority > rhs.reason.priority
            }
            return (lhs.distanceMeters ?? .greatestFiniteMagnitude) < (rhs.distanceMeters ?? .greatestFiniteMagnitude)
        }
    }

    static func warnings(for leads: [TeamLead]) -> [TeamDuplicateLeadWarning] {
        var seenPairKeys = Set<String>()
        var warnings: [TeamDuplicateLeadWarning] = []

        for lead in leads {
            let candidates = candidates(for: lead, existingLeads: leads)
            for candidate in candidates {
                let pairKey = [lead.id, candidate.existingLead.id].sorted().joined(separator: ":")
                guard seenPairKeys.insert(pairKey).inserted else { continue }
                warnings.append(TeamDuplicateLeadWarning(lead: lead, candidate: candidate))
            }
        }

        return warnings.sorted { lhs, rhs in
            if lhs.candidate.reason.priority != rhs.candidate.reason.priority {
                return lhs.candidate.reason.priority > rhs.candidate.reason.priority
            }
            return lhs.summary.localizedCaseInsensitiveCompare(rhs.summary) == .orderedAscending
        }
    }

    private static func normalizedPhone(_ phone: String?) -> String? {
        let digits = phone?.filter(\.isNumber) ?? ""
        guard digits.count >= 7 else { return nil }
        if digits.count == 11, digits.first == "1" {
            return String(digits.dropFirst())
        }
        return digits
    }

    private static func normalizedAddress(_ address: String) -> String {
        let lowered = address.lowercased()
        let scalars = lowered.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? Character($0) : " " }
        let words = String(scalars)
            .split(separator: " ")
            .map(String.init)
            .map(normalizedAddressWord)
        return words.joined(separator: " ")
    }

    private static func normalizedAddressWord(_ word: String) -> String {
        switch word {
        case "street":
            return "st"
        case "road":
            return "rd"
        case "avenue":
            return "ave"
        case "boulevard":
            return "blvd"
        default:
            return word
        }
    }

    private static func distanceMeters(from start: TeamCoordinate, to end: TeamCoordinate) -> Double {
        let earthRadiusMeters = 6_371_000.0
        let startLatitude = start.latitude * .pi / 180
        let endLatitude = end.latitude * .pi / 180
        let latitudeDelta = (end.latitude - start.latitude) * .pi / 180
        let longitudeDelta = (end.longitude - start.longitude) * .pi / 180

        let a = sin(latitudeDelta / 2) * sin(latitudeDelta / 2)
            + cos(startLatitude) * cos(endLatitude)
            * sin(longitudeDelta / 2) * sin(longitudeDelta / 2)
        let c = 2 * atan2(sqrt(a), sqrt(1 - a))
        return earthRadiusMeters * c
    }
}

struct TeamTodayWorkSummary: Equatable, Sendable {
    var memberUserId: String
    var leadCount: Int
    var importantLeadCount: Int
    var bookingCount: Int
    var activeDutyCount: Int

    static func make(
        currentMember: TeamMember,
        leads: [TeamLead],
        bookings: [TeamBooking],
        dutySessions: [TeamDutySession],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> TeamTodayWorkSummary {
        let scopedLeads = scoped(leads, for: currentMember)
        let scopedBookings = scoped(bookings, for: currentMember)
        let scopedDutySessions = scoped(dutySessions, for: currentMember)

        return TeamTodayWorkSummary(
            memberUserId: currentMember.userId,
            leadCount: scopedLeads.count,
            importantLeadCount: scopedLeads.filter(TeamLeadAttentionPolicy.needsOwnerAttention).count,
            bookingCount: scopedBookings.filter { calendar.isDate($0.startDate, inSameDayAs: now) && $0.isFutureEditable }.count,
            activeDutyCount: scopedDutySessions.filter { $0.status == .active }.count
        )
    }

    private static func scoped(_ leads: [TeamLead], for member: TeamMember) -> [TeamLead] {
        member.role == .owner ? leads : leads.filter { $0.assignedToUserId == member.userId }
    }

    private static func scoped(_ bookings: [TeamBooking], for member: TeamMember) -> [TeamBooking] {
        member.role == .owner ? bookings : bookings.filter { $0.assignedToUserId == member.userId }
    }

    private static func scoped(_ dutySessions: [TeamDutySession], for member: TeamMember) -> [TeamDutySession] {
        member.role == .owner ? dutySessions : dutySessions.filter { $0.repUserId == member.userId }
    }
}

enum TeamSyncWriteState: Equatable, Sendable {
    case idle
    case pending(localWriteCount: Int)
    case failed(String)

    var displayText: String {
        switch self {
        case .idle:
            return "Synced"
        case .pending(let localWriteCount):
            return localWriteCount == 1 ? "Saving 1 team edit..." : "Saving \(localWriteCount) team edits..."
        case .failed(let message):
            return message
        }
    }

    var pendingWriteCount: Int {
        if case .pending(let count) = self {
            return count
        }
        return 0
    }
}

enum TeamSyncHealthLevel: String, Equatable, Sendable {
    case ready
    case refreshing
    case saving
    case offline
    case blocked
    case setup
}

struct TeamSyncHealthSnapshot: Equatable, Sendable {
    var level: TeamSyncHealthLevel
    var title: String
    var detail: String
    var actionTitle: String?
}

enum TeamSyncHealthPolicy {
    static func snapshot(
        isAuthenticated: Bool,
        hasActiveTeam: Bool,
        hasCurrentMember: Bool,
        isLoading: Bool,
        isWorking: Bool,
        syncWriteState: TeamSyncWriteState,
        lastErrorMessage: String?,
        lastSuccessfulSyncAt: Date?,
        now: Date = Date()
    ) -> TeamSyncHealthSnapshot? {
        if !isAuthenticated {
            return TeamSyncHealthSnapshot(
                level: .setup,
                title: "Team sign-in needed",
                detail: "Sign in before creating or joining a team workspace.",
                actionTitle: nil
            )
        }

        if isLoading {
            return TeamSyncHealthSnapshot(
                level: .refreshing,
                title: "Refreshing Team",
                detail: "Checking your latest team data.",
                actionTitle: nil
            )
        }

        switch syncWriteState {
        case .pending:
            return TeamSyncHealthSnapshot(
                level: .saving,
                title: syncWriteState.displayText,
                detail: "Keep this screen open until the cloud confirms the change.",
                actionTitle: nil
            )
        case .failed(let message):
            if TeamFirebaseService.isOfflineMessage(message) {
                return TeamSyncHealthSnapshot(
                    level: .offline,
                    title: "Offline",
                    detail: "Saved team data stays visible. Refresh when the connection returns.",
                    actionTitle: "Refresh Team"
                )
            }

            if TeamFirebaseService.isPermissionMessage(message) {
                return TeamSyncHealthSnapshot(
                    level: .blocked,
                    title: "Team access needs refresh",
                    detail: "Refresh Team or sign in again to confirm your current access.",
                    actionTitle: "Refresh Team"
                )
            }

            return TeamSyncHealthSnapshot(
                level: .blocked,
                title: "Team sync needs attention",
                detail: message,
                actionTitle: "Refresh Team"
            )
        case .idle:
            break
        }

        if let lastErrorMessage {
            if TeamFirebaseService.isOfflineMessage(lastErrorMessage) {
                return TeamSyncHealthSnapshot(
                    level: .offline,
                    title: "Offline",
                    detail: hasActiveTeam && hasCurrentMember
                        ? "Showing saved team data until the connection returns."
                        : "Connect to the internet to create or join a team.",
                    actionTitle: "Refresh Team"
                )
            }

            if TeamFirebaseService.isPermissionMessage(lastErrorMessage) {
                return TeamSyncHealthSnapshot(
                    level: .blocked,
                    title: "Team access needs refresh",
                    detail: "Refresh Team or sign in again to confirm your current access.",
                    actionTitle: "Refresh Team"
                )
            }
        }

        if isWorking {
            return TeamSyncHealthSnapshot(
                level: .saving,
                title: "Saving team edit...",
                detail: "Waiting for the cloud to confirm this change.",
                actionTitle: nil
            )
        }

        if hasActiveTeam && hasCurrentMember {
            return TeamSyncHealthSnapshot(
                level: .ready,
                title: "Team online",
                detail: lastSuccessfulSyncAt.map { "Last synced \(relativeSyncText(since: $0, now: now))." }
                    ?? "Team data is ready.",
                actionTitle: nil
            )
        }

        return nil
    }

    private static func relativeSyncText(since date: Date, now: Date) -> String {
        let seconds = max(0, now.timeIntervalSince(date))
        if seconds < 60 { return "just now" }

        let minutes = Int(seconds / 60)
        if minutes < 60 {
            return minutes == 1 ? "1 min ago" : "\(minutes) min ago"
        }

        let hours = Int(seconds / 3600)
        if hours < 24 {
            return hours == 1 ? "1 hr ago" : "\(hours) hrs ago"
        }

        let days = Int(seconds / 86_400)
        return days == 1 ? "1 day ago" : "\(days) days ago"
    }
}

extension TeamOwnerNotification {
    static func markedRead(_ notification: TeamOwnerNotification, at readAt: Date) -> TeamOwnerNotification {
        var updated = notification
        updated.readAt = readAt
        return updated
    }
}

enum TeamOwnerLeadEvent: String, Codable, Equatable, Sendable {
    case interested = "lead_interested"
    case followUp = "lead_follow_up"
    case booked = "lead_booked"
    case converted = "lead_converted"
    case highPriority = "lead_high_priority"

    var ownerTitle: String {
        switch self {
        case .interested:
            return "Rep marked a lead interested"
        case .followUp:
            return "Rep needs follow-up"
        case .booked:
            return "Rep booked a lead"
        case .converted:
            return "Rep converted a lead"
        case .highPriority:
            return "Rep marked a lead high priority"
        }
    }
}

enum TeamNotificationPolicy {
    static func ownerLeadEvents(before: TeamLead?, after: TeamLead) -> [TeamOwnerLeadEvent] {
        var events: [TeamOwnerLeadEvent] = []

        if before?.workflowStatus != after.workflowStatus {
            switch after.workflowStatus {
            case .interested:
                events.append(.interested)
            case .converted:
                events.append(.converted)
            default:
                break
            }
        }

        if before?.followUpDate != after.followUpDate,
           after.followUpDate != nil,
           !events.contains(.interested) {
            events.append(.followUp)
        }

        if before?.isHighPriority != true && after.isHighPriority {
            events.append(.highPriority)
        }

        return events
    }
}
