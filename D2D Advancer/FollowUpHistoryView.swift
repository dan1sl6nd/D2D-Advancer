import SwiftUI
import CoreData

struct FollowUpHistoryView: View {
    let lead: Lead
    @Environment(\.managedObjectContext) private var viewContext
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
        NavigationView {
            VStack(spacing: 0) {
                // Lead Summary Header
                leadSummaryHeader
                
                // Check-ins List
                if checkIns.isEmpty {
                    emptyStateView
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
            .navigationTitle("Follow-up History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        showingAddCheckIn = true
                    }) {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingAddCheckIn) {
                AddCheckInView(lead: lead)
            }
            .onAppear {
                migrateCheckInOutcomes()
            }
        }
    }
    
    private var leadSummaryHeader: some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(lead.displayName)
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    if let address = lead.address {
                        Text(address)
                            .font(.caption)
                            .foregroundColor(Color.textSecondary)
                    }
                }
                
                Spacer()
                
                StatusBadge(status: LeadStatus.from(leadStatus: lead.leadStatus))
            }
            
            HStack(spacing: 20) {
                VStack {
                    Text("\(lead.checkInCount)")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(Color.electricViolet)
                    Text("Check-ins")
                        .font(.caption)
                        .foregroundColor(Color.textSecondary)
                }
                
                Divider()
                    .frame(height: 30)
                
                VStack {
                    if let lastCheckIn = lead.lastCheckIn {
                        Text(lastCheckIn.formattedCheckInDate)
                            .font(.caption)
                            .fontWeight(.medium)
                    } else {
                        Text("Never")
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                    Text("Last Contact")
                        .font(.caption)
                        .foregroundColor(Color.textSecondary)
                }
                
                Spacer()
            }
        }
        .padding()
        .background(Color.obsidianSurface)
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 60))
                .foregroundColor(Color.textSecondary)
            
            Text("No Follow-ups Recorded")
                .font(.title2)
                .fontWeight(.medium)
                .foregroundColor(Color.textPrimary)
            
            Text("Start tracking your interactions with this lead by recording your first follow-up.")
                .font(.body)
                .foregroundColor(Color.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            Button(action: {
                showingAddCheckIn = true
            }) {
                HStack {
                    Image(systemName: "plus.circle.fill")
                    Text("Record First Check-in")
                }
                .padding()
                .background(Color.electricViolet)
                .foregroundColor(.white)
                .cornerRadius(12)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        VStack(alignment: .leading, spacing: 12) {
            // Main check-in info
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    // Check-in type with icon
                    HStack(spacing: 8) {
                        Image(systemName: getCheckInIcon())
                            .foregroundColor(getCheckInColor())
                            .frame(width: 20)
                        
                        Text(getCheckInType())
                            .font(.headline)
                            .foregroundColor(Color.textPrimary)
                    }
                    
                    // Outcome - simple and always visible
                    HStack(spacing: 6) {
                        Circle()
                            .fill(getOutcomeColor())
                            .frame(width: 8, height: 8)
                        
                        Text(getOutcomeText())
                            .font(.subheadline)
                            .foregroundColor(getOutcomeColor())
                    }
                    .padding(.leading, 4)
                }
                
                Spacer()
                
                // Date and time
                VStack(alignment: .trailing, spacing: 2) {
                    Text(checkIn.checkInDate?.formatted(.dateTime.day().month()) ?? "")
                        .font(.caption)
                        .foregroundColor(Color.textSecondary)
                    Text(checkIn.checkInDate?.formatted(.dateTime.hour().minute()) ?? "")
                        .font(.caption2)
                        .foregroundColor(Color.textSecondary)
                }
            }
            
            // Notes if available
            if let notes = checkIn.notes, !notes.isEmpty {
                Text(notes)
                    .font(.body)
                    .foregroundColor(Color.textSecondary)
                    .padding(.top, 4)
                    .lineLimit(nil)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.obsidianSurface)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.obsidianBorder.opacity(0.3), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.06), radius: 3, x: 0, y: 2)
        )
        .padding(.horizontal, 16)
        .contextMenu {
            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Delete Check-in", systemImage: "trash")
            }
        }
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
        VStack(alignment: .leading, spacing: 12) {
            // Main check-in info
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    // Check-in type with icon
                    HStack(spacing: 8) {
                        Image(systemName: getCheckInIcon())
                            .foregroundColor(getCheckInColor())
                            .frame(width: 20)
                        
                        Text(getCheckInType())
                            .font(.headline)
                            .foregroundColor(Color.textPrimary)
                    }
                    
                    // Outcome - simple and always visible
                    HStack(spacing: 6) {
                        Circle()
                            .fill(getOutcomeColor())
                            .frame(width: 8, height: 8)
                        
                        Text(getOutcomeText())
                            .font(.subheadline)
                            .foregroundColor(getOutcomeColor())
                    }
                    .padding(.leading, 4)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    // Date
                    Text(getFormattedDate())
                        .font(.caption)
                        .foregroundColor(Color.textSecondary)
                    
                    // Delete button
                    Button(action: onDelete) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(Color.statusNotInterested)
                            .font(.title3)
                    }
                    .buttonStyle(BorderlessButtonStyle())
                }
            }
            
            // Notes if available
            if let notes = checkIn.notes, !notes.isEmpty {
                Text(notes)
                    .font(.body)
                    .foregroundColor(Color.textSecondary)
                    .padding(.top, 4)
            }
        }
        .padding(.vertical, 8)
    }
    
    // Simple helper functions that will definitely work
    private func getCheckInType() -> String {
        let type = checkIn.checkInType ?? "door_knock"
        
        switch type {
        case "phone_call": return "Phone Call"
        case "email": return "Email"
        case "sms_message": return "SMS Message"
        case "in_person_meeting": return "In-Person Meeting"
        case "virtual_meeting": return "Virtual Meeting"
        case "door_knock": return "Door Knock"
        default: return "Door Knock"
        }
    }
    
    private func getCheckInIcon() -> String {
        let type = checkIn.checkInType ?? "door_knock"
        switch type {
        case "phone_call": return "phone.fill"
        case "email": return "envelope.fill"
        case "sms_message": return "message.fill"
        case "in_person_meeting": return "person.2.fill"
        case "virtual_meeting": return "video.fill"
        default: return "door.left.hand.open"
        }
    }
    
    private func getCheckInColor() -> Color {
        let type = checkIn.checkInType ?? "door_knock"
        switch type {
        case "phone_call": return Color.electricViolet
        case "email": return Color.electricViolet
        case "sms_message": return Color.statusInterested
        case "in_person_meeting": return Color.statusNotInterested
        case "virtual_meeting": return Color.statusNotHome
        default: return .brown
        }
    }
    
    private func getOutcomeText() -> String {
        let rawOutcome = checkIn.outcome ?? ""
        
        if rawOutcome.isEmpty {
            return "No outcome recorded"
        }
        
        // Simple mapping without complex enum logic
        switch rawOutcome {
        case "successful": return "Successful Contact"
        case "no_answer": return "No Answer"
        case "not_interested": return "Not Interested"
        case "interested": return "Showed Interest"
        case "converted": return "Converted"
        case "reschedule": return "Reschedule Needed"
        case "callback": return "Callback Requested"
        default: return rawOutcome.capitalized
        }
    }
    
    private func getOutcomeColor() -> Color {
        let rawOutcome = checkIn.outcome ?? ""

        switch rawOutcome {
        case "successful", "interested": return Color.statusInterested
        case "converted": return Color.electricViolet
        case "no_answer", "reschedule", "callback": return Color.statusNotHome
        case "not_interested": return Color.statusNotInterested
        default: return Color.textSecondary
        }
    }
    
    private func getFormattedDate() -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: checkIn.checkInDate ?? Date())
    }
}

#Preview {
    let context = PersistenceController.preview.container.viewContext
    let lead = Lead(context: context)
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
    
    private let deleteButtonWidth: CGFloat = 80
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
                    VStack {
                        Image(systemName: "trash.fill")
                            .font(.title2)
                        Text("Delete")
                            .font(.caption2)
                    }
                    .foregroundColor(.white)
                    .frame(width: deleteButtonWidth)
                    .frame(maxHeight: .infinity)
                    .background(Color.statusNotInterested)
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
