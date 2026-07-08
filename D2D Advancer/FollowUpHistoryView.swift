import SwiftUI
import CoreData

struct FollowUpHistoryView: View {
    let lead: Lead
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    @State private var showingAddCheckIn = false

    @FetchRequest private var checkIns: FetchedResults<FollowUpCheckIn>

    init(lead: Lead) {
        self.lead = lead

        // Create a fetch request for this specific lead's check-ins
        let request: NSFetchRequest<FollowUpCheckIn> = FollowUpCheckIn.fetchRequest()
        request.predicate = NSPredicate(format: "lead == %@", lead)
        request.sortDescriptors = [NSSortDescriptor(keyPath: \FollowUpCheckIn.checkInDate, ascending: false)]

        self._checkIns = FetchRequest(fetchRequest: request)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                leadSummaryHeader

                if checkIns.isEmpty {
                    ObsidianEmptyState(
                        icon: "clock.arrow.circlepath",
                        title: "No follow-ups recorded",
                        message: "Record the first check-in to keep this lead history useful.",
                        actionTitle: "Record Check-in",
                        actionIcon: "plus",
                        action: { showingAddCheckIn = true }
                    )
                } else {
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(checkIns, id: \.id) { checkIn in
                                SwipeToDeleteCheckInRow(checkIn: checkIn) {
                                    deleteCheckIn(checkIn)
                                }
                            }
                        }
                        .padding(.vertical, 8)
                    }
                }
            }
            .accessibilityIdentifier("followUpHistoryScreen")
            .obsidianScreenBackground()
            .obsidianPushedNavigation(
                "Follow-up History",
                backButtonAccessibilityIdentifier: "followUpHistoryBackButton",
                onBack: { dismiss() }
            ) {
                ObsidianCompactIconButton(
                    icon: "plus",
                    accessibilityLabel: "Add follow-up check-in",
                    accessibilityIdentifier: "followUpHistoryAddCheckInButton",
                    action: { showingAddCheckIn = true }
                )
            }
            .sheet(isPresented: $showingAddCheckIn) {
                AddCheckInView(lead: lead)
            }
            .obsidianModalBackground()
            .onAppear {
                migrateCheckInOutcomes()
            }
        }
    }

    private var leadSummaryHeader: some View {
        LeadFormSectionCard(title: "Lead", icon: "person.crop.circle.fill") {
            VStack(spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(lead.displayName)
                            .font(.obsidianHeadline)
                            .foregroundColor(.textPrimary)

                        if let address = lead.address {
                            Text(address)
                                .font(.obsidianFootnote)
                                .foregroundColor(Color.textSecondary)
                        }
                    }

                    Spacer()

                    StatusBadge(status: LeadStatus.from(leadStatus: lead.leadStatus))
                }

                HStack(spacing: 20) {
                    VStack {
                        Text("\(lead.checkInCount)")
                            .font(.obsidianHeadline)
                            .foregroundColor(Color.electricViolet)
                        Text("Check-ins")
                            .font(.obsidianSmall)
                            .foregroundColor(Color.textSecondary)
                    }

                    Divider()
                        .frame(height: 30)

                    VStack {
                        if let lastCheckIn = lead.lastCheckIn {
                            Text(lastCheckIn.formattedCheckInDate)
                                .font(.obsidianFootnote)
                                .foregroundColor(.textPrimary)
                        } else {
                            Text("Never")
                                .font(.obsidianFootnote)
                                .foregroundColor(.textPrimary)
                        }
                        Text("Last Contact")
                            .font(.obsidianSmall)
                            .foregroundColor(Color.textSecondary)
                    }

                    Spacer()
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func migrateCheckInOutcomes() {
        var hasChanges = false

        print("FollowUpHistoryView: Running migration for \(checkIns.count) check-ins...")

        for checkIn in checkIns {
            // If the check-in doesn't have an outcome, add a default one
            if checkIn.outcome == nil || checkIn.outcome?.isEmpty == true {
                print("FollowUpHistoryView: Migrating check-in \(checkIn.id?.uuidString ?? "unknown") - setting outcome to successful")
                checkIn.outcomeEnum = .successful  // Default to successful contact
                hasChanges = true
            } else {
                print("FollowUpHistoryView: Check-in \(checkIn.id?.uuidString ?? "unknown") already has outcome: \(checkIn.outcome ?? "nil")")
            }
        }

        if hasChanges {
            print("FollowUpHistoryView: Saving \(checkIns.count) check-ins with new outcomes...")
            do {
                try viewContext.save()
                print("FollowUpHistoryView: Successfully migrated check-in outcomes")
            } catch {
                print("FollowUpHistoryView: Error migrating check-in outcomes: \(error)")
                viewContext.rollback()
            }
        } else {
            print("FollowUpHistoryView: No check-ins needed migration")
        }
    }

    private func deleteCheckIn(_ checkIn: FollowUpCheckIn) {
        lead.updatedDate = Date()
        viewContext.delete(checkIn)

        do {
            try viewContext.save()
        } catch {
            print("Error deleting check-in: \(error)")
            viewContext.rollback()
        }
    }
}

struct CheckInInteractiveRowView: View {
    let checkIn: FollowUpCheckIn
    let onDelete: () -> Void

    var body: some View {
        let typeColor = getCheckInColor()
        let outcomeColor = getOutcomeColor()

        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                ObsidianIconTile(icon: getCheckInIcon(), tint: typeColor, size: 42)

                VStack(alignment: .leading, spacing: 6) {
                    Text(getCheckInType())
                        .font(.obsidianCallout)
                        .foregroundColor(Color.textPrimary)

                    Label(getOutcomeText(), systemImage: "circle.fill")
                        .font(.micro)
                        .foregroundColor(outcomeColor)
                        .labelStyle(.titleAndIcon)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(outcomeColor.opacity(0.12)))
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 3) {
                    Text(checkIn.checkInDate?.formatted(.dateTime.month().day()) ?? "No date")
                        .font(.obsidianFootnote)
                        .foregroundColor(Color.textPrimary)

                    Text(checkIn.checkInDate?.formatted(.dateTime.hour().minute()) ?? "")
                        .font(.micro)
                        .foregroundColor(Color.textSecondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Color.obsidianElevated)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

            if let notes = checkIn.notes, !notes.isEmpty {
                Text(notes)
                    .font(.obsidianBody)
                    .foregroundColor(Color.textSecondary)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.obsidianElevated)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.obsidianBorder.opacity(0.45), lineWidth: 0.5)
                    )
                    .lineLimit(nil)
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
        .contextMenu {
            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Delete Check-in", systemImage: "trash")
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func getCheckInIcon() -> String {
        switch checkIn.checkInTypeEnum {
        case .phoneCall: return "phone.fill"
        case .email: return "envelope.fill"
        case .smsMessage: return "message.fill"
        case .inPersonMeeting: return "person.2.fill"
        case .virtualMeeting: return "video.fill"
        case .doorKnock: return "door.left.hand.open"
        }
    }

    private func getCheckInColor() -> Color {
        switch checkIn.checkInTypeEnum {
        case .phoneCall: return Color.electricViolet
        case .email: return Color.electricViolet
        case .smsMessage: return Color.statusInterested
        case .inPersonMeeting: return Color.statusNotInterested
        case .virtualMeeting: return Color.statusNotHome
        case .doorKnock: return .brown
        }
    }

    private func getCheckInType() -> String {
        return checkIn.checkInTypeEnum.displayName
    }

    private func getOutcomeColor() -> Color {
        guard let outcome = checkIn.outcomeEnum else { return Color.textSecondary }
        switch outcome {
        case .interested, .successful: return Color.statusInterested
        case .notInterested: return Color.statusNotInterested
        case .callback, .reschedule, .noAnswer: return Color.statusNotHome
        case .converted: return Color.electricViolet
        }
    }

    private func getOutcomeText() -> String {
        return checkIn.outcomeEnum?.displayName ?? "Unknown"
    }
}

struct CheckInRowView: View {
    let checkIn: FollowUpCheckIn
    let onDelete: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ObsidianIconTile(icon: checkInIcon, tint: checkInColor, size: 34)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(checkInType)
                        .font(.obsidianCallout)
                        .foregroundColor(Color.textPrimary)
                        .lineLimit(1)

                    Text(outcomeText)
                        .font(.micro)
                        .foregroundColor(outcomeColor)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(outcomeColor.opacity(0.12)))
                }

                Text(checkIn.checkInDate?.formatted(.dateTime.month().day().hour().minute()) ?? "No date saved")
                    .font(.obsidianFootnote)
                    .foregroundColor(Color.textSecondary)

                if let notes = checkIn.notes, !notes.isEmpty {
                    Text(notes)
                        .font(.obsidianFootnote)
                        .foregroundColor(Color.textSecondary)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 8)

            Button(action: onDelete) {
                Image(systemName: "trash.fill")
                    .font(.micro)
                    .foregroundColor(Color.statusNotInterested)
                    .frame(width: 30, height: 30)
                    .background(Color.statusNotInterested.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(PlainButtonStyle())
            .accessibilityLabel("Delete check-in")
        }
        .accessibilityElement(children: .combine)
    }

    private var checkInType: String {
        checkIn.checkInTypeEnum.displayName
    }

    private var checkInIcon: String {
        switch checkIn.checkInTypeEnum {
        case .phoneCall: return "phone.fill"
        case .email: return "envelope.fill"
        case .smsMessage: return "message.fill"
        case .inPersonMeeting: return "person.2.fill"
        case .virtualMeeting: return "video.fill"
        case .doorKnock: return "door.left.hand.open"
        }
    }

    private var checkInColor: Color {
        switch checkIn.checkInTypeEnum {
        case .phoneCall, .email: return Color.electricViolet
        case .smsMessage: return Color.statusInterested
        case .inPersonMeeting: return Color.statusNotInterested
        case .virtualMeeting: return Color.statusNotHome
        case .doorKnock: return Color.statusConverted
        }
    }

    private var outcomeText: String {
        checkIn.outcomeEnum?.displayName ?? "No outcome"
    }

    private var outcomeColor: Color {
        guard let outcome = checkIn.outcomeEnum else { return Color.textSecondary }
        switch outcome {
        case .interested, .successful: return Color.statusInterested
        case .notInterested: return Color.statusNotInterested
        case .callback, .reschedule, .noAnswer: return Color.statusNotHome
        case .converted: return Color.electricViolet
        }
    }
}

