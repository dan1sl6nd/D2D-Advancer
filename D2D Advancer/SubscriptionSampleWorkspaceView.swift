import MapKit
import SwiftUI

struct SubscriptionSampleWorkspaceView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss

    let offering: PaywallManager.Offering

    @State private var selectedTab: SampleTab = .map
    @State private var selectedLead: SampleLead?
    @State private var mapPosition: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 43.5915, longitude: -79.6434),
            span: MKCoordinateSpan(latitudeDelta: 0.024, longitudeDelta: 0.024)
        )
    )

    init(offering: PaywallManager.Offering = .solo) {
        self.offering = offering
    }

    var body: some View {
        ZStack {
            Color.obsidianBackground(for: colorScheme)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                header
                readOnlyBanner
                content
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            tabBar
        }
        .sheet(item: $selectedLead) { lead in
            sampleLeadDetails(lead)
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(offering == .team ? "Sample Team Workspace" : "Sample Workspace")
                    .font(.displayMedium)
                    .foregroundColor(.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .accessibilityIdentifier("sampleWorkspaceScreen")

                Text("Mississauga route")
                    .font(.obsidianCaption)
                    .foregroundColor(.textSecondary)
            }

            Spacer(minLength: 8)

            ObsidianCloseButton(
                accessibilityLabel: "Close sample workspace",
                accessibilityIdentifier: "sampleWorkspaceCloseButton"
            ) {
                dismiss()
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Color.obsidianBackground(for: colorScheme))
    }

    private var readOnlyBanner: some View {
        HStack(spacing: 9) {
            Image(systemName: "eye.fill")
                .foregroundColor(.electricViolet)
            Text("Sample data")
                .font(.obsidianSmall)
                .foregroundColor(.textPrimary)
            Text("Read only")
                .font(.nano)
                .foregroundColor(.textSecondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.obsidianElevated)
                .clipShape(Capsule())
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 10)
    }

    @ViewBuilder
    private var content: some View {
        switch selectedTab {
        case .map:
            sampleMap
        case .leads:
            leadList(leads)
        case .followUp:
            leadList(leads.filter { $0.followUp != nil })
        case .schedule:
            scheduleList
        }
    }

    private var sampleMap: some View {
        Map(position: $mapPosition, interactionModes: [.pan, .zoom]) {
            ForEach(leads) { lead in
                Annotation(lead.name, coordinate: lead.coordinate, anchor: .bottom) {
                    Button {
                        selectedLead = lead
                    } label: {
                        VStack(spacing: 4) {
                            Text(lead.name)
                                .font(.nano)
                                .foregroundColor(.textPrimary)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 4)
                                .background(Color.obsidianSurface.opacity(0.94))
                                .clipShape(Capsule())

                            Image(systemName: lead.status.icon)
                                .font(.obsidianCaption)
                                .foregroundColor(.white)
                                .frame(width: 34, height: 34)
                                .background(lead.status.color)
                                .clipShape(Circle())
                                .overlay(Circle().stroke(Color.white.opacity(0.9), lineWidth: 2))
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Open sample lead \(lead.name)")
                }
            }
        }
        .mapStyle(.standard(elevation: .flat))
        .mapControls {
            MapCompass()
        }
        .overlay(alignment: .bottom) {
            HStack(spacing: 10) {
                sampleMetric(value: "2", label: "Due", color: .statusNotHome)
                sampleMetric(value: "$3.6K", label: "Sold", color: .statusConverted)
                sampleMetric(value: "3", label: "Stops", color: .statusInterested)
            }
            .padding(12)
            .background(Color.obsidianSurface.opacity(0.96))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.obsidianBorder.opacity(0.6), lineWidth: 0.5)
            )
            .padding(16)
        }
    }

    private func sampleMetric(value: String, label: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.obsidianTitle)
                .foregroundColor(color)
            Text(label)
                .font(.nano)
                .foregroundColor(.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func leadList(_ visibleLeads: [SampleLead]) -> some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(spacing: 10) {
                ForEach(visibleLeads) { lead in
                    Button {
                        selectedLead = lead
                    } label: {
                        sampleLeadRow(lead)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
        }
    }

    private func sampleLeadRow(_ lead: SampleLead) -> some View {
        HStack(spacing: 12) {
            Image(systemName: lead.status.icon)
                .font(.obsidianCallout)
                .foregroundColor(lead.status.color)
                .frame(width: 40, height: 40)
                .background(lead.status.color.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 7) {
                    Text(lead.name)
                        .font(.obsidianTitle)
                        .foregroundColor(.textPrimary)
                    Text(lead.status.title)
                        .font(.nano)
                        .foregroundColor(lead.status.color)
                }
                Text(lead.address)
                    .font(.obsidianCaption)
                    .foregroundColor(.textSecondary)
                    .lineLimit(1)
                if offering == .team {
                    Text("Assigned to \(lead.assignee)")
                        .font(.nano)
                        .foregroundColor(.textSecondary)
                }
            }

            Spacer(minLength: 8)
            Text(lead.value)
                .font(.obsidianHeadline)
                .foregroundColor(.textPrimary)
        }
        .padding(14)
        .background(Color.obsidianSurface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.obsidianBorder.opacity(0.55), lineWidth: 0.5)
        )
    }

    private var scheduleList: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(spacing: 10) {
                ForEach(leads.filter { $0.arrival != nil }) { lead in
                    HStack(spacing: 12) {
                        Image(systemName: "calendar.badge.clock")
                            .font(.obsidianCallout)
                            .foregroundColor(.statusConverted)
                            .frame(width: 40, height: 40)
                            .background(Color.statusConverted.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                        VStack(alignment: .leading, spacing: 4) {
                            Text(lead.service)
                                .font(.obsidianTitle)
                                .foregroundColor(.textPrimary)
                            Text("\(lead.name) • \(lead.arrival ?? "")")
                                .font(.obsidianCaption)
                                .foregroundColor(.textSecondary)
                            if offering == .team {
                                Text("Assigned to \(lead.assignee)")
                                    .font(.nano)
                                    .foregroundColor(.textSecondary)
                            }
                        }
                        Spacer()
                    }
                    .padding(14)
                    .background(Color.obsidianSurface)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color.obsidianBorder.opacity(0.55), lineWidth: 0.5)
                    )
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
        }
    }

    private var tabBar: some View {
        HStack(spacing: 4) {
            ForEach(SampleTab.allCases) { tab in
                Button {
                    selectedTab = tab
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: tab.icon)
                            .font(.obsidianCallout)
                        Text(tab.title)
                            .font(.nano)
                            .lineLimit(1)
                    }
                    .foregroundColor(selectedTab == tab ? .electricViolet : .textSecondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(selectedTab == tab ? Color.electricViolet.opacity(0.1) : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("sampleWorkspaceTab_\(tab.rawValue)")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.obsidianBackground(for: colorScheme))
        .overlay(Rectangle().fill(Color.obsidianBorder.opacity(0.5)).frame(height: 0.5), alignment: .top)
    }

    private func sampleLeadDetails(_ lead: SampleLead) -> some View {
        ZStack {
            Color.obsidianBackground(for: colorScheme).ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(lead.name)
                                .font(.displayMedium)
                                .foregroundColor(.textPrimary)
                            Text(lead.status.title)
                                .font(.obsidianCaption)
                                .foregroundColor(lead.status.color)
                        }
                        Spacer()
                        ObsidianCloseButton { selectedLead = nil }
                    }

                    ObsidianSectionCard(title: "Lead", icon: "person.text.rectangle", accentColor: lead.status.color) {
                        detailRow("Address", value: lead.address)
                        detailRow("Service", value: lead.service)
                        detailRow("Value", value: lead.value)
                        if offering == .team {
                            detailRow("Assigned", value: lead.assignee)
                        }
                    }

                    if let followUp = lead.followUp {
                        ObsidianSectionCard(title: "Next step", icon: "arrow.forward.circle.fill", accentColor: .statusNotHome) {
                            detailRow("Follow up", value: followUp)
                        }
                    }
                }
                .padding(20)
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func detailRow(_ label: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(label)
                .font(.obsidianCaption)
                .foregroundColor(.textSecondary)
                .frame(width: 74, alignment: .leading)
            Text(value)
                .font(.obsidianBody)
                .foregroundColor(.textPrimary)
            Spacer(minLength: 0)
        }
    }

    private var leads: [SampleLead] {
        [
            SampleLead(
                id: "avery-sold",
                name: "Avery",
                address: "100 City Centre Dr",
                coordinate: CLLocationCoordinate2D(latitude: 43.5932, longitude: -79.6411),
                status: .sold,
                service: "Window Cleaning",
                value: "$2,400",
                assignee: "Mike",
                followUp: nil,
                arrival: "Tomorrow, 9:30 AM"
            ),
            SampleLead(
                id: "jordan-interested",
                name: "Jordan",
                address: "201 City Centre Dr",
                coordinate: CLLocationCoordinate2D(latitude: 43.5899, longitude: -79.6447),
                status: .interested,
                service: "Gutter Cleaning",
                value: "$1,250",
                assignee: "Sofiia",
                followUp: "Today, 3:00 PM",
                arrival: nil
            ),
            SampleLead(
                id: "morgan-due",
                name: "Morgan",
                address: "300 City Centre Dr",
                coordinate: CLLocationCoordinate2D(latitude: 43.5878, longitude: -79.6423),
                status: .due,
                service: "Exterior Cleaning",
                value: "$980",
                assignee: "Mike",
                followUp: "Overdue by 1 hour",
                arrival: "Friday, 1:00 PM"
            )
        ]
    }
}

