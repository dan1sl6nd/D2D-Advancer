import Foundation
import SwiftUI

/// User preferences for target demographics and ideal customer profile
class TargetDemographicsPreferences: ObservableObject {
    static let shared = TargetDemographicsPreferences()

    // MARK: - Income Preferences

    @AppStorage("targetIncomeMin") var targetIncomeMin: Double = 60000
    @AppStorage("targetIncomeMax") var targetIncomeMax: Double = 250000

    // Predefined income brackets for quick selection
    enum IncomeBracket: String, CaseIterable {
        case budget = "Budget ($30k-$60k)"
        case moderate = "Moderate ($60k-$100k)"
        case comfortable = "Comfortable ($100k-$150k)"
        case affluent = "Affluent ($150k-$250k)"
        case wealthy = "Wealthy ($250k+)"
        case custom = "Custom Range"

        var range: (min: Double, max: Double) {
            switch self {
            case .budget:
                return (30000, 60000)
            case .moderate:
                return (60000, 100000)
            case .comfortable:
                return (100000, 150000)
            case .affluent:
                return (150000, 250000)
            case .wealthy:
                return (250000, 1000000)
            case .custom:
                return (0, 0)
            }
        }
    }

    // MARK: - Home Value Preferences

    @AppStorage("targetHomeValueMin") var targetHomeValueMin: Double = 600000
    @AppStorage("targetHomeValueMax") var targetHomeValueMax: Double = 1500000

    enum HomeValueBracket: String, CaseIterable {
        case starter = "Starter Homes ($100k-$250k)"
        case established = "Established ($250k-$500k)"
        case upscale = "Upscale ($500k-$750k)"
        case luxury = "Luxury ($750k-$1M)"
        case estate = "Estate ($1M+)"
        case torontoCondo = "Toronto Condo ($600k-$900k)"
        case torontoHome = "Toronto Home ($800k-$1.5M)"
        case torontoPremium = "Toronto Premium ($1.5M-$3M)"
        case custom = "Custom Range"

        var range: (min: Double, max: Double) {
            switch self {
            case .starter:
                return (100000, 250000)
            case .established:
                return (250000, 500000)
            case .upscale:
                return (500000, 750000)
            case .luxury:
                return (750000, 1000000)
            case .estate:
                return (1000000, 5000000)
            case .torontoCondo:
                return (600000, 900000)
            case .torontoHome:
                return (800000, 1500000)
            case .torontoPremium:
                return (1500000, 3000000)
            case .custom:
                return (0, 0)
            }
        }
    }

    // MARK: - Density Preferences

    @AppStorage("preferredDensity") var preferredDensity: String = "suburban"

    enum DensityPreference: String, CaseIterable {
        case rural = "Rural Areas"
        case suburban = "Suburban"
        case urban = "Urban"
        case mixed = "Mixed/Any"

        var description: String {
            switch self {
            case .rural:
                return "Low density, spread out homes"
            case .suburban:
                return "Medium density, neighborhoods"
            case .urban:
                return "High density, apartments/condos"
            case .mixed:
                return "No preference on density"
            }
        }
    }

    // MARK: - Homeownership Preferences

    @AppStorage("preferHomeowners") var preferHomeowners: Bool = true
    @AppStorage("minimumOwnershipRate") var minimumOwnershipRate: Double = 0.5

    // MARK: - Scoring Weight Customization

    @AppStorage("weightIncome") var weightIncome: Double = 0.30
    @AppStorage("weightDensity") var weightDensity: Double = 0.20
    @AppStorage("weightHomeValue") var weightHomeValue: Double = 0.25
    @AppStorage("weightConversion") var weightConversion: Double = 0.25

    var scoringWeights: NeighborhoodScoreEngine.ScoringWeights {
        return NeighborhoodScoreEngine.ScoringWeights(
            incomeMatch: weightIncome,
            populationDensity: weightDensity,
            homeValueMatch: weightHomeValue,
            conversionRate: weightConversion
        )
    }

    // MARK: - Preset Profiles

    enum TargetProfile: String, CaseIterable {
        case solarPanels = "Solar Panels"
        case roofing = "Roofing"
        case hvac = "HVAC"
        case windows = "Windows & Doors"
        case landscaping = "Landscaping"
        case remodeling = "Home Remodeling"
        case security = "Security Systems"
        case pools = "Pools & Spas"
        case torontoGeneral = "Toronto - General"
        case torontoPremium = "Toronto - Premium Areas"
        case custom = "Custom Profile"

