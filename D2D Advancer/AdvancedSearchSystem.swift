import SwiftUI
import CoreData
import CoreLocation

struct SearchFilter: Equatable {
    var text: String = ""
    var selectedStatuses: Set<LeadStatus> = []
    var dateRange: DateRange?
    var hasFollowUp: Bool? = nil
    var visitCountRange: ClosedRange<Int>?
    var priorityRange: ClosedRange<Int>?
    var priceRange: ClosedRange<Double>?
    var estimatedValueRange: ClosedRange<Double>?
    var selectedSources: Set<String> = []
    var selectedTags: Set<String> = []
    var hasCheckIns: Bool? = nil
    var hasLastContact: Bool? = nil
    var sortOption: SortOption = .dateCreated
    var sortAscending: Bool = false
}

struct DateRange: Equatable {
    var startDate: Date
    var endDate: Date
    var type: DateRangeType
    
    enum DateRangeType: String, CaseIterable, Codable {
        case created = "Date Created"
        case updated = "Date Updated"
        case followUp = "Follow-up Date"
        case lastContact = "Last Contact Date"
        
        var icon: String {
            switch self {
            case .created: return "calendar.badge.plus"
            case .updated: return "calendar.badge.exclamationmark"
            case .followUp: return "clock.badge"
            case .lastContact: return "calendar.badge.clock"
            }
        }
    }
}


enum SortOption: String, CaseIterable {
    case name = "Name"
    case dateCreated = "Date Created"
    case dateUpdated = "Date Updated"
    case followUpDate = "Follow-up Date"
    case lastContactDate = "Last Contact Date"
    case status = "Status"
    case visitCount = "Visit Count"
    case priority = "Priority"
    case price = "Price"
    case estimatedValue = "Estimated Value"
    
    var icon: String {
        switch self {
        case .name: return "textformat.abc"
        case .dateCreated: return "calendar.badge.plus"
        case .dateUpdated: return "calendar.badge.exclamationmark"
        case .followUpDate: return "clock.badge"
        case .lastContactDate: return "calendar.badge.clock"
        case .status: return "flag.fill"
        case .visitCount: return "number.circle"
        case .priority: return "exclamationmark.triangle"
        case .price: return "dollarsign.circle"
        case .estimatedValue: return "chart.line.uptrend.xyaxis"
        }
    }
}

class SearchFilterManager: ObservableObject {
    @Published var currentFilter = SearchFilter()
    @Published var savedPresets: [SearchPreset] = []
    @Published var showingAdvancedFilters = false
    
    private let userDefaults = UserDefaults.standard
    private let presetsKey = "saved_search_presets"
    
    init() {
        loadSavedPresets()
    }
    
    func applyFilter(to request: NSFetchRequest<Lead>, userLocation: CLLocation? = nil) {
        var predicates: [NSPredicate] = []
        
        // Text search filter
        if !currentFilter.text.isEmpty {
            let searchText = currentFilter.text.trimmingCharacters(in: .whitespacesAndNewlines)
            let searchPredicate = NSPredicate(format: "name CONTAINS[cd] %@ OR address CONTAINS[cd] %@ OR phone CONTAINS[cd] %@ OR email CONTAINS[cd] %@", 
                                            searchText, searchText, searchText, searchText)
            predicates.append(searchPredicate)
        }

        // Status filter (map UI LeadStatus -> Core Data Lead.Status)
        if !currentFilter.selectedStatuses.isEmpty {
            let legacyStatuses = currentFilter.selectedStatuses.map { $0.leadStatus.rawValue }
            predicates.append(NSPredicate(format: "status IN %@", legacyStatuses))
        }

        // Has follow-up filter
        if let hasFollowUp = currentFilter.hasFollowUp {
            if hasFollowUp {
                predicates.append(NSPredicate(format: "followUpDate != nil"))
            } else {
                predicates.append(NSPredicate(format: "followUpDate == nil"))
            }
        }

        // Date range filter
        if let range = currentFilter.dateRange {
            predicates.append(createDatePredicate(for: range))
        }
        
        // Apply all predicates
        if !predicates.isEmpty {
            request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
        }
        
        // Apply sorting
        request.sortDescriptors = [createSortDescriptor()]
    }
    
