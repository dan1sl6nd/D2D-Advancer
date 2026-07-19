import CoreData
import MapKit
import MessageUI
import SwiftUI
import UIKit

enum FollowUpQueueItem: Identifiable {
    case personal(Lead)
    case team(TeamLead)

    var id: String {
        switch self {
        case .personal(let lead):
            return "personal:\(lead.objectID.uriRepresentation().absoluteString)"
        case .team(let lead):
            return "team:\(lead.id)"
        }
    }

    var name: String {
        switch self {
        case .personal(let lead): return lead.displayName
        case .team(let lead): return lead.name
        }
    }

    var address: String {
        switch self {
        case .personal(let lead): return lead.address ?? ""
        case .team(let lead): return lead.address
        }
    }

    var phone: String? {
        switch self {
        case .personal(let lead): return Self.normalized(lead.phone)
        case .team(let lead): return Self.normalized(lead.phone)
        }
    }

    var email: String? {
        switch self {
        case .personal(let lead): return Self.normalized(lead.email)
        case .team(let lead): return Self.normalized(lead.email)
        }
    }

    var dueDate: Date? {
        switch self {
        case .personal(let lead):
            return lead.followUpDate
        case .team(let lead):
            return lead.followUpDate ?? (lead.status == .followUp ? lead.updatedAt : nil)
        }
    }

    var lastContactDate: Date? {
        switch self {
        case .personal(let lead):
            return lead.lastCheckIn?.checkInDate ?? lead.lastContactDate
        case .team(let lead):
            return lead.lastContactedAt
        }
    }

    var lastContactSummary: String? {
        switch self {
        case .personal(let lead):
            guard let checkIn = lead.lastCheckIn else { return nil }
            let method = checkIn.checkInTypeEnum.displayName
            let outcome = checkIn.outcomeEnum?.displayName ?? "Contact recorded"
            return "\(method) · \(outcome)"
        case .team(let lead):
            return Self.normalized(lead.lastContactSummary)
        }
    }

    var sourceLabel: String {
        switch self {
        case .personal: return "Personal"
        case .team: return "Team"
        }
    }

    var assignedUserId: String? {
        switch self {
        case .personal: return nil
        case .team(let lead): return lead.assignedToUserId
        }
    }

    var statusLabel: String {
        switch self {
        case .personal(let lead): return lead.leadStatus.compactDisplayName
        case .team(let lead): return lead.status.followUpDisplayName
        }
    }

    var statusIsInterested: Bool {
        switch self {
        case .personal(let lead): return lead.leadStatus == .interested
        case .team(let lead): return lead.status == .interested
        }
    }

    var isHighPriority: Bool {
        switch self {
        case .personal(let lead): return lead.priority > 0
        case .team(let lead): return lead.isHighPriority
        }
    }

    var value: Double {
        switch self {
        case .personal(let lead): return max(lead.price, lead.estimatedValue)
        case .team(let lead): return max(lead.price, lead.estimatedValue)
        }
    }

    var coordinate: CLLocationCoordinate2D? {
        let latitude: Double
        let longitude: Double
        switch self {
        case .personal(let lead):
            latitude = lead.latitude
            longitude = lead.longitude
        case .team(let lead):
            latitude = lead.latitude
            longitude = lead.longitude
        }

        guard CLLocationCoordinate2DIsValid(.init(latitude: latitude, longitude: longitude)),
              latitude != 0 || longitude != 0 else {
            return nil
        }
        return .init(latitude: latitude, longitude: longitude)
    }

    var priorityAttributes: FollowUpPriorityAttributes? {
        guard let dueDate else { return nil }
        return FollowUpPriorityAttributes(
            isHighPriority: isHighPriority,
            isInterested: statusIsInterested,
            dueDate: dueDate,
            value: value,
            name: name
        )
    }

    var isPersonal: Bool {
        if case .personal = self { return true }
        return false
    }

    func matches(_ query: String) -> Bool {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty else { return true }
        return [name, address, phone ?? "", email ?? "", statusLabel]
            .contains { $0.localizedCaseInsensitiveContains(normalizedQuery) }
    }

    func defaultMessage(using manager: FollowUpMessageTemplates) -> String {
        let templates = manager.getTemplatesForCategory(.reminder)
        if case .personal(let lead) = self,
           let template = templates.first(where: { $0.isForSMS }) ?? templates.first {
            return manager.personalizeMessage(template, for: lead)
        }

        let firstName = name.split(separator: " ").first.map(String.init) ?? name
        let location = address.isEmpty ? "your property" : address
        return "Hi \(firstName), just following up about the service for \(location). Let me know if you have any questions or would like to choose a time."
    }

    func message(from template: MessageTemplate, using manager: FollowUpMessageTemplates) -> String {
        if case .personal(let lead) = self {
            return manager.personalizeMessage(template, for: lead)
        }

        return template.message
            .replacingOccurrences(of: "{name}", with: name)
            .replacingOccurrences(of: "{address}", with: address.isEmpty ? "your property" : address)
            .replacingOccurrences(of: "{service_type}", with: "our services")
            .replacingOccurrences(of: "{price}", with: MessageTemplatePriceFormatter.string(from: value))
            .replacingOccurrences(of: "{phone}", with: phone ?? "")
            .replacingOccurrences(of: "{email}", with: email ?? "")
    }