        var recommendedPreferences: (income: IncomeBracket, homeValue: HomeValueBracket) {
            switch self {
            case .solarPanels:
                return (.comfortable, .established)
            case .roofing:
                return (.moderate, .established)
            case .hvac:
                return (.comfortable, .established)
            case .windows:
                return (.moderate, .established)
            case .landscaping:
                return (.comfortable, .upscale)
            case .remodeling:
                return (.affluent, .upscale)
            case .security:
                return (.comfortable, .established)
            case .pools:
                return (.affluent, .luxury)
            case .torontoGeneral:
                return (.moderate, .torontoHome)
            case .torontoPremium:
                return (.affluent, .torontoPremium)
            case .custom:
                return (.moderate, .established)
            }
        }

        var description: String {
            switch self {
            case .solarPanels:
                return "Target homeowners with higher income who care about energy efficiency"
            case .roofing:
                return "Established homes, moderate to high income"
            case .hvac:
                return "Homeowners with comfortable income, established properties"
            case .windows:
                return "Moderate income, focus on home improvement"
            case .landscaping:
                return "Higher income, upscale properties with yards"
            case .remodeling:
                return "Affluent homeowners with valuable properties"
            case .security:
                return "Comfortable income, security-conscious homeowners"
            case .pools:
                return "Affluent, luxury homes with space for pools"
            case .torontoGeneral:
                return "Optimized for typical Toronto neighborhoods ($800k-$1.5M homes)"
            case .torontoPremium:
                return "Target high-end Toronto areas like Forest Hill, Rosedale ($1.5M-$3M+)"
            case .custom:
                return "Customize your own target demographics"
            }
        }
    }

    @AppStorage("selectedProfile") var selectedProfileRaw: String = TargetProfile.custom.rawValue

    var selectedProfile: TargetProfile {
        get {
            return TargetProfile(rawValue: selectedProfileRaw) ?? .custom
        }
        set {
            selectedProfileRaw = newValue.rawValue
        }
    }

    // MARK: - Methods

    func applyProfile(_ profile: TargetProfile) {
        selectedProfile = profile
        let prefs = profile.recommendedPreferences
        let incomeRange = prefs.income.range
        let homeValueRange = prefs.homeValue.range

        targetIncomeMin = incomeRange.min
        targetIncomeMax = incomeRange.max
        targetHomeValueMin = homeValueRange.min
        targetHomeValueMax = homeValueRange.max

        print("✅ Applied profile: \(profile.rawValue)")
        print("   Income: $\(Int(targetIncomeMin/1000))k-$\(Int(targetIncomeMax/1000))k")
        print("   Home Value: $\(Int(targetHomeValueMin/1000))k-$\(Int(targetHomeValueMax/1000))k")
    }

    func resetToDefaults() {
        targetIncomeMin = 50000
        targetIncomeMax = 150000
        targetHomeValueMin = 200000
        targetHomeValueMax = 500000
        preferredDensity = "suburban"
        preferHomeowners = true
        minimumOwnershipRate = 0.5
        weightIncome = 0.30
        weightDensity = 0.20
        weightHomeValue = 0.25
        weightConversion = 0.25
        selectedProfile = .custom
    }

    // MARK: - Validation

    func validatePreferences() -> Bool {
        guard targetIncomeMin < targetIncomeMax else {
            return false
        }
        guard targetHomeValueMin < targetHomeValueMax else {
            return false
        }
        guard minimumOwnershipRate >= 0 && minimumOwnershipRate <= 1.0 else {
            return false
        }
        return true
    }

    // MARK: - Formatted Display

    var formattedIncomeRange: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.maximumFractionDigits = 0
        let min = formatter.string(from: NSNumber(value: targetIncomeMin)) ?? "$0"
        let max = formatter.string(from: NSNumber(value: targetIncomeMax)) ?? "$0"
        return "\(min) - \(max)"
    }

    var formattedHomeValueRange: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.maximumFractionDigits = 0
        let min = formatter.string(from: NSNumber(value: targetHomeValueMin)) ?? "$0"
        let max = formatter.string(from: NSNumber(value: targetHomeValueMax)) ?? "$0"
        return "\(min) - \(max)"
    }
}