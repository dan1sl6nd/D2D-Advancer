import Foundation
import SwiftUI

// MARK: - Custom Appointment Type Model

struct CustomAppointmentType: Identifiable, Codable, Equatable {
    let id: String
    let name: String
    let icon: String
    let color: String
    let isDefault: Bool
    let dateCreated: Date
    
    init(id: String = UUID().uuidString, name: String, icon: String, color: String, isDefault: Bool = false, dateCreated: Date = Date()) {
        self.id = id
        self.name = name
        self.icon = icon
        self.color = color
        self.isDefault = isDefault
        self.dateCreated = dateCreated
    }
    
    var swiftUIColor: Color {
        switch color.lowercased() {
        case "red": return .red
        case "blue": return .blue
        case "green": return .green
        case "orange": return .orange
        case "purple": return .purple
        case "pink": return .pink
        case "yellow": return .yellow
        case "gray": return .gray
        case "brown": return .brown
        case "cyan": return .cyan
        case "mint": return .mint
        case "indigo": return .indigo
        case "teal": return .teal
        default: return .blue
        }
    }
}

// MARK: - Appointment Type Wrapper

enum AppointmentTypeWrapper: Identifiable, Equatable {
    case defaultType(Appointment.AppointmentType)
    case customType(CustomAppointmentType)
    
    var id: String {
        switch self {
        case .defaultType(let type):
            return "default_\(type.rawValue)"
        case .customType(let custom):
            return "custom_\(custom.id)"
        }
    }
    
    var name: String {
        switch self {
        case .defaultType(let type):
            return type.rawValue
        case .customType(let custom):
            return custom.name
        }
    }
    
    var icon: String {
        switch self {
        case .defaultType(let type):
            return type.icon
        case .customType(let custom):
            return custom.icon
        }
    }
    
    var color: Color {
        switch self {
        case .defaultType(let type):
            return type.color
        case .customType(let custom):
            return custom.swiftUIColor
        }
    }
    
    var isCustom: Bool {
        switch self {
        case .defaultType:
            return false
        case .customType:
            return true
        }
    }
}

// MARK: - Custom Appointment Type Manager

class CustomAppointmentTypeManager: ObservableObject {
    static let shared = CustomAppointmentTypeManager()
    
    @Published var customTypes: [CustomAppointmentType] = []
    private let userDefaults = UserDefaults.standard
    private let customTypesKey = "custom_appointment_types"
    
    private init() {
        loadCustomTypes()
    }
    
    var allAppointmentTypes: [AppointmentTypeWrapper] {
        var types: [AppointmentTypeWrapper] = []
        
        // Add default types
        for defaultType in Appointment.AppointmentType.allCases {
            types.append(.defaultType(defaultType))
        }
        
        // Add custom types
        for customType in customTypes {
            types.append(.customType(customType))
        }
        
        return types
    }
    
    func addCustomType(_ customType: CustomAppointmentType) {
        var newType = customType
        newType = CustomAppointmentType(
            id: customType.id,
            name: customType.name,
            icon: customType.icon,
            color: customType.color,
            isDefault: false,
            dateCreated: Date()
        )
        customTypes.append(newType)
        saveCustomTypes()
        
        // Force UI update
        DispatchQueue.main.async {
            self.objectWillChange.send()
        }
    }
    
    func updateCustomType(_ customType: CustomAppointmentType) {
        if let index = customTypes.firstIndex(where: { $0.id == customType.id }) {
            customTypes[index] = customType
            saveCustomTypes()
            
            // Force UI update
            DispatchQueue.main.async {
                self.objectWillChange.send()
            }
        }
    }
    
    func deleteCustomType(_ customType: CustomAppointmentType) {
        customTypes.removeAll { $0.id == customType.id }
        saveCustomTypes()
        
        // Force UI update
        DispatchQueue.main.async {
            self.objectWillChange.send()
        }
    }
    