    private static func normalized(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private struct FollowUpCompletedQueueItem: Identifiable {
    let target: FollowUpQueueItem
    let completedAt: Date
    let summary: String

    var id: String { target.id }
}

struct FollowUpOutcomeRequest: Identifiable {
    let id = UUID()
    let target: FollowUpQueueItem
    let method: FollowUpContactMethod
}

private struct FollowUpSnoozeRequest: Identifiable {
    let id = UUID()
    let target: FollowUpQueueItem
}

struct FollowUpQueueContent: View {
    let personalLeads: [Lead]
    let recentCheckIns: [FollowUpCheckIn]

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.openURL) private var openURL
    @ObservedObject private var teamService = TeamFirebaseService.shared
    @State private var selectedSegment: FollowUpQueueSegment = .due
    @State private var searchText = ""
    @State private var selectedAssigneeId = "all"
    @State private var selectedPersonalLead: Lead?
    @State private var selectedTeamLead: TeamLead?
    @State private var messageTarget: FollowUpQueueItem?
    @State private var outcomeRequest: FollowUpOutcomeRequest?
    @State private var snoozeRequest: FollowUpSnoozeRequest?
    @State private var isSelecting = false
    @State private var selectedItemIds: Set<String> = []
    @State private var isBatchSaving = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            if let errorMessage {
                ObsidianStatusBanner(
                    icon: "exclamationmark.triangle.fill",
                    title: "Follow-up update failed",
                    message: errorMessage,
                    tint: Color.statusNotInterested
                )
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }

            ScrollView {
                LazyVStack(spacing: 10) {
                    summaryHeader
                    segmentControl
                    queueControls

                    if selectedSegment == .completed {
                        completedQueue
                    } else {
                        activeQueue
                    }
                }
                .padding(.top, 4)
                .padding(.bottom, isSelecting ? 90 : 16)
            }
        }
        .background(Color.obsidianBackground(for: colorScheme))
        .safeAreaInset(edge: .bottom) {
            if isSelecting {
                batchActionBar
            }
        }
        .sheet(item: $selectedPersonalLead) { lead in
            FollowUpDetailView(lead: lead)
        }
        .sheet(item: $selectedTeamLead) { lead in
            TeamLeadDetailSheet(initialLead: lead)
        }
        .sheet(item: $messageTarget) { target in
            QuickFollowUpMessageView(target: target) { method in
                messageTarget = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    outcomeRequest = FollowUpOutcomeRequest(target: target, method: method)
                }
            }
        }
        .sheet(item: $outcomeRequest) { request in
            FollowUpOutcomeSheet(request: request) {
                selectedItemIds.remove(request.target.id)
            }
        }
        .sheet(item: $snoozeRequest) { request in
            FollowUpSnoozeSheet(target: request.target) { date in
                Task { await reschedule(request.target, to: date) }
            }
        }
        .onChange(of: selectedSegment) { _, newValue in
            if newValue == .completed {
                stopSelecting()
            }
        }
    }

    private var allActiveItems: [FollowUpQueueItem] {
        let personal = personalLeads.map(FollowUpQueueItem.personal)
        let team = teamService.teamLeads.compactMap { lead -> FollowUpQueueItem? in
            guard lead.status.allowsFollowUpQueue,
                  lead.followUpDate != nil || lead.status == .followUp else {
                return nil
            }
            return .team(lead)
        }
        return personal + team
    }

    private var sourceFilteredActiveItems: [FollowUpQueueItem] {
        allActiveItems.filter(matchesSelectedAssignee)
    }

    private var visibleActiveItems: [FollowUpQueueItem] {
        sourceFilteredActiveItems
            .filter { item in
                guard let dueDate = item.dueDate else { return false }
                let isDue = FollowUpWorkflowPolicy.isDue(dueDate)
                return selectedSegment == .due ? isDue : !isDue
            }
            .filter { $0.matches(searchText) }
            .sorted { lhs, rhs in
                guard let lhsAttributes = lhs.priorityAttributes,
                      let rhsAttributes = rhs.priorityAttributes else {
                    return lhs.name < rhs.name
                }
                return FollowUpWorkflowPolicy.priorityComesFirst(lhs: lhsAttributes, rhs: rhsAttributes)
            }
    }

    private var completedItems: [FollowUpCompletedQueueItem] {
        var results: [FollowUpCompletedQueueItem] = []
        var seenTargetIds: Set<String> = []

        for checkIn in recentCheckIns {
            guard let lead = checkIn.lead,
                  let completedAt = checkIn.checkInDate else { continue }
            let target = FollowUpQueueItem.personal(lead)
            guard seenTargetIds.insert(target.id).inserted,
                  matchesSelectedAssignee(target),
                  target.matches(searchText) else { continue }
            let summary = "\(checkIn.checkInTypeEnum.displayName) · \(checkIn.outcomeEnum?.displayName ?? "Contact recorded")"
            results.append(.init(target: target, completedAt: completedAt, summary: summary))
        }

        for lead in teamService.teamLeads {
            guard let completedAt = lead.lastContactedAt else { continue }
            let target = FollowUpQueueItem.team(lead)
            guard matchesSelectedAssignee(target), target.matches(searchText) else { continue }
            results.append(.init(
                target: target,
                completedAt: completedAt,
                summary: lead.lastContactSummary ?? "Team follow-up recorded"
            ))
        }

        return results.sorted { $0.completedAt > $1.completedAt }
    }

    private var dueItems: [FollowUpQueueItem] {
        sourceFilteredActiveItems.filter { item in
            item.dueDate.map { FollowUpWorkflowPolicy.isDue($0) } ?? false
        }
    }

    private var overdueCount: Int {
        dueItems.filter { ($0.dueDate ?? .distantFuture) < Calendar.current.startOfDay(for: Date()) }.count
    }

    private var todayCount: Int {
        dueItems.filter { item in
            item.dueDate.map(Calendar.current.isDateInToday) ?? false
        }.count
    }

    private var handledTodayCount: Int {
        completedItems.filter { Calendar.current.isDateInToday($0.completedAt) }.count
    }

    private var summaryHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Today Queue")
                        .font(.obsidianHeadline)
                        .foregroundColor(Color.textPrimary)
                    Text(todayProgressText)
                        .font(.obsidianFootnote)
                        .foregroundColor(Color.textSecondary)
                }

                Spacer()

                Text("\(handledTodayCount)/\(max(handledTodayCount + todayCount, 1))")
                    .font(.obsidianTitle)
                    .foregroundColor(Color.statusInterested)
                    .accessibilityLabel("\(handledTodayCount) handled today")
            }

            ProgressView(
                value: Double(handledTodayCount),
                total: Double(max(handledTodayCount + todayCount, 1))
            )
            .tint(Color.statusInterested)

            HStack(spacing: 8) {
                summaryMetric(title: "Overdue", value: overdueCount, tint: Color.statusNotInterested)
                summaryMetric(title: "Today", value: todayCount, tint: Color.statusNotHome)
                summaryMetric(title: "Handled", value: handledTodayCount, tint: Color.statusInterested)
            }
        }
        .padding(14)
        .background(Color.obsidianSurface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.obsidianBorder.opacity(0.55), lineWidth: 0.5)
        )
        .padding(.horizontal, 16)
        .accessibilityIdentifier("followUpTodaySummary")
    }

    private var todayProgressText: String {
        if todayCount == 0 {
            return handledTodayCount == 0 ? "Nothing due today." : "Today is cleared."
        }
        return "\(todayCount) remaining today"
    }

    private func summaryMetric(title: String, value: Int, tint: Color) -> some View {
        HStack(spacing: 6) {
            Circle().fill(tint).frame(width: 7, height: 7)
            Text("\(value) \(title)")
                .font(.micro)
                .foregroundColor(Color.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, minHeight: 34)
        .background(Color.obsidianElevated)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var segmentControl: some View {
        HStack(spacing: 4) {
            ForEach(FollowUpQueueSegment.allCases) { segment in
                let isSelected = selectedSegment == segment
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedSegment = segment
                    }
                } label: {
                    Label(segment.title, systemImage: segment.icon)
                        .font(.micro)
                        .foregroundColor(isSelected ? .white : Color.textSecondary)
                        .frame(maxWidth: .infinity, minHeight: 40)
                        .background(
                            RoundedRectangle(cornerRadius: 11, style: .continuous)
                                .fill(isSelected ? Color.electricViolet : Color.clear)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("followUpSegment_\(segment.rawValue)")
            }
        }
        .padding(4)
        .background(Color.obsidianSurface)
        .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .stroke(Color.obsidianBorder.opacity(0.45), lineWidth: 0.5)
        )
        .padding(.horizontal, 16)
    }

    private var queueControls: some View {
        HStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(Color.textMuted)
                TextField("Search follow-ups", text: $searchText)
                    .font(.obsidianFootnote)
                    .foregroundColor(Color.textPrimary)
                    .textInputAutocapitalization(.never)
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(Color.textMuted)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear search")
                }
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 42)
            .background(Color.obsidianSurface)
            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .stroke(Color.obsidianBorder.opacity(0.45), lineWidth: 0.5)
            )

            if assigneeOptions.count > 1 {
                Menu {
                    ForEach(assigneeOptions, id: \.id) { option in
                        Button {
                            selectedAssigneeId = option.id
                            selectedItemIds.removeAll()
                        } label: {
                            Label(option.title, systemImage: option.icon)
                        }
                    }
                } label: {
                    Image(systemName: "person.crop.circle.badge.checkmark")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(Color.electricViolet)
                        .frame(width: 42, height: 42)
                        .background(Color.obsidianSurface)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Color.obsidianBorder.opacity(0.45), lineWidth: 0.5))
                }
                .accessibilityLabel("Filter by assignee")
                .accessibilityValue(selectedAssigneeTitle)
            }

            if selectedSegment != .completed && !visibleActiveItems.isEmpty {
                Button {
                    isSelecting ? stopSelecting() : (isSelecting = true)
                } label: {
                    Image(systemName: isSelecting ? "xmark" : "checkmark.circle")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(isSelecting ? Color.statusNotInterested : Color.electricViolet)
                        .frame(width: 42, height: 42)
                        .background(Color.obsidianSurface)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Color.obsidianBorder.opacity(0.45), lineWidth: 0.5))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isSelecting ? "Cancel selection" : "Select follow-ups")
                .accessibilityIdentifier("followUpSelectButton")
            }
        }
        .padding(.horizontal, 16)
    }

    @ViewBuilder
    private var activeQueue: some View {
        if visibleActiveItems.isEmpty {
            ObsidianEmptyState(
                icon: selectedSegment == .due ? "checkmark.circle" : "calendar.badge.clock",
                title: selectedSegment == .due ? "Queue Cleared" : "Nothing Upcoming",
                message: searchText.isEmpty
                    ? (selectedSegment == .due ? "No overdue or due-today follow-ups match this view." : "Future reminders will appear here.")
                    : "No follow-ups match your search."
            )
            .frame(minHeight: 280)
        } else {
            ForEach(visibleActiveItems) { item in
                FollowUpQueueRow(
                    item: item,
                    assigneeName: assigneeName(for: item),
                    isSelecting: isSelecting,
                    isSelected: selectedItemIds.contains(item.id),
                    onOpen: { open(item) },
                    onToggleSelection: { toggleSelection(item) },
                    onMessage: { messageTarget = item },
                    onCall: { call(item) },
                    onNavigate: { navigate(to: item) },
                    onRecord: {
                        outcomeRequest = FollowUpOutcomeRequest(target: item, method: .manual)
                    },
                    onSnooze: { date in
                        Task { await reschedule(item, to: date) }
                    },
                    onCustomSnooze: {
                        snoozeRequest = FollowUpSnoozeRequest(target: item)
                    }
                )
            }
        }
    }

    @ViewBuilder
    private var completedQueue: some View {
        if completedItems.isEmpty {
            ObsidianEmptyState(
                icon: "clock.arrow.circlepath",
                title: "No Recent Activity",
                message: searchText.isEmpty ? "Completed follow-ups from the last 30 days will appear here." : "No completed follow-ups match your search."
            )
            .frame(minHeight: 280)
        } else {
            ForEach(completedItems) { item in
                FollowUpCompletedRow(
                    item: item,
                    assigneeName: assigneeName(for: item.target),
                    onOpen: { open(item.target) }
                )
            }
        }
    }

    private var batchActionBar: some View {
        HStack(spacing: 10) {
            Text("\(selectedItemIds.count) selected")
                .font(.obsidianFootnote)
                .foregroundColor(Color.textSecondary)
                .lineLimit(1)

            Spacer(minLength: 4)

            batchButton(title: "Tomorrow", icon: "sunrise.fill", days: 1)
            batchButton(title: "+1 Week", icon: "calendar.badge.plus", days: 7)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.obsidianElevated)
        .overlay(alignment: .top) {
            Rectangle().fill(Color.obsidianBorder.opacity(0.5)).frame(height: 0.5)
        }
    }

    private func batchButton(title: String, icon: String, days: Int) -> some View {
        Button {
            Task { await rescheduleSelected(days: days) }
        } label: {
            Label(title, systemImage: icon)
                .font(.micro)
                .foregroundColor(.white)
                .padding(.horizontal, 10)
                .frame(minHeight: 42)
                .background(Color.electricViolet)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(selectedItemIds.isEmpty || isBatchSaving)
        .opacity(selectedItemIds.isEmpty || isBatchSaving ? 0.5 : 1)
    }

    private struct AssigneeOption {
        let id: String
        let title: String
        let icon: String
    }

    private var assigneeOptions: [AssigneeOption] {
        var options = [
            AssigneeOption(id: "all", title: "All work", icon: "tray.full.fill"),
            AssigneeOption(id: "personal", title: "Personal", icon: "person.fill")
        ]
        let userIds = Set(teamService.teamLeads.map(\.assignedToUserId))
        let members = TeamMemberRoster.normalized(teamService.teamMembers)
            .filter { $0.status == .active && !$0.isPendingInvite && userIds.contains($0.userId) }
        options.append(contentsOf: members.map {
            AssigneeOption(id: "team:\($0.userId)", title: $0.displayName, icon: "person.crop.circle.fill")
        })
        return options
    }

    private var selectedAssigneeTitle: String {
        assigneeOptions.first { $0.id == selectedAssigneeId }?.title ?? "All work"
    }

    private func matchesSelectedAssignee(_ item: FollowUpQueueItem) -> Bool {
        switch selectedAssigneeId {
        case "all":
            return true
        case "personal":
            return item.isPersonal
        default:
            guard selectedAssigneeId.hasPrefix("team:") else { return true }
            return item.assignedUserId == String(selectedAssigneeId.dropFirst("team:".count))
        }
    }

    private func assigneeName(for item: FollowUpQueueItem) -> String? {
        guard let userId = item.assignedUserId else { return nil }
        return teamService.teamMembers.first { $0.userId == userId }?.displayName ?? "Assigned worker"
    }

    private func open(_ item: FollowUpQueueItem) {
        switch item {
        case .personal(let lead): selectedPersonalLead = lead
        case .team(let lead): selectedTeamLead = lead
        }
    }

    private func toggleSelection(_ item: FollowUpQueueItem) {
        if selectedItemIds.contains(item.id) {
            selectedItemIds.remove(item.id)
        } else {
            selectedItemIds.insert(item.id)
        }
    }

    private func stopSelecting() {
        isSelecting = false
        selectedItemIds.removeAll()
    }

    private func call(_ item: FollowUpQueueItem) {
        guard let phone = item.phone else { return }
        let digits = phone.filter { $0.isNumber || $0 == "+" }
        guard let url = URL(string: "tel:\(digits)") else { return }
        openURL(url) { accepted in
            guard accepted else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                outcomeRequest = FollowUpOutcomeRequest(target: item, method: .phoneCall)
            }
        }
    }

    private func navigate(to item: FollowUpQueueItem) {
        guard let coordinate = item.coordinate else { return }
        let mapItem = MKMapItem(placemark: MKPlacemark(coordinate: coordinate))
        mapItem.name = item.name
        mapItem.openInMaps(launchOptions: [
            MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving
        ])
    }

    private func reschedule(_ item: FollowUpQueueItem, to date: Date) async {
        do {
            switch item {
            case .personal(let lead):
                lead.setFollowUpDate(date)
                NotificationService.shared.requestPermissionAfterSchedulingIfNeeded()
            case .team(let lead):
                _ = try await teamService.updateTeamLead(
                    leadId: lead.id,
                    followUpDate: date,
                    shouldReplaceFollowUpDate: true
                )
            }
            errorMessage = nil
        } catch {
            errorMessage = TeamFirebaseService.userFacingErrorMessage(for: error)
        }
    }

    private func rescheduleSelected(days: Int) async {
        isBatchSaving = true
        defer { isBatchSaving = false }

        let selectedItems = visibleActiveItems.filter { selectedItemIds.contains($0.id) }
        let targetDate = Self.quickSnoozeDate(days: days)
        for item in selectedItems {
            await reschedule(item, to: targetDate)
            if errorMessage != nil { return }
        }
        stopSelecting()
    }

    static func quickSnoozeDate(days: Int, now: Date = Date()) -> Date {
        let calendar = Calendar.current
        let target = calendar.date(byAdding: .day, value: days, to: now) ?? now.addingTimeInterval(TimeInterval(days) * 86_400)
        return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: target) ?? target
    }
}