#Preview {
    let context = PersistenceController.preview.container.viewContext
    let lead = Lead.create(in: context)
    lead.name = "John Doe"
    lead.address = "123 Main St, Toronto, ON"
    lead.leadStatus = .interested

    // Create sample check-ins
    let checkIn1 = FollowUpCheckIn.create(in: context, for: lead)
    checkIn1.checkInTypeEnum = .doorKnock
    checkIn1.outcomeEnum = .noAnswer
    checkIn1.notes = "No one home, left a business card"
    checkIn1.checkInDate = Calendar.current.date(byAdding: .day, value: -2, to: Date())

    let checkIn2 = FollowUpCheckIn.create(in: context, for: lead)
    checkIn2.checkInTypeEnum = .phoneCall
    checkIn2.outcomeEnum = .interested
    checkIn2.notes = "Spoke with homeowner, very interested in our services"
    checkIn2.checkInDate = Calendar.current.date(byAdding: .day, value: -1, to: Date())

    return FollowUpHistoryView(lead: lead)
        .environment(\.managedObjectContext, context)
}

struct SwipeToDeleteCheckInRow: View {
    let checkIn: FollowUpCheckIn
    let onDelete: () -> Void

    @State private var offset: CGFloat = 0
    @State private var showingDeleteButton = false
    @State private var initialOffset: CGFloat = 0

