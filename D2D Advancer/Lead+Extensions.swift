import Foundation
import CoreData
import CoreLocation
import SwiftUI
import FirebaseFirestore

extension Lead {
    enum Status: String, CaseIterable, Sendable, Codable, Hashable {
        case notContacted = "not_contacted"
        case notHome = "not_home"
        case interested = "interested"
        case converted = "converted"
        case notInterested = "not_interested"
        
        var displayName: String {
            switch self {
            case .notContacted:
                return "Not Contacted"
            case .notHome:
                return "Not Home"
            case .interested:
                return "Interested"
            case .converted:
                return "Sold"
            case .notInterested:
                return "No Interest"
            }
        }
        
        var color: String {
            switch self {
            case .notContacted:
                return "gray"
            case .notHome:
                return "brown"
            case .interested:
                return "orange"
            case .converted:
                return "green"
            case .notInterested:
                return "red"
            }
        }

        var icon: String {
            switch self {
            case .notContacted: return "plus.circle"
            case .notHome: return "house"
            case .interested: return "heart"
            case .converted: return "checkmark.seal"
            case .notInterested: return "xmark.circle"
            }
        }

        var swiftUIColor: Color {
            switch self {
            case .notContacted: return .statusNotContacted
            case .notHome: return .statusNotHome
            case .interested: return .statusInterested
            case .converted: return .statusConverted
            case .notInterested: return .statusNotInterested
            }
        }
    }
    
    
    var leadStatus: Status {
        get {
            return Status(rawValue: status ?? "not_contacted") ?? .notContacted
        }
        set {
            willChangeValue(forKey: "status")
            status = newValue.rawValue
            updatedDate = Date()
            didChangeValue(forKey: "status")
        }
    }
    
    // Add helper method to set follow-up date with automatic sync
    func setFollowUpDate(_ date: Date?, autoSave: Bool = true) {
        // Cancel existing follow-up notification if we have an ID
        if let leadId = id {
            Task { @MainActor in
                NotificationService.shared.cancelFollowUpNotification(for: leadId)
            }
        }

        // Set the values directly
        followUpDate = date
        updatedDate = Date()

        print("📅 Follow-up date updated for \(self.displayName): \(date?.description ?? "nil")")

        // Schedule new notification if date is set
        if date != nil {
            let lead = self
            Task { @MainActor in
                NotificationService.shared.scheduleFollowUpNotification(for: lead)
            }
        }

        // Only auto-save if requested (for views that don't manage their own saving)
        if autoSave, let context = managedObjectContext {
            do {
                try context.save()
                print("✅ Context auto-saved after follow-up date change")
            } catch {
                print("❌ Failed to auto-save context: \(error)")
            }
        }

        // Individual sync removed - follow-up dates will sync manually, hourly, or before sign-out
        print("📅 Follow-up date modified - will sync on next manual/hourly/sign-out sync")
    }
    
    
    // MARK: - Follow-up Cadence

    enum FollowUpCadence: String, CaseIterable {
        case none = "none"
        case everyThreeDays = "3days"
        case weekly = "weekly"
        case biweekly = "biweekly"
        case monthly = "monthly"

        var displayName: String {
            switch self {
            case .none: return "One-time"
            case .everyThreeDays: return "Every 3 days"
            case .weekly: return "Weekly"
            case .biweekly: return "Every 2 weeks"
            case .monthly: return "Monthly"
            }
        }

        var days: Int {
            switch self {
            case .none: return 0
            case .everyThreeDays: return 3
            case .weekly: return 7
            case .biweekly: return 14
            case .monthly: return 30
            }
        }
    }

    var followUpCadence: FollowUpCadence {
        get {
            guard let raw = tags, raw.hasPrefix("cadence:") else { return .none }
            let value = String(raw.dropFirst("cadence:".count))
            return FollowUpCadence(rawValue: value) ?? .none
        }
        set {
            tags = newValue == .none ? nil : "cadence:\(newValue.rawValue)"
        }
    }

    /// Advance the follow-up date by the cadence interval. Returns the new date or nil if no cadence.
    func advanceFollowUpByCadence() -> Date? {
        let cadence = followUpCadence
        guard cadence != .none else { return nil }
        let base = followUpDate ?? Date()
        let calendar = Calendar.current
        guard let next = calendar.date(byAdding: .day, value: cadence.days, to: base),
              let morning = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: next) else { return nil }
        return morning
    }

    var coordinate: CLLocationCoordinate2D {
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
    
    var location: CLLocation {
        return CLLocation(latitude: latitude, longitude: longitude)
    }
    
    static func create(in context: NSManagedObjectContext) -> Lead {
        let lead = Lead(context: context)
        lead.id = UUID()
        lead.createdDate = Date()
        lead.updatedDate = Date()
        lead.status = Status.notContacted.rawValue
        lead.latitude = 0.0
        lead.longitude = 0.0
        lead.price = 0.0
        return lead
    }
    
    // Validate that a lead has either a name or an address before saving
    func validate() -> Bool {
        let hasName = name?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        let hasAddress = address?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        return hasName || hasAddress
    }
    
    func updateLocation(coordinate: CLLocationCoordinate2D) {
        self.latitude = coordinate.latitude
        self.longitude = coordinate.longitude
        self.updatedDate = Date()
    }
    
    var displayName: String {
        if let name = name, !name.isEmpty {
            return name
        } else if let address = address, !address.isEmpty {
            return address
        } else {
            return "Lead \(id?.uuidString.prefix(8) ?? "Unknown")"
        }
    }
    
    // MARK: - Service Category
    var serviceCategoryObject: ServiceCategory? {
        guard let categoryId = serviceCategory else { return nil }
        return ServiceCategoryManager.shared.getCategory(byId: categoryId)
    }
    
    func setServiceCategory(_ category: ServiceCategory?) {
        willChangeValue(forKey: "serviceCategory")
        serviceCategory = category?.id
        updatedDate = Date()
        didChangeValue(forKey: "serviceCategory")
    }
    
    // MARK: - Firebase Sync
    // Individual lead sync removed - all leads sync together via UserDataSyncManager
    // This ensures better performance and consistency
    
}