private struct FollowUpQueueRow: View {
    let item: FollowUpQueueItem
    let assigneeName: String?
    let isSelecting: Bool
    let isSelected: Bool
    let onOpen: () -> Void
    let onToggleSelection: () -> Void
    let onMessage: () -> Void
    let onCall: () -> Void
    let onNavigate: () -> Void
    let onRecord: () -> Void
    let onSnooze: (Date) -> Void
    let onCustomSnooze: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                if isSelecting {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundColor(isSelected ? Color.electricViolet : Color.textMuted)
                        .frame(width: 38, height: 38)
                } else {
                    ObsidianIconTile(icon: urgencyIcon, tint: urgencyColor, size: 38, filled: true)
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(item.name)
                            .font(.obsidianTitle)
                            .foregroundColor(Color.textPrimary)
                            .lineLimit(1)

                        if item.isHighPriority {
                            Image(systemName: "star.fill")
                                .font(.micro)
                                .foregroundColor(Color.statusInterested)
                                .accessibilityLabel("High priority")
                        }

                        Spacer(minLength: 4)

                        Text(urgencyText)
                            .font(.nano)
                            .foregroundColor(urgencyColor)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(urgencyColor.opacity(0.12)))
                    }

                    HStack(spacing: 6) {
                        Text(item.statusLabel)
                            .font(.micro)
                            .foregroundColor(statusColor)
                        Text("·")
                            .foregroundColor(Color.textMuted)
                        Text(sourceText)
                            .font(.micro)
                            .foregroundColor(Color.textSecondary)
                            .lineLimit(1)
                    }

                    if !item.address.isEmpty {
                        Text(item.address)
                            .font(.micro)
                            .foregroundColor(Color.textMuted)
                            .lineLimit(1)
                    }

                    if let summary = item.lastContactSummary {
                        Label(summary, systemImage: "clock.arrow.circlepath")
                            .font(.nano)
                            .foregroundColor(Color.textMuted)
                            .lineLimit(1)
                    }
                }
            }

            if !isSelecting {
                HStack(spacing: 8) {
                    compactAction(icon: messageIcon, label: messageLabel, isEnabled: item.phone != nil || item.email != nil, action: onMessage)
                    compactAction(icon: "phone.fill", label: "Call", isEnabled: item.phone != nil, action: onCall)
                    compactAction(icon: "arrow.triangle.turn.up.right.diamond.fill", label: "Navigate", isEnabled: item.coordinate != nil, action: onNavigate)

                    Menu {
                        Button { onSnooze(FollowUpQueueContent.quickSnoozeDate(days: 1)) } label: {
                            Label("Tomorrow at 9 AM", systemImage: "sunrise.fill")
                        }
                        Button { onSnooze(FollowUpQueueContent.quickSnoozeDate(days: 3)) } label: {
                            Label("In 3 days", systemImage: "calendar.badge.clock")
                        }
                        Button { onSnooze(FollowUpQueueContent.quickSnoozeDate(days: 7)) } label: {
                            Label("Next week", systemImage: "calendar.badge.plus")
                        }
                        Button(action: onCustomSnooze) {
                            Label("Choose date", systemImage: "calendar")
                        }
                    } label: {
                        compactActionLabel(icon: "clock.arrow.circlepath", label: "Snooze", isEnabled: true)
                    }
                    .accessibilityLabel("Snooze \(item.name)")

                    compactAction(icon: "checkmark.circle.fill", label: "Outcome", isEnabled: true, tint: Color.statusInterested, action: onRecord)
                }
            }
        }
        .padding(12)
        .background(isSelected ? Color.electricViolet.opacity(0.12) : Color.obsidianSurface)
        .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .stroke(isSelected ? Color.electricViolet : Color.obsidianBorder.opacity(0.5), lineWidth: isSelected ? 1 : 0.5)
        )
        .padding(.horizontal, 16)
        .contentShape(Rectangle())
        .onTapGesture {
            isSelecting ? onToggleSelection() : onOpen()
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("followUpRow")
        .accessibilityLabel("\(item.name), \(urgencyText), \(item.statusLabel)")
    }

    private var sourceText: String {
        assigneeName.map { "\(item.sourceLabel) · \($0)" } ?? item.sourceLabel
    }

    private var messageIcon: String { item.phone != nil ? "message.fill" : "envelope.fill" }
    private var messageLabel: String { item.phone != nil ? "Text" : "Email" }

    private var statusColor: Color {
        item.statusIsInterested ? Color.statusInterested : Color.textSecondary
    }

    private var urgencyColor: Color {
        guard let date = item.dueDate else { return Color.textMuted }
        if date < Calendar.current.startOfDay(for: Date()) { return Color.statusNotInterested }
        if Calendar.current.isDateInToday(date) { return Color.statusNotHome }
        return Color.electricViolet
    }

    private var urgencyIcon: String {
        guard let date = item.dueDate else { return "calendar" }
        if date < Calendar.current.startOfDay(for: Date()) { return "exclamationmark.triangle.fill" }
        if Calendar.current.isDateInToday(date) { return "clock.fill" }
        return "calendar"
    }

    private var urgencyText: String {
        guard let date = item.dueDate else { return "Unscheduled" }
        if date < Calendar.current.startOfDay(for: Date()) {
            let days = max(1, Calendar.current.dateComponents([.day], from: date, to: Date()).day ?? 1)
            return "\(days)d overdue"
        }
        if Calendar.current.isDateInToday(date) {
            return date.formatted(.dateTime.hour().minute())
        }
        if Calendar.current.isDateInTomorrow(date) { return "Tomorrow" }
        return date.formatted(.dateTime.month().day())
    }

    private func compactAction(
        icon: String,
        label: String,
        isEnabled: Bool,
        tint: Color = Color.electricViolet,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            compactActionLabel(icon: icon, label: label, isEnabled: isEnabled, tint: tint)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityLabel(label)
    }

    private func compactActionLabel(
        icon: String,
        label: String,
        isEnabled: Bool,
        tint: Color = Color.electricViolet
    ) -> some View {
        Image(systemName: icon)
            .font(.system(size: 14, weight: .semibold))
            .foregroundColor(isEnabled ? tint : Color.textMuted)
            .frame(maxWidth: .infinity, minHeight: 38)
            .background((isEnabled ? tint : Color.textMuted).opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            .accessibilityLabel(label)
    }
}