    private let deleteButtonWidth: CGFloat = 88
    private let swipeThreshold: CGFloat = 50

    var body: some View {
        HStack(spacing: 0) {
            // Main content
            CheckInInteractiveRowView(checkIn: checkIn, onDelete: onDelete)
                .offset(x: offset)
                .contentShape(Rectangle())

            // Delete button (hidden behind the row)
            if showingDeleteButton {
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        onDelete()
                    }
                }) {
                    VStack(spacing: 6) {
                        Image(systemName: "trash.fill")
                            .font(.obsidianCallout)
                        Text("Delete")
                            .font(.micro)
                            .fontWeight(.semibold)
                    }
                    .foregroundColor(.white)
                    .frame(width: deleteButtonWidth)
                    .frame(maxHeight: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color.statusNotInterested)
                    )
                }
                .buttonStyle(PlainButtonStyle())
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .clipped()
        .simultaneousGesture(
            DragGesture(minimumDistance: 20)
                .onChanged { value in
                    let translation = value.translation

                    // Only respond to primarily horizontal gestures
                    if abs(translation.width) > abs(translation.height) {
                        // Calculate cumulative offset from initial position
                        let newOffset = max(min(initialOffset + translation.width, 0), -deleteButtonWidth)
                        offset = newOffset
                    }

                    // Don't update showingDeleteButton here to avoid animation conflicts
                    // It will be updated in onEnded with proper animation
                }
                .onEnded { value in
                    let translation = value.translation

                    // Only process primarily horizontal gestures
                    if abs(translation.width) > abs(translation.height) {
                        let velocity = value.velocity.width

                        // Calculate final offset from initial position
                        let finalOffset = initialOffset + translation.width
                        let shouldShowDelete = abs(finalOffset) > swipeThreshold || velocity < -300

                        withAnimation(.easeInOut(duration: 0.3)) {
                            if shouldShowDelete {
                                offset = -deleteButtonWidth
                                showingDeleteButton = true
                                initialOffset = -deleteButtonWidth
                            } else {
                                offset = 0
                                showingDeleteButton = false
                                initialOffset = 0
                            }
                        }
                    }
                }
        )
    }
}
