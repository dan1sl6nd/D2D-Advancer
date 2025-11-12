import SwiftUI

struct ScheduleAppointmentView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var appointmentManager = AppointmentManager.shared
    
    let lead: Lead
    
    @State private var appointmentType: Appointment.AppointmentType = .consultation
    @State private var customAppointmentTypeId: String? = nil
    @State private var title = ""
    @State private var notes = ""
    @State private var selectedDate = Date()
    @State private var duration: TimeInterval = 60 * 60 // 1 hour default
    @State private var location = ""
    
    private var endDate: Date {
        selectedDate.addingTimeInterval(duration)
    }
    
    private var durationOptions: [(String, TimeInterval)] {
        [
            ("30 minutes", 30 * 60),
            ("1 hour", 60 * 60),
            ("1.5 hours", 90 * 60),
            ("2 hours", 120 * 60),
            ("3 hours", 180 * 60),
            ("Half day", 4 * 60 * 60),
            ("Full day", 8 * 60 * 60)
        ]
    }
    
    var body: some View {
        AppointmentFormView(
            appointmentType: $appointmentType,
            customAppointmentTypeId: $customAppointmentTypeId,
            title: $title,
            notes: $notes,
            selectedDate: $selectedDate,
            duration: $duration,
            location: $location,
            mode: .create,
            lead: lead,
            existingAppointment: nil,
            onSave: {
                scheduleAppointment()
            },
            onCancel: {
                dismiss()
            }
        )
        .onAppear {
            setupDefaultValues()
        }
        .onChange(of: appointmentType) { _, _ in
            updateTitleForType()
        }
        .onChange(of: customAppointmentTypeId) { _, _ in
            updateTitleForType()
        }
    }
    
    private func setupDefaultValues() {
        print("🗓️ Setting up default values for appointment scheduling")
        print("🗓️ Lead displayName: '\(lead.displayName)'")
        // Set default title based on appointment type
        updateTitleForType()
        print("🗓️ Title after setup: '\(title)'")
        
        // Set default location to lead's address
        if let address = lead.address {
            location = address
        }
        
        // Set default date to next business day at 10 AM
        let calendar = Calendar.current
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: Date()) ?? Date()
        let businessDay = nextBusinessDay(from: tomorrow)
        let tenAM = calendar.date(bySettingHour: 10, minute: 0, second: 0, of: businessDay) ?? businessDay
        selectedDate = tenAM
    }
    
    private func nextBusinessDay(from date: Date) -> Date {
        let calendar = Calendar.current
        var currentDate = date
        
        while calendar.component(.weekday, from: currentDate) == 1 || // Sunday
              calendar.component(.weekday, from: currentDate) == 7 {   // Saturday
            currentDate = calendar.date(byAdding: .day, value: 1, to: currentDate) ?? currentDate
        }
        
        return currentDate
    }
    
    private func updateTitleForType() {
        print("🗓️ Updating title for appointment type: \(appointmentType.rawValue)")
        if let customId = customAppointmentTypeId,
           let customType = CustomAppointmentTypeManager.shared.customTypes.first(where: { $0.id == customId }) {
            title = "\(customType.name) - \(lead.displayName)"
            print("🗓️ Title updated for custom type to: '\(title)'")
        } else {
            switch appointmentType {
            case .installation:
                title = "Installation - \(lead.displayName)"
            case .consultation:
                title = "Consultation - \(lead.displayName)"
            case .followUp:
                title = "Follow-up - \(lead.displayName)"
            case .maintenance:
                title = "Maintenance - \(lead.displayName)"
            case .repair:
                title = "Repair - \(lead.displayName)"
            case .inspection:
                title = "Inspection - \(lead.displayName)"
            }
            print("🗓️ Title updated for default type to: '\(title)'")
        }
    }
    
    private func scheduleAppointment() {
        print("🗓️ Schedule button pressed - Title: '\(title)', isEmpty: \(title.isEmpty)")
        guard !title.isEmpty else { 
            print("❌ Schedule failed: Title is empty")
            return 
        }
        
        print("🗓️ Starting appointment scheduling...")
        
        let appointment = Appointment(
            title: title,
            notes: notes,
            startDate: selectedDate,
            endDate: endDate,
            location: location,
            appointmentType: appointmentType,
            customAppointmentTypeId: customAppointmentTypeId,
            status: .scheduled
        )
        
        let leadObjectID = lead.objectID
        Task { @MainActor in
            // Re-fetch the Lead on main context to avoid capturing non-Sendable NSManagedObject across concurrency
            let context = PersistenceController.shared.container.viewContext
            guard let safeLead = try? context.existingObject(with: leadObjectID) as? Lead else {
                print("❌ Could not refetch lead for scheduling")
                return
            }
            let success = await appointmentManager.scheduleAppointment(for: safeLead, appointment: appointment)

            if success {
                print("✅ Appointment scheduled successfully")
                dismiss()
            } else {
                print("❌ Appointment scheduling failed")
            }
        }
    }
}

// MARK: - Subviews

struct LeadInfoCard: View {
    let lead: Lead
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "person.crop.circle.fill")
                    .foregroundColor(.blue)
                    .font(.title2)
                
                Text("Customer Information")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Spacer()
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Text(lead.displayName)
                    .font(.title3)
                    .fontWeight(.medium)
                
                if let address = lead.address {
                    HStack {
                        Image(systemName: "location")
                            .foregroundColor(.secondary)
                            .frame(width: 16)
                        Text(address)
                            .foregroundColor(.secondary)
                    }
                }
                
                if let phone = lead.phone {
                    HStack {
                        Image(systemName: "phone")
                            .foregroundColor(.secondary)
                            .frame(width: 16)
                        Text(phone)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding(20)
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
    }
}

struct AppointmentDetailsSection: View {
    @Binding var appointmentType: Appointment.AppointmentType
    @Binding var customAppointmentTypeId: String?
    @Binding var title: String
    @Binding var notes: String
    @ObservedObject private var customTypeManager = CustomAppointmentTypeManager.shared
    @State private var showingCustomTypeCreator = false
    
    private var allAppointmentTypes: [AppointmentTypeWrapper] {
        customTypeManager.allAppointmentTypes
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "calendar.badge.plus")
                    .foregroundColor(.blue)
                    .font(.title2)
                
                Text("Appointment Details")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Spacer()
            }
            
            VStack(alignment: .leading, spacing: 12) {
                Text("Type")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                LazyVGrid(columns: [
                    GridItem(.adaptive(minimum: 120), spacing: 12)
                ], spacing: 12) {
                    ForEach(allAppointmentTypes) { typeWrapper in
                        AppointmentTypeWrapperChip(
                            typeWrapper: typeWrapper,
                            isSelected: isSelected(typeWrapper),
                            action: {
                                selectType(typeWrapper)
                            },
                            onDelete: { deletedCustomType in
                                // If the deleted type was selected, reset selection
                                if let selectedCustomId = customAppointmentTypeId,
                                   selectedCustomId == deletedCustomType.id {
                                    customAppointmentTypeId = nil
                                    appointmentType = .consultation // Reset to default
                                }
                            }
                        )
                    }
                    
                    // Add New Type button
                    Button(action: {
                        showingCustomTypeCreator = true
                    }) {
                        VStack(spacing: 4) {
                            Image(systemName: "plus.circle")
                                .font(.title3)

                            Text("Add New")
                                .font(.caption)
                                .fontWeight(.medium)
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                        }
                        .padding(.vertical, 12)
                        .padding(.horizontal, 8)
                        .frame(maxWidth: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.blue.opacity(0.1))
                        )
                        .foregroundColor(.blue)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.blue.opacity(0.4), lineWidth: 1)
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Title")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                TextField("Appointment title", text: $title)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Notes")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                TextEditor(text: $notes)
                    .frame(minHeight: 80)
                    .padding(8)
                    .background(Color(UIColor.tertiarySystemBackground))
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color(UIColor.separator).opacity(0.3), lineWidth: 1)
                    )
            }
        }
        .padding(20)
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
        .sheet(isPresented: $showingCustomTypeCreator) {
            CustomAppointmentTypeCreatorView()
        }
    }
    
    private func isSelected(_ typeWrapper: AppointmentTypeWrapper) -> Bool {
        switch typeWrapper {
        case .defaultType(let defaultType):
            return customAppointmentTypeId == nil && appointmentType == defaultType
        case .customType(let custom):
            return customAppointmentTypeId == custom.id
        }
    }
    
    private func selectType(_ typeWrapper: AppointmentTypeWrapper) {
        // Extract the lead name from existing title if it exists
        let leadNameSuffix = extractLeadNameFromTitle(title)
        
        switch typeWrapper {
        case .defaultType(let defaultType):
            appointmentType = defaultType
            customAppointmentTypeId = nil
        case .customType(let custom):
            customAppointmentTypeId = custom.id
            // Update title to match the custom type, preserving lead name
            title = custom.name + leadNameSuffix
        }
    }
    
    private func extractLeadNameFromTitle(_ currentTitle: String) -> String {
        // Look for pattern " - [Lead Name]" at the end of the title
        if let dashIndex = currentTitle.lastIndex(of: "-") {
            let afterDash = currentTitle[currentTitle.index(after: dashIndex)...].trimmingCharacters(in: .whitespaces)
            
            // Only treat it as a lead name suffix if there's content after the dash
            if !afterDash.isEmpty {
                return " - " + afterDash
            }
        }
        return ""
    }
}

struct AppointmentTypeWrapperChip: View {
    let typeWrapper: AppointmentTypeWrapper
    let isSelected: Bool
    let action: () -> Void
    let onDelete: ((CustomAppointmentType) -> Void)?
    @ObservedObject private var customTypeManager = CustomAppointmentTypeManager.shared
    @State private var showingDeleteConfirmation = false
    
