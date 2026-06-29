import SwiftUI
import CoreData

struct FollowUpView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @ObservedObject private var paywallManager = PaywallManager.shared
    @State private var selectedLead: Lead?
    @State private var leadForMessaging: Lead?
    @State private var leadForCheckIn: Lead?

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Lead.followUpDate, ascending: true)],
        predicate: Lead.Status.activeFollowUpPredicate,
        animation: .default
    )
    private var followUpLeads: FetchedResults<Lead>

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                VStack(spacing: 0) {
                    Rectangle()
                        .fill(Color.obsidianBlack)
                        .frame(height: geometry.safeAreaInsets.top)

                    ObsidianHeaderView("Follow Up")

                    if followUpLeads.isEmpty {
                        emptyStateView
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 8) {
                                // OVERDUE section
                                if !overdueLeads.isEmpty {
                                    followUpSectionHeader("OVERDUE", color: Color.statusNotInterested, count: overdueLeads.count)
                                    ForEach(overdueLeads, id: \.id) { lead in
                                        followUpRow(for: lead)
                                    }
                                }

                                // TODAY section
                                if !todayLeads.isEmpty {
                                    followUpSectionHeader("TODAY", color: Color.electricViolet, count: todayLeads.count)
                                    ForEach(todayLeads, id: \.id) { lead in
                                        followUpRow(for: lead)
                                    }
                                }

                                // UPCOMING section
                                if !upcomingLeads.isEmpty {
                                    followUpSectionHeader("UPCOMING", color: Color.textSecondary, count: upcomingLeads.count)
                                    ForEach(upcomingLeads, id: \.id) { lead in
                                        followUpRow(for: lead)
                                    }
                                }
                            }
                            .padding(.vertical, 8)
                            .padding(.bottom, 12)
                        }
                    }
                }
                .ignoresSafeArea(.all, edges: .top)
            }
            .navigationBarHidden(true)
            .background(Color.obsidianBlack)
            .accessibilityIdentifier("followUpScreen")
            .sheet(item: $selectedLead) { lead in
                FollowUpDetailView(lead: lead)
            }
            .sheet(item: $leadForMessaging) { lead in
                MessageSelectionView(lead: lead)
            }
            .sheet(item: $leadForCheckIn) { lead in
                AddCheckInView(lead: lead)
            }
        }
    }

    private func deleteLeads(offsets: IndexSet) {
        guard paywallManager.gateAction() else { return }
        withAnimation {
            offsets.map { followUpLeads[$0] }.forEach { lead in
                // Instead of deleting the lead, just remove the follow-up date
                lead.setFollowUpDate(nil)
            }

            // Note: Context save is handled by setFollowUpDate()

            // Trigger immediate sync for follow-up deletions
            print("🔄 Follow-ups deleted, triggering immediate sync...")
            UserDataSyncManager.shared.syncWithServer()
        }
    }

    // MARK: - Urgency Grouping

    private var overdueLeads: [Lead] {
        followUpLeads.filter { lead in
            guard let date = lead.followUpDate else { return false }
            return date < Date() && !Calendar.current.isDateInToday(date)
        }
    }

    private var todayLeads: [Lead] {
        followUpLeads.filter { lead in
            guard let date = lead.followUpDate else { return false }
            return Calendar.current.isDateInToday(date)
        }
    }

    private var upcomingLeads: [Lead] {
        followUpLeads.filter { lead in
            guard let date = lead.followUpDate else { return false }
            return date > Date() && !Calendar.current.isDateInToday(date)
        }
    }

    private func followUpSectionHeader(_ title: String, color: Color, count: Int) -> some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(color)
                .frame(width: 3, height: 14)
            Text(title)
                .font(.micro)
                .textCase(.uppercase)
                .tracking(0.8)
                .foregroundColor(color)
            Text("\(count)")
                .font(.micro)
                .foregroundColor(color.opacity(0.7))
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 4)
    }

    @ViewBuilder
    private func followUpRow(for lead: Lead) -> some View {
        FollowUpInteractiveRowView(
            lead: lead,
            onTap: {
                selectedLead = lead
            },
            onMessageTap: {
                guard paywallManager.gateAction() else { return }
                leadForMessaging = lead
            },
            onCheckInTap: {
                guard paywallManager.gateAction() else { return }
                leadForCheckIn = lead
            },
            onDelete: {
                guard paywallManager.gateAction() else { return }
                // Remove follow-up date instead of deleting lead
                lead.setFollowUpDate(nil)
                UserDataSyncManager.shared.syncWithServer()
            }
        )
        .onLongPressGesture {
            guard paywallManager.gateAction() else { return }
            // Haptic feedback
            let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
            impactFeedback.impactOccurred()

            // Show delete confirmation
            let alert = UIAlertController(
                title: "Remove Follow-up",
                message: "Remove follow-up reminder for \(lead.displayName)?",
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
            alert.addAction(UIAlertAction(title: "Remove", style: .destructive) { _ in
                lead.setFollowUpDate(nil)
                UserDataSyncManager.shared.syncWithServer()
            })

            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let window = windowScene.windows.first {
                window.rootViewController?.present(alert, animated: true)
            }
        }
    }

    private var emptyStateView: some View {
        ObsidianEmptyState(
            icon: "calendar.badge.clock",
            title: "No Follow Ups",
            message: "Set a follow-up date on any lead and it will appear here in priority order."
        )
    }

}

struct FollowUpInteractiveRowView: View {
    @ObservedObject var lead: Lead
    let onTap: () -> Void
    let onMessageTap: () -> Void
    let onCheckInTap: () -> Void
    let onDelete: () -> Void

    var body: some View {
        let followUpDate = lead.followUpDate ?? Date()
        let accent = timeColor(for: followUpDate)

        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                ObsidianIconTile(
                    icon: timeIcon(for: followUpDate),
                    tint: accent,
                    size: 46
                )

                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(lead.displayName)
                            .font(.themeTitle)
                            .dynamicTypeSize(...DynamicTypeSize.accessibility2)
                            .foregroundColor(Color.textPrimary)
                            .lineLimit(1)
                            .accessibilityAddTraits(.isHeader)

                        Spacer(minLength: 6)

                        Label(timeStatus(for: followUpDate), systemImage: timeIcon(for: followUpDate))
                            .font(.micro)
                            .foregroundColor(accent)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(Capsule().fill(accent.opacity(0.12)))
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel("Follow-up status")
                            .accessibilityValue(timeStatus(for: followUpDate))
                    }

                    Text(followUpDate.formatted(.dateTime.month().day().hour().minute()))
                        .font(.obsidianFootnote)
                        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                        .foregroundColor(Color.textSecondary)
                        .lineLimit(1)

                    if let address = lead.address, !address.isEmpty {
                        Label(address, systemImage: "location.fill")
                            .font(.micro)
                            .foregroundColor(Color.textMuted)
                            .lineLimit(1)
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel("Address")
                            .accessibilityValue(address)
                    }
                }
            }

            HStack(spacing: 8) {
                followUpActionButton(
                    title: "Message",
                    icon: "message.fill",
                    tint: Color.electricViolet,
                    isEnabled: hasContactInfo,
                    action: onMessageTap
                )

                followUpActionButton(
                    title: "Check-in",
                    icon: "checkmark.circle.fill",
                    tint: Color.statusInterested,
                    action: onCheckInTap
                )

                Spacer(minLength: 0)
            }
        }
        .padding(14)
        .background(Color.obsidianSurface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.obsidianBorder.opacity(0.55), lineWidth: 0.5)
        )
        .shadow(color: Color.black.opacity(0.22), radius: 8, x: 0, y: 3)
        .padding(.horizontal, 16)
        .contentShape(Rectangle())
        .onTapGesture {
            onTap()
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button {
                rescheduleTo(days: 7)
            } label: {
                Label("+1 Week", systemImage: "calendar.badge.plus")
            }
            .tint(Color.electricViolet)

            Button {
                rescheduleTo(days: 1)
            } label: {
                Label("Tomorrow", systemImage: "sunrise")
            }
            .tint(Color.statusInterested)
        }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Remove", systemImage: "bell.slash")
            }
        }
        .contextMenu {
            Button {
                onTap()
            } label: {
                Label("View Details", systemImage: "eye")
            }

            Button {
                onMessageTap()
            } label: {
                Label("Send Message", systemImage: "message")
            }
            .disabled(!hasContactInfo)

            Button {
                onCheckInTap()
            } label: {
                Label("Record Check-in", systemImage: "checkmark.circle")
            }

            Divider()

            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Remove Follow-up", systemImage: "trash")
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func followUpActionButton(
        title: String,
        icon: String,
        tint: Color,
        isEnabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.micro)
                .foregroundColor(isEnabled ? tint : Color.textMuted)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Capsule().fill((isEnabled ? tint : Color.textMuted).opacity(0.12)))
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(!isEnabled)
    }

    private var hasContactInfo: Bool {
        !(lead.phone?.isEmpty ?? true) || !(lead.email?.isEmpty ?? true)
    }

    private var leadInitial: String {
        String(lead.displayName.prefix(1)).uppercased()
    }

    private func rescheduleTo(days: Int) {
        let calendar = Calendar.current
        let baseDate: Date
        if days == 1 {
            let tomorrow = calendar.date(byAdding: .day, value: 1, to: Date()) ?? Date().addingTimeInterval(86_400)
            baseDate = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow) ?? tomorrow
        } else {
            let from = lead.followUpDate ?? Date()
            baseDate = calendar.date(byAdding: .day, value: days, to: from) ?? from.addingTimeInterval(TimeInterval(days) * 86_400)
        }
        lead.setFollowUpDate(baseDate)
        NotificationService.shared.scheduleFollowUpNotification(for: lead)
        UserDataSyncManager.shared.syncWithServer()
        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
        impactFeedback.impactOccurred()
    }

    private func timeIcon(for date: Date) -> String {
        let now = Date()
        if date < now {
            return "exclamationmark.triangle.fill"
        } else if Calendar.current.isDateInToday(date) {
            return "clock.fill"
        } else {
            return "calendar"
        }
    }

    private func timeColor(for date: Date) -> Color {
        let now = Date()
        if date < now {
            return Color.statusNotInterested
        } else if Calendar.current.isDateInToday(date) {
            return Color.statusNotHome
        } else {
            return Color.electricViolet
        }
    }

    private func timeStatus(for date: Date) -> String {
        let now = Date()
        if date < now {
            return "Overdue"
        } else if Calendar.current.isDateInToday(date) {
            return "Today"
        } else if Calendar.current.isDateInTomorrow(date) {
            return "Tomorrow"
        } else {
            let days = Calendar.current.dateComponents([.day], from: now, to: date).day ?? 0
            return "In \(days) days"
        }
    }
}

struct FollowUpDetailView: View {
    @ObservedObject var lead: Lead
    @Environment(\.dismiss) private var dismiss
    @State private var leadForMessaging: Lead?
    @State private var leadForCheckIn: Lead?
    @State private var showingLeadDetail = false
    @State private var showingRescheduleView = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        followUpHeaderSection
                        followUpDetailsSection
                        followUpActionsSection
                    }
                    .padding()
                    .padding(.bottom, 16)
                }

                followUpBottomBar
            }
            .background(Color.obsidianBlack)
            .navigationTitle("Follow-Up")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(true)
            .sheet(item: $leadForMessaging) { lead in
                MessageSelectionView(lead: lead)
            }
            .sheet(item: $leadForCheckIn) { lead in
                AddCheckInView(lead: lead)
            }
            .sheet(isPresented: $showingLeadDetail) {
                LeadDetailView(lead: lead)
            }
            .sheet(isPresented: $showingRescheduleView) {
                RescheduleFollowUpView(lead: lead, currentDate: lead.followUpDate ?? Date())
            }
        }
    }

    private var followUpHeaderSection: some View {
        let followUpDate = lead.followUpDate ?? Date()
        let accent = timeColor(for: followUpDate)

        return HStack(alignment: .top, spacing: 12) {
            ObsidianIconTile(
                icon: timeIcon(for: followUpDate),
                tint: accent,
                size: 46,
                filled: true
            )

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(lead.displayName)
                        .font(.themeTitle)
                        .foregroundColor(Color.textPrimary)
                        .lineLimit(1)

                    Spacer(minLength: 6)

                    Label(timeStatus(for: followUpDate), systemImage: timeIcon(for: followUpDate))
                        .font(.micro)
                        .foregroundColor(accent)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(accent.opacity(0.12)))
                }

                Text(lead.address.flatMap { address in
                    let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
                    return trimmed.isEmpty ? nil : trimmed
                } ?? "No address saved")
                    .font(.obsidianFootnote)
                    .foregroundColor(Color.textSecondary)
                    .lineLimit(2)

                if let followUpDate = lead.followUpDate {
                    Label(followUpDate.formatted(.dateTime.weekday(.abbreviated).month().day().hour().minute()), systemImage: "calendar.badge.clock")
                        .font(.micro)
                        .foregroundColor(Color.textMuted)
                }
            }
        }
        .padding()
        .background(Color.obsidianElevated)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.obsidianBorder.opacity(0.6), lineWidth: 0.5)
        )
    }

    private var followUpDetailsSection: some View {
        LeadFormSectionCard(title: "Follow-Up Details", icon: "calendar.badge.clock") {
            VStack(spacing: 12) {
                if let followUpDate = lead.followUpDate {
                    ObsidianDetailRow(
                        title: "Status",
                        value: timeStatus(for: followUpDate),
                        icon: timeIcon(for: followUpDate),
                        tint: timeColor(for: followUpDate),
                        valueColor: timeColor(for: followUpDate)
                    )

                    ObsidianDetailRow(
                        title: "Date",
                        value: followUpDate.formatted(.dateTime.day().month().year().weekday(.wide)),
                        icon: "calendar",
                        tint: Color.electricViolet
                    )

                    ObsidianDetailRow(
                        title: "Time",
                        value: followUpDate.formatted(.dateTime.hour().minute()),
                        icon: "clock.fill",
                        tint: Color.statusNotHome
                    )
                } else {
                    ObsidianDetailRow(
                        title: "Status",
                        value: "No follow-up scheduled",
                        icon: "calendar.badge.minus",
                        tint: Color.textMuted,
                        valueColor: Color.textSecondary
                    )
                }

                if let notes = lead.notes, !notes.isEmpty {
                    Text(notes)
                        .font(.obsidianBody)
                        .foregroundColor(Color.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(Color.obsidianElevated)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(Color.obsidianBorder.opacity(0.45), lineWidth: 0.5)
                        )
                }
            }
        }
    }

    private var followUpActionsSection: some View {
        LeadFormSectionCard(title: "Quick Actions", icon: "bolt.fill") {
            VStack(spacing: 12) {
                ObsidianActionTile(
                    title: "Send Message",
                    subtitle: hasContactInfo ? "Use saved phone or email." : "Add contact info before messaging.",
                    icon: "message.fill",
                    tint: Color.electricViolet,
                    isEnabled: hasContactInfo
                ) {
                    leadForMessaging = lead
                }

                ObsidianActionTile(
                    title: "Record Check-in",
                    subtitle: "Log what happened after contacting this customer.",
                    icon: "checkmark.circle.fill",
                    tint: Color.statusInterested
                ) {
                    leadForCheckIn = lead
                }

                if lead.followUpDate != nil {
                    ObsidianActionTile(
                        title: "Reschedule",
                        subtitle: "Move this reminder to a new date or time.",
                        icon: "calendar.badge.plus",
                        tint: Color.statusNotHome
                    ) {
                        showingRescheduleView = true
                    }
                }

                ObsidianActionTile(
                    title: "View Full Lead",
                    subtitle: "Open customer details, status, notes, and history.",
                    icon: "person.text.rectangle.fill",
                    tint: Color.electricViolet
                ) {
                    showingLeadDetail = true
                }
            }
        }
    }

    @ViewBuilder
    private var followUpBottomBar: some View {
        HStack(spacing: 12) {
            if lead.followUpDate != nil {
                Button {
                    completeFollowUp()
                } label: {
                    Label("Complete", systemImage: "checkmark.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(ObsidianSecondaryButtonStyle())
            }

            Button {
                dismiss()
            } label: {
                Label("Done", systemImage: "checkmark.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(ObsidianPrimaryButtonStyle())
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.obsidianElevated)
                .shadow(color: Color.black.opacity(0.35), radius: 10, x: 0, y: -3)
        )
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
        .background(Color.obsidianBlack.ignoresSafeArea(edges: .bottom))
    }

    private var leadInitial: String {
        String(lead.displayName.prefix(1)).uppercased()
    }

    private var hasContactInfo: Bool {
        !(lead.phone?.isEmpty ?? true) || !(lead.email?.isEmpty ?? true)
    }

    private func timeIcon(for date: Date) -> String {
        let now = Date()
        if date < now {
            return "exclamationmark.triangle.fill"
        } else if Calendar.current.isDateInToday(date) {
            return "clock.fill"
        } else {
            return "calendar"
        }
    }

    private func timeColor(for date: Date) -> Color {
        let now = Date()
        if date < now {
            return Color.statusNotInterested
        } else if Calendar.current.isDateInToday(date) {
            return Color.statusNotHome
        } else {
            return Color.electricViolet
        }
    }

    private func timeStatus(for date: Date) -> String {
        let now = Date()
        if date < now {
            return "Overdue"
        } else if Calendar.current.isDateInToday(date) {
            return "Today"
        } else if Calendar.current.isDateInTomorrow(date) {
            return "Tomorrow"
        } else {
            let days = Calendar.current.dateComponents([.day], from: now, to: date).day ?? 0
            return "In \(days) days"
        }
    }

    private func completeFollowUp() {
        lead.setFollowUpDate(nil)
        dismiss()
    }
}

struct RescheduleFollowUpView: View {
    @ObservedObject var lead: Lead
    let currentDate: Date
    @Environment(\.dismiss) private var dismiss
    @State private var newDate: Date

    init(lead: Lead, currentDate: Date) {
        self.lead = lead
        self.currentDate = currentDate
        self._newDate = State(initialValue: currentDate)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    ObsidianScreenTitle(
                        title: "Reschedule",
                        subtitle: "Move the follow-up reminder for \(lead.displayName).",
                        icon: "calendar.badge.clock"
                    )

                    changeSummarySection
                    dateSelectionSection
                    reminderSummarySection
                }
                .padding(.horizontal, 16)
                .padding(.top, 18)
                .padding(.bottom, 28)
            }
            .background(Color.obsidianBlack.ignoresSafeArea())
            .navigationTitle("Reschedule")
            .obsidianInlineNavigation()
            .safeAreaInset(edge: .bottom) {
                ObsidianBottomActionBar(
                    isPrimaryDisabled: newDate <= Date(),
                    primaryAction: save,
                    secondaryAction: { dismiss() },
                    primaryLabel: {
                        Label("Save", systemImage: "checkmark.circle.fill")
                    },
                    secondaryLabel: {
                        Label("Cancel", systemImage: "xmark.circle.fill")
                    }
                )
            }
        }
        .presentationBackground(Color.obsidianBlack)
    }

    private var changeSummarySection: some View {
        ObsidianSectionCard(
            title: "Move Reminder",
            icon: "arrow.right.circle.fill",
            subtitle: "Check the old time against the new one before saving."
        ) {
            HStack(spacing: 10) {
                reminderDateCard(
                    title: "Current",
                    date: currentDate,
                    color: Color.statusNotInterested,
                    isStruckThrough: true
                )

                Image(systemName: "arrow.right")
                    .font(.obsidianFootnote)
                    .foregroundColor(Color.textMuted)

                reminderDateCard(
                    title: "New",
                    date: newDate,
                    color: newDate <= Date() ? Color.statusNotInterested : Color.statusInterested
                )
            }
        }
    }

    private var dateSelectionSection: some View {
        ObsidianSectionCard(
            title: "New Date & Time",
            icon: "calendar",
            subtitle: "Pick an exact time or use one of the common presets."
        ) {
            VStack(alignment: .leading, spacing: 14) {
                DatePicker(
                    "Follow-up Date",
                    selection: $newDate,
                    in: Date()...,
                    displayedComponents: [.date, .hourAndMinute]
                )
                .datePickerStyle(.compact)
                .font(.obsidianCallout)
                .foregroundColor(Color.textPrimary)
                .padding(12)
                .background(Color.obsidianElevated)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.obsidianBorder.opacity(0.45), lineWidth: 0.5)
                )

                VStack(alignment: .leading, spacing: 10) {
                    Text("Quick Suggestions")
                        .font(.obsidianFootnote)
                        .foregroundColor(Color.textSecondary)

                    LazyVGrid(columns: [
                        GridItem(.flexible(), spacing: 8),
                        GridItem(.flexible(), spacing: 8)
                    ], spacing: 8) {
                        QuickTimeButton(title: "Tomorrow 9 AM", date: quickDate(days: 1, hour: 9), selectedDate: $newDate)
                        QuickTimeButton(title: "Tomorrow 2 PM", date: quickDate(days: 1, hour: 14), selectedDate: $newDate)
                        QuickTimeButton(title: "In 3 Days 10 AM", date: quickDate(days: 3, hour: 10), selectedDate: $newDate)
                        QuickTimeButton(title: "Next Week 9 AM", date: quickDate(days: 7, hour: 9), selectedDate: $newDate)
                    }
                }
            }
        }
    }

    private var reminderSummarySection: some View {
        ObsidianStatusBanner(
            icon: newDate <= Date() ? "exclamationmark.triangle.fill" : "checkmark.circle.fill",
            title: newDate <= Date() ? "Choose a future time" : "Reminder will move to \(newDate.formatted(.dateTime.weekday(.abbreviated).month().day().hour().minute()))",
            message: timeUntilFollowUp.map { "That is \($0) from now." },
            tint: newDate <= Date() ? Color.statusNotInterested : Color.statusInterested
        )
    }

    private func reminderDateCard(title: String, date: Date, color: Color, isStruckThrough: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.micro)
                .foregroundColor(Color.textSecondary)
                .textCase(.uppercase)

            Text(date.formatted(.dateTime.month().day().hour().minute()))
                .font(.obsidianCallout)
                .foregroundColor(color)
                .strikethrough(isStruckThrough)
                .lineLimit(2)
                .minimumScaleFactor(0.82)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.obsidianElevated)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(color.opacity(0.35), lineWidth: 0.5)
        )
    }

    private func quickDate(days: Int, hour: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: days, to: Date())?.setting(hour: hour, minute: 0) ?? Date()
    }

    private func save() {
        guard newDate > Date() else { return }
        lead.setFollowUpDate(newDate)
        dismiss()
    }

    private var timeUntilFollowUp: String? {
        let timeInterval = newDate.timeIntervalSince(Date())
        if timeInterval <= 0 { return nil }

        let days = Int(timeInterval / 86400)
        let hours = Int((timeInterval.truncatingRemainder(dividingBy: 86400)) / 3600)

        if days > 0 {
            return days == 1 ? "1 day" : "\(days) days"
        } else if hours > 0 {
            return hours == 1 ? "1 hour" : "\(hours) hours"
        } else {
            let minutes = Int((timeInterval.truncatingRemainder(dividingBy: 3600)) / 60)
            return minutes == 1 ? "1 minute" : "\(minutes) minutes"
        }
    }
}

struct QuickTimeButton: View {
    let title: String
    let date: Date
    @Binding var selectedDate: Date

    private var isSelected: Bool {
        Calendar.current.isDate(selectedDate, equalTo: date, toGranularity: .minute)
    }

    var body: some View {
        Button(action: {
            selectedDate = date
        }) {
            HStack(spacing: 6) {
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.micro)
                }

                Text(title)
                    .font(.micro)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }
            .foregroundColor(isSelected ? .white : Color.electricViolet)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isSelected ? Color.electricViolet : Color.electricViolet.opacity(0.1))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.electricViolet.opacity(isSelected ? 0.0 : 0.3), lineWidth: 1)
                    )
                )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

extension Date {
    func setting(hour: Int, minute: Int) -> Date? {
        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month, .day], from: self)
        components.hour = hour
        components.minute = minute
        return calendar.date(from: components)
    }
}

#Preview {
    let context = PersistenceController.preview.container.viewContext

    // Create sample leads with follow-up dates
    let lead1 = Lead.create(in: context)
    lead1.name = "John Doe"
    lead1.followUpDate = Calendar.current.date(byAdding: .hour, value: 2, to: Date())
    lead1.address = "123 Main St, Toronto, ON"
    lead1.notes = "Very interested in our service"

    let lead2 = Lead.create(in: context)
    lead2.name = "Jane Smith"
    lead2.followUpDate = Calendar.current.date(byAdding: .day, value: -1, to: Date())
    lead2.address = "456 Oak Ave, Toronto, ON"

    return FollowUpView()
        .environment(\.managedObjectContext, context)
}
