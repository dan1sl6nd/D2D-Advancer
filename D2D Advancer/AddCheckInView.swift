import SwiftUI
import CoreData

struct AddCheckInView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var preferences = AppPreferences.shared
    
    let lead: Lead
    
    @State private var checkInType: FollowUpCheckIn.CheckInType = AppPreferences.shared.defaultCheckInTypeEnum
    @State private var outcome: FollowUpCheckIn.Outcome = .successful
    @State private var notes = ""
    @State private var scheduledNextFollowUp: Date?
    @State private var showingDatePicker = false
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    ObsidianScreenTitle(
                        title: "Record Check-in",
                        subtitle: "Log the contact method, outcome, notes, and next follow-up.",
                        icon: "checkmark.circle.fill"
                    )

                    // Lead Information Section
                    modernSectionCard(title: "Lead Information", icon: "person.crop.circle.fill") {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(lead.displayName)
                                        .font(.obsidianCallout)
                                        .foregroundColor(Color.textPrimary)

                                    if let address = lead.address {
                                        Text(address)
                                            .font(.obsidianFootnote)
                                            .foregroundColor(Color.textSecondary)
                                    }
                                }
                                
                                Spacer()
                                
                                StatusBadge(status: LeadStatus.from(leadStatus: lead.leadStatus))
                            }
                            
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(Color.electricViolet)
                                    .frame(width: 20)
                                
                                Text("Check-in #\(lead.checkInCount + 1)")
                                    .font(.obsidianTitle)
                                    .foregroundColor(Color.textPrimary)
                                
                                Spacer()
                            }
                        }
                    }
                    
                    // Check-in Details Section
                    modernSectionCard(title: "Check-in Details", icon: "phone.fill") {
                        VStack(spacing: 16) {
                            modernCheckInTypePickerField(title: "Contact Method", selection: $checkInType, icon: "phone.circle.fill")
                            
                            modernOutcomePickerField(title: "Outcome", selection: $outcome, icon: "target")
                        }
                    }
                    
                    // Notes Section
                    modernSectionCard(title: "Notes", icon: "note.text") {
                        LeadNotesEditor(title: "Check-in Notes", text: $notes, minHeight: 108)
                    }
                    
                    // Next Follow-up Section
                    modernSectionCard(title: "Next Follow-up", icon: "calendar.circle.fill") {
                        modernDateField(title: "Schedule Next Follow-up", date: $scheduledNextFollowUp, icon: "calendar.circle.fill") {
                            if scheduledNextFollowUp == nil {
                                scheduledNextFollowUp = preferences.defaultFollowUpDate()
                            }
                            showingDatePicker = true
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 18)
                .padding(.bottom, 28)
            }
            .accessibilityIdentifier("addCheckInScreen")
            .obsidianScreenBackground()
            .obsidianPushedNavigation(
                "Record Check-in",
                backButtonAccessibilityIdentifier: "addCheckInBackButton",
                onBack: { dismiss() }
            )
            .safeAreaInset(edge: .bottom) {
                ObsidianBottomActionBar(
                    primaryAccessibilityIdentifier: "addCheckInSaveButton",
                    secondaryAccessibilityIdentifier: "addCheckInCancelButton",
                    primaryAction: saveCheckIn,
                    secondaryAction: { dismiss() },
                    primaryLabel: {
                        Label("Save", systemImage: "checkmark.circle.fill")
                    },
                    secondaryLabel: {
                        Label("Cancel", systemImage: "xmark.circle.fill")
                    }
                )
            }
            .sheet(isPresented: $showingDatePicker) {
                NavigationStack {
                    VStack(spacing: 20) {
                        Text("Select Next Follow-up Date")
                            .font(.obsidianTitle)
                            .foregroundColor(Color.textPrimary)
                            .padding(.top)
                        
                        DatePicker("Next follow-up date", selection: Binding(
                            get: { scheduledNextFollowUp ?? Date() },
                            set: { scheduledNextFollowUp = $0 }
                        ), displayedComponents: [.date, .hourAndMinute])
                        .datePickerStyle(.compact)
                        .labelsHidden()
                        .padding(.horizontal)
                        
                        Spacer(minLength: 20)
                    }
                    .obsidianScreenBackground()
                    .obsidianPushedNavigation(
                        "Next Follow-up",
                        backButtonAccessibilityIdentifier: "addCheckInDateBackButton",
                        onBack: { showingDatePicker = false }
                    )
                    .accessibilityIdentifier("addCheckInNextFollowUpDatePicker")
                    .safeAreaInset(edge: .bottom) {
                        ObsidianBottomActionBar(
                            primaryAccessibilityIdentifier: "addCheckInDateDoneButton",
                            secondaryAccessibilityIdentifier: "addCheckInDateCancelButton",
                            primaryAction: { showingDatePicker = false },
                            secondaryAction: { showingDatePicker = false },
                            primaryLabel: { Label("Done", systemImage: "checkmark.circle.fill") },
                            secondaryLabel: { Label("Cancel", systemImage: "xmark.circle.fill") }
                        )
                    }
                }
                .presentationDetents([.height(250)])
            }
        }
    }
    
    private func saveCheckIn() {
        let resultingStatus = FollowUpCheckIn.resolvedLeadStatus(
            after: outcome,
            currentStatus: lead.leadStatus
        )
        let effectiveNextFollowUp = FollowUpCheckIn.effectiveScheduledNextFollowUp(
            scheduledNextFollowUp,
            resultingStatus: resultingStatus
        )

        let checkIn = FollowUpCheckIn.create(in: viewContext, for: lead)
        checkIn.checkInTypeEnum = checkInType
        checkIn.outcomeEnum = outcome
        checkIn.notes = notes.isEmpty ? nil : notes
        checkIn.scheduledNextFollowUp = effectiveNextFollowUp
        
        lead.applyLeadStatus(
            resultingStatus,
            followUpDate: effectiveNextFollowUp,
            shouldReplaceFollowUpDate: true,
            autoSave: false
        )
        
        do {
            try viewContext.save()
            
            // Individual sync removed - will sync manually, hourly, or before sign-out
            print("📝 Check-in saved locally - will sync on next manual/hourly/sign-out sync")
            
            dismiss()
        } catch {
            let nsError = error as NSError
            print("Save error: \(nsError), \(nsError.userInfo)")
        }
    }
    
    // MARK: - Modern UI Components
    
    private func modernSectionCard<Content: View>(title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        ObsidianSectionCard(title: title, icon: icon) {
            content()
        }
    }
    
    @ViewBuilder
    private func modernCheckInTypePickerField(title: String, selection: Binding<FollowUpCheckIn.CheckInType>, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(Color.electricViolet)
                    .frame(width: 20)

                Text(title)
                    .font(.obsidianFootnote)
                    .foregroundColor(Color.textSecondary)
            }

            Menu {
                Picker(title, selection: selection) {
                    ForEach(FollowUpCheckIn.CheckInType.allCases, id: \.self) { type in
                        Label(type.displayName, systemImage: type.icon)
                            .tag(type)
                    }
                }
            } label: {
                HStack {
                    Label(selection.wrappedValue.displayName, systemImage: selection.wrappedValue.icon)
                        .font(.obsidianBody)
                        .foregroundColor(Color.textPrimary)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .foregroundColor(Color.textSecondary)
                        .font(.caption)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color.obsidianSurface)
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.obsidianBorder.opacity(0.3), lineWidth: 1)
                )
            }
        }
    }
    
    @ViewBuilder
    private func modernOutcomePickerField(title: String, selection: Binding<FollowUpCheckIn.Outcome>, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(Color.electricViolet)
                    .frame(width: 20)

                Text(title)
                    .font(.obsidianFootnote)
                    .foregroundColor(Color.textSecondary)
            }

            Menu {
                Picker(title, selection: selection) {
                    ForEach(FollowUpCheckIn.Outcome.allCases, id: \.self) { outcome in
                        Text(outcome.displayName)
                            .tag(outcome)
                    }
                }
            } label: {
                HStack {
                    Text(selection.wrappedValue.displayName)
                        .font(.obsidianBody)
                        .foregroundColor(Color.textPrimary)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .foregroundColor(Color.textSecondary)
                        .font(.caption)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color.obsidianSurface)
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.obsidianBorder.opacity(0.3), lineWidth: 1)
                )
            }
        }
    }
    
    @ViewBuilder
    private func modernDateField(title: String, date: Binding<Date?>, icon: String, action: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(Color.electricViolet)
                    .frame(width: 20)

                Text(title)
                    .font(.obsidianFootnote)
                    .foregroundColor(Color.textSecondary)
            }

            Button(action: action) {
                HStack {
                    if let selectedDate = date.wrappedValue {
                        Text(selectedDate.formatted(.dateTime.day().month().year().hour().minute()))
                            .font(.obsidianBody)
                            .foregroundColor(Color.textPrimary)

                        Spacer()

                        Button(action: {
                            date.wrappedValue = nil
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(Color.textSecondary)
                        }
                    } else {
                        Text("Set Date & Time")
                            .font(.obsidianBody)
                            .foregroundColor(Color.textSecondary)

                        Spacer()

                        Image(systemName: "calendar")
                            .foregroundColor(Color.textSecondary)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color.obsidianSurface)
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.obsidianBorder.opacity(0.3), lineWidth: 1)
                )
            }
        }
    }
}

#Preview {
    let context = PersistenceController.preview.container.viewContext
    let lead = Lead.create(in: context)
    lead.name = "John Doe"
    lead.address = "123 Main St, Toronto, ON"
    lead.leadStatus = .notContacted
    
    return AddCheckInView(lead: lead)
        .environment(\.managedObjectContext, context)
}
