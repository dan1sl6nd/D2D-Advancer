import Foundation
import SwiftUI
import MapKit

enum DefaultServicePreferencePolicy {
    static func resolvedCategory(
        storedID: String,
        availableCategories: [ServiceCategory]
    ) -> ServiceCategory? {
        let normalizedID = storedID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedID.isEmpty else { return nil }
        return availableCategories.first { $0.id == normalizedID }
    }
}

class AppPreferences: ObservableObject {
    static let shared = AppPreferences()
    
    @AppStorage("leadSortPreference") var leadSortPreference = "date"
    @AppStorage("defaultLeadStatus") var defaultLeadStatus = "not_contacted"
    @AppStorage("defaultServiceCategoryID") var defaultServiceCategoryID = ""
    @AppStorage("defaultFollowUpTime") var defaultFollowUpTime = "1_day"
    @AppStorage("autoBackupFrequency") var autoBackupFrequency = "weekly"
    @AppStorage("mapDefaultView") var mapDefaultView = "standard"
    @AppStorage("defaultCheckInType") var defaultCheckInType = "door_knock"
    
    private init() {}
    
    // MARK: - Helper Methods
    
    var defaultLeadStatusEnum: Lead.Status {
        return Lead.Status(rawValue: defaultLeadStatus) ?? .notContacted
    }

    var effectiveDefaultServiceCategoryID: String {
        #if DEBUG
        let launchArguments = ProcessInfo.processInfo.arguments
        if let flagIndex = launchArguments.firstIndex(of: "-defaultServiceForUITests"),
           launchArguments.indices.contains(flagIndex + 1) {
            return launchArguments[flagIndex + 1]
        }
        #endif
        return defaultServiceCategoryID
    }

    var defaultServiceCategory: ServiceCategory? {
        DefaultServicePreferencePolicy.resolvedCategory(
            storedID: effectiveDefaultServiceCategoryID,
            availableCategories: ServiceCategoryManager.shared.allCategories
        )
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
        let legacyDefaultAscending = leadSortPreference == "name" || leadSortPreference == "status"
        let ascending = UserDefaults.standard.object(forKey: "leadSortAscending") as? Bool
            ?? legacyDefaultAscending

        switch leadSortPreference {
        case "name":
            return [NSSortDescriptor(keyPath: \Lead.name, ascending: ascending)]
        case "created":
            return [NSSortDescriptor(keyPath: \Lead.createdDate, ascending: ascending)]
        case "status":
            return [
                NSSortDescriptor(keyPath: \Lead.status, ascending: ascending),
                NSSortDescriptor(keyPath: \Lead.updatedDate, ascending: false)
            ]
        default: // "date"
            return [NSSortDescriptor(keyPath: \Lead.updatedDate, ascending: ascending)]
        }
    }
    
    // MARK: - Default Follow-up Date
    
    func defaultFollowUpDate() -> Date {
        return Date().addingTimeInterval(defaultFollowUpTimeInterval)
    }
}
