import CoreData
import Foundation

enum FollowUpQueueSegment: String, CaseIterable, Identifiable {
    case due
    case upcoming
    case completed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .due: return "Due"
        case .upcoming: return "Upcoming"
        case .completed: return "Completed"
        }
    }

    var icon: String {
        switch self {
        case .due: return "clock.badge.exclamationmark"
        case .upcoming: return "calendar"
        case .completed: return "checkmark.circle"
        }
    }
}

enum FollowUpContactMethod: String, CaseIterable, Sendable {
    case phoneCall
    case sms
    case email
    case visit
    case manual

    var checkInType: FollowUpCheckIn.CheckInType {
        switch self {
        case .phoneCall: return .phoneCall
        case .sms: return .smsMessage
        case .email: return .email
        case .visit: return .doorKnock
        case .manual: return .inPersonMeeting
        }
    }

    var displayName: String {
        switch self {
        case .phoneCall: return "Phone call"
        case .sms: return "Text message"
        case .email: return "Email"
        case .visit: return "Visit"
        case .manual: return "Manual update"
        }
    }
}

enum FollowUpOutcomeChoice: String, CaseIterable, Identifiable, Sendable {
    case done
    case noAnswer
    case interested
    case later
    case sold
    case pass

    var id: String { rawValue }

    var title: String {
        switch self {
        case .done: return "Done"
        case .noAnswer: return "No answer"
        case .interested: return "Interested"
        case .later: return "Follow up later"
        case .sold: return "Sold"
        case .pass: return "Pass"
        }
    }

    var icon: String {
        switch self {
        case .done: return "checkmark.circle.fill"
        case .noAnswer: return "phone.down.fill"
        case .interested: return "heart.fill"
        case .later: return "clock.arrow.circlepath"
        case .sold: return "checkmark.seal.fill"
        case .pass: return "xmark.circle.fill"
        }
    }

    var checkInOutcome: FollowUpCheckIn.Outcome {
        switch self {
        case .done: return .successful
        case .noAnswer: return .noAnswer
        case .interested: return .interested
        case .later: return .reschedule
        case .sold: return .converted
        case .pass: return .notInterested
        }
    }

    var requiresNextDate: Bool {
        switch self {
        case .noAnswer, .interested, .later:
            return true
        case .done, .sold, .pass:
            return false
        }
    }

    func personalStatus(from currentStatus: Lead.Status) -> Lead.Status {
        FollowUpCheckIn.resolvedLeadStatus(after: checkInOutcome, currentStatus: currentStatus)
    }

    func teamStatus(from currentStatus: TeamLeadStatus) -> TeamLeadStatus {
        switch self {
        case .done:
            return currentStatus.workflowStatus
        case .noAnswer:
            return .notHome
        case .interested:
            return .interested
        case .later:
            return .interested
        case .sold:
            return .converted
        case .pass:
            return .notInterested
        }
    }
}

enum FollowUpWorkflowPolicy {
    static func defaultNextDate(
        for outcome: FollowUpOutcomeChoice,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Date? {
        let dayOffset: Int
        switch outcome {
        case .noAnswer, .later:
            dayOffset = 1
        case .interested:
            dayOffset = 3
        case .done, .sold, .pass:
            return nil
        }

        guard let targetDay = calendar.date(byAdding: .day, value: dayOffset, to: now) else {
            return now.addingTimeInterval(TimeInterval(dayOffset) * 86_400)
        }
        return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: targetDay) ?? targetDay
    }

    static func resolvedNextDate(
        for outcome: FollowUpOutcomeChoice,
        selectedDate: Date?,
        cadenceDate: Date?,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Date? {
        switch outcome {
        case .sold, .pass:
            return nil
        case .done:
            return cadenceDate
        case .noAnswer, .interested, .later:
            return selectedDate ?? defaultNextDate(for: outcome, now: now, calendar: calendar)
        }
    }

    static func isDue(_ date: Date, now: Date = Date(), calendar: Calendar = .current) -> Bool {
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) else {
            return date <= now
        }
        return date < tomorrow
    }

    static func priorityComesFirst(
        lhs: FollowUpPriorityAttributes,
        rhs: FollowUpPriorityAttributes
    ) -> Bool {
        if lhs.isHighPriority != rhs.isHighPriority {
            return lhs.isHighPriority
        }
        if lhs.isInterested != rhs.isInterested {
            return lhs.isInterested
        }
        if lhs.dueDate != rhs.dueDate {
            return lhs.dueDate < rhs.dueDate
        }
        if lhs.value != rhs.value {
            return lhs.value > rhs.value
        }
        return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
    }
}

struct FollowUpPriorityAttributes: Equatable, Sendable {
    var isHighPriority: Bool
    var isInterested: Bool
    var dueDate: Date
    var value: Double
    var name: String
}

@MainActor
enum FollowUpOutcomeRecorder {
    static func recordPersonal(
        lead: Lead,
        outcome: FollowUpOutcomeChoice,
        method: FollowUpContactMethod,
        note: String?,
        selectedNextDate: Date?,
        in context: NSManagedObjectContext,
        now: Date = Date()
    ) throws {
        let resultingStatus = outcome.personalStatus(from: lead.leadStatus)
        let cadenceDate = lead.advanceFollowUpByCadence(after: now)
        let nextDate = FollowUpWorkflowPolicy.resolvedNextDate(
            for: outcome,
            selectedDate: selectedNextDate,
            cadenceDate: cadenceDate,
            now: now
        )

        let checkIn = FollowUpCheckIn.create(in: context, for: lead)
        checkIn.checkInDate = now
        checkIn.checkInTypeEnum = method.checkInType
        checkIn.outcomeEnum = outcome.checkInOutcome
        checkIn.notes = normalizedNote(note)
        checkIn.scheduledNextFollowUp = resultingStatus.resolvedFollowUpDate(nextDate)

        lead.lastContactDate = now
        lead.applyLeadStatus(
            resultingStatus,
            followUpDate: nextDate,
            shouldReplaceFollowUpDate: true,
            autoSave: false
        )
        try context.save()
    }

    private static func normalizedNote(_ note: String?) -> String? {
        guard let note else { return nil }
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
