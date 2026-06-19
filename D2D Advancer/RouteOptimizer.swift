import Foundation
import CoreLocation
import MapKit

// MARK: - Types

struct RouteStop: Identifiable, Equatable {
    let id = UUID()
    let lead: Lead
    let order: Int
    let distanceFromPrevious: CLLocationDistance

    static func == (lhs: RouteStop, rhs: RouteStop) -> Bool {
        lhs.id == rhs.id
    }
}

struct RoutePlan: Equatable {
    let stops: [RouteStop]
    let startLocation: CLLocationCoordinate2D
    let totalDistanceMeters: CLLocationDistance
    let totalDurationEstimateSeconds: TimeInterval

    var isEmpty: Bool { stops.isEmpty }

    var totalDistanceFormatted: String {
        let formatter = MeasurementFormatter()
        formatter.unitOptions = .naturalScale
        formatter.numberFormatter.maximumFractionDigits = 1
        let measurement = Measurement(value: totalDistanceMeters, unit: UnitLength.meters)
        return formatter.string(from: measurement)
    }

    var totalDurationFormatted: String {
        let totalMinutes = Int(totalDurationEstimateSeconds / 60)
        if totalMinutes < 60 {
            return "\(totalMinutes) min"
        }
        let hours = totalMinutes / 60
        let remainingMinutes = totalMinutes % 60
        return remainingMinutes == 0 ? "\(hours) hr" : "\(hours) hr \(remainingMinutes) min"
    }

    static func == (lhs: RoutePlan, rhs: RoutePlan) -> Bool {
        lhs.stops == rhs.stops
    }
}

// MARK: - Optimizer

enum RouteOptimizer {

    /// Average urban travel speed in m/s (25 km/h ≈ 6.94 m/s). This blends
    /// driving between clusters with walking/idling between adjacent doors,
    /// which is how door-to-door work actually plays out. Override per-call
    /// if callers want strict walking (1.4 m/s) or strict driving (11 m/s).
    private static let defaultSpeedMetersPerSecond: Double = 6.94

    /// Compute an ordered route from `start` through all `leads` using a
    /// nearest-neighbor greedy heuristic. Runs O(n²) which is fine for the
    /// small-to-medium stop counts D2D planning produces (typically 5–30).
    ///
    /// The algorithm is sub-optimal for large n — it can produce routes 10–25%
    /// longer than the true TSP optimum — but each pass is deterministic and
    /// fast (<1 ms for n=30). For D2D workflows the sub-optimality is
    /// irrelevant compared to the time saved over guessing.
    static func optimize(
        leads: [Lead],
        startingFrom start: CLLocationCoordinate2D,
        averageSpeedMetersPerSecond: Double = defaultSpeedMetersPerSecond
    ) -> RoutePlan {
        guard !leads.isEmpty else {
            return RoutePlan(
                stops: [],
                startLocation: start,
                totalDistanceMeters: 0,
                totalDurationEstimateSeconds: 0
            )
        }

        var remaining = leads
        var ordered: [RouteStop] = []
        var cursor = start
        var totalDistance: CLLocationDistance = 0

        while !remaining.isEmpty {
            guard let nearestIndex = indexOfNearestLead(to: cursor, in: remaining) else { break }
            let lead = remaining[nearestIndex]
            let distance = distanceBetween(cursor, and: lead.coordinate)
            totalDistance += distance
            ordered.append(
                RouteStop(
                    lead: lead,
                    order: ordered.count + 1,
                    distanceFromPrevious: distance
                )
            )
            cursor = lead.coordinate
            remaining.remove(at: nearestIndex)
        }

        // Apply one 2-opt improvement pass. This is a common TSP heuristic
        // refinement: repeatedly reverse sub-paths if doing so shortens the
        // total distance. Single pass is a good cost/quality trade-off for
        // interactive UI.
        let improved = twoOptImprove(stops: ordered, start: start)
        let improvedDistance = improved.reduce(0) { $0 + $1.distanceFromPrevious }
        let finalStops = improvedDistance < totalDistance ? improved : ordered
        let finalDistance = improvedDistance < totalDistance ? improvedDistance : totalDistance

        let duration = averageSpeedMetersPerSecond > 0 ? finalDistance / averageSpeedMetersPerSecond : 0
        return RoutePlan(
            stops: finalStops,
            startLocation: start,
            totalDistanceMeters: finalDistance,
            totalDurationEstimateSeconds: duration
        )
    }

    // MARK: - Private helpers

    private static func indexOfNearestLead(
        to location: CLLocationCoordinate2D,
        in leads: [Lead]
    ) -> Int? {
        var bestIndex: Int?
        var bestDistance = CLLocationDistance.infinity
        for (index, lead) in leads.enumerated() {
            let d = distanceBetween(location, and: lead.coordinate)
            if d < bestDistance {
                bestDistance = d
                bestIndex = index
            }
        }
        return bestIndex
    }

    private static func distanceBetween(
        _ a: CLLocationCoordinate2D,
        and b: CLLocationCoordinate2D
    ) -> CLLocationDistance {
        let locA = CLLocation(latitude: a.latitude, longitude: a.longitude)
        let locB = CLLocation(latitude: b.latitude, longitude: b.longitude)
        return locA.distance(from: locB)
    }