    private func createDatePredicate(for dateRange: DateRange) -> NSPredicate {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: dateRange.startDate)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: dateRange.endDate)) ?? dateRange.endDate
        
        switch dateRange.type {
        case .created:
            return NSPredicate(format: "createdDate >= %@ AND createdDate < %@", startOfDay as NSDate, endOfDay as NSDate)
        case .updated:
            return NSPredicate(format: "updatedDate >= %@ AND updatedDate < %@", startOfDay as NSDate, endOfDay as NSDate)
        case .followUp:
            return NSPredicate(format: "followUpDate >= %@ AND followUpDate < %@", startOfDay as NSDate, endOfDay as NSDate)
        case .lastContact:
            return NSPredicate(format: "lastContactDate >= %@ AND lastContactDate < %@", startOfDay as NSDate, endOfDay as NSDate)
        }
    }
    
    private func createSortDescriptor() -> NSSortDescriptor {
        switch currentFilter.sortOption {
        case .name:
            return NSSortDescriptor(keyPath: \Lead.name, ascending: currentFilter.sortAscending)
        case .dateCreated:
            return NSSortDescriptor(keyPath: \Lead.createdDate, ascending: currentFilter.sortAscending)
        case .dateUpdated:
            return NSSortDescriptor(keyPath: \Lead.updatedDate, ascending: currentFilter.sortAscending)
        case .followUpDate:
            return NSSortDescriptor(keyPath: \Lead.followUpDate, ascending: currentFilter.sortAscending)
        case .lastContactDate:
            return NSSortDescriptor(keyPath: \Lead.lastContactDate, ascending: currentFilter.sortAscending)
        case .status:
            return NSSortDescriptor(keyPath: \Lead.status, ascending: currentFilter.sortAscending)
        case .visitCount:
            return NSSortDescriptor(keyPath: \Lead.visitCount, ascending: currentFilter.sortAscending)
        case .priority:
            return NSSortDescriptor(keyPath: \Lead.priority, ascending: currentFilter.sortAscending)
        case .price:
            return NSSortDescriptor(keyPath: \Lead.price, ascending: currentFilter.sortAscending)
        case .estimatedValue:
            return NSSortDescriptor(keyPath: \Lead.estimatedValue, ascending: currentFilter.sortAscending)
        }
    }
    
    func clearAllFilters() {
        currentFilter = SearchFilter()
    }
    
    func savePreset(name: String) {
        let preset = SearchPreset(
            id: UUID(),
            name: name,
            filter: currentFilter,
            dateCreated: Date()
        )
        savedPresets.append(preset)
        savePresetsToUserDefaults()
    }
    
    func loadPreset(_ preset: SearchPreset) {
        currentFilter = preset.filter
    }
    
    func deletePreset(_ preset: SearchPreset) {
        savedPresets.removeAll { $0.id == preset.id }
        savePresetsToUserDefaults()
    }
    
    
    private func savePresetsToUserDefaults() {
        if let encoded = try? JSONEncoder().encode(savedPresets) {
            userDefaults.set(encoded, forKey: presetsKey)
        }
    }
    
    private func loadSavedPresets() {
        if let data = userDefaults.data(forKey: presetsKey),
           let decoded = try? JSONDecoder().decode([SearchPreset].self, from: data) {
            savedPresets = decoded
        }
    }
}

struct SearchPreset: Codable, Identifiable {
    let id: UUID
    let name: String
    let filter: SearchFilter
    let dateCreated: Date
}

extension SearchFilter: Codable {
    enum CodingKeys: String, CodingKey {
        case text, selectedStatuses, dateRange, hasFollowUp, visitCountRange, priorityRange, priceRange, estimatedValueRange, selectedSources, selectedTags, hasCheckIns, hasLastContact, sortOption, sortAscending
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        text = try container.decodeIfPresent(String.self, forKey: .text) ?? ""
        
        let statusStrings = try container.decodeIfPresent([String].self, forKey: .selectedStatuses) ?? []
        selectedStatuses = Set(statusStrings.compactMap(LeadStatus.init))
        
        dateRange = try container.decodeIfPresent(DateRange.self, forKey: .dateRange)
        hasFollowUp = try container.decodeIfPresent(Bool.self, forKey: .hasFollowUp)
        hasLastContact = try container.decodeIfPresent(Bool.self, forKey: .hasLastContact)
        hasCheckIns = try container.decodeIfPresent(Bool.self, forKey: .hasCheckIns)
        
        // Decode ranges
        if let rangeData = try container.decodeIfPresent([Int].self, forKey: .visitCountRange), rangeData.count == 2 {
            visitCountRange = rangeData[0]...rangeData[1]
        }
        
        if let rangeData = try container.decodeIfPresent([Int].self, forKey: .priorityRange), rangeData.count == 2 {
            priorityRange = rangeData[0]...rangeData[1]
        }
        
        if let rangeData = try container.decodeIfPresent([Double].self, forKey: .priceRange), rangeData.count == 2 {
            priceRange = rangeData[0]...rangeData[1]
        }
        
        if let rangeData = try container.decodeIfPresent([Double].self, forKey: .estimatedValueRange), rangeData.count == 2 {
            estimatedValueRange = rangeData[0]...rangeData[1]
        }
        
        // Decode sets
        selectedSources = Set(try container.decodeIfPresent([String].self, forKey: .selectedSources) ?? [])
        selectedTags = Set(try container.decodeIfPresent([String].self, forKey: .selectedTags) ?? [])
        
        let sortString = try container.decodeIfPresent(String.self, forKey: .sortOption) ?? "dateCreated"
        sortOption = SortOption(rawValue: sortString) ?? .dateCreated
        sortAscending = try container.decodeIfPresent(Bool.self, forKey: .sortAscending) ?? false
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(text, forKey: .text)
        try container.encode(selectedStatuses.map(\.rawValue), forKey: .selectedStatuses)
        try container.encodeIfPresent(dateRange, forKey: .dateRange)
        try container.encodeIfPresent(hasFollowUp, forKey: .hasFollowUp)
        try container.encodeIfPresent(hasLastContact, forKey: .hasLastContact)
        try container.encodeIfPresent(hasCheckIns, forKey: .hasCheckIns)
        
        // Encode ranges
        if let range = visitCountRange {
            try container.encode([range.lowerBound, range.upperBound], forKey: .visitCountRange)
        }
        
        if let range = priorityRange {
            try container.encode([range.lowerBound, range.upperBound], forKey: .priorityRange)
        }
        
        if let range = priceRange {
            try container.encode([range.lowerBound, range.upperBound], forKey: .priceRange)
        }
        
        if let range = estimatedValueRange {
            try container.encode([range.lowerBound, range.upperBound], forKey: .estimatedValueRange)
        }
        
        // Encode sets
        try container.encode(Array(selectedSources), forKey: .selectedSources)
        try container.encode(Array(selectedTags), forKey: .selectedTags)
        
        try container.encode(sortOption.rawValue, forKey: .sortOption)
        try container.encode(sortAscending, forKey: .sortAscending)
    }
}

extension DateRange: Codable {}

