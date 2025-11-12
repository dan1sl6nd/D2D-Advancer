import Foundation

struct SeasonalDatePreset: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let season: Season
    let year: Int
    let calculatedDate: Date
    
    enum Season: String, CaseIterable {
        case spring = "Spring"
        case summer = "Summer"
        case fall = "Fall"
        case winter = "Winter"
        
        var icon: String {
            switch self {
            case .spring: return "leaf.fill"
            case .summer: return "sun.max.fill"
            case .fall: return "leaf.arrow.circlepath"
            case .winter: return "snowflake"
            }
        }
        
        var color: String {
            switch self {
            case .spring: return "green"
            case .summer: return "orange"
            case .fall: return "brown"
            case .winter: return "blue"
            }
        }
        
        // Define season date ranges (Northern Hemisphere)
        func dateRange(for year: Int) -> (start: Date, end: Date) {
            let calendar = Calendar.current
            
            switch self {
            case .spring:
                // March 20 - June 19
                let start = calendar.date(from: DateComponents(year: year, month: 3, day: 20)) ?? Date()
                let end = calendar.date(from: DateComponents(year: year, month: 6, day: 19)) ?? Date()
                return (start, end)
            case .summer:
                // June 20 - September 21
                let start = calendar.date(from: DateComponents(year: year, month: 6, day: 20)) ?? Date()
                let end = calendar.date(from: DateComponents(year: year, month: 9, day: 21)) ?? Date()
                return (start, end)
            case .fall:
                // September 22 - December 20
                let start = calendar.date(from: DateComponents(year: year, month: 9, day: 22)) ?? Date()
                let end = calendar.date(from: DateComponents(year: year, month: 12, day: 20)) ?? Date()
                return (start, end)
            case .winter:
                // December 21 - March 19 (next year)
                let start = calendar.date(from: DateComponents(year: year, month: 12, day: 21)) ?? Date()
                let end = calendar.date(from: DateComponents(year: year + 1, month: 3, day: 19)) ?? Date()
                return (start, end)
            }
        }
    }
}

class SeasonalDatePresetManager {
    static let shared = SeasonalDatePresetManager()
    
    private init() {}
    
    /// Generates seasonal date presets for the next few years
    func generatePresets() -> [SeasonalDatePreset] {
        let calendar = Calendar.current
        let currentDate = Date()
        let currentYear = calendar.component(.year, from: currentDate)
        let currentDay = calendar.component(.day, from: currentDate)
        let currentHour = calendar.component(.hour, from: currentDate)
        let currentMinute = calendar.component(.minute, from: currentDate)
        
        var presets: [SeasonalDatePreset] = []
        
        // Generate presets for the next 3 years
        for yearOffset in 0...2 {
            let targetYear = currentYear + yearOffset
            
            for season in SeasonalDatePreset.Season.allCases {
                let seasonRange = season.dateRange(for: targetYear)
                
                // Calculate the target date by trying to match the current day of month
                let targetDate = calculateSeasonalDate(
                    seasonRange: seasonRange,
                    preferredDay: currentDay,
                    hour: currentHour,
                    minute: currentMinute
                )
                
                // Only include future dates
                if targetDate > currentDate {
                    let preset = SeasonalDatePreset(
                        title: "\(season.rawValue) \(targetYear)",
                        season: season,
                        year: targetYear,
                        calculatedDate: targetDate
                    )
                    presets.append(preset)
                }
            }
        }
        
        // Sort by date
        return presets.sorted { $0.calculatedDate < $1.calculatedDate }
    }
    
    /// Calculates a date within a season that tries to match the preferred day of month
    private func calculateSeasonalDate(seasonRange: (start: Date, end: Date), preferredDay: Int, hour: Int, minute: Int) -> Date {
        let calendar = Calendar.current
        
        // Get the middle month of the season for more reasonable dates
        let startComponents = calendar.dateComponents([.year, .month], from: seasonRange.start)
        let endComponents = calendar.dateComponents([.year, .month], from: seasonRange.end)
        
        guard let startYear = startComponents.year, let startMonth = startComponents.month,
              let endYear = endComponents.year, let endMonth = endComponents.month else {
            return seasonRange.start
        }
        
        // Calculate middle month
        let totalMonths = (endYear - startYear) * 12 + (endMonth - startMonth)
        let middleMonthOffset = totalMonths / 2
        let targetYear = startYear + ((startMonth + middleMonthOffset - 1) / 12)
        let targetMonth = ((startMonth + middleMonthOffset - 1) % 12) + 1
        
        // Try to use the preferred day, but adjust if it doesn't exist in that month
        let daysInMonth = calendar.range(of: .day, in: .month, for: calendar.date(from: DateComponents(year: targetYear, month: targetMonth)) ?? Date())?.count ?? 30
        let adjustedDay = min(preferredDay, daysInMonth)
        
        // Create the target date
        let targetDateComponents = DateComponents(
            year: targetYear,
            month: targetMonth,
            day: adjustedDay,
            hour: hour,
            minute: minute
        )
        
        return calendar.date(from: targetDateComponents) ?? seasonRange.start
    }
    
    /// Gets a seasonal preset that matches today's date pattern for a specific season/year
    func getPresetForSeason(_ season: SeasonalDatePreset.Season, year: Int) -> SeasonalDatePreset? {
        let presets = generatePresets()
        return presets.first { $0.season == season && $0.year == year }
    }
    
    /// Gets the next logical seasonal preset (next season from current date)
    func getNextSeasonalPreset() -> SeasonalDatePreset? {
        let presets = generatePresets()
        return presets.first
    }
    
    /// Gets seasonal presets grouped by year for display
    func getPresetsGroupedByYear() -> [Int: [SeasonalDatePreset]] {
        let presets = generatePresets()
        return Dictionary(grouping: presets) { $0.year }
    }
}