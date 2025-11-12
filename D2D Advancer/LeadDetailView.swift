 import SwiftUI
import CoreData
import MapKit
import UserNotifications

struct LeadDetailView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var lead: Lead
    @ObservedObject private var locationManager = LocationManager.shared

    @State private var isEditing = false
    @State private var editedName = ""
    @State private var editedPhone = ""
    @State private var editedEmail = ""
    @State private var editedAddress = ""
    @State private var editedNotes = ""
    @State private var editedPrice: Double = 0.0
    @State private var editedStatus = Lead.Status.notContacted
    @State private var editedFollowUpDate: Date?
    @State private var editedServiceCategory: ServiceCategory?
    @State private var showingDatePicker = false
    @State private var showingAddCheckIn = false
    @State private var showingFullHistory = false
    @State private var showingDeleteAlert = false
    @State private var showingScheduleAppointment = false
    @State private var showingServiceCategoryCreator = false
    @State private var isUpdatingAddress = false

    @ObservedObject private var categoryManager = ServiceCategoryManager.shared
    
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
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                headerSection
                
                if !isEditing {
                    actionButtonsSection
                }
                
                if isEditing {
                    editForm
                } else {
                    detailView
                }
                
                mapSection
                
                followUpHistorySection
            }
            .padding()
        }
        .navigationTitle(isEditing ? "Edit Lead" : "Lead Details")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(false)
        .safeAreaInset(edge: .bottom) {
            // Card-based button design
            if isEditing {
                // Show Cancel and Save buttons when editing
                HStack(spacing: 16) {
                    Button(action: {
                        cancelEditing()
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
                        saveLead()
                    }) {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.title3)
                            Text("Save Changes")
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
            } else {
                // Show Edit and Delete buttons when not editing
                HStack(spacing: 16) {
                    Button(action: {
                        showingDeleteAlert = true
                    }) {
                        HStack {
                            Image(systemName: "trash.circle.fill")
                                .font(.title3)
                            Text("Delete Lead")
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
                                        gradient: Gradient(colors: [Color.red, Color.red.opacity(0.8)]),
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .shadow(color: .red.opacity(0.3), radius: 4, x: 0, y: 2)
                        )
                    }
                    
                    Button(action: {
                        startEditing()
                    }) {
                        HStack {
                            Image(systemName: "pencil.circle.fill")
                                .font(.title3)
                            Text("Edit Lead")
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
        }
        .onAppear {
            loadLeadData()
            migrateCheckInOutcomes()
        }
    }
    
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                StatusBadge(status: LeadStatus.from(leadStatus: lead.leadStatus))
                
                Spacer()
                
            }
            
                        Text(lead.displayName)
                .font(.title2)
                .fontWeight(.bold)
            
            HStack {
                Text("Created: \(lead.createdDate?.formatted(.dateTime.day().month().year().hour().minute()) ?? "Unknown")")
                Spacer()
            }
            .font(.caption)
            .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(UIColor.tertiarySystemBackground))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(UIColor.separator).opacity(0.5), lineWidth: 1)
        )
    }
    
    private var detailView: some View {
        VStack(spacing: 24) {
            // Personal Information Section
            modernSectionCard(title: "Personal Information", icon: "person.circle.fill") {
                VStack(spacing: 16) {
                    modernDetailCell(
                        title: "Name",
                        value: lead.name ?? "Not provided",
                        icon: "person.fill",
                        iconColor: .blue
                    )
                    
                    modernDetailCell(
                        title: "Phone",
                        value: lead.phone ?? "Not provided",
                        icon: "phone.fill",
                        iconColor: .green,
                        isCallable: lead.phone != nil
                    )
                    
                    modernDetailCell(
                        title: "Email",
                        value: lead.email ?? "Not provided",
                        icon: "envelope.fill",
                        iconColor: .orange,
                        isEmailable: lead.email != nil
                    )
                }
            }
            
            // Location & Deal Section
            modernSectionCard(title: "Location & Deal", icon: "map.circle.fill") {
                VStack(spacing: 16) {
                    modernAddressCell(
                        title: "Address",
                        value: lead.address ?? "Not provided",
                        icon: "location.fill",
                        iconColor: .red,
                        hasAddress: lead.address != nil
                    )
                    
                    modernDetailCell(
                        title: "Deal Value",
                        value: String(format: "$%.2f CAD", lead.price),
                        icon: "dollarsign.circle.fill",
                        iconColor: .purple
                    )
                }
            }
            
            // Status Section
            modernSectionCard(title: "Status", icon: "flag.circle.fill") {
                VStack(spacing: 16) {
                    modernStatusCell(
                        title: "Lead Status",
                        status: lead.leadStatus,
                        icon: "checkmark.circle.fill",
                        iconColor: .blue
                    )
                    
                }
            }
            
            // Follow-up & Notes Section
            if lead.followUpDate != nil || (lead.notes != nil && !lead.notes!.isEmpty) {
                modernSectionCard(title: "Follow-up & Notes", icon: "calendar.circle.fill") {
                    VStack(spacing: 16) {
                        if let followUpDate = lead.followUpDate {
                            modernDetailCell(
                                title: "Follow Up Date",
                                value: followUpDate.formatted(.dateTime.day().month().year().hour().minute()),
                                icon: "clock.fill",
                                iconColor: .purple
                            )
                        }
                        
                        if let notes = lead.notes, !notes.isEmpty {
                            modernNotesCell(
                                title: "Notes",
                                value: notes,
                                icon: "note.text",
                                iconColor: .indigo
                            )
                        }
                    }
                }
            }
        }
    }
    
    private var editForm: some View {
        VStack(spacing: 24) {
            // Contact Information Section
            modernSectionCard(title: "Contact Information", icon: "person.crop.circle.fill") {
                VStack(spacing: 16) {
                    modernTextField(title: "Name", text: $editedName, icon: "person.fill")
                    
                    modernTextField(title: "Phone", text: $editedPhone, icon: "phone.fill")
                        .keyboardType(.phonePad)
                        .onChange(of: editedPhone) { oldValue, newValue in
                            DispatchQueue.main.async {
                                editedPhone = Utilities.formatPhoneNumber(newValue)
                            }
                        }
                    
                    modernTextField(title: "Email", text: $editedEmail, icon: "envelope.fill")
                        .keyboardType(.emailAddress)
                        .autocapitalization(.none)
                }
            }
            
            // Location & Deal Section
            modernSectionCard(title: "Location & Deal", icon: "map.circle.fill") {
                VStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "location.fill")
                                .foregroundColor(.blue)
                                .frame(width: 20)

                            Text("Address")
                                .font(.headline)
                                .fontWeight(.semibold)

                            Spacer()

                            // Update Address Button
                            Button(action: {
                                updateAddressFromCurrentLocation()
                            }) {
                                HStack(spacing: 4) {
                                    if isUpdatingAddress {
                                        ProgressView()
                                            .scaleEffect(0.7)
                                    } else {
                                        Image(systemName: "arrow.clockwise")
                                            .font(.system(size: 12, weight: .semibold))
                                    }
                                    Text("Update")
                                        .font(.caption)
                                        .fontWeight(.medium)
                                }
                                .foregroundColor(.white)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(Color.blue)
                                )
                            }
                            .disabled(isUpdatingAddress)
                        }

                        TextField("Address", text: $editedAddress)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .background(Color(UIColor.tertiarySystemBackground))
                            .cornerRadius(8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color(UIColor.separator).opacity(0.5), lineWidth: 1)
                            )

                        // Update status indicator
                        if isUpdatingAddress {
                            HStack(spacing: 8) {
                                ProgressView()
                                    .scaleEffect(0.8)
                                Text("Updating address from current location...")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.leading, 8)
                        }
                    }

                    modernTextField(title: "Price", text: Binding(
                        get: { editedPrice == 0.0 ? "" : String(format: "%.2f", editedPrice) },
                        set: { editedPrice = Double($0) ?? 0.0 }
                    ), icon: "dollarsign.circle.fill")
                        .keyboardType(.decimalPad)
                }
            }

            // Service Category Section
            modernSectionCard(title: "Service Type", icon: "tag.circle.fill") {
                VStack(spacing: 16) {
                    HStack {
                        Image(systemName: "tag.fill")
                            .foregroundColor(.blue)
                            .frame(width: 20)

                        Text("Service Type")
                            .font(.headline)
                            .fontWeight(.semibold)

                        Spacer()

                        Button {
                            showingServiceCategoryCreator = true
                        } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.blue)
                        }
                        .accessibilityLabel("Add new service category")
                    }

                    if categoryManager.allCategories.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "tag")
                                .font(.system(size: 24))
                                .foregroundColor(.secondary)

                            Text("No service categories available")
                                .font(.subheadline)
                                .foregroundColor(.secondary)

                            Button("Add Service Category") {
                                showingServiceCategoryCreator = true
                            }
                            .font(.caption)
                            .foregroundColor(.blue)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                        .background(Color(UIColor.tertiarySystemBackground))
                        .cornerRadius(8)
                    } else {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                // None option
                                ServiceCategoryChip(
                                    category: nil,
                                    isSelected: editedServiceCategory == nil
                                ) {
                                    editedServiceCategory = nil
                                }

                                // Available categories
                                ForEach(categoryManager.allCategories, id: \.id) { category in
                                    ServiceCategoryChip(
                                        category: category,
                                        isSelected: editedServiceCategory?.id == category.id
                                    ) {
                                        editedServiceCategory = category
                                    }
                                }
                            }
                            .padding(.horizontal, 4)
                        }
                    }
                }
            }

            // Lead Status Section
            modernSectionCard(title: "Lead Status", icon: "chart.bar.fill") {
                VStack(spacing: 16) {
                    HStack {
                        Image(systemName: "flag.fill")
                            .foregroundColor(.blue)
                            .frame(width: 20)
                        Text("Status")
                            .font(.headline)
                            .fontWeight(.semibold)
                        Spacer()
                    }
                    
                    // Modern Status Grid
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 2), spacing: 12) {
                        ForEach(Lead.Status.allCases, id: \.self) { status in
                            ModernStatusCard(
                                status: status,
                                isSelected: editedStatus == status,
                                onTap: { editedStatus = status }
                            )
                        }
                    }
                }
            }
            
            // Follow-up & Notes Section
            modernSectionCard(title: "Follow-up & Notes", icon: "calendar.circle.fill") {
                VStack(spacing: 20) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "clock.fill")
                                .foregroundColor(.orange)
                                .frame(width: 20)
                            Text("Follow Up Date")
                                .font(.headline)
                                .fontWeight(.semibold)
                            
                            Spacer()
                            
                            if editedFollowUpDate != nil {
                                Button("Clear") {
                                    editedFollowUpDate = nil
                                }
                                .font(.caption)
                                .foregroundColor(.red)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color.red.opacity(0.1))
                                .cornerRadius(16)
                            }
                        }
                        
                        Button(action: {
                            showingDatePicker = true
                        }) {
                            HStack {
                                Image(systemName: editedFollowUpDate != nil ? "calendar.badge.clock" : "calendar.badge.plus")
                                    .foregroundColor(editedFollowUpDate != nil ? .blue : .gray)
                                
                                Text(editedFollowUpDate?.formatted(.dateTime.day().month().year().hour().minute()) ?? "Set follow up date & time")
                                    .foregroundColor(editedFollowUpDate != nil ? .primary : .secondary)
                                
                                Spacer()
                                
                                Image(systemName: "chevron.right")
                                    .foregroundColor(.gray)
                                    .font(.caption)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .background(Color(UIColor.tertiarySystemBackground))
                            .cornerRadius(12)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color(UIColor.separator).opacity(0.5), lineWidth: 1)
                            )
                        }
                    }
                    
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "note.text")
                                .foregroundColor(.purple)
                                .frame(width: 20)
                            Text("Notes")
                                .font(.headline)
                                .fontWeight(.semibold)
                        }
                        
                        TextEditor(text: $editedNotes)
                            .frame(minHeight: 100)
                            .padding(12)
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
        .sheet(isPresented: $showingDatePicker) {
            SeasonalDatePickerView(selectedDate: $editedFollowUpDate)
        }
    }
    
    private var mapSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Location")
                .font(.headline)
            
            Map(initialPosition: .region(MKCoordinateRegion(
                center: lead.coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
            ))) {
                Annotation(lead.displayName, coordinate: lead.coordinate) {
                    LeadAnnotationView(lead: lead)
                }
            }
            .frame(height: 200)
            .cornerRadius(12)
        }
    }
    
    
    private var followUpHistorySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Follow-up History")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Button(action: {
                    showingAddCheckIn = true
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "plus.circle.fill")
                        Text("Record")
                    }
                    .font(.caption)
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.blue)
                    .cornerRadius(16)
                }
            }
            
            if checkIns.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.title2)
                        .foregroundColor(.gray)
                    
                    Text("No follow-ups recorded yet")
                        .font(.body)
                        .foregroundColor(.secondary)
                    
                    Text("Start tracking your interactions with this lead")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
                .background(Color(UIColor.tertiarySystemBackground))
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color(UIColor.separator).opacity(0.5), lineWidth: 1)
                )
            } else {
                VStack(spacing: 8) {
                    HStack {
                        Text("\(checkIns.count) check-ins recorded")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        Spacer()
                        
                        if checkIns.count > 2 {
                            Button("View All") {
                                showingFullHistory = true
                            }
                            .font(.caption)
                            .foregroundColor(.blue)
                        }
                    }
                    
                    // Show last 2 check-ins
                    ForEach(Array(checkIns.prefix(2)), id: \.id) { checkIn in
                        CheckInRowView(checkIn: checkIn) {
                            deleteCheckIn(checkIn)
                        }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color(UIColor.tertiarySystemBackground))
                            .cornerRadius(8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color(UIColor.separator).opacity(0.5), lineWidth: 1)
                            )
                    }
                }
            }
        }
        .sheet(isPresented: $showingAddCheckIn) {
            AddCheckInView(lead: lead)
        }
        .sheet(isPresented: $showingFullHistory) {
            FollowUpHistoryView(lead: lead)
        }
        .sheet(isPresented: $showingScheduleAppointment) {
            ScheduleAppointmentView(lead: lead)
        }
        .sheet(isPresented: $showingServiceCategoryCreator) {
            ServiceCategoryCreatorView(editingCategory: nil)
        }
        .alert("Delete Lead", isPresented: $showingDeleteAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                deleteLead()
            }
        } message: {
            Text("Are you sure you want to delete this lead? This action cannot be undone.")
        }
        .errorAlert(onRetry: {
            if let errorContext = ErrorHandler.shared.currentError {
                switch errorContext {
                case .dataError:
                    saveLead()
                default:
                    break
                }
            }
        })
    }
    
    private var actionButtonsSection: some View {
        VStack(spacing: 12) {
            // Use LazyVGrid for better button layout with 2 columns
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 2), spacing: 12) {
                // Schedule Appointment Button (only for interested, scheduled, or converted leads)
                if shouldShowScheduleButton {
                    Button(action: {
                        showingScheduleAppointment = true
                    }) {
                        VStack(spacing: 8) {
                            Image(systemName: "calendar.badge.plus")
                                .font(.title2)
                                .foregroundColor(.white)
                            
                            VStack(spacing: 4) {
                                Text("Schedule")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                Text("Appointment")
                                    .font(.caption2)
                            }
                            .foregroundColor(.white)
                        }
                        .frame(maxWidth: .infinity, minHeight: 80)
                        .padding(.vertical, 12)
                        .padding(.horizontal, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.blue.gradient)
                        )
                        .shadow(color: .blue.opacity(0.3), radius: 4, x: 0, y: 2)
                    }
                }
                
                // Call Button (if phone number exists)
                if let phone = lead.phone, !phone.isEmpty {
                    Button(action: {
                        if let url = URL(string: "tel:\(phone)") {
                            UIApplication.shared.open(url)
                        }
                    }) {
                        VStack(spacing: 8) {
                            Image(systemName: "phone.fill")
                                .font(.title2)
                                .foregroundColor(.white)
                            
                            VStack(spacing: 4) {
                                Text("Call")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                Text("Customer")
                                    .font(.caption2)
                            }
                            .foregroundColor(.white)
                        }
                        .frame(maxWidth: .infinity, minHeight: 80)
                        .padding(.vertical, 12)
                        .padding(.horizontal, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.green.gradient)
                        )
                        .shadow(color: .green.opacity(0.3), radius: 4, x: 0, y: 2)
                    }
                }
                
                // Message Button (if phone number exists)
                if let phone = lead.phone, !phone.isEmpty {
                    Button(action: {
                        Utilities.sendSMS(to: phone)
                    }) {
                        VStack(spacing: 8) {
                            Image(systemName: "message.fill")
                                .font(.title2)
                                .foregroundColor(.white)
                            
                            VStack(spacing: 4) {
                                Text("Message")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                Text("Customer")
                                    .font(.caption2)
                            }
                            .foregroundColor(.white)
                        }
                        .frame(maxWidth: .infinity, minHeight: 80)
                        .padding(.vertical, 12)
                        .padding(.horizontal, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.purple.gradient)
                        )
                        .shadow(color: .purple.opacity(0.3), radius: 4, x: 0, y: 2)
                    }
                }
                
                // Email Button (if email exists)
                if let email = lead.email, !email.isEmpty {
                    Button(action: {
                        if let url = URL(string: "mailto:\(email)") {
                            UIApplication.shared.open(url)
                        }
                    }) {
                        VStack(spacing: 8) {
                            Image(systemName: "envelope.fill")
                                .font(.title2)
                                .foregroundColor(.white)
                            
                            VStack(spacing: 4) {
                                Text("Email")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                Text("Customer")
                                    .font(.caption2)
                            }
                            .foregroundColor(.white)
                        }
                        .frame(maxWidth: .infinity, minHeight: 80)
                        .padding(.vertical, 12)
                        .padding(.horizontal, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.orange.gradient)
                        )
                        .shadow(color: .orange.opacity(0.3), radius: 4, x: 0, y: 2)
                    }
                }
            }
            
            // Show current appointments if any exist
            if !leadAppointments.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "calendar.badge.checkmark")
                            .foregroundColor(.blue)
                        Text("Upcoming Appointments")
                            .font(.headline)
                            .fontWeight(.semibold)
                        Spacer()
                    }
                    
                    ForEach(leadAppointments.prefix(2), id: \.id) { appointment in
                        AppointmentSummaryRow(appointment: appointment)
                    }
                    
                    if leadAppointments.count > 2 {
                        Button("View all \(leadAppointments.count) appointments") {
                            // Navigate to appointments view filtered for this lead
                        }
                        .font(.caption)
                        .foregroundColor(.blue)
                    }
                }
                .padding(16)
                .background(Color(UIColor.tertiarySystemBackground))
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color(UIColor.separator).opacity(0.5), lineWidth: 1)
                )
            }
        }
        .padding(.horizontal, 16)
    }
    
    private var shouldShowScheduleButton: Bool {
        let status = LeadStatus.from(leadStatus: lead.leadStatus)
        return status == .interested || status == .closed
    }
    
    private var leadAppointments: [Appointment] {
        AppointmentManager.shared.getAppointments(for: lead)
            .filter { $0.status != .cancelled && $0.status != .completed }
            .sorted { $0.startDate < $1.startDate }
    }
    
    // MARK: - Modern UI Helper Functions
    
    @ViewBuilder
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
    private func modernTextField(title: String, text: Binding<String>, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(.blue)
                    .frame(width: 20)
                
                Text(title)
                    .font(.headline)
                    .fontWeight(.semibold)
            }
            
            TextField(title, text: text)
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
    
    private func loadLeadData() {
        editedName = lead.name ?? ""
        editedPhone = lead.phone ?? ""
        editedEmail = lead.email ?? ""
        editedAddress = lead.address ?? ""
        editedNotes = lead.notes ?? ""
        editedPrice = lead.price
        editedStatus = lead.leadStatus
        editedFollowUpDate = lead.followUpDate
        editedServiceCategory = lead.serviceCategoryObject
    }
    
    private func startEditing() {
        isEditing = true
    }
    
    private func cancelEditing() {
        isEditing = false
        loadLeadData()
    }
    
    private func saveLead() {
        print("LeadDetailView: Saving lead with status: \(editedStatus.displayName)")

        lead.name = editedName.isEmpty ? nil : editedName
        lead.phone = editedPhone.isEmpty ? nil : editedPhone
        lead.email = editedEmail.isEmpty ? nil : editedEmail
        lead.address = editedAddress.isEmpty ? nil : editedAddress
        lead.notes = editedNotes.isEmpty ? nil : editedNotes
        lead.price = editedPrice
        lead.leadStatus = editedStatus
        lead.setServiceCategory(editedServiceCategory)
        lead.setFollowUpDate(editedFollowUpDate, autoSave: false)

        cancelNotification(for: lead)
        if let followUpDate = editedFollowUpDate {
            scheduleNotification(for: lead, on: followUpDate)
        }

        do {
            try viewContext.save()
            print("LeadDetailView: Successfully saved lead with status: \(lead.leadStatus.displayName)")

            // Individual lead sync removed - data will sync manually, hourly, or before sign-out
            print("📝 Lead updated locally - will sync on next manual/hourly/sign-out sync")

            // Force the managed object context to refresh to ensure UI updates
            viewContext.refreshAllObjects()

            // Notify UI about follow-up date changes
            NotificationCenter.default.post(name: NSNotification.Name("FollowUpDateChanged"), object: lead)

            if isEditing {
                isEditing = false
            }
        } catch {
            ErrorHandler.shared.handle(error, context: "Save Lead")
        }
    }

    private func updateAddressFromCurrentLocation() {
        guard let userLocation = locationManager.location else {
            print("⚠️ No current location available")
            return
        }

        isUpdatingAddress = true
        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
        impactFeedback.impactOccurred()

        locationManager.reverseGeocode(coordinate: userLocation.coordinate) { addressString in
            DispatchQueue.main.async {
                self.isUpdatingAddress = false

                if let addressString = addressString, !addressString.isEmpty {
                    self.editedAddress = addressString
                    self.lead.latitude = userLocation.coordinate.latitude
                    self.lead.longitude = userLocation.coordinate.longitude
                    print("✅ Address updated from current location: \(addressString)")

                    // Success haptic feedback
                    let successFeedback = UINotificationFeedbackGenerator()
                    successFeedback.notificationOccurred(.success)
                } else {
                    print("❌ Failed to get address from current location")

                    // Error haptic feedback
                    let errorFeedback = UINotificationFeedbackGenerator()
                    errorFeedback.notificationOccurred(.error)
                }
            }
        }
    }

    private func deleteLead() {
        print("LeadDetailView: Deleting lead: \(lead.displayName)")
        
        // Cancel any scheduled notifications
        cancelNotification(for: lead)
        
        // Get lead ID for potential Firebase deletion
        let leadId = lead.id?.uuidString
        let leadName = lead.displayName
        
        // Delete from Core Data context
        viewContext.delete(lead)
        
        do {
            try viewContext.save()
            print("✅ Lead '\(leadName)' deleted successfully from Core Data")
            
            // Force refresh of all contexts to ensure UI updates
            viewContext.refreshAllObjects()
            
            // Notify other views about lead deletion
            NotificationCenter.default.post(name: NSNotification.Name("LeadDeleted"), object: leadId)
            
            // Delete from Firebase if authenticated
            if let leadId = leadId, FirebaseService.shared.isAuthenticated {
                Task {
                    do {
                        try await UserDataSyncManager.shared.deleteLeadFromFirebase(leadId: leadId)
                        print("✅ Lead \(leadId) deleted from Firebase")
                    } catch {
                        print("❌ Failed to delete lead from Firebase: \(error)")
                    }
                }
            }
            
            // Dismiss the view and return to previous screen
            DispatchQueue.main.async {
                self.dismiss()
            }
            
        } catch {
            ErrorHandler.shared.handle(error, context: "Delete Lead")
        }
    }

    private func scheduleNotification(for lead: Lead, on date: Date) {
        let content = UNMutableNotificationContent()
        content.title = "Follow up with \(lead.displayName)"
        
        // Create comprehensive notification body with key information
        var bodyParts: [String] = []
        
        // Add address if available
        if let address = lead.address, !address.isEmpty {
            bodyParts.append("📍 \(address)")
        }
        
        // Add phone if available
        if let phone = lead.phone, !phone.isEmpty {
            bodyParts.append("📞 \(phone)")
        }
        
        // Add status
        bodyParts.append("🏷️ Status: \(lead.leadStatus.displayName)")
        
        // Add price if greater than 0
        if lead.price > 0 {
            let formatter = NumberFormatter()
            formatter.numberStyle = .currency
            if let priceString = formatter.string(from: NSNumber(value: lead.price)) {
                bodyParts.append("💰 \(priceString)")
            }
        }
        
        // Add notes if available
        if let notes = lead.notes, !notes.isEmpty {
            bodyParts.append("📝 \(notes)")
        } else {
            bodyParts.append("📝 Time for a follow-up visit!")
        }
        
        content.body = bodyParts.joined(separator: "\n")
        content.sound = .default
        
        // Add user info for potential actions
        content.userInfo = [
            "leadId": lead.id?.uuidString ?? "",
            "leadName": lead.displayName,
            "leadPhone": lead.phone ?? "",
            "leadAddress": lead.address ?? ""
        ]
        
        // Add notification categories for quick actions (iOS 10+)
        content.categoryIdentifier = "LEAD_FOLLOWUP"

        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)

        let request = UNNotificationRequest(identifier: lead.id!.uuidString, content: content, trigger: trigger)

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                ErrorHandler.shared.handle(error, context: "Schedule Notification")
            }
        }
    }

    private func cancelNotification(for lead: Lead) {
        guard let leadId = lead.id else {
            print("❌ Cannot cancel notification: Lead ID is nil")
            return
        }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [leadId.uuidString])
    }

    private func openInMaps() {
        let coordinate = lead.coordinate
        
        // Validate coordinates
        guard coordinate.latitude != 0.0 || coordinate.longitude != 0.0 else {
            print("Invalid coordinates for navigation")
            return
        }
        
        // Create Apple Maps URL with coordinates
        let urlString = "http://maps.apple.com/?daddr=\(coordinate.latitude),\(coordinate.longitude)&dirflg=d"
        guard let mapsURL = URL(string: urlString) else {
            print("Failed to create Maps URL")
            return
        }
        
        if UIApplication.shared.canOpenURL(mapsURL) {
            UIApplication.shared.open(mapsURL)
        } else {
            print("Cannot open Maps application")
        }
    }
    
    private func migrateCheckInOutcomes() {
        var hasChanges = false
        
        print("Running migration for \(checkIns.count) check-ins...")
        
        for checkIn in checkIns {
            // If the check-in doesn't have an outcome, add a default one
            if checkIn.outcome == nil || checkIn.outcome?.isEmpty == true {
                print("Migrating check-in \(checkIn.id?.uuidString ?? "unknown") - setting outcome to successful")
                checkIn.outcomeEnum = .successful  // Default to successful contact
                hasChanges = true
            } else {
                print("Check-in \(checkIn.id?.uuidString ?? "unknown") already has outcome: \(checkIn.outcome ?? "nil")")
            }
        }
        
        if hasChanges {
            print("Saving \(checkIns.count) check-ins with new outcomes...")
            do {
                try viewContext.save()
                print("Successfully migrated check-in outcomes")
            } catch {
                ErrorHandler.shared.handle(error, context: "Migrate Check-ins")
                viewContext.rollback()
            }
        } else {
            print("No check-ins needed migration")
        }
    }
    
    private func deleteCheckIn(_ checkIn: FollowUpCheckIn) {
        viewContext.delete(checkIn)
        
        do {
            try viewContext.save()
        } catch {
            ErrorHandler.shared.handle(error, context: "Delete Check-in")
            viewContext.rollback()
        }
    }
    
    // MARK: - Modern Cell Components
    
    @ViewBuilder
    private func modernDetailCell(title: String, value: String, icon: String, iconColor: Color, isCallable: Bool = false, isEmailable: Bool = false) -> some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .foregroundColor(iconColor)
                .frame(width: 24, height: 24)
                .font(.title3)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)
                
                Text(value)
                    .font(.body)
                    .fontWeight(.medium)
                    .foregroundColor(value == "Not provided" ? .secondary : .primary)
            }
            
            Spacer()
            
            if isCallable && value != "Not provided" {
                Button(action: {
                    if let url = URL(string: "tel:\(value.filter { $0.isNumber })") {
                        UIApplication.shared.open(url)
                    }
                }) {
                    Image(systemName: "phone.circle.fill")
                        .foregroundColor(.green)
                        .font(.title2)
                }
            } else if isEmailable && value != "Not provided" {
                Button(action: {
                    if let url = URL(string: "mailto:\(value)") {
                        UIApplication.shared.open(url)
                    }
                }) {
                    Image(systemName: "envelope.circle.fill")
                        .foregroundColor(.orange)
                        .font(.title2)
                }
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .background(Color(UIColor.tertiarySystemBackground))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(UIColor.separator).opacity(0.3), lineWidth: 0.5)
        )
    }
    
    @ViewBuilder
    private func modernAddressCell(title: String, value: String, icon: String, iconColor: Color, hasAddress: Bool) -> some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .foregroundColor(iconColor)
                .frame(width: 24, height: 24)
                .font(.title3)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)
                
                Text(value)
                    .font(.body)
                    .fontWeight(.medium)
                    .foregroundColor(value == "Not provided" ? .secondary : .primary)
                    .lineLimit(2)
            }
            
            Spacer()
            
            if hasAddress && value != "Not provided" {
                Button(action: {
                    openInMaps()
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "location.fill")
                        Text("Navigate")
                    }
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.blue)
                    .cornerRadius(16)
                }
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .background(Color(UIColor.tertiarySystemBackground))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(UIColor.separator).opacity(0.3), lineWidth: 0.5)
        )
    }
    
    @ViewBuilder
    private func modernStatusCell(title: String, status: Lead.Status, icon: String, iconColor: Color) -> some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .foregroundColor(iconColor)
                .frame(width: 24, height: 24)
                .font(.title3)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)
                
                Text(status.displayName)
                    .font(.body)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
            }
            
            Spacer()
            
            StatusBadge(status: LeadStatus.from(leadStatus: status))
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .background(Color(UIColor.tertiarySystemBackground))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(UIColor.separator).opacity(0.3), lineWidth: 0.5)
        )
    }
    
    
    @ViewBuilder
    private func modernNotesCell(title: String, value: String, icon: String, iconColor: Color) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .foregroundColor(iconColor)
                    .frame(width: 24, height: 24)
                    .font(.title3)
                
                Text(title)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)
                
                Spacer()
            }
            
            Text(value)
                .font(.body)
                .fontWeight(.medium)
                .foregroundColor(.primary)
                .multilineTextAlignment(.leading)
                .lineLimit(nil)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .background(Color(UIColor.tertiarySystemBackground))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(UIColor.separator).opacity(0.3), lineWidth: 0.5)
        )
    }

}

