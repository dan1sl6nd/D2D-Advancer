import Foundation
import CoreData
import CoreLocation

@MainActor
class NeighborhoodDataService: ObservableObject {
    static let shared = NeighborhoodDataService()

    @Published var isLoading = false
    @Published var lastError: Error?

    private let viewContext: NSManagedObjectContext
    private let censusBureauAPIBase = "https://api.census.gov/data/2021/acs/acs5"
    private let canadianDataService = CanadianNeighborhoodDataService()

    // Cache duration: 30 days
    private let cacheExpirationInterval: TimeInterval = 30 * 24 * 60 * 60

    private init() {
        self.viewContext = PersistenceController.shared.container.viewContext
    }

    // MARK: - Public API

    /// Fetches neighborhood data for a given coordinate
    func fetchNeighborhoodData(for coordinate: CLLocationCoordinate2D) async throws -> Neighborhood {
        // Check cache first
        if let cached = try getCachedNeighborhood(for: coordinate) {
            print("📍 Using cached neighborhood data for \(coordinate)")
            return cached
        }

        print("📍 Fetching new neighborhood data for \(coordinate)")

        // Detect if coordinate is in Canada or US
        let isCanadian = CanadianNeighborhoodDataService.isCanadianCoordinate(coordinate)

        let censusData: CensusData
        let censusTractId: String

        if isCanadian {
            print("🇨🇦 Canadian location detected - using Statistics Canada API")
            censusTractId = "CA-\(coordinate.latitude)-\(coordinate.longitude)" // Placeholder ID
            censusData = try await canadianDataService.fetchCanadianCensusData(for: coordinate)
        } else {
            print("🇺🇸 US location detected - using Census Bureau API")
            // Step 1: Get Census Tract ID from coordinate using FCC API
            censusTractId = try await getCensusTractId(for: coordinate)
            // Step 2: Fetch census data for this tract
            censusData = try await fetchCensusData(for: censusTractId)
        }

        // Step 3: Create and cache neighborhood entity
        let neighborhood = try createNeighborhood(
            coordinate: coordinate,
            censusTractId: censusTractId,
            censusData: censusData
        )

        // Debug: Log fetched census data
        print("📊 Census Data Fetched:")
        print("   Name: \(censusData.name)")
        print("   City: \(censusData.cityName), \(censusData.stateName)")
        print("   Median Income: $\(Int(censusData.medianHouseholdIncome))")
        print("   Avg Home Value: $\(Int(censusData.averageHomeValue))")
        print("   Population: \(Int(censusData.totalPopulation))")
        print("   Ownership Rate: \(String(format: "%.1f%%", censusData.homeOwnershipRate * 100))")

        return neighborhood
    }

    /// Refreshes neighborhood data if cache is expired
    func refreshNeighborhoodIfNeeded(_ neighborhood: Neighborhood) async throws {
        guard let lastUpdated = neighborhood.lastUpdated else {
            return
        }

        let timeElapsed = Date().timeIntervalSince(lastUpdated)
        if timeElapsed > cacheExpirationInterval {
            print("📍 Cache expired, refreshing neighborhood data")
            let coordinate = CLLocationCoordinate2D(
                latitude: neighborhood.centerLatitude,
                longitude: neighborhood.centerLongitude
            )
            _ = try await fetchNeighborhoodData(for: coordinate)
        }
    }

