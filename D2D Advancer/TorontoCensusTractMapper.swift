import Foundation
import CoreLocation

/// Helper class to map Toronto coordinates to census tracts
/// This is a simplified mapping for demonstration purposes
/// For production use, integrate Statistics Canada's PCCF (Postal Code Conversion File)
class TorontoCensusTractMapper {

    // Sample Toronto census tracts with approximate boundaries
    // In production, load this from a proper GeoJSON or database
    private static let torontoCensusTracts: [(id: String, name: String, center: CLLocationCoordinate2D, radius: Double)] = [
        // Downtown Toronto
        ("5350001.00", "Downtown Toronto - Financial District", CLLocationCoordinate2D(latitude: 43.6481, longitude: -79.3816), 1000),
        ("5350002.00", "Downtown Toronto - Entertainment District", CLLocationCoordinate2D(latitude: 43.6454, longitude: -79.3915), 1000),
        ("5350003.00", "Downtown Toronto - Harbourfront", CLLocationCoordinate2D(latitude: 43.6416, longitude: -79.3780), 1000),

        // Midtown Toronto
        ("5350101.00", "Yonge-Eglinton", CLLocationCoordinate2D(latitude: 43.7065, longitude: -79.3991), 1500),
        ("5350102.00", "Forest Hill", CLLocationCoordinate2D(latitude: 43.6940, longitude: -79.4102), 1500),
        ("5350103.00", "Rosedale", CLLocationCoordinate2D(latitude: 43.6782, longitude: -79.3790), 1200),

        // Scarborough
        ("5350201.00", "Scarborough - Agincourt", CLLocationCoordinate2D(latitude: 43.7853, longitude: -79.2807), 2000),
        ("5350202.00", "Scarborough - Malvern", CLLocationCoordinate2D(latitude: 43.8066, longitude: -79.2167), 2000),

        // North York
        ("5350301.00", "North York - Willowdale", CLLocationCoordinate2D(latitude: 43.7635, longitude: -79.4149), 1800),
        ("5350302.00", "North York - York Mills", CLLocationCoordinate2D(latitude: 43.7450, longitude: -79.4060), 1500),

        // Etobicoke
        ("5350401.00", "Etobicoke - Kingsway", CLLocationCoordinate2D(latitude: 43.6566, longitude: -79.5154), 1800),
        ("5350402.00", "Etobicoke - Long Branch", CLLocationCoordinate2D(latitude: 43.5959, longitude: -79.5451), 2000),

        // East York
        ("5350501.00", "East York - Leaside", CLLocationCoordinate2D(latitude: 43.7071, longitude: -79.3633), 1500),
        ("5350502.00", "East York - The Danforth", CLLocationCoordinate2D(latitude: 43.6828, longitude: -79.3487), 1200),

        // York
        ("5350601.00", "York - Weston", CLLocationCoordinate2D(latitude: 43.6980, longitude: -79.5203), 1800),
        ("5350602.00", "York - Mount Dennis", CLLocationCoordinate2D(latitude: 43.6884, longitude: -79.4958), 1500),
    ]

    /// Finds the closest census tract to the given coordinate
    static func findCensusTract(for coordinate: CLLocationCoordinate2D) -> (id: String, name: String)? {
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)

        var closestTract: (id: String, name: String, distance: Double)?

        for tract in torontoCensusTracts {
            let tractLocation = CLLocation(latitude: tract.center.latitude, longitude: tract.center.longitude)
            let distance = location.distance(from: tractLocation)

            // Only consider tracts within their radius
            if distance <= tract.radius {
                if closestTract == nil || distance < closestTract!.distance {
                    closestTract = (tract.id, tract.name, distance)
                }
            }
        }

        if let closest = closestTract {
            return (closest.id, closest.name)
        }

        // Default fallback for Toronto area
        return ("5350000.00", "Greater Toronto Area")
    }

    /// Maps postal code FSA (first 3 characters) to approximate census tract
    /// This is a very simplified mapping - production should use PCCF
    static func postalCodeToTract(_ postalCode: String) -> (id: String, name: String)? {
        let fsa = String(postalCode.prefix(3)).uppercased().replacingOccurrences(of: " ", with: "")

        switch fsa {
        // Downtown Toronto FSAs
        case "M5A", "M5B", "M5C", "M5E", "M5G", "M5H", "M5J", "M5K", "M5L", "M5X":
            return ("5350001.00", "Downtown Toronto")

        // Midtown FSAs
        case "M4N", "M4P", "M4R", "M4S", "M4T", "M5N", "M5P", "M5R":
            return ("5350101.00", "Midtown Toronto")

        // Scarborough FSAs
        case "M1B", "M1C", "M1E", "M1G", "M1H", "M1J", "M1K", "M1L", "M1M", "M1N", "M1P", "M1R", "M1S", "M1T", "M1V", "M1W", "M1X":
            return ("5350201.00", "Scarborough")

        // North York FSAs
        case "M2H", "M2J", "M2K", "M2L", "M2M", "M2N", "M2P", "M2R", "M3A", "M3B", "M3C", "M3H", "M3J", "M3K", "M3L", "M3M", "M3N":
            return ("5350301.00", "North York")

        // Etobicoke FSAs
        case "M8V", "M8W", "M8X", "M8Y", "M8Z", "M9A", "M9B", "M9C", "M9P", "M9R", "M9V", "M9W":
            return ("5350401.00", "Etobicoke")

        // East York FSAs
        case "M4C", "M4E", "M4G", "M4H", "M4J", "M4K", "M4L", "M4M":
            return ("5350501.00", "East York")

        // York FSAs
        case "M6A", "M6B", "M6C", "M6E", "M6L", "M6M", "M6N":
            return ("5350601.00", "York")

        default:
            return ("5350000.00", "Greater Toronto Area")
        }
    }
}

// MARK: - Production Enhancement Instructions

/*
 For production use with real census tract data:

 1. **Purchase Statistics Canada PCCF**:
    - Get the Postal Code Conversion File from Statistics Canada
    - URL: https://www150.statcan.gc.ca/n1/en/catalogue/92-154-X
    - Cost: ~$200-$500 depending on version

 2. **Load PCCF Data**:
    - Import the CSV/database into your app
    - Create a lookup table: PostalCode -> Census Tract ID

 3. **GeoJSON Boundaries**:
    - Download census tract boundary files from Statistics Canada
    - URL: https://www12.statcan.gc.ca/census-recensement/2021/geo/sip-pis/boundary-limites/index-eng.cfm
    - Use GeoJSON to determine exact tract for any coordinate

 4. **Alternative Free Options**:
    - Use CensusMapper API (requires free API key)
    - Use OpenStreetMap Nominatim (less precise)
    - Contribute to crowdsourced postal code databases

 5. **Database Schema**:
    CREATE TABLE postal_code_conversion (
        postal_code VARCHAR(6) PRIMARY KEY,
        census_tract_id VARCHAR(10),
        latitude DECIMAL(9,6),
        longitude DECIMAL(9,6),
        province VARCHAR(2)
    );
 */