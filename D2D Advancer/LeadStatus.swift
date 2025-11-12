import SwiftUI

enum LeadStatus: String, CaseIterable, Codable {
    case new = "new"
    case contacted = "contacted"
    case interested = "interested"
    case scheduled = "scheduled"
    case visited = "visited"
    case followUp = "follow_up"
    case closed = "closed"
    case notInterested = "not_interested"
    
    var displayName: String {
        switch self {
        case .new: return "New"
        case .contacted: return "Contacted"
        case .interested: return "Interested"
        case .scheduled: return "Scheduled"
        case .visited: return "Visited"
        case .followUp: return "Follow-up"
        case .closed: return "Closed"
        case .notInterested: return "Not Interested"
        }
    }
    
    var color: Color {
        switch self {
        case .new: return .blue
        case .contacted: return .orange
        case .interested: return .green
        case .scheduled: return .purple
        case .visited: return .teal
        case .followUp: return .yellow
        case .closed: return .gray
        case .notInterested: return .red
        }
    }
    
    var icon: String {
        switch self {
        case .new: return "plus.circle"
        case .contacted: return "phone"
        case .interested: return "heart"
        case .scheduled: return "calendar"
        case .visited: return "checkmark.circle"
        case .followUp: return "clock"
        case .closed: return "checkmark.seal"
        case .notInterested: return "xmark.circle"
        }
    }
    
    // Map to existing Lead.Status for backward compatibility
    var leadStatus: Lead.Status {
        switch self {
        case .new, .contacted, .visited, .followUp, .scheduled:
            return .notContacted
        case .interested:
            return .interested
        case .closed:
            return .converted
        case .notInterested:
            return .notInterested
        }
    }
    
    // Create from existing Lead.Status
    static func from(leadStatus: Lead.Status) -> LeadStatus {
        switch leadStatus {
        case .notContacted:
            return .new
        case .interested:
            return .interested
        case .converted:
            return .closed
        case .notInterested:
            return .notInterested
        case .notHome:
            return .contacted
        }
    }
    
    // Create from string status
    init?(rawValue: String) {
        switch rawValue {
        case "new": self = .new
        case "contacted": self = .contacted
        case "interested": self = .interested
        case "scheduled": self = .scheduled
        case "visited": self = .visited
        case "follow_up": self = .followUp
        case "closed": self = .closed
        case "not_interested": self = .notInterested
        // Handle legacy statuses
        case "not_contacted": self = .new
        case "not_home": self = .contacted
        case "converted": self = .closed
        default: return nil
        }
    }
}