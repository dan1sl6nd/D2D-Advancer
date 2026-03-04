import Foundation
import MapKit
import CoreLocation

/// A single stop in an optimized route.
struct RouteStop {
    let lead: Lead
    let order: Int
    let estimatedArrival: Date?
    let drivingDurationFromPrevious: TimeInterval? // seconds
    let distanceFromPrevious: CLLocationDistance? // meters
}

/// Result of route optimization.
struct OptimizedRoute {
    let stops: [RouteStop]
    let totalDuration: TimeInterval
    let totalDistance: CLLocationDistance
    let polyline: MKPolyline?
}

@MainActor
class RouteOptimizer: ObservableObject {
    @Published var currentRoute: OptimizedRoute?
    @Published var isCalculating = false

    /// Optimizes visit order using nearest-neighbor heuristic + MKDirections refinement.
    @discardableResult
    func optimizeRoute(from start: CLLocationCoordinate2D, leads: [Lead]) async -> OptimizedRoute? {
        guard !leads.isEmpty else { return nil }
        isCalculating = true
        defer { isCalculating = false }

        var remaining = leads
        var ordered: [Lead] = []
        var currentLocation = start

        // Nearest-neighbor with MKDirections refinement for top candidates
        while !remaining.isEmpty {
            // Sort by haversine distance
            remaining.sort { lead1, lead2 in
                haversineDistance(from: currentLocation, to: lead1.coordinate) <
                haversineDistance(from: currentLocation, to: lead2.coordinate)
            }

            // Take top 3 candidates and get driving ETAs
            let candidates = Array(remaining.prefix(min(3, remaining.count)))

            if candidates.count == 1 {
                ordered.append(candidates[0])
                remaining.removeAll { $0.id == candidates[0].id }
                currentLocation = candidates[0].coordinate
                continue
            }

            // Get driving times for top candidates
            let best = await bestByDrivingTime(from: currentLocation, candidates: candidates)
            ordered.append(best)
            remaining.removeAll { $0.id == best.id }
            currentLocation = best.coordinate
        }

        // Respect appointment time windows: reorder leads with appointments to their correct slot
        let reordered = adjustForAppointments(ordered, startTime: Date(), startLocation: start)

        // Build route with ETAs
        let route = await buildRouteDetails(from: start, leads: reordered)
        currentRoute = route
        return route
    }

    /// Clears the current route.
    func clearRoute() {
        currentRoute = nil
    }

    // MARK: - Private

    private func haversineDistance(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) -> CLLocationDistance {
        let loc1 = CLLocation(latitude: from.latitude, longitude: from.longitude)
        let loc2 = CLLocation(latitude: to.latitude, longitude: to.longitude)
        return loc1.distance(from: loc2)
    }

    private func bestByDrivingTime(from: CLLocationCoordinate2D, candidates: [Lead]) async -> Lead {
        // Request MKDirections for each candidate
        var results: [(lead: Lead, eta: TimeInterval)] = []

        await withTaskGroup(of: (Lead, TimeInterval?).self) { group in
            for lead in candidates {
                group.addTask {
                    let eta = await self.getDrivingETA(from: from, to: lead.coordinate)
                    return (lead, eta)
                }
            }
            for await result in group {
                let eta = result.1 ?? self.haversineDistance(from: from, to: result.0.coordinate) / 13.0 // ~47km/h fallback
                results.append((result.0, eta))
            }
        }

        return results.min(by: { $0.eta < $1.eta })?.lead ?? candidates[0]
    }

    private nonisolated func getDrivingETA(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) async -> TimeInterval? {
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: from))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: to))
        request.transportType = .automobile

        do {
            let response = try await MKDirections(request: request).calculateETA()
            return response.expectedTravelTime
        } catch {
            return nil
        }
    }

    private func adjustForAppointments(_ leads: [Lead], startTime: Date, startLocation: CLLocationCoordinate2D) -> [Lead] {
        // Separate leads with and without appointment times
        var withAppointment: [(lead: Lead, time: Date)] = []
        var withoutAppointment: [Lead] = []

        for lead in leads {
            if let followUp = lead.followUpDate {
                withAppointment.append((lead, followUp))
            } else {
                withoutAppointment.append(lead)
            }
        }

        // If no appointments, return original order
        guard !withAppointment.isEmpty else { return leads }

        // Sort appointments by time
        withAppointment.sort { $0.time < $1.time }

        // Insert appointment leads at their correct time slots
        var result: [Lead] = []
        var freeLeads = withoutAppointment
        var appointmentIdx = 0
        var currentTime = startTime

        // Estimate ~10 min per stop + 5 min driving average
        let avgStopTime: TimeInterval = 15 * 60

        while appointmentIdx < withAppointment.count || !freeLeads.isEmpty {
            if appointmentIdx < withAppointment.count {
                let nextAppointment = withAppointment[appointmentIdx]
                let timeUntilAppointment = nextAppointment.time.timeIntervalSince(currentTime)

                // Fill time with free leads
                while !freeLeads.isEmpty && timeUntilAppointment > avgStopTime {
                    result.append(freeLeads.removeFirst())
                    currentTime = currentTime.addingTimeInterval(avgStopTime)
                    let remaining = nextAppointment.time.timeIntervalSince(currentTime)
                    if remaining <= avgStopTime { break }
                }

                result.append(nextAppointment.lead)
                currentTime = nextAppointment.time.addingTimeInterval(avgStopTime)
                appointmentIdx += 1
            } else {
                result.append(contentsOf: freeLeads)
                freeLeads.removeAll()
            }
        }

        return result
    }

    private func buildRouteDetails(from start: CLLocationCoordinate2D, leads: [Lead]) async -> OptimizedRoute {
        var stops: [RouteStop] = []
        var totalDuration: TimeInterval = 0
        var totalDistance: CLLocationDistance = 0
        var currentLocation = start
        var currentTime = Date()
        var allCoordinates: [CLLocationCoordinate2D] = [start]

        for (index, lead) in leads.enumerated() {
            let eta = await getDrivingETA(from: currentLocation, to: lead.coordinate)
            let distance = haversineDistance(from: currentLocation, to: lead.coordinate)
            let duration = eta ?? (distance / 13.0) // fallback ~47km/h

            currentTime = currentTime.addingTimeInterval(duration)
            totalDuration += duration
            totalDistance += distance

            stops.append(RouteStop(
                lead: lead,
                order: index + 1,
                estimatedArrival: currentTime,
                drivingDurationFromPrevious: duration,
                distanceFromPrevious: distance
            ))

            allCoordinates.append(lead.coordinate)
            currentLocation = lead.coordinate
        }

        let polyline = MKPolyline(coordinates: allCoordinates, count: allCoordinates.count)

        return OptimizedRoute(
            stops: stops,
            totalDuration: totalDuration,
            totalDistance: totalDistance,
            polyline: polyline
        )
    }
}