    /// 2-opt: tries reversing every sub-path of length ≥ 2 and keeps any
    /// reversal that reduces total distance. A single pass is enough to catch
    /// the "obvious" crossings in a nearest-neighbor result.
    private static func twoOptImprove(
        stops: [RouteStop],
        start: CLLocationCoordinate2D
    ) -> [RouteStop] {
        guard stops.count >= 4 else { return stops }

        var leads = stops.map { $0.lead }
        var improved = true
        var iterations = 0
        let maxIterations = 3 // keep it bounded even on pathological inputs

        while improved && iterations < maxIterations {
            improved = false
            iterations += 1

            for i in 0..<(leads.count - 1) {
                for j in (i + 1)..<leads.count {
                    if shouldSwap(leads: leads, start: start, i: i, j: j) {
                        leads[i...j].reverse()
                        improved = true
                    }
                }
            }
        }

        return rebuildStops(from: leads, start: start)
    }

    private static func shouldSwap(
        leads: [Lead],
        start: CLLocationCoordinate2D,
        i: Int,
        j: Int
    ) -> Bool {
        let before = distance(from: previousCoordinate(leads: leads, index: i, start: start), to: leads[i].coordinate)
                   + distance(from: leads[j].coordinate, to: nextCoordinate(leads: leads, index: j))
        let after = distance(from: previousCoordinate(leads: leads, index: i, start: start), to: leads[j].coordinate)
                   + distance(from: leads[i].coordinate, to: nextCoordinate(leads: leads, index: j))
        return after < before
    }

    private static func previousCoordinate(
        leads: [Lead],
        index: Int,
        start: CLLocationCoordinate2D
    ) -> CLLocationCoordinate2D {
        index == 0 ? start : leads[index - 1].coordinate
    }

    private static func nextCoordinate(
        leads: [Lead],
        index: Int
    ) -> CLLocationCoordinate2D {
        // When j is the last stop, we treat "next" as the same point (we don't
        // optimize returning to the start — D2D routes are typically one-way).
        index == leads.count - 1 ? leads[index].coordinate : leads[index + 1].coordinate
    }

    private static func distance(
        from a: CLLocationCoordinate2D,
        to b: CLLocationCoordinate2D
    ) -> CLLocationDistance {
        distanceBetween(a, and: b)
    }

    private static func rebuildStops(
        from leads: [Lead],
        start: CLLocationCoordinate2D
    ) -> [RouteStop] {
        var stops: [RouteStop] = []
        var cursor = start
        for (index, lead) in leads.enumerated() {
            let d = distanceBetween(cursor, and: lead.coordinate)
            stops.append(
                RouteStop(
                    lead: lead,
                    order: index + 1,
                    distanceFromPrevious: d
                )
            )
            cursor = lead.coordinate
        }
        return stops
    }

    // MARK: - Candidate selection

    /// Returns leads with a follow-up date due today or overdue. This is the
    /// default set of "route candidates" a D2D rep wants to visit today.
    /// Sorted by followUpDate ascending so the oldest overdue items surface first.
    static func followUpsDueToday(from allLeads: [Lead], referenceDate: Date = Date()) -> [Lead] {
        let endOfDay = Calendar.current
            .date(bySettingHour: 23, minute: 59, second: 59, of: referenceDate) ?? referenceDate

        let filtered = allLeads.filter { lead in
            isRouteCandidate(lead, endOfDay: endOfDay)
        }
        return filtered.sorted { a, b in
            let aDate = a.followUpDate ?? Date.distantFuture
            let bDate = b.followUpDate ?? Date.distantFuture
            return aDate < bDate
        }
    }

    /// Route-candidate predicate extracted so the type-checker can resolve it
    /// in reasonable time (a chained filter/sort closure on a Core Data type
    /// was tripping the "expression too complex" compiler warning).
    private static func isRouteCandidate(_ lead: Lead, endOfDay: Date) -> Bool {
        guard let due = lead.followUpDate else { return false }
        let status = lead.status ?? ""
        if status == "converted" || status == "not_interested" {
            return false
        }
        return due <= endOfDay
    }

    /// Returns leads whose coordinates fall inside the supplied map region,
    /// excluding statuses the rep has already closed out (`converted`,
    /// `not_interested`). Used by the "This Area" route mode — the rep pans
    /// the map to the neighborhood they're about to work, then opens the
    /// route planner, and gets every live lead visible on screen.
    static func leadsInRegion(from allLeads: [Lead], region: MKCoordinateRegion) -> [Lead] {
        let minLat = region.center.latitude - region.span.latitudeDelta / 2
        let maxLat = region.center.latitude + region.span.latitudeDelta / 2
        let minLon = region.center.longitude - region.span.longitudeDelta / 2
        let maxLon = region.center.longitude + region.span.longitudeDelta / 2

        return allLeads.filter { lead in
            isAreaCandidate(lead, minLat: minLat, maxLat: maxLat, minLon: minLon, maxLon: maxLon)
        }
    }

    private static func isAreaCandidate(
        _ lead: Lead,
        minLat: Double,
        maxLat: Double,
        minLon: Double,
        maxLon: Double
    ) -> Bool {
        let status = lead.status ?? ""
        if status == "converted" || status == "not_interested" {
            return false
        }
        let lat = lead.latitude
        let lon = lead.longitude
        // Leads with (0, 0) coordinates are placeholders from legacy imports;
        // exclude so we don't route to the middle of the Atlantic.
        if lat == 0 && lon == 0 { return false }
        return lat >= minLat && lat <= maxLat && lon >= minLon && lon <= maxLon
    }
}