struct DetailRow: View {
    let title: String
    let value: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.headline)
            Text(value)
                .font(.body)
                .foregroundColor(value == "Not provided" ? .secondary : .primary)
        }
    }
}

struct AppointmentSummaryRow: View {
    let appointment: Appointment
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(appointment.title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)
                
                HStack(spacing: 8) {
                    Image(systemName: appointment.appointmentType.icon)
                        .foregroundColor(appointment.appointmentType.color)
                        .font(.caption)
                    
                    Text(appointment.startDate.formatted(.dateTime.day().month().hour().minute()))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 4) {
                AppointmentStatusBadge(status: appointment.status)
                
                if !appointment.location.isEmpty {
                    Text(appointment.location)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .multilineTextAlignment(.trailing)
                }
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(Color(.systemBackground))
        .cornerRadius(8)
    }
}

struct AppointmentStatusBadge: View {
    let status: Appointment.AppointmentStatus
    
    var body: some View {
        Text(status.rawValue)
            .font(.caption2)
            .fontWeight(.semibold)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(status.color.opacity(0.2))
            .foregroundColor(status.color)
            .cornerRadius(6)
    }
}

struct ModernStatusCard: View {
    let status: Lead.Status
    let isSelected: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 8) {
                // Status Icon
                Image(systemName: status.iconName)
                    .font(.title2)
                    .foregroundColor(isSelected ? .white : status.uiColor)
                    .frame(width: 32, height: 32)
                
                // Status Text
                Text(status.displayName)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(isSelected ? .white : .primary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .padding(.horizontal, 8)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? AnyShapeStyle(status.uiColor.gradient) : AnyShapeStyle(Color(.systemBackground)))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(status.uiColor.opacity(isSelected ? 0 : 0.3), lineWidth: isSelected ? 0 : 1.5)
                    )
            )
            .shadow(
                color: isSelected ? status.uiColor.opacity(0.4) : Color.clear,
                radius: isSelected ? 8 : 0,
                x: 0,
                y: isSelected ? 4 : 0
            )
            .scaleEffect(isSelected ? 1.05 : 1.0)
            .animation(.easeInOut(duration: 0.2), value: isSelected)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// Extension to provide icons for Lead Status
extension Lead.Status {
    var iconName: String {
        switch self {
        case .notContacted: return "person.circle"
        case .notHome: return "house.circle"
        case .interested: return "star.circle.fill"
        case .converted: return "checkmark.circle.fill"
        case .notInterested: return "xmark.circle"
        }
    }
    
    var uiColor: Color {
        switch self {
        case .notContacted: return .gray
        case .notHome: return .orange
        case .interested: return .blue
        case .converted: return .green
        case .notInterested: return .red
        }
    }
}

#Preview {
    let context = PersistenceController.preview.container.viewContext
    let lead = Lead(context: context)
    lead.name = "John Doe"
    lead.phone = "555-1234"
    
    return LeadDetailView(lead: lead)
        .environment(\.managedObjectContext, context)
}