    init(typeWrapper: AppointmentTypeWrapper, isSelected: Bool, action: @escaping () -> Void, onDelete: ((CustomAppointmentType) -> Void)? = nil) {
        self.typeWrapper = typeWrapper
        self.isSelected = isSelected
        self.action = action
        self.onDelete = onDelete
    }
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: typeWrapper.icon)
                    .font(.title3)
                
                Text(typeWrapper.name)
                    .font(.caption)
                    .fontWeight(.medium)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? typeWrapper.color.opacity(0.2) : Color(UIColor.tertiarySystemBackground))
            )
            .foregroundColor(isSelected ? typeWrapper.color : .primary)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(typeWrapper.color.opacity(isSelected ? 0.8 : 0.3), lineWidth: isSelected ? 2 : 1)
            )
            .overlay(
                // Show custom indicator for custom types
                Group {
                    if case .customType = typeWrapper {
                        VStack {
                            HStack {
                                Spacer()
                                Image(systemName: "ellipsis.circle.fill")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                    .background(Color(UIColor.systemBackground))
                                    .clipShape(Circle())
                            }
                            Spacer()
                        }
                        .padding(4)
                    }
                }
            )
        }
        .buttonStyle(PlainButtonStyle())
        .contextMenu {
            if case .customType = typeWrapper {
                Button("Delete Custom Type", role: .destructive) {
                    showingDeleteConfirmation = true
                }
            }
        }
        .alert("Delete Appointment Type", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                if case .customType(let customType) = typeWrapper {
                    withAnimation {
                        customTypeManager.deleteCustomType(customType)
                        onDelete?(customType)
                    }
                }
            }
        } message: {
            if case .customType(let customType) = typeWrapper {
                Text("Are you sure you want to delete '\(customType.name)'? This action cannot be undone.")
            }
        }
    }
}

struct AppointmentTypeChip: View {
    let type: Appointment.AppointmentType
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: type.icon)
                    .font(.title3)
                
                Text(type.rawValue)
                    .font(.caption)
                    .fontWeight(.medium)
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? type.color.opacity(0.2) : Color(UIColor.tertiarySystemBackground))
            )
            .foregroundColor(isSelected ? type.color : .primary)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(type.color.opacity(isSelected ? 0.8 : 0.3), lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct DateTimeSection: View {
    @Binding var selectedDate: Date
    @Binding var duration: TimeInterval
    let durationOptions: [(String, TimeInterval)]
    let endDate: Date
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "clock")
                    .foregroundColor(.blue)
                    .font(.title2)
                
                Text("Date & Time")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Spacer()
            }
            
            VStack(alignment: .leading, spacing: 12) {
                Text("Start Date & Time")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                DatePicker("", selection: $selectedDate, displayedComponents: [.date, .hourAndMinute])
                    .datePickerStyle(.compact)
                    .labelsHidden()
            }
            
            VStack(alignment: .leading, spacing: 12) {
                Text("Duration")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Menu {
                    ForEach(Array(durationOptions.enumerated()), id: \.offset) { _, option in
                        Button(option.0) {
                            duration = option.1
                        }
                    }
                } label: {
                    HStack {
                        Text(durationOptions.first(where: { $0.1 == duration })?.0 ?? "1 hour")
                            .foregroundColor(.primary)
                        
                        Spacer()
                        
                        Image(systemName: "chevron.down")
                            .foregroundColor(.secondary)
                            .font(.caption)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Color(UIColor.tertiarySystemBackground))
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color(UIColor.separator).opacity(0.3), lineWidth: 1)
                    )
                }
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Text("End Time")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
                
                Text(endDate.formatted(.dateTime.day().month().year().hour().minute()))
                    .font(.body)
                    .foregroundColor(.secondary)
            }
        }
        .padding(20)
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
    }
}

struct LocationSection: View {
    @Binding var location: String
    let lead: Lead
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "location")
                    .foregroundColor(.blue)
                    .font(.title2)
                
                Text("Location")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Spacer()
            }
            
            VStack(alignment: .leading, spacing: 8) {
                TextField("Enter appointment location", text: $location)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                
                if let address = lead.address, location != address {
                    Button(action: {
                        location = address
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "location.fill")
                                .font(.caption2)
                            Text("Use customer address")
                                .font(.caption)
                        }
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color(.tertiarySystemBackground))
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
        }
        .padding(20)
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
    }
}


#Preview {
    let context = PersistenceController.preview.container.viewContext
    let lead = Lead(context: context)
    lead.name = "John Doe"
    lead.address = "123 Main St, Toronto, ON"
    lead.phone = "(555) 123-4567"
    lead.leadStatus = .interested
    
    return ScheduleAppointmentView(lead: lead)
        .environment(\.managedObjectContext, context)
}
