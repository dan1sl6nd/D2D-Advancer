import SwiftUI
import CoreData
import MapKit
import CoreLocation

struct RoutePlannerSheet: View {
    enum RouteFilter: String, CaseIterable, Identifiable {
        case followUps
        case thisArea

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .followUps: return "Due Today"
            case .thisArea:  return "This Area"
            }
        }

        var icon: String {
            switch self {
            case .followUps: return "calendar.badge.exclamationmark"
            case .thisArea:  return "map.circle.fill"
            }
        }

        var emptyStateTitle: String {
            switch self {
            case .followUps: return "No follow-ups due today"
            case .thisArea:  return "No leads in this area"
            }
        }

        var emptyStateMessage: String {
            switch self {
            case .followUps:
                return "Leads with a follow-up date of today or overdue will appear here, ordered by the shortest route from your current location."
            case .thisArea:
                return "Pan the map to the neighbourhood you want to work, then open the route planner again. Every live lead inside that view will be ordered optimally."
            }
        }
    }

    let region: MKCoordinateRegion

    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext
    @ObservedObject private var locationManager = LocationManager.shared

    @State private var filter: RouteFilter = .followUps
    @State private var plan: RoutePlan?
    @State private var isComputing = false
    @State private var visitedStopIds: Set<UUID> = []

    // Fetch all leads that aren't already closed. Filtering by follow-up date
    // vs. map region happens in-memory via `RouteOptimizer` so we can swap
    // filters live without re-hitting Core Data.
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Lead.followUpDate, ascending: true)],
        predicate: NSPredicate(format: "NOT (status IN %@)", ["converted", "not_interested"]),
        animation: .default
    ) private var candidateLeads: FetchedResults<Lead>

    var body: some View {
        NavigationStack {
            ZStack {
                Color.obsidianBlack.ignoresSafeArea()

                VStack(spacing: 0) {
                    ObsidianScreenTitle(
                        title: "Route Planner",
                        subtitle: "Order today's stops or leads in the visible map area.",
                        icon: "point.topleft.down.curvedto.point.bottomright.up"
                    )
                    .padding(.horizontal, 20)
                    .padding(.top, 16)

                    filterPicker

                    if let plan = plan, !plan.isEmpty {
                        routeContent(plan: plan)
                    } else if isComputing {
                        progressView
                    } else {
                        emptyState
                    }
                }
            }
            .navigationTitle("Route Planner")
            .obsidianInlineNavigation()
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.obsidianCaption.weight(.semibold))
                            .foregroundColor(Color.textSecondary)
                            .frame(width: 30, height: 30)
                            .background(Color.obsidianElevated)
                            .clipShape(Circle())
                    }
                    .accessibilityLabel("Close")
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: recompute) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.obsidianCaption.weight(.semibold))
                            .foregroundColor(Color.electricViolet)
                            .frame(width: 30, height: 30)
                            .background(Color.obsidianElevated)
                            .clipShape(Circle())
                    }
                    .disabled(isComputing)
                    .accessibilityLabel("Recompute route")
                }
            }
        }
        .onAppear(perform: recompute)
    }

    // MARK: - States

    private var filterPicker: some View {
        HStack(spacing: 6) {
            ForEach(RouteFilter.allCases) { option in
                Button {
                    guard filter != option else { return }
                    withAnimation(.easeInOut(duration: 0.2)) {
                        filter = option
                    }
                    recompute()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: option.icon)
                            .font(.obsidianSmall)
                        Text(option.displayName)
                            .font(.obsidianCaption)
                            .fontWeight(.semibold)
                    }
                    .foregroundColor(filter == option ? .white : Color.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(filter == option ? Color.electricViolet : Color.clear)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(Color.obsidianSurface)
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(Color.obsidianBorder, lineWidth: 0.5)
        )
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 10)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: filter.icon)
                .font(.system(size: 56))
                .foregroundColor(Color.textSecondary.opacity(0.6))
            Text(filter.emptyStateTitle)
                .font(.obsidianTitle)
                .foregroundColor(Color.textPrimary)
            Text(filter.emptyStateMessage)
                .font(.obsidianFootnote)
                .foregroundColor(Color.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
        }
    }

    private var progressView: some View {
        VStack(spacing: 14) {
            ProgressView()
                .tint(Color.electricViolet)
                .scaleEffect(1.2)
            Text("Computing route…")
                .font(.obsidianFootnote)
                .foregroundColor(Color.textSecondary)
        }
    }

    private func routeContent(plan: RoutePlan) -> some View {
        VStack(spacing: 0) {
            summaryHeader(plan: plan)
            stopsList(plan: plan)
            navigateAllBar(plan: plan)
        }
    }

    // MARK: - Pieces

    private func summaryHeader(plan: RoutePlan) -> some View {
        HStack(spacing: 20) {
            summaryStat(value: "\(plan.stops.count)", label: plan.stops.count == 1 ? "stop" : "stops")
            summaryStat(value: plan.totalDistanceFormatted, label: "distance")
            summaryStat(value: plan.totalDurationFormatted, label: "est. time")
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .padding(.horizontal, 20)
        .background(Color.obsidianSurface)
        .overlay(
            Rectangle()
                .fill(Color.obsidianBorder)
                .frame(height: 0.5),
            alignment: .bottom
        )
    }

    private func summaryStat(value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.obsidianAction)
                .foregroundColor(Color.textPrimary)
            Text(label.uppercased())
                .font(.obsidianSmall)
                .foregroundColor(Color.textSecondary)
                .kerning(0.5)
        }
        .frame(maxWidth: .infinity)
    }

    private func stopsList(plan: RoutePlan) -> some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                ForEach(plan.stops) { stop in
                    stopRow(stop: stop)
                }
                Spacer(minLength: 20)
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
        }
    }

    private func stopRow(stop: RouteStop) -> some View {
        let isVisited = visitedStopIds.contains(stop.id)
        return HStack(alignment: .top, spacing: 12) {
            orderBadge(order: stop.order, visited: isVisited)

            VStack(alignment: .leading, spacing: 6) {
                Text(stop.lead.displayName)
                    .font(.obsidianTitle)
                    .foregroundColor(isVisited ? Color.textSecondary : Color.textPrimary)
                    .strikethrough(isVisited, color: Color.textSecondary)

                if let address = stop.lead.address, !address.isEmpty {
                    Text(address)
                        .font(.obsidianFootnote)
                        .foregroundColor(Color.textSecondary)
                        .lineLimit(2)
                }

                HStack(spacing: 8) {
                    Label(distanceLabel(stop.distanceFromPrevious), systemImage: "figure.walk.arrival")
                        .font(.obsidianCaption)
                        .foregroundColor(Color.textMuted)
                    if let status = stop.lead.status, !status.isEmpty {
                        Text("·").foregroundColor(Color.textMuted).font(.obsidianCaption)
                        Text(displayStatus(status))
                            .font(.obsidianCaption)
                            .foregroundColor(Color.textMuted)
                    }
                }
            }

            Spacer()

            VStack(spacing: 8) {
                Button(action: { navigate(to: stop) }) {
                    Image(systemName: "location.north.line.fill")
                        .font(.obsidianCallout)
                        .foregroundColor(.white)
                        .frame(width: 38, height: 38)
                        .background(
                            LinearGradient(
                                colors: [Color.electricViolet, Color.electricVioletDeep],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .clipShape(Circle())
                }
                .accessibilityLabel("Navigate to \(stop.lead.displayName)")

                Button(action: { toggleVisited(stop: stop) }) {
                    Image(systemName: isVisited ? "arrow.uturn.backward.circle" : "checkmark.circle")
                        .font(.obsidianCallout)
                        .foregroundColor(isVisited ? Color.textMuted : Color.statusInterested)
                }
                .accessibilityLabel(isVisited ? "Mark as not visited" : "Mark as visited")
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.obsidianSurface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.obsidianBorder.opacity(0.5), lineWidth: 0.5)
        )
        .opacity(isVisited ? 0.6 : 1.0)
    }

    private func orderBadge(order: Int, visited: Bool) -> some View {
        ZStack {
            Circle()
                .fill(visited ? Color.obsidianElevated : Color.electricViolet.opacity(0.15))
                .frame(width: 32, height: 32)
            if visited {
                Image(systemName: "checkmark")
                    .font(.obsidianCallout.bold())
                    .foregroundColor(Color.statusInterested)
            } else {
                Text("\(order)")
                    .font(.obsidianCallout.bold())
                    .foregroundColor(Color.electricViolet)
            }
        }
    }

    private func navigateAllBar(plan: RoutePlan) -> some View {
        let firstUnvisited = plan.stops.first { !visitedStopIds.contains($0.id) }
        return VStack(spacing: 10) {
            Button(action: {
                if let stop = firstUnvisited {
                    navigate(to: stop)
                }
            }) {
                HStack(spacing: 10) {
                    Image(systemName: "location.north.line.fill")
                        .font(.obsidianAction)
                    VStack(spacing: 2) {
                        Text(firstUnvisited == nil ? "All Stops Visited" : "Start Route")
                            .font(.obsidianTitle)
                        if let stop = firstUnvisited {
                            Text("Navigate to \(stop.lead.displayName)")
                                .font(.obsidianCaption)
                                .opacity(0.85)
                        }
                    }
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(ObsidianPrimaryButtonStyle())
            .disabled(firstUnvisited == nil)
            .opacity(firstUnvisited == nil ? 0.6 : 1)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(
            Color.obsidianSurface
                .overlay(
                    Rectangle()
                        .fill(Color.obsidianBorder)
                        .frame(height: 0.5),
                    alignment: .top
                )
        )
    }

    // MARK: - Actions

    private func recompute() {
        isComputing = true

        // Compute on a background queue to keep the UI responsive for large
        // candidate lists; the algorithm itself is fast but a synchronous hop
        // is still perceptible as jank on a cold sheet open.
        let start = locationManager.location?.coordinate ?? region.center
        let allLeads = Array(candidateLeads)
        let currentRegion = region
        let selectedFilter = filter

        DispatchQueue.global(qos: .userInitiated).async {
            let candidates: [Lead]
            switch selectedFilter {
            case .followUps:
                candidates = RouteOptimizer.followUpsDueToday(from: allLeads)
            case .thisArea:
                candidates = RouteOptimizer.leadsInRegion(from: allLeads, region: currentRegion)
            }
            let computed = RouteOptimizer.optimize(leads: candidates, startingFrom: start)
            DispatchQueue.main.async {
                self.plan = computed
                self.isComputing = false
            }
        }
    }

    private func navigate(to stop: RouteStop) {
        let placemark = MKPlacemark(coordinate: stop.lead.coordinate)
        let item = MKMapItem(placemark: placemark)
        item.name = stop.lead.displayName
        item.openInMaps(launchOptions: [
            MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving
        ])
    }

    private func toggleVisited(stop: RouteStop) {
        withAnimation(.easeInOut(duration: 0.2)) {
            if visitedStopIds.contains(stop.id) {
                visitedStopIds.remove(stop.id)
            } else {
                visitedStopIds.insert(stop.id)
            }
        }
    }

    // MARK: - Formatting

    private func distanceLabel(_ meters: CLLocationDistance) -> String {
        guard meters > 0 else { return "Start" }
        if meters < 1000 {
            return "\(Int(meters.rounded())) m"
        }
        return String(format: "%.1f km", meters / 1000)
    }

    private func displayStatus(_ raw: String) -> String {
        raw.replacingOccurrences(of: "_", with: " ").capitalized
    }
}