    /// Gets all cached neighborhoods sorted by score
    func getCachedNeighborhoods() throws -> [Neighborhood] {
        let request: NSFetchRequest<Neighborhood> = Neighborhood.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Neighborhood.score, ascending: false)]
        return try viewContext.fetch(request)
    }

    // MARK: - Private Helpers

    private func getCachedNeighborhood(for coordinate: CLLocationCoordinate2D) throws -> Neighborhood? {
        let request: NSFetchRequest<Neighborhood> = Neighborhood.fetchRequest()

        // Search within approximately 1km radius (0.01 degrees ≈ 1.1km)
        let latMin = coordinate.latitude - 0.01
        let latMax = coordinate.latitude + 0.01
        let lonMin = coordinate.longitude - 0.01
        let lonMax = coordinate.longitude + 0.01

        request.predicate = NSPredicate(
            format: "centerLatitude >= %f AND centerLatitude <= %f AND centerLongitude >= %f AND centerLongitude <= %f",
            latMin, latMax, lonMin, lonMax
        )
        request.fetchLimit = 1

        guard let neighborhood = try viewContext.fetch(request).first else {
            return nil
        }

        // Check if cache is still valid
        if let lastUpdated = neighborhood.lastUpdated {
            let timeElapsed = Date().timeIntervalSince(lastUpdated)
            if timeElapsed > cacheExpirationInterval {
                return nil // Cache expired
            }
        }

        return neighborhood
    }

    private func getCensusTractId(for coordinate: CLLocationCoordinate2D) async throws -> String {
        // Use FCC Census Block API (free, no key required)
        let urlString = "https://geo.fcc.gov/api/census/block/find?latitude=\(coordinate.latitude)&longitude=\(coordinate.longitude)&format=json"

        guard let url = URL(string: urlString) else {
            throw NeighborhoodError.invalidURL
        }

        let (data, response) = try await URLSession.shared.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw NeighborhoodError.apiRequestFailed
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let blockData = json?["Block"] as? [String: Any],
              let fips = blockData["FIPS"] as? String else {
            throw NeighborhoodError.invalidResponse
        }

        // Census tract is first 11 digits of FIPS code
        let tractId = String(fips.prefix(11))
        return tractId
    }

    private func fetchCensusData(for tractId: String) async throws -> CensusData {
        // Extract state and county from tract ID
        let stateCode = String(tractId.prefix(2))
        let countyCode = String(tractId.dropFirst(2).prefix(3))
        let tract = String(tractId.dropFirst(5))

        // Census API variables:
        // B19013_001E: Median household income
        // B01003_001E: Total population
        // B25077_001E: Median home value
        // B25003_002E: Owner-occupied housing units
        // B25003_001E: Total housing units

        let variables = "NAME,B19013_001E,B01003_001E,B25077_001E,B25003_002E,B25003_001E"
        let urlString = "\(censusBureauAPIBase)?get=\(variables)&for=tract:\(tract)&in=state:\(stateCode)%20county:\(countyCode)"

        guard let url = URL(string: urlString) else {
            throw NeighborhoodError.invalidURL
        }

        let (data, response) = try await URLSession.shared.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw NeighborhoodError.apiRequestFailed
        }

        // Parse JSON array response
        guard let jsonArray = try JSONSerialization.jsonObject(with: data) as? [[Any]],
              jsonArray.count > 1 else {
            throw NeighborhoodError.invalidResponse
        }

        // First row is headers, second row is data
        let dataRow = jsonArray[1]

        guard dataRow.count >= 6 else {
            throw NeighborhoodError.invalidResponse
        }

        let name = dataRow[0] as? String ?? "Unknown"
        let medianIncome = parseDouble(dataRow[1])
        let totalPopulation = parseDouble(dataRow[2])
        let medianHomeValue = parseDouble(dataRow[3])
        let ownerOccupied = parseDouble(dataRow[4])
        let totalHousing = parseDouble(dataRow[5])

        let ownershipRate = totalHousing > 0 ? (ownerOccupied / totalHousing) : 0

        // Extract city and state from name
        let nameParts = name.components(separatedBy: ", ")
        let cityName = nameParts.first?.trimmingCharacters(in: .whitespaces) ?? "Unknown"
        let stateName = nameParts.last?.trimmingCharacters(in: .whitespaces) ?? "Unknown"

        return CensusData(
            name: name,
            cityName: cityName,
            stateName: stateName,
            medianHouseholdIncome: medianIncome,
            totalPopulation: totalPopulation,
            averageHomeValue: medianHomeValue,
            homeOwnershipRate: ownershipRate
        )
    }

    private func createNeighborhood(
        coordinate: CLLocationCoordinate2D,
        censusTractId: String,
        censusData: CensusData
    ) throws -> Neighborhood {
        let neighborhood = Neighborhood(context: viewContext)
        neighborhood.id = UUID()
        neighborhood.censusTractId = censusTractId
        neighborhood.centerLatitude = coordinate.latitude
        neighborhood.centerLongitude = coordinate.longitude
        neighborhood.name = censusData.name
        neighborhood.cityName = censusData.cityName
        neighborhood.state = censusData.stateName
        neighborhood.medianHouseholdIncome = censusData.medianHouseholdIncome
        neighborhood.averageHomeValue = censusData.averageHomeValue
        neighborhood.homeOwnershipRate = censusData.homeOwnershipRate
        neighborhood.populationDensity = censusData.totalPopulation
        neighborhood.lastUpdated = Date()
        neighborhood.score = 0 // Will be calculated by NeighborhoodScoreEngine

        try viewContext.save()
        print("✅ Created neighborhood: \(censusData.name)")

        return neighborhood
    }

    private func parseDouble(_ value: Any?) -> Double {
        if let doubleValue = value as? Double {
            return doubleValue
        } else if let stringValue = value as? String,
                  let doubleValue = Double(stringValue) {
            return doubleValue
        } else if let intValue = value as? Int {
            return Double(intValue)
        }
        return 0
    }
}

// MARK: - Supporting Types

struct CensusData {
    let name: String
    let cityName: String
    let stateName: String
    let medianHouseholdIncome: Double
    let totalPopulation: Double
    let averageHomeValue: Double
    let homeOwnershipRate: Double
}

enum NeighborhoodError: LocalizedError {
    case invalidURL
    case apiRequestFailed
    case invalidResponse
    case cacheExpired

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid API URL"
        case .apiRequestFailed:
            return "Failed to fetch data from API"
        case .invalidResponse:
            return "Invalid response from API"
        case .cacheExpired:
            return "Cached data has expired"
        }
    }
}