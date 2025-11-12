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
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // Lead Information Section
                    modernSectionCard(title: "Lead Information", icon: "person.crop.circle.fill") {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(lead.displayName)
                                        .font(.title3)
                                        .fontWeight(.semibold)
                                    
                                    if let address = lead.address {
                                        Text(address)
                                            .font(.subheadline)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                
                                Spacer()
                                
                                StatusBadge(status: LeadStatus.from(leadStatus: lead.leadStatus))
                            }
                            
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.blue)
                                    .frame(width: 20)
                                
                                Text("Check-in #\(lead.checkInCount + 1)")
                                    .font(.headline)
                                    .fontWeight(.semibold)
                                
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
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: "note.text")
                                    .foregroundColor(.blue)
                                    .frame(width: 20)
                                
                                Text("Check-in Notes")
                                    .font(.headline)
                                    .fontWeight(.semibold)
                            }
                            
                            TextEditor(text: $notes)
                                .frame(minHeight: 100)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                                .background(Color(UIColor.tertiarySystemBackground))
                                .cornerRadius(12)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color(UIColor.separator).opacity(0.3), lineWidth: 1)
                                )
                                .placeholder(when: notes.isEmpty) {
                                    Text("Add notes about this follow-up...")
                                        .foregroundColor(.gray)
                                        .padding(.horizontal, 20)
                                        .padding(.vertical, 20)
                                }
                        }
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
                .padding(.vertical, 20)
            }
            .navigationTitle("Record Check-in")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(true)
            .safeAreaInset(edge: .bottom) {
                // Card-based button design
                HStack(spacing: 16) {
                    Button(action: {
                        dismiss()
                    }) {
                        HStack {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title3)
                            Text("Cancel")
                                .font(.headline)
                                .fontWeight(.semibold)
                        }
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color(UIColor.secondarySystemBackground))
                                .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
                        )
                    }
                    
                    Button(action: {
                        saveCheckIn()
                    }) {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.title3)
                            Text("Save Check-in")
                                .font(.headline)
                                .fontWeight(.semibold)
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(
                                    LinearGradient(
                                        gradient: Gradient(colors: [Color.blue, Color.blue.opacity(0.8)]),
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .shadow(color: .blue.opacity(0.3), radius: 4, x: 0, y: 2)
                        )
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(
                    Rectangle()
                        .fill(Color(UIColor.systemBackground))
                        .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: -2)
                )
            }
            .sheet(isPresented: $showingDatePicker) {
                NavigationView {
                    VStack(spacing: 20) {
                        Text("Select Next Follow-up Date")
                            .font(.title2)
                            .fontWeight(.semibold)
                            .padding(.top)
                        
                        DatePicker("", selection: Binding(
                            get: { scheduledNextFollowUp ?? Date() },
                            set: { scheduledNextFollowUp = $0 }
                        ), displayedComponents: [.date, .hourAndMinute])
                        .datePickerStyle(.compact)
                        .labelsHidden()
                        .padding(.horizontal)
                        
                        Spacer(minLength: 20)
                    }
                    .navigationTitle("Next Follow-up")
                    .navigationBarTitleDisplayMode(.inline)
                    .safeAreaInset(edge: .bottom) {
                        HStack(spacing: 12) {
                            Button(action: {
                                showingDatePicker = false
                            }) {
                                Text("Cancel")
                                    .font(.headline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.secondary)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(
                                        RoundedRectangle(cornerRadius: 12)
                                            .fill(Color(UIColor.secondarySystemBackground))
                                    )
                            }
                            
                            Button(action: {
                                showingDatePicker = false
                            }) {
                                Text("Done")
                                    .font(.headline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(
                                        RoundedRectangle(cornerRadius: 12)
                                            .fill(Color.blue)
                                    )
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color(UIColor.systemBackground))
                    }
                }
                .presentationDetents([.height(250)])
            }
        }
    }
    
    private func saveCheckIn() {
        let checkIn = FollowUpCheckIn.create(in: viewContext, for: lead)
        checkIn.checkInTypeEnum = checkInType
        checkIn.outcomeEnum = outcome
        checkIn.notes = notes.isEmpty ? nil : notes
        checkIn.scheduledNextFollowUp = scheduledNextFollowUp
        
        // Update lead's next follow-up date if scheduled
        if let nextFollowUp = scheduledNextFollowUp {
            lead.setFollowUpDate(nextFollowUp)
        }
        
        // Update lead status based on outcome
        switch outcome {
        case .converted:
            lead.leadStatus = .converted
        case .interested:
            // Do not downgrade a sold lead to interested
            if lead.leadStatus != .converted {
                lead.leadStatus = .interested
            }
        case .notInterested:
            // Explicit user action: allow setting to not interested even from sold
            lead.leadStatus = .notInterested
        case .successful, .noAnswer, .reschedule, .callback:
            // Keep current status
            break
        }
        
        lead.updatedDate = Date()
        
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
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(.blue)
                    .font(.title2)
                
                Text(title)
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            
            content()
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
        }
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color(UIColor.separator).opacity(0.2), lineWidth: 1)
        )
    }
    
    @ViewBuilder
    private func modernCheckInTypePickerField(title: String, selection: Binding<FollowUpCheckIn.CheckInType>, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(.blue)
                    .frame(width: 20)
                
                Text(title)
                    .font(.headline)
                    .fontWeight(.semibold)
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
                        .foregroundColor(.primary)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .foregroundColor(.secondary)
                        .font(.caption)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color(UIColor.tertiarySystemBackground))
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color(UIColor.separator).opacity(0.3), lineWidth: 1)
                )
            }
        }
    }
    
    @ViewBuilder
    private func modernOutcomePickerField(title: String, selection: Binding<FollowUpCheckIn.Outcome>, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(.blue)
                    .frame(width: 20)
                
                Text(title)
                    .font(.headline)
                    .fontWeight(.semibold)
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
                        .foregroundColor(.primary)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .foregroundColor(.secondary)
                        .font(.caption)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color(UIColor.tertiarySystemBackground))
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color(UIColor.separator).opacity(0.3), lineWidth: 1)
                )
            }
        }
    }
    
    @ViewBuilder
    private func modernDateField(title: String, date: Binding<Date?>, icon: String, action: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(.blue)
                    .frame(width: 20)
                
                Text(title)
                    .font(.headline)
                    .fontWeight(.semibold)
            }
            
            Button(action: action) {
                HStack {
                    if let selectedDate = date.wrappedValue {
                        Text(selectedDate.formatted(.dateTime.day().month().year().hour().minute()))
                            .foregroundColor(.primary)
                        
                        Spacer()
                        
                        Button(action: {
                            date.wrappedValue = nil
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                    } else {
                        Text("Set Date & Time")
                            .foregroundColor(.secondary)
                        
                        Spacer()
                        
                        Image(systemName: "calendar")
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color(UIColor.tertiarySystemBackground))
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color(UIColor.separator).opacity(0.3), lineWidth: 1)
                )
            }
        }
    }
}

#Preview {
    let context = PersistenceController.preview.container.viewContext
    let lead = Lead(context: context)
    lead.name = "John Doe"
    lead.address = "123 Main St, Toronto, ON"
    lead.leadStatus = .notContacted
    
    return AddCheckInView(lead: lead)
        .environment(\.managedObjectContext, context)
}