private struct FollowUpCompletedRow: View {
    let item: FollowUpCompletedQueueItem
    let assigneeName: String?
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 12) {
                ObsidianIconTile(icon: "checkmark.circle.fill", tint: Color.statusInterested, size: 40, filled: true)

                VStack(alignment: .leading, spacing: 4) {
                    Text(item.target.name)
                        .font(.obsidianTitle)
                        .foregroundColor(Color.textPrimary)
                        .lineLimit(1)
                    Text(item.summary)
                        .font(.micro)
                        .foregroundColor(Color.textSecondary)
                        .lineLimit(1)
                    Text(assigneeName.map { "\(item.target.sourceLabel) · \($0)" } ?? item.target.sourceLabel)
                        .font(.nano)
                        .foregroundColor(Color.textMuted)
                }

                Spacer(minLength: 6)

                Text(item.completedAt.formatted(.dateTime.month().day().hour().minute()))
                    .font(.nano)
                    .foregroundColor(Color.textMuted)
                    .multilineTextAlignment(.trailing)

                Image(systemName: "chevron.right")
                    .font(.micro)
                    .foregroundColor(Color.textMuted)
            }
            .padding(12)
            .background(Color.obsidianSurface)
            .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .stroke(Color.obsidianBorder.opacity(0.5), lineWidth: 0.5)
            )
            .padding(.horizontal, 16)
        }
        .buttonStyle(.plain)
    }
}

