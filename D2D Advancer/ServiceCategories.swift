import Foundation
import SwiftUI

struct ServiceCategory: Codable, Identifiable, Equatable {
    let id: String
    let name: String
    let icon: String
    let color: String
    let isCustom: Bool
    let dateCreated: Date
    
    init(id: String = UUID().uuidString, name: String, icon: String, color: String, isCustom: Bool = false, dateCreated: Date = Date()) {
        self.id = id
        self.name = name
        self.icon = icon
        self.color = color
        self.isCustom = isCustom
        self.dateCreated = dateCreated
    }
    
    var displayColor: Color {
        switch color {
        case "blue": return .blue
        case "green": return .green
        case "orange": return .orange
        case "red": return .red
        case "purple": return .purple
        case "pink": return .pink
        case "yellow": return .yellow
        case "indigo": return .indigo
        case "teal": return .teal
        case "mint": return .mint
        case "cyan": return .cyan
        case "brown": return .brown
        default: return .blue
        }
    }
    
    static let availableColors = ["blue", "green", "orange", "red", "purple", "pink", "yellow", "indigo", "teal", "mint", "cyan", "brown"]
    static let availableIcons = [
        "drop.fill", "wind", "sparkles", "leaf.fill", "paintbrush.fill", 
        "hammer.fill", "wrench.fill", "screwdriver.fill", "gear", "house.fill",
        "building.fill", "car.fill", "tree.fill", "trash.fill", "snowflake",
        "sun.max.fill", "bolt.fill", "flame.fill", "water.waves", "bubbles.and.sparkles.fill"
    ]
}

class ServiceCategoryManager: ObservableObject {
    static let shared = ServiceCategoryManager()
    
    @Published var customCategories: [ServiceCategory] = []
    private let userDefaults = UserDefaults.standard
    private let customCategoriesKey = "custom_service_categories"
    
    let defaultCategories: [ServiceCategory] = [
        ServiceCategory(
            id: "window_cleaning",
            name: "Window Cleaning",
            icon: "drop.fill",
            color: "blue"
        ),
        ServiceCategory(
            id: "gutter_cleaning",
            name: "Gutter Cleaning", 
            icon: "water.waves",
            color: "teal"
        ),
        ServiceCategory(
            id: "pressure_washing",
            name: "Pressure Washing",
            icon: "wind",
            color: "cyan"
        ),
        ServiceCategory(
            id: "roof_cleaning",
            name: "Roof Cleaning",
            icon: "house.fill",
            color: "brown"
        ),
        ServiceCategory(
            id: "solar_cleaning",
            name: "Solar Panel Cleaning",
            icon: "sun.max.fill",
            color: "orange"
        ),
        ServiceCategory(
            id: "deck_cleaning",
            name: "Deck/Patio Cleaning",
            icon: "sparkles",
            color: "green"
        ),
        ServiceCategory(
            id: "driveway_cleaning",
            name: "Driveway Cleaning",
            icon: "car.fill",
            color: "indigo"
        ),
        ServiceCategory(
            id: "fence_cleaning",
            name: "Fence Cleaning",
            icon: "leaf.fill",
            color: "mint"
        ),
        ServiceCategory(
            id: "exterior_washing",
            name: "Exterior House Washing",
            icon: "building.fill",
            color: "purple"
        ),
        ServiceCategory(
            id: "concrete_cleaning",
            name: "Concrete Cleaning",
            icon: "hammer.fill",
            color: "red"
        )
    ]
    
    init() {
        loadCustomCategories()
    }
    
    var allCategories: [ServiceCategory] {
        return defaultCategories + customCategories
    }
    
    func addCustomCategory(_ category: ServiceCategory) {
        var customCategory = category
        customCategory = ServiceCategory(
            id: category.id,
            name: category.name,
            icon: category.icon,
            color: category.color,
            isCustom: true,
            dateCreated: Date()
        )
        customCategories.append(customCategory)
        saveCustomCategories()
    }
    
    func updateCustomCategory(_ category: ServiceCategory) {
        if let index = customCategories.firstIndex(where: { $0.id == category.id }) {
            customCategories[index] = category
            saveCustomCategories()
        }
    }
    
    func deleteCustomCategory(_ category: ServiceCategory) {
        customCategories.removeAll { $0.id == category.id }
        saveCustomCategories()
    }
    
    func getCategory(byId id: String) -> ServiceCategory? {
        return allCategories.first { $0.id == id }
    }
    
    func getCategory(byName name: String) -> ServiceCategory? {
        return allCategories.first { $0.name.lowercased() == name.lowercased() }
    }
    
    private func saveCustomCategories() {
        if let encoded = try? JSONEncoder().encode(customCategories) {
            userDefaults.set(encoded, forKey: customCategoriesKey)
        }
    }
    
    private func loadCustomCategories() {
        if let data = userDefaults.data(forKey: customCategoriesKey),
           let categories = try? JSONDecoder().decode([ServiceCategory].self, from: data) {
            customCategories = categories
        }
    }
}