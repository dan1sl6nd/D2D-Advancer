import Foundation
import CoreData

extension FollowUpCheckIn {
    enum CheckInType: String, CaseIterable {
        case doorKnock = "door_knock"
        case phoneCall = "phone_call"
        case smsMessage = "sms_message"
        case email = "email"
        case virtualMeeting = "virtual_meeting"
        case inPersonMeeting = "in_person_meeting"
        
        var displayName: String {
            switch self {
            case .doorKnock:
                return "Door Knock"
            case .phoneCall:
                return "Phone Call"
            case .smsMessage:
                return "SMS Message"
            case .email:
                return "Email"
            case .virtualMeeting:
                return "Virtual Meeting"
            case .inPersonMeeting:
                return "In-Person Meeting"
            }
        }
        
        var icon: String {
            switch self {
            case .doorKnock:
                return "door.left.hand.open"
            case .phoneCall:
                return "phone.fill"
            case .smsMessage:
                return "message.fill"
            case .email:
                return "envelope.fill"
            case .virtualMeeting:
                return "video.fill"
            case .inPersonMeeting:
                return "person.2.fill"
            }
        }
        
        var color: String {
            switch self {
            case .doorKnock:
                return "brown"
            case .phoneCall:
                return "blue"
            case .smsMessage:
                return "green"
            case .email:
                return "purple"
            case .virtualMeeting:
                return "orange"
            case .inPersonMeeting:
                return "red"
            }
        }
    }
    
    enum Outcome: String, CaseIterable {
        case successful = "successful"
        case noAnswer = "no_answer"
        case notInterested = "not_interested"
        case interested = "interested"
        case converted = "converted"
        case reschedule = "reschedule"
        case callback = "callback"
        
        var displayName: String {
            switch self {
            case .successful:
                return "Successful Contact"
            case .noAnswer:
                return "No Answer"
            case .notInterested:
                return "Not Interested"
            case .interested:
                return "Showed Interest"
            case .converted:
                return "Converted"
            case .reschedule:
                return "Reschedule Needed"
            case .callback:
                return "Callback Requested"
            }
        }
        
        var color: String {
            switch self {
            case .successful, .interested:
                return "green"
            case .converted:
                return "blue"
            case .noAnswer, .reschedule, .callback:
                return "orange"
            case .notInterested:
                return "red"
            }
        }
    }
    
    var checkInTypeEnum: CheckInType {
        get {
            return CheckInType(rawValue: checkInType ?? "door_knock") ?? .doorKnock
        }
        set {
            checkInType = newValue.rawValue
        }
    }
    
    var outcomeEnum: Outcome? {
        get {
            guard let outcome = outcome else { return nil }
            return Outcome(rawValue: outcome)
        }
        set {
            outcome = newValue?.rawValue
        }
    }
    
    var formattedCheckInDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: checkInDate ?? Date())
    }
    
    static func create(in context: NSManagedObjectContext, for lead: Lead) -> FollowUpCheckIn {
        let checkIn = FollowUpCheckIn(context: context)
        checkIn.id = UUID()
        checkIn.checkInDate = Date()
        checkIn.checkInType = CheckInType.doorKnock.rawValue
        checkIn.lead = lead
        return checkIn
    }
}

extension Lead {
    var sortedCheckIns: [FollowUpCheckIn] {
        let checkInsArray = checkIns?.allObjects as? [FollowUpCheckIn] ?? []
        return checkInsArray.sorted { ($0.checkInDate ?? Date.distantPast) > ($1.checkInDate ?? Date.distantPast) }
    }
    
    var lastCheckIn: FollowUpCheckIn? {
        return sortedCheckIns.first
    }
    
    var checkInCount: Int {
        return checkIns?.count ?? 0
    }
}