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
    @Published var lastErrorMessage: String?
    private let userDefaults: UserDefaults
    private let customCategoriesKey: String
    private var hasCorruptStoredCategories = false
    
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
    
    init(userDefaults: UserDefaults = .standard, customCategoriesKey: String = "custom_service_categories") {
        self.userDefaults = userDefaults
        self.customCategoriesKey = customCategoriesKey
        loadCustomCategories()
    }
    
    var allCategories: [ServiceCategory] {
        return defaultCategories + customCategories
    }
    
    @discardableResult
    func addCustomCategory(_ category: ServiceCategory) -> Bool {
        let previousCategories = customCategories
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
        guard saveCustomCategories() else {
            customCategories = previousCategories
            return false
        }
        return true
    }
    
    @discardableResult
    func updateCustomCategory(_ category: ServiceCategory) -> Bool {
        guard let index = customCategories.firstIndex(where: { $0.id == category.id }) else {
            lastErrorMessage = "Could not update service because it no longer exists."
            return false
        }

        let previousCategory = customCategories[index]
        customCategories[index] = category
        guard saveCustomCategories() else {
            customCategories[index] = previousCategory
            return false
        }
        return true
    }
    
    @discardableResult
    func deleteCustomCategory(_ category: ServiceCategory) -> Bool {
        guard customCategories.contains(where: { $0.id == category.id }) else {
            lastErrorMessage = "Could not delete service because it no longer exists."
            return false
        }

        let previousCategories = customCategories
        customCategories.removeAll { $0.id == category.id }
        guard saveCustomCategories() else {
            customCategories = previousCategories
            return false
        }
        return true
    }
    
    func getCategory(byId id: String) -> ServiceCategory? {
        return allCategories.first { $0.id == id }
    }
    
    func getCategory(byName name: String) -> ServiceCategory? {
        return allCategories.first { $0.name.lowercased() == name.lowercased() }
    }
    
    @discardableResult
    private func saveCustomCategories() -> Bool {
        guard !hasCorruptStoredCategories else {
            let message = "Could not save service categories because the saved services could not be loaded. Your existing saved data was left untouched."
            lastErrorMessage = message
            print("❌ \(message)")
            return false
        }

        do {
            let encoded = try JSONEncoder().encode(customCategories)
            userDefaults.set(encoded, forKey: customCategoriesKey)
            lastErrorMessage = nil
            hasCorruptStoredCategories = false
            return true
        } catch {
            let message = "Could not save service categories: \(error.localizedDescription)"
            lastErrorMessage = message
            print("❌ \(message)")
            return false
        }
    }
    
    private func loadCustomCategories() {
        guard let data = userDefaults.data(forKey: customCategoriesKey) else {
            hasCorruptStoredCategories = false
            return
        }

        do {
            let categories = try JSONDecoder().decode([ServiceCategory].self, from: data)
            customCategories = categories
            lastErrorMessage = nil
            hasCorruptStoredCategories = false
        } catch {
            let message = "Could not load saved service categories: \(error.localizedDescription)"
            lastErrorMessage = message
            hasCorruptStoredCategories = true
            print("❌ \(message)")
        }
    }
}
