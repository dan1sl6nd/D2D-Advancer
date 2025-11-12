import Foundation
import SwiftUI
import MapKit

class AppPreferences: ObservableObject {
    static let shared = AppPreferences()
    
    @AppStorage("leadSortPreference") var leadSortPreference = "date"
    @AppStorage("defaultLeadStatus") var defaultLeadStatus = "not_contacted"
    @AppStorage("defaultFollowUpTime") var defaultFollowUpTime = "1_day"
    @AppStorage("autoBackupFrequency") var autoBackupFrequency = "weekly"
    @AppStorage("mapDefaultView") var mapDefaultView = "standard"
    @AppStorage("defaultCheckInType") var defaultCheckInType = "door_knock"
    
    private init() {}
    
    // MARK: - Helper Methods
    
    var defaultLeadStatusEnum: Lead.Status {
        return Lead.Status(rawValue: defaultLeadStatus) ?? .notContacted
    }
    
    var defaultFollowUpTimeInterval: TimeInterval {
        switch defaultFollowUpTime {
        case "1_hour": return 3600
        case "4_hours": return 14400
        case "1_day": return 86400
        case "3_days": return 259200
        case "1_week": return 604800
        default: return 86400 // Default to 1 day
        }
    }
    
    var mapDefaultViewType: MKMapType {
        switch mapDefaultView {
        case "satellite": return .satellite
        case "hybrid": return .hybrid
        default: return .standard
        }
    }
    
    var defaultCheckInTypeEnum: FollowUpCheckIn.CheckInType {
        return FollowUpCheckIn.CheckInType(rawValue: defaultCheckInType) ?? .doorKnock
    }
    
    // MARK: - Lead Sorting
    
    func sortDescriptors() -> [NSSortDescriptor] {
        switch leadSortPreference {
        case "name":
            return [NSSortDescriptor(keyPath: \Lead.name, ascending: true)]
        case "status":
            return [
                NSSortDescriptor(keyPath: \Lead.status, ascending: true),
                NSSortDescriptor(keyPath: \Lead.updatedDate, ascending: false)
            ]
        default: // "date"
            return [NSSortDescriptor(keyPath: \Lead.updatedDate, ascending: false)]
        }
    }
    
    // MARK: - Default Follow-up Date
    
    func defaultFollowUpDate() -> Date {
        return Date().addingTimeInterval(defaultFollowUpTimeInterval)
    }
}