private enum SampleTab: String, CaseIterable, Identifiable {
    case map
    case leads
    case followUp
    case schedule

    var id: String { rawValue }

    var title: String {
        switch self {
        case .map: return "Map"
        case .leads: return "Leads"
        case .followUp: return "Follow Up"
        case .schedule: return "Schedule"
        }
    }

    var icon: String {
        switch self {
        case .map: return "map.fill"
        case .leads: return "person.2.fill"
        case .followUp: return "bell.fill"
        case .schedule: return "calendar"
        }
    }
}

private struct SampleLead: Identifiable {
    enum Status {
        case sold
        case interested
        case due

        var title: String {
            switch self {
            case .sold: return "Sold"
            case .interested: return "Interested"
            case .due: return "Due"
            }
        }

        var icon: String {
            switch self {
            case .sold: return "checkmark"
            case .interested: return "heart.fill"
            case .due: return "clock.fill"
            }
        }

        var color: Color {
            switch self {
            case .sold: return .statusConverted
            case .interested: return .statusInterested
            case .due: return .statusNotHome
            }
        }
    }

    let id: String
    let name: String
    let address: String
    let coordinate: CLLocationCoordinate2D
    let status: Status
    let service: String
    let value: String
    let assignee: String
    let followUp: String?
    let arrival: String?
}