    private func saveCustomTypes() {
        if let encoded = try? JSONEncoder().encode(customTypes) {
            userDefaults.set(encoded, forKey: customTypesKey)
        }
    }
    
    private func loadCustomTypes() {
        if let data = userDefaults.data(forKey: customTypesKey),
           let types = try? JSONDecoder().decode([CustomAppointmentType].self, from: data) {
            customTypes = types
        }
    }
}

// MARK: - Available Icons and Colors

extension CustomAppointmentTypeManager {
    // Icon with user-friendly names and categories
    static let availableIcons: [(symbol: String, name: String, category: String)] = [
        // Business & Professional
        ("person.2.fill", "Team Meeting", "Business"),
        ("briefcase.fill", "Business Meeting", "Business"),
        ("person.crop.circle", "Client Meeting", "Business"),
        ("bubble.left.and.bubble.right.fill", "Discussion", "Business"),
        ("chart.line.uptrend.xyaxis", "Planning Session", "Business"),
        ("doc.text.fill", "Document Review", "Business"),
        ("building.2.fill", "Site Visit", "Business"),
        
        // Technical & Services
        ("wrench.and.screwdriver.fill", "Repair", "Technical"),
        ("hammer.fill", "Installation", "Technical"),
        ("gear", "Maintenance", "Technical"),
        ("checkmark.circle.fill", "Inspection", "Technical"),
        ("magnifyingglass.circle.fill", "Assessment", "Technical"),
        ("screwdriver.fill", "Setup", "Technical"),
        ("wrench.fill", "Service Call", "Technical"),
        
        // Communication
        ("phone.fill", "Phone Call", "Communication"),
        ("video.fill", "Video Call", "Communication"),
        ("message.fill", "Follow-up", "Communication"),
        ("envelope.fill", "Email Meeting", "Communication"),
        ("speaker.wave.3.fill", "Conference Call", "Communication"),
        
        // Calendar & Time
        ("calendar", "Appointment", "Calendar"),
        ("clock.fill", "Scheduled Visit", "Calendar"),
        ("timer", "Quick Meeting", "Calendar"),
        ("alarm.fill", "Reminder", "Calendar"),
        ("calendar.badge.plus", "Planning", "Calendar"),
        
        // Home & Property
        ("house.fill", "Home Visit", "Property"),
        ("building.fill", "Property Visit", "Property"),
        ("location.fill", "On-Site", "Property"),
        ("map.fill", "Survey", "Property"),
        ("ruler.fill", "Measurement", "Property"),
        
        // Medical & Health
        ("heart.text.square.fill", "Health Check", "Medical"),
        ("cross.fill", "Medical", "Medical"),
        ("heart.fill", "Wellness", "Medical"),
        ("pill.fill", "Treatment", "Medical"),
        
        // Education & Training
        ("graduationcap.fill", "Training", "Education"),
        ("book.fill", "Workshop", "Education"),
        ("display", "Presentation", "Education"),
        ("lightbulb.fill", "Ideas Session", "Education"),
        
        // General
        ("star.fill", "Priority", "General"),
        ("flag.fill", "Important", "General"),
        ("exclamationmark.triangle.fill", "Urgent", "General"),
        ("questionmark.circle.fill", "Q&A Session", "General"),
        ("info.circle.fill", "Information", "General"),
        ("gift.fill", "Special Event", "General")
    ]
    
    // For backward compatibility, provide just the symbol names
    static var availableIconSymbols: [String] {
        return availableIcons.map { $0.symbol }
    }
    
    static let availableColors = [
        ("Red", "red"),
        ("Blue", "blue"),
        ("Green", "green"),
        ("Orange", "orange"),
        ("Purple", "purple"),
        ("Pink", "pink"),
        ("Yellow", "yellow"),
        ("Gray", "gray"),
        ("Brown", "brown"),
        ("Cyan", "cyan"),
        ("Mint", "mint"),
        ("Indigo", "indigo"),
        ("Teal", "teal")
    ]
}