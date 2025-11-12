import Foundation
import CoreData
import CoreLocation

@MainActor
class NeighborhoodScoreEngine {
    static let shared = NeighborhoodScoreEngine()

    private let viewContext: NSManagedObjectContext

    private init() {
        self.viewContext = PersistenceController.shared.container.viewContext
    }

    // MARK: - Scoring Weights

    struct ScoringWeights {
        var incomeMatch: Double = 0.30        // 30%: How well income matches target
        var populationDensity: Double = 0.20  // 20%: Population concentration
        var homeValueMatch: Double = 0.25     // 25%: Home value alignment
        var conversionRate: Double = 0.25     // 25%: Historical success in area

        // Ensure weights sum to 1.0
        var normalized: ScoringWeights {
            let total = incomeMatch + populationDensity + homeValueMatch + conversionRate
            return ScoringWeights(
                incomeMatch: incomeMatch / total,
                populationDensity: populationDensity / total,
                homeValueMatch: homeValueMatch / total,
                conversionRate: conversionRate / total
            )
        }
    }

    // MARK: - Public API

    /// Calculates and updates the score for a neighborhood
    func calculateScore(
        for neighborhood: Neighborhood,
        preferences: TargetDemographicsPreferences,
        weights: ScoringWeights = ScoringWeights()
    ) async throws -> Double {
        let normalizedWeights = weights.normalized

        // Calculate individual component scores (0-100)
        let incomeScore = calculateIncomeScore(
            neighborhood: neighborhood,
            preferences: preferences
        )

        let densityScore = calculateDensityScore(neighborhood: neighborhood)

        let homeValueScore = calculateHomeValueScore(
            neighborhood: neighborhood,
            preferences: preferences
        )

        let conversionScore = calculateConversionScore(neighborhood: neighborhood)

        // Weighted total score
        let totalScore = (incomeScore * normalizedWeights.incomeMatch) +
                        (densityScore * normalizedWeights.populationDensity) +
                        (homeValueScore * normalizedWeights.homeValueMatch) +
                        (conversionScore * normalizedWeights.conversionRate)

        // Update neighborhood score in CoreData
        neighborhood.score = totalScore
        try viewContext.save()

        print("📊 Scored neighborhood \(neighborhood.name ?? "Unknown"): \(String(format: "%.1f", totalScore))")
        print("   Income: $\(Int(neighborhood.medianHouseholdIncome))k (target: $\(Int(preferences.targetIncomeMin/1000))k-$\(Int(preferences.targetIncomeMax/1000))k) → Score: \(String(format: "%.1f", incomeScore))")
        print("   Home Value: $\(Int(neighborhood.averageHomeValue/1000))k (target: $\(Int(preferences.targetHomeValueMin/1000))k-$\(Int(preferences.targetHomeValueMax/1000))k) → Score: \(String(format: "%.1f", homeValueScore))")
        print("   Density: \(Int(neighborhood.populationDensity)) → Score: \(String(format: "%.1f", densityScore))")
        print("   Conversion: \(String(format: "%.1f", conversionScore))")

        return totalScore
    }

    /// Recalculates scores for all neighborhoods
    func recalculateAllScores(
        preferences: TargetDemographicsPreferences,
        weights: ScoringWeights = ScoringWeights()
    ) async throws {
        let request: NSFetchRequest<Neighborhood> = Neighborhood.fetchRequest()
        let neighborhoods = try viewContext.fetch(request)

        for neighborhood in neighborhoods {
            _ = try await calculateScore(
                for: neighborhood,
                preferences: preferences,
                weights: weights
            )
        }
    }

    // MARK: - Component Scoring Functions

    private func calculateIncomeScore(
        neighborhood: Neighborhood,
        preferences: TargetDemographicsPreferences
    ) -> Double {
        let income = neighborhood.medianHouseholdIncome
        let targetMin = preferences.targetIncomeMin
        let targetMax = preferences.targetIncomeMax

        // Perfect score if within target range
        if income >= targetMin && income <= targetMax {
            return 100.0
        }

        // Calculate distance from target range
        let distanceFromRange: Double
        if income < targetMin {
            distanceFromRange = targetMin - income
        } else {
            distanceFromRange = income - targetMax
        }

        // Score decays as distance increases (with 50k buffer at 50% score)
        let buffer = 50000.0
        let normalizedDistance = distanceFromRange / buffer
        let score = max(0, 100.0 - (normalizedDistance * 50.0))

        return score
    }

    private func calculateDensityScore(neighborhood: Neighborhood) -> Double {
        let population = neighborhood.populationDensity

        // Optimal range: 2000-8000 people (typical suburban density)
        let optimalMin = 2000.0
        let optimalMax = 8000.0

        if population >= optimalMin && population <= optimalMax {
            return 100.0
        }

        // Too sparse or too dense reduces score
        if population < optimalMin {
            // Rural areas: decay from optimal
            let ratio = population / optimalMin
            return max(0, ratio * 100.0)
        } else {
            // Urban areas: gradual decay
            let excess = population - optimalMax
            let penalty = min(50, (excess / 10000.0) * 50.0)
            return max(50, 100.0 - penalty)
        }
    }

    private func calculateHomeValueScore(
        neighborhood: Neighborhood,
        preferences: TargetDemographicsPreferences
    ) -> Double {
        let homeValue = neighborhood.averageHomeValue
        let targetMin = preferences.targetHomeValueMin
        let targetMax = preferences.targetHomeValueMax

        // Perfect score if within target range
        if homeValue >= targetMin && homeValue <= targetMax {
            return 100.0
        }

        // Calculate distance from target range
        let distanceFromRange: Double
        if homeValue < targetMin {
            distanceFromRange = targetMin - homeValue
        } else {
            distanceFromRange = homeValue - targetMax
        }

        // Score decays (with 100k buffer at 50% score)
        let buffer = 100000.0
        let normalizedDistance = distanceFromRange / buffer
        let score = max(0, 100.0 - (normalizedDistance * 50.0))

        return score
    }

    private func calculateConversionScore(neighborhood: Neighborhood) -> Double {
        // Get all leads in this neighborhood
        guard let leads = neighborhood.leads?.allObjects as? [Lead],
              !leads.isEmpty else {
            // No data yet - return neutral score
            return 50.0
        }

        let totalLeads = leads.count
        let convertedLeads = leads.filter { $0.leadStatus == .converted }.count
        let interestedLeads = leads.filter { $0.leadStatus == .interested }.count

        // Calculate conversion metrics
        let conversionRate = Double(convertedLeads) / Double(totalLeads)
        let interestRate = Double(interestedLeads + convertedLeads) / Double(totalLeads)

        // Weight conversion rate heavily, interest rate moderately
        let score = (conversionRate * 70.0 + interestRate * 30.0) * 100.0

        // Boost score if we have good sample size (20+ leads)
        let sampleBoost = min(10.0, Double(totalLeads) / 2.0)

        return min(100.0, score + sampleBoost)
    }

    // MARK: - Helper Methods

    /// Gets top N neighborhoods by score
    func getTopNeighborhoods(limit: Int = 10) throws -> [Neighborhood] {
        let request: NSFetchRequest<Neighborhood> = Neighborhood.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Neighborhood.score, ascending: false)]
        request.fetchLimit = limit
        return try viewContext.fetch(request)
    }

    /// Finds the nearest neighborhood to a coordinate
    func findNearestNeighborhood(to coordinate: CLLocationCoordinate2D) throws -> Neighborhood? {
        let request: NSFetchRequest<Neighborhood> = Neighborhood.fetchRequest()
        let neighborhoods = try viewContext.fetch(request)

        guard !neighborhoods.isEmpty else { return nil }

        // Find closest by distance
        return neighborhoods.min { n1, n2 in
            let d1 = distance(
                from: coordinate,
                to: CLLocationCoordinate2D(
                    latitude: n1.centerLatitude,
                    longitude: n1.centerLongitude
                )
            )
            let d2 = distance(
                from: coordinate,
                to: CLLocationCoordinate2D(
                    latitude: n2.centerLatitude,
                    longitude: n2.centerLongitude
                )
            )
            return d1 < d2
        }
    }

    private func distance(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) -> Double {
        let loc1 = CLLocation(latitude: from.latitude, longitude: from.longitude)
        let loc2 = CLLocation(latitude: to.latitude, longitude: to.longitude)
        return loc1.distance(from: loc2)
    }
}

// MARK: - Score Interpretation Extension

extension Neighborhood {
    var scoreGrade: String {
        switch score {
        case 90...100:
            return "Excellent"
        case 75..<90:
            return "Very Good"
        case 60..<75:
            return "Good"
        case 45..<60:
            return "Fair"
        default:
            return "Poor"
        }
    }

    var scoreColor: String {
        switch score {
        case 90...100:
            return "green"
        case 75..<90:
            return "lightGreen"
        case 60..<75:
            return "yellow"
        case 45..<60:
            return "orange"
        default:
            return "red"
        }
    }

    var formattedIncome: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: medianHouseholdIncome)) ?? "$0"
    }

    var formattedHomeValue: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: averageHomeValue)) ?? "$0"
    }

    var formattedPopulation: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: populationDensity)) ?? "0"
    }
}