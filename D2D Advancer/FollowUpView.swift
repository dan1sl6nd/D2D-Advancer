import SwiftUI
import CoreData

struct FollowUpView: View {
    let isEmbeddedInWork: Bool

    @Environment(\.colorScheme) private var colorScheme

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Lead.followUpDate, ascending: true)],
        predicate: Lead.Status.activeFollowUpPredicate,
        animation: .default
    )
    private var followUpLeads: FetchedResults<Lead>

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \FollowUpCheckIn.checkInDate, ascending: false)],
        predicate: NSPredicate(
            format: "checkInDate >= %@",
            Date().addingTimeInterval(-30 * 24 * 60 * 60) as NSDate
        ),
        animation: .default
    )
    private var recentCheckIns: FetchedResults<FollowUpCheckIn>

    init(isEmbeddedInWork: Bool = false) {
        self.isEmbeddedInWork = isEmbeddedInWork
    }

    @ViewBuilder
    var body: some View {
        if isEmbeddedInWork {
            screenContent
        } else {
            NavigationStack {
                screenContent
            }
        }
    }

    private var screenContent: some View {
        GeometryReader { geometry in
            let screenBackground = Color.obsidianBackground(for: colorScheme)

            VStack(spacing: 0) {
                if !isEmbeddedInWork {
                    Rectangle()
                        .fill(screenBackground)
                        .frame(height: ObsidianLayout.safeAreaTop(geometry))

                    ObsidianHeaderView("Follow Up")
                }

                FollowUpQueueContent(
                    personalLeads: Array(followUpLeads),
                    recentCheckIns: Array(recentCheckIns)
                )
            }
            .ignoresSafeArea(.all, edges: isEmbeddedInWork ? [] : .top)
        }
        .navigationBarHidden(true)
        .background(Color.obsidianBackground(for: colorScheme))
        .accessibilityIdentifier("followUpScreen")
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
        .accessibilityIdentifier("followUpRow")
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
        .accessibilityLabel("\(lead.displayName), \(timeStatus(for: followUpDate)), \(followUpDate.formatted(.dateTime.month().day().hour().minute()))")
        .accessibilityHint("Open follow-up details")
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
        NotificationService.shared.requestPermissionAfterSchedulingIfNeeded()
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
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @State private var leadForMessaging: Lead?
    @State private var leadForCheckIn: Lead?
    @State private var showingLeadDetail = false
    @State private var showingRescheduleView = false
    @State private var showingHistory = false
    @State private var outcomeRequest: FollowUpOutcomeRequest?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        followUpHeaderSection
                        followUpDetailsSection
                        followUpActionsSection
                        followUpHistorySection
                    }
                    .padding()
                    .padding(.bottom, 16)
                }
                .accessibilityIdentifier("followUpDetailScreen")

                followUpBottomBar
            }
            .background(Color.obsidianBackground(for: colorScheme))
            .obsidianPushedNavigation(
                "Follow-Up",
                backButtonAccessibilityIdentifier: "followUpDetailBackButton"
            )
            .sheet(item: $leadForMessaging) { lead in
                MessageSelectionView(lead: lead) { method in
                    leadForMessaging = nil
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        outcomeRequest = FollowUpOutcomeRequest(
                            target: .personal(lead),
                            method: method
                        )
                    }
                }
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
            .sheet(isPresented: $showingHistory) {
                FollowUpHistoryView(lead: lead)
            }
            .sheet(item: $outcomeRequest) { request in
                FollowUpOutcomeSheet(request: request) {}
            }
        }
        .obsidianModalBackground()
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
                .accessibilityIdentifier("followUpDetailMessageButton")

                ObsidianActionTile(
                    title: "Record Check-in",
                    subtitle: "Log what happened after contacting this customer.",
                    icon: "checkmark.circle.fill",
                    tint: Color.statusInterested
                ) {
                    leadForCheckIn = lead
                }
                .accessibilityIdentifier("followUpDetailCheckInButton")

                if lead.followUpDate != nil {
                    ObsidianActionTile(
                        title: "Reschedule",
                        subtitle: "Move this reminder to a new date or time.",
                        icon: "calendar.badge.plus",
                        tint: Color.statusNotHome
                    ) {
                        showingRescheduleView = true
                    }
                    .accessibilityIdentifier("followUpDetailRescheduleButton")
                }

                ObsidianActionTile(
                    title: "View Full Lead",
                    subtitle: "Open customer details, status, notes, and history.",
                    icon: "person.text.rectangle.fill",
                    tint: Color.electricViolet
                ) {
                    showingLeadDetail = true
                }
                .accessibilityIdentifier("followUpDetailViewLeadButton")
            }
        }
    }

    @ViewBuilder
    private var followUpHistorySection: some View {
        if !lead.sortedCheckIns.isEmpty {
            LeadFormSectionCard(title: "Recent Contact", icon: "clock.arrow.circlepath") {
                VStack(spacing: 12) {
                    ForEach(Array(lead.sortedCheckIns.prefix(3)), id: \.objectID) { checkIn in
                        HStack(alignment: .top, spacing: 10) {
                            ObsidianIconTile(
                                icon: checkIn.checkInTypeEnum.icon,
                                tint: historyTint(for: checkIn),
                                size: 34
                            )

                            VStack(alignment: .leading, spacing: 3) {
                                Text(checkIn.outcomeEnum?.displayName ?? checkIn.checkInTypeEnum.displayName)
                                    .font(.obsidianCallout)
                                    .foregroundColor(Color.textPrimary)

                                Text(checkIn.checkInDate?.formatted(.dateTime.month().day().hour().minute()) ?? "Date unavailable")
                                    .font(.obsidianFootnote)
                                    .foregroundColor(Color.textSecondary)

                                if let notes = checkIn.notes, !notes.isEmpty {
                                    Text(notes)
                                        .font(.obsidianFootnote)
                                        .foregroundColor(Color.textSecondary)
                                        .lineLimit(2)
                                }
                            }

                            Spacer(minLength: 0)
                        }
                    }

                    Button {
                        showingHistory = true
                    } label: {
                        Label("View all contact history", systemImage: "chevron.right")
                            .font(.obsidianFootnote)
                            .fontWeight(.semibold)
                            .foregroundColor(Color.electricViolet)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("followUpDetailHistoryButton")
                }
            }
        }
    }

    @ViewBuilder
    private var followUpBottomBar: some View {
        HStack(spacing: 12) {
            if lead.followUpDate != nil {
                followUpActionButton(
                    title: "Complete",
                    icon: "checkmark.circle.fill",
                    tone: .secondary,
                    accessibilityIdentifier: "followUpDetailCompleteButton"
                ) {
                    completeFollowUp()
                }
            }

            followUpActionButton(
                title: "Done",
                icon: "checkmark.circle.fill",
                tone: .primary,
                accessibilityIdentifier: "followUpDetailDoneButton"
            ) {
                dismiss()
            }
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
        .background(Color.obsidianBackground(for: colorScheme).ignoresSafeArea(edges: .bottom))
    }

    private func followUpActionButton(
        title: String,
        icon: String,
        tone: FollowUpActionTone,
        accessibilityIdentifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .bold))
                    .frame(width: 16, height: 16)

                Text(title)
                    .font(.system(size: 15, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .allowsTightening(true)
            }
            .foregroundColor(tone.foregroundColor)
            .frame(maxWidth: .infinity, minHeight: 48)
            .padding(.horizontal, 8)
            .background(tone.backgroundColor)
            .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .stroke(tone.borderColor, lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
        }
        .buttonStyle(.plain)
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityIdentifier(accessibilityIdentifier)
    }

    private enum FollowUpActionTone {
        case primary
        case secondary

        var foregroundColor: Color {
            switch self {
            case .primary:
                return .white
            case .secondary:
                return Color.textPrimary
            }
        }

        var backgroundColor: Color {
            switch self {
            case .primary:
                return Color.electricViolet
            case .secondary:
                return Color.obsidianSurface
            }
        }

        var borderColor: Color {
            switch self {
            case .primary:
                return Color.electricViolet.opacity(0.85)
            case .secondary:
                return Color.obsidianBorder.opacity(0.75)
            }
        }
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
        do {
            try FollowUpOutcomeRecorder.recordPersonal(
                lead: lead,
                outcome: .done,
                method: .manual,
                note: "Completed from follow-up detail",
                selectedNextDate: nil,
                in: viewContext
            )
            dismiss()
        } catch {
            print("Failed to complete follow-up: \(error.localizedDescription)")
        }
    }

    private func historyTint(for checkIn: FollowUpCheckIn) -> Color {
        switch checkIn.outcomeEnum {
        case .interested, .successful:
            return Color.statusInterested
        case .converted:
            return Color.statusConverted
        case .notInterested:
            return Color.statusNotInterested
        case .callback, .reschedule, .noAnswer:
            return Color.statusNotHome
        case .none:
            return Color.electricViolet
        }
    }
}

struct RescheduleFollowUpView: View {
    @ObservedObject var lead: Lead
    let currentDate: Date
    @Environment(\.colorScheme) private var colorScheme
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
                    Text(lead.displayName)
                        .font(.obsidianCallout)
                        .foregroundColor(Color.textSecondary)
                        .padding(.horizontal, 4)

                    changeSummarySection
                    dateSelectionSection
                    reminderSummarySection
                }
                .padding(.horizontal, 16)
                .padding(.top, 18)
                .padding(.bottom, 28)
            }
            .background(Color.obsidianBackground(for: colorScheme).ignoresSafeArea())
            .accessibilityIdentifier("followUpRescheduleSheet")
            .obsidianPushedNavigation(
                "Reschedule",
                backButtonAccessibilityIdentifier: "followUpRescheduleBackButton",
                onBack: { dismiss() }
            )
            .safeAreaInset(edge: .bottom) {
                ObsidianBottomActionBar(
                    isPrimaryDisabled: newDate <= Date(),
                    primaryAccessibilityIdentifier: "followUpRescheduleSaveButton",
                    secondaryAccessibilityIdentifier: "followUpRescheduleCancelButton",
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
        .obsidianModalBackground()
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
                .accessibilityIdentifier("followUpRescheduleDatePicker")
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
                        QuickTimeButton(title: "Tomorrow 9 AM", date: quickDate(days: 1, hour: 9), selectedDate: $newDate, accessibilityIdentifier: "followUpRescheduleTomorrow9Button")
                        QuickTimeButton(title: "Tomorrow 2 PM", date: quickDate(days: 1, hour: 14), selectedDate: $newDate, accessibilityIdentifier: "followUpRescheduleTomorrow2Button")
                        QuickTimeButton(title: "In 3 Days 10 AM", date: quickDate(days: 3, hour: 10), selectedDate: $newDate, accessibilityIdentifier: "followUpReschedule3DaysButton")
                        QuickTimeButton(title: "Next Week 9 AM", date: quickDate(days: 7, hour: 9), selectedDate: $newDate, accessibilityIdentifier: "followUpRescheduleNextWeekButton")
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
        NotificationService.shared.requestPermissionAfterSchedulingIfNeeded()
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
    var accessibilityIdentifier: String? = nil

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
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isSelected ? Color.electricViolet : Color.electricViolet.opacity(0.1))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.electricViolet.opacity(isSelected ? 0.0 : 0.3), lineWidth: 1)
                    )
                )
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityIdentifier(accessibilityIdentifier ?? title)
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
