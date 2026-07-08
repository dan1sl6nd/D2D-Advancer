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
                await scheduleAppointment()
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
    
    @MainActor
    private func scheduleAppointment() async -> Bool {
        print("🗓️ Schedule button pressed - Title: '\(title)', isEmpty: \(title.isEmpty)")
        guard !title.isEmpty else { 
            print("❌ Schedule failed: Title is empty")
            appointmentManager.errorMessage = "Appointment title is required."
            return false
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
        // Re-fetch the Lead on main context to avoid capturing non-Sendable NSManagedObject across concurrency
        let context = PersistenceController.shared.container.viewContext
        guard let safeLead = try? context.existingObject(with: leadObjectID) as? Lead else {
            print("❌ Could not refetch lead for scheduling")
            appointmentManager.errorMessage = "Could not schedule appointment because the lead could not be loaded."
            return false
        }

        let success = await appointmentManager.scheduleAppointment(for: safeLead, appointment: appointment)
        if success {
            print("✅ Appointment scheduled successfully")
            dismiss()
        } else {
            print("❌ Appointment scheduling failed")
        }
        return success
    }
}

// MARK: - Subviews

struct LeadInfoCard: View {
    let lead: Lead
    
    var body: some View {
        LeadFormSectionCard(title: "Customer", icon: "person.crop.circle.fill") {
            VStack(alignment: .leading, spacing: 8) {
                Text(lead.displayName)
                    .font(.obsidianCallout)
                    .foregroundColor(Color.textPrimary)
                
                if let address = lead.address {
                    HStack {
                        Image(systemName: "location")
                            .foregroundColor(Color.textSecondary)
                            .frame(width: 16)
                        Text(address)
                            .foregroundColor(Color.textSecondary)
                    }
                }

                if let phone = lead.phone {
                    HStack {
                        Image(systemName: "phone")
                            .foregroundColor(Color.textSecondary)
                            .frame(width: 16)
                        Text(phone)
                            .foregroundColor(Color.textSecondary)
                    }
                }
            }
        }
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
        LeadFormSectionCard(title: "Appointment Details", icon: "calendar.badge.plus") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Type")
                    .font(.obsidianFootnote)
                    .foregroundColor(Color.textSecondary)
                
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
                                .font(.obsidianCallout)

                            Text("Add New")
                                .font(.obsidianSmall)
                                .fontWeight(.medium)
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                        }
                        .padding(.vertical, 12)
                        .padding(.horizontal, 8)
                        .frame(maxWidth: .infinity, minHeight: 76)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color.electricViolet.opacity(0.1))
                        )
                        .foregroundColor(Color.electricViolet)
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(Color.electricViolet.opacity(0.35), lineWidth: 0.5)
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            
            LeadFormTextField(
                title: "Title",
                placeholder: "Appointment title",
                text: $title,
                icon: "text.cursor",
                accessibilityIdentifier: "appointmentTitleField"
            )

            LeadNotesEditor(title: "Notes", text: $notes, minHeight: 88)
                .accessibilityIdentifier("appointmentNotesField")
        }
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
    @State private var deleteErrorMessage: String?
    
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
                    .font(.obsidianCallout)
                
                Text(typeWrapper.name)
                    .font(.obsidianSmall)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, minHeight: 76)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isSelected ? typeWrapper.color.opacity(0.2) : Color.obsidianSurface)
            )
            .foregroundColor(isSelected ? typeWrapper.color : Color.textPrimary)
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(typeWrapper.color.opacity(isSelected ? 0.8 : 0.3), lineWidth: isSelected ? 1.5 : 0.5)
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
                                    .foregroundColor(Color.textSecondary)
                                    .background(Color.obsidianElevated)
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
                        let didDelete = customTypeManager.deleteCustomType(customType)
                        if didDelete {
                            onDelete?(customType)
                        } else {
                            deleteErrorMessage = customTypeManager.lastErrorMessage ?? "Could not delete this appointment type. Please try again."
                        }
                    }
                }
            }
        } message: {
            if case .customType(let customType) = typeWrapper {
                Text("Are you sure you want to delete '\(customType.name)'? This action cannot be undone.")
            }
        }
        .alert(
            "Type not deleted",
            isPresented: Binding(
                get: { deleteErrorMessage != nil },
                set: { if !$0 { deleteErrorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(deleteErrorMessage ?? "Please try again.")
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
                    .font(.obsidianCallout)
                
                Text(type.rawValue)
                    .font(.obsidianSmall)
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isSelected ? type.color.opacity(0.2) : Color.obsidianSurface)
            )
            .foregroundColor(isSelected ? type.color : Color.textPrimary)
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(type.color.opacity(isSelected ? 0.8 : 0.3), lineWidth: isSelected ? 1.5 : 0.5)
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
        LeadFormSectionCard(title: "Date & Time", icon: "clock") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Start Date & Time")
                    .font(.obsidianFootnote)
                    .foregroundColor(Color.textSecondary)
                
                DatePicker("Start date and time", selection: $selectedDate, displayedComponents: [.date, .hourAndMinute])
                    .datePickerStyle(.compact)
                    .labelsHidden()
            }
            
            VStack(alignment: .leading, spacing: 12) {
                Text("Duration")
                    .font(.obsidianFootnote)
                    .foregroundColor(Color.textSecondary)
                
                Menu {
                    ForEach(Array(durationOptions.enumerated()), id: \.offset) { _, option in
                        Button(option.0) {
                            duration = option.1
                        }
                    }
                } label: {
                    HStack {
                        Text(durationOptions.first(where: { $0.1 == duration })?.0 ?? "1 hour")
                            .font(.obsidianCallout)
                            .foregroundColor(Color.textPrimary)

                        Spacer()

                        Image(systemName: "chevron.down")
                            .foregroundColor(Color.textSecondary)
                            .font(.micro)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Color.obsidianElevated)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.obsidianBorder.opacity(0.45), lineWidth: 0.5)
                    )
                }
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Text("End Time")
                    .font(.obsidianFootnote)
                    .foregroundColor(Color.textSecondary)

                Text(endDate.formatted(.dateTime.day().month().year().hour().minute()))
                    .font(.obsidianBody)
                    .foregroundColor(Color.textSecondary)
            }
        }
    }
}

struct LocationSection: View {
    @Binding var location: String
    let lead: Lead
    
    var body: some View {
        LeadFormSectionCard(title: "Location", icon: "location") {
            VStack(alignment: .leading, spacing: 8) {
                LeadFormTextField(
                    title: "Address",
                    placeholder: "Appointment location",
                    text: $location,
                    icon: "location.fill",
                    accessibilityIdentifier: "appointmentLocationField"
                )
                
                if let address = lead.address, location != address {
                    Button(action: {
                        location = address
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "location.fill")
                                .font(.micro)
                            Text("Use customer address")
                                .font(.obsidianSmall)
                        }
                        .foregroundColor(Color.textSecondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.obsidianElevated)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
        }
    }
}


#Preview {
    let context = PersistenceController.preview.container.viewContext
    let lead = Lead.create(in: context)
    lead.name = "John Doe"
    lead.address = "123 Main St, Toronto, ON"
    lead.phone = "(555) 123-4567"
    lead.leadStatus = .interested
    
    return ScheduleAppointmentView(lead: lead)
        .environment(\.managedObjectContext, context)
}
