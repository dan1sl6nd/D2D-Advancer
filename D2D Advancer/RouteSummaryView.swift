import SwiftUI
import MapKit

struct RouteSummaryView: View {
    @ObservedObject var routeOptimizer: RouteOptimizer
    var onNavigate: () -> Void
    var onSkip: (Lead) -> Void
    var onComplete: (Lead) -> Void
    var onEndRoute: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Route Plan")
                        .font(.headline)
                        .foregroundColor(Color.textPrimary)
                    if let route = routeOptimizer.currentRoute {
                        Text("\(route.stops.count) stops \u{00B7} \(formatDuration(route.totalDuration)) \u{00B7} \(formatDistance(route.totalDistance))")
                            .font(.caption)
                            .foregroundColor(Color.textSecondary)
                    }
                }
                Spacer()
                Button("Navigate") {
                    onNavigate()
                }
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.electricViolet)
                .clipShape(Capsule())
            }
            .padding()
            .background(Color.obsidianSurface)

            // Stop list
            if let route = routeOptimizer.currentRoute {
                List {
                    ForEach(route.stops, id: \.lead.objectID) { stop in
                        HStack(spacing: 12) {
                            // Order number
                            Text("\(stop.order)")
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                                .frame(width: 28, height: 28)
                                .background(Color.electricViolet)
                                .clipShape(Circle())

                            VStack(alignment: .leading, spacing: 2) {
                                Text(stop.lead.displayName)
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .foregroundColor(Color.textPrimary)
                                if let address = stop.lead.address, !address.isEmpty {
                                    Text(address)
                                        .font(.caption)
                                        .foregroundColor(Color.textSecondary)
                                        .lineLimit(1)
                                }
                            }

                            Spacer()

                            VStack(alignment: .trailing, spacing: 2) {
                                if let eta = stop.estimatedArrival {
                                    Text(eta, style: .time)
                                        .font(.caption)
                                        .fontWeight(.medium)
                                        .foregroundColor(Color.textPrimary)
                                }
                                if let duration = stop.drivingDurationFromPrevious {
                                    Text(formatDuration(duration))
                                        .font(.caption2)
                                        .foregroundColor(Color.textMuted)
                                }
                            }
                        }
                        .listRowBackground(Color.obsidianSurface)
                        .swipeActions(edge: .trailing) {
                            Button("Skip") { onSkip(stop.lead) }
                                .tint(Color.statusNotHome)
                        }
                        .swipeActions(edge: .leading) {
                            Button("Done") { onComplete(stop.lead) }
                                .tint(Color.statusInterested)
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }

            // End route button
            Button(action: onEndRoute) {
                Text("End Route")
                    .font(.subheadline)
                    .foregroundColor(Color.statusNotInterested)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .background(Color.obsidianSurface)
        }
        .background(Color.obsidianBlack)
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes) min"
    }

    private func formatDistance(_ meters: CLLocationDistance) -> String {
        if meters >= 1000 {
            return String(format: "%.1f km", meters / 1000)
        }
        return "\(Int(meters)) m"
    }
}