struct FollowUpOutcomeSheet: View {
    let request: FollowUpOutcomeRequest
    let onSaved: () -> Void

    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var teamService = TeamFirebaseService.shared
    @State private var selectedOutcome: FollowUpOutcomeChoice = .done
    @State private var nextDate = FollowUpWorkflowPolicy.defaultNextDate(for: .later) ?? Date().addingTimeInterval(86_400)
    @State private var note = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    LeadFormSectionCard(title: request.target.name, icon: "person.crop.circle.fill") {
                        HStack {
                            Label(request.method.displayName, systemImage: methodIcon)
                                .font(.obsidianFootnote)
                                .foregroundColor(Color.textSecondary)
                            Spacer()
                            Text(request.target.sourceLabel)
                                .font(.micro)
                                .foregroundColor(Color.electricViolet)
                        }
                    }

                    LeadFormSectionCard(title: "What happened?", icon: "checkmark.bubble.fill") {
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                            ForEach(FollowUpOutcomeChoice.allCases) { outcome in
                                outcomeButton(outcome)
                            }
                        }
                    }

                    if selectedOutcome.requiresNextDate {
                        LeadFormSectionCard(title: "Next follow-up", icon: "calendar.badge.clock") {
                            VStack(spacing: 12) {
                                HStack(spacing: 8) {
                                    datePreset("Tomorrow", days: 1)
                                    datePreset("3 days", days: 3)
                                    datePreset("Next week", days: 7)
                                }

                                DatePicker(
                                    "Date and time",
                                    selection: $nextDate,
                                    in: Date()...,
                                    displayedComponents: [.date, .hourAndMinute]
                                )
                                .font(.obsidianFootnote)
                                .padding(12)
                                .background(Color.obsidianElevated)
                                .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                            }
                        }
                    }

                    LeadFormSectionCard(title: "Short note", icon: "note.text") {
                        TextField("Optional outcome note", text: $note, axis: .vertical)
                            .lineLimit(2...4)
                            .font(.obsidianBody)
                            .padding(12)
                            .background(Color.obsidianElevated)
                            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                    }

                    if let errorMessage {
                        ObsidianStatusBanner(
                            icon: "exclamationmark.triangle.fill",
                            title: "Could not save outcome",
                            message: errorMessage,
                            tint: Color.statusNotInterested
                        )
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 18)
                .padding(.bottom, 28)
            }
            .obsidianScreenBackground()
            .obsidianPushedNavigation(
                "Follow-up Outcome",
                backButtonAccessibilityIdentifier: "followUpOutcomeBackButton",
                onBack: { dismiss() }
            )
            .safeAreaInset(edge: .bottom) {
                ObsidianBottomActionBar(
                    isPrimaryDisabled: isSaving || (selectedOutcome.requiresNextDate && nextDate <= Date()),
                    primaryAccessibilityIdentifier: "followUpOutcomeSaveButton",
                    secondaryAccessibilityIdentifier: "followUpOutcomeCancelButton",
                    primaryAction: { Task { await save() } },
                    secondaryAction: { dismiss() },
                    primaryLabel: { Label("Save Outcome", systemImage: "checkmark.circle.fill") },
                    secondaryLabel: { Label("Cancel", systemImage: "xmark.circle.fill") }
                )
            }
            .onChange(of: selectedOutcome) { _, outcome in
                if let defaultDate = FollowUpWorkflowPolicy.defaultNextDate(for: outcome) {
                    nextDate = defaultDate
                }
            }
        }
        .obsidianModalBackground()
        .presentationDetents([.medium, .large])
        .accessibilityIdentifier("followUpOutcomeSheet")
    }

    private var methodIcon: String {
        switch request.method {
        case .phoneCall: return "phone.fill"
        case .sms: return "message.fill"
        case .email: return "envelope.fill"
        case .visit: return "figure.walk"
        case .manual: return "hand.tap.fill"
        }
    }

    private func outcomeButton(_ outcome: FollowUpOutcomeChoice) -> some View {
        let isSelected = selectedOutcome == outcome
        let tint = outcome.tintColor
        return Button {
            selectedOutcome = outcome
        } label: {
            Label(outcome.title, systemImage: outcome.icon)
                .font(.micro)
                .foregroundColor(isSelected ? .white : tint)
                .frame(maxWidth: .infinity, minHeight: 46)
                .background(isSelected ? tint : tint.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .stroke(tint.opacity(isSelected ? 0 : 0.3), lineWidth: 0.5)
                )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("followUpOutcome_\(outcome.rawValue)")
    }

    private func datePreset(_ title: String, days: Int) -> some View {
        Button {
            nextDate = FollowUpQueueContent.quickSnoozeDate(days: days)
        } label: {
            Text(title)
                .font(.micro)
                .foregroundColor(Color.electricViolet)
                .frame(maxWidth: .infinity, minHeight: 40)
                .background(Color.electricViolet.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    @MainActor
    private func save() async {
        guard !isSaving else { return }
        isSaving = true
        defer { isSaving = false }

        do {
            switch request.target {
            case .personal(let lead):
                try FollowUpOutcomeRecorder.recordPersonal(
                    lead: lead,
                    outcome: selectedOutcome,
                    method: request.method,
                    note: note,
                    selectedNextDate: selectedOutcome.requiresNextDate ? nextDate : nil,
                    in: viewContext
                )
            case .team(let lead):
                let now = Date()
                let nextDate = FollowUpWorkflowPolicy.resolvedNextDate(
                    for: selectedOutcome,
                    selectedDate: selectedOutcome.requiresNextDate ? self.nextDate : nil,
                    cadenceDate: nil,
                    now: now
                )
                let summary = [request.method.displayName, selectedOutcome.title, normalizedNote]
                    .compactMap { $0 }
                    .joined(separator: " · ")
                _ = try await teamService.updateTeamLead(
                    leadId: lead.id,
                    status: selectedOutcome.teamStatus(from: lead.status),
                    followUpDate: nextDate,
                    shouldReplaceFollowUpDate: true,
                    lastContactedAt: now,
                    lastContactSummary: summary,
                    now: now
                )
            }

            errorMessage = nil
            onSaved()
            dismiss()
        } catch {
            errorMessage = TeamFirebaseService.userFacingErrorMessage(for: error)
        }
    }

    private var normalizedNote: String? {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private struct FollowUpSnoozeSheet: View {
    let target: FollowUpQueueItem
    let onSave: (Date) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedDate = FollowUpQueueContent.quickSnoozeDate(days: 1)

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                LeadFormSectionCard(title: target.name, icon: "clock.arrow.circlepath") {
                    DatePicker(
                        "New follow-up",
                        selection: $selectedDate,
                        in: Date()...,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    .datePickerStyle(.graphical)
                    .tint(Color.electricViolet)
                }
                Spacer(minLength: 0)
            }
            .padding(16)
            .obsidianScreenBackground()
            .obsidianPushedNavigation(
                "Snooze Follow-up",
                backButtonAccessibilityIdentifier: "followUpSnoozeBackButton",
                onBack: { dismiss() }
            )
            .safeAreaInset(edge: .bottom) {
                ObsidianBottomActionBar(
                    isPrimaryDisabled: selectedDate <= Date(),
                    primaryAction: {
                        onSave(selectedDate)
                        dismiss()
                    },
                    secondaryAction: { dismiss() },
                    primaryLabel: { Label("Save", systemImage: "checkmark.circle.fill") },
                    secondaryLabel: { Label("Cancel", systemImage: "xmark.circle.fill") }
                )
            }
        }
        .obsidianModalBackground()
    }
}

private struct QuickFollowUpMessageView: View {
    enum Channel: String, CaseIterable, Identifiable {
        case sms = "Text"
        case email = "Email"

        var id: String { rawValue }
    }

    let target: FollowUpQueueItem
    let onSent: (FollowUpContactMethod) -> Void

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var templateManager = FollowUpMessageTemplates.shared
    @State private var channel: Channel
    @State private var message: String
    @State private var showingSMSComposer = false
    @State private var showingEmailComposer = false

    init(target: FollowUpQueueItem, onSent: @escaping (FollowUpContactMethod) -> Void) {
        self.target = target
        self.onSent = onSent
        let initialChannel: Channel = target.phone != nil ? .sms : .email
        _channel = State(initialValue: initialChannel)
        _message = State(initialValue: target.defaultMessage(using: FollowUpMessageTemplates.shared))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    LeadFormSectionCard(title: target.name, icon: "person.crop.circle.fill") {
                        Picker("Channel", selection: $channel) {
                            if target.phone != nil {
                                Label("Text", systemImage: "message.fill").tag(Channel.sms)
                            }
                            if target.email != nil {
                                Label("Email", systemImage: "envelope.fill").tag(Channel.email)
                            }
                        }
                        .pickerStyle(.segmented)
                    }

                    LeadFormSectionCard(title: "Message", icon: "message.fill") {
                        HStack {
                            Text("Quick composer")
                                .font(.micro)
                                .foregroundColor(Color.textSecondary)
                            Spacer()
                            templateMenu
                        }

                        TextEditor(text: $message)
                            .frame(minHeight: 150)
                            .obsidianEditorSurface(cornerRadius: 14)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 18)
                .padding(.bottom, 28)
            }
            .obsidianScreenBackground()
            .obsidianPushedNavigation(
                "Quick Follow-up",
                backButtonAccessibilityIdentifier: "quickFollowUpMessageBackButton",
                onBack: { dismiss() }
            )
            .safeAreaInset(edge: .bottom) {
                ObsidianBottomActionBar(
                    isPrimaryDisabled: message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                    primaryAccessibilityIdentifier: "quickFollowUpMessageSendButton",
                    secondaryAccessibilityIdentifier: "quickFollowUpMessageCancelButton",
                    primaryAction: send,
                    secondaryAction: { dismiss() },
                    primaryLabel: {
                        Label(channel == .sms ? "Send Text" : "Send Email", systemImage: channel == .sms ? "message.fill" : "envelope.fill")
                    },
                    secondaryLabel: { Label("Cancel", systemImage: "xmark.circle.fill") }
                )
            }
        }
        .sheet(isPresented: $showingSMSComposer) {
            if MFMessageComposeViewController.canSendText(), let phone = target.phone {
                MessageComposeView(
                    recipients: [phone],
                    messageBody: trimmedMessage,
                    onFinished: handleMessageResult
                )
            } else {
                ObsidianEmptyState(icon: "message.badge.filled.fill", title: "Texting Unavailable", message: "SMS is not available on this device.")
            }
        }
        .sheet(isPresented: $showingEmailComposer) {
            if MFMailComposeViewController.canSendMail(), let email = target.email {
                EmailComposeView(
                    recipients: [email],
                    subject: "Follow-up: \(target.name)",
                    messageBody: trimmedMessage,
                    onFinished: handleEmailResult
                )
            } else {
                ObsidianEmptyState(icon: "envelope.badge.fill", title: "Email Unavailable", message: "Mail is not configured on this device.")
            }
        }
        .obsidianModalBackground()
    }

    private var availableTemplates: [MessageTemplate] {
        templateManager.getTemplatesForCategory(.reminder).filter {
            channel == .sms ? $0.isForSMS : $0.isForEmail
        }
    }

    private var templateMenu: some View {
        Menu {
            ForEach(availableTemplates, id: \.id) { template in
                Button(template.title) {
                    message = target.message(from: template, using: templateManager)
                }
            }
        } label: {
            Label("Template", systemImage: "doc.text.fill")
                .font(.micro)
                .foregroundColor(Color.electricViolet)
        }
    }

    private var trimmedMessage: String {
        message.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func send() {
        channel == .sms ? (showingSMSComposer = true) : (showingEmailComposer = true)
    }

    private func handleMessageResult(_ result: MessageComposeResult) {
        showingSMSComposer = false
        guard result == .sent else { return }
        dismiss()
        onSent(.sms)
    }

    private func handleEmailResult(_ result: MFMailComposeResult) {
        showingEmailComposer = false
        guard result == .sent else { return }
        dismiss()
        onSent(.email)
    }
}

private extension FollowUpOutcomeChoice {
    var tintColor: Color {
        switch self {
        case .done: return Color.electricViolet
        case .noAnswer, .later: return Color.statusNotHome
        case .interested: return Color.statusInterested
        case .sold: return Color.statusConverted
        case .pass: return Color.statusNotInterested
        }
    }
}

private extension TeamLeadStatus {
    var allowsFollowUpQueue: Bool {
        switch self {
        case .booked, .converted, .notInterested:
            return false
        case .notContacted, .notHome, .contacted, .interested, .followUp:
            return true
        }
    }

    var followUpDisplayName: String {
        switch self {
        case .notContacted: return "New"
        case .notHome: return "Not Home"
        case .contacted: return "Contacted"
        case .interested: return "Interested"
        case .followUp: return "Follow Up"
        case .booked: return "Booked"
        case .converted: return "Sold"
        case .notInterested: return "Pass"
        }
    }
}
