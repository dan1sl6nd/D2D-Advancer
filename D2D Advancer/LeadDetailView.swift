import SwiftUI
import CoreData
import MapKit
import UIKit

struct LeadDetailView: View {
    @Environment(\.colorScheme) private var colorScheme
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
    @State private var editedFollowUpCadence = Lead.FollowUpCadence.none
    @State private var editedServiceCategory: ServiceCategory?
    @State private var editedLatitude: Double = 0.0
    @State private var editedLongitude: Double = 0.0
    @State private var showingDatePicker = false
    @State private var showingAddCheckIn = false
    @State private var showingFullHistory = false
    @State private var showingDeleteAlert = false
    @State private var showingScheduleAppointment = false
    @State private var showingServiceCategoryCreator = false
    @State private var showingLookAround = false
    @State private var lookAroundCoordinate = CLLocationCoordinate2D(latitude: 0, longitude: 0)
    @State private var isUpdatingAddress = false
    @State private var isCreatingContact = false
    @State private var showingContactCreationAlert = false
    @State private var contactCreationAlertTitle = ""
    @State private var contactCreationAlertMessage = ""
    @State private var copiedFieldName: String?
    @State private var copyToastDismissTask: Task<Void, Never>?

    @ObservedObject private var categoryManager = ServiceCategoryManager.shared
    @ObservedObject private var paywallManager = PaywallManager.shared
    
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
        VStack(spacing: 0) {
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

                    LeadPhotoSection(lead: lead)
                        .padding(.horizontal, 4)

                    LeadVoiceNoteSection(lead: lead)
                        .padding(.horizontal, 4)

                    mapSection

                    followUpHistorySection
                }
                .padding()
                .padding(.bottom, 16)
            }

            leadDetailBottomBar
        }
        .obsidianScreenBackground()
        .obsidianPushedNavigation(
            isEditing ? "Edit Lead" : "Lead Details",
            backButtonAccessibilityIdentifier: "leadDetailBackButton",
            onBack: { dismiss() }
        )
        .obsidianModalBackground()
        .overlay(alignment: .bottom) {
            copyToastOverlay
                .padding(.bottom, 96)
        }
        .sheet(isPresented: $showingDatePicker) {
            SeasonalDatePickerView(selectedDate: $editedFollowUpDate)
        }
        .onAppear {
            loadLeadData()
            migrateCheckInOutcomes()
        }
        .onDisappear {
            copyToastDismissTask?.cancel()
            copyToastDismissTask = nil
        }
    }
    
    private var headerSection: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: lead.leadStatus.iconName)
                .font(.obsidianAction)
                .foregroundColor(.white)
                .frame(width: 46, height: 46)
                .background(statusColor(for: lead.leadStatus))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(lead.displayName)
                        .font(.themeTitle)
                        .foregroundColor(Color.textPrimary)
                        .lineLimit(1)
                        .textSelection(.enabled)
                        .contextMenu {
                            copyMenuButton(title: "Name", value: lead.displayName)
                        }
                        .accessibilityHint("Long press to copy name")

                    Spacer(minLength: 6)

                    StatusBadge(status: lead.leadStatus)
                }

                Text(lead.address.flatMap { address in
                    let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
                    return trimmed.isEmpty ? nil : trimmed
                } ?? "No address saved")
                    .font(.obsidianFootnote)
                    .foregroundColor(Color.textSecondary)
                    .lineLimit(2)
                    .contextMenu {
                        copyMenuButton(title: "Address", value: lead.address ?? "")
                    }

                let createdText = lead.createdDate?.formatted(.dateTime.day().month().year().hour().minute()) ?? "Unknown"
                Label("Created \(createdText)", systemImage: "clock")
                    .font(.micro)
                    .foregroundColor(Color.textMuted)
                    .contextMenu {
                        copyMenuButton(title: "Created Date", value: createdText)
                    }
                    .accessibilityHint("Long press to copy created date")
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

    @ViewBuilder
    private var leadDetailBottomBar: some View {
        HStack(spacing: 12) {
            if isEditing {
                Button(action: cancelEditing) {
                    Label("Cancel", systemImage: "xmark.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(ObsidianSecondaryButtonStyle())
                .accessibilityIdentifier("leadDetailCancelEditButton")

                Button(action: saveLead) {
                    Label("Save", systemImage: "checkmark.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(ObsidianPrimaryButtonStyle())
                .accessibilityIdentifier("leadDetailSaveButton")
            } else {
                Button {
                    guard paywallManager.gateAction() else { return }
                    showingDeleteAlert = true
                } label: {
                    Label("Delete", systemImage: "trash.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(ObsidianDangerButtonStyle())
                .accessibilityIdentifier("leadDetailDeleteButton")

                Button(action: startEditing) {
                    Label("Edit", systemImage: "pencil.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(ObsidianPrimaryButtonStyle())
                .accessibilityIdentifier("leadDetailEditButton")
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

    private func statusColor(for status: Lead.Status) -> Color {
        switch status {
        case .notContacted:
            return Color.statusNotContacted
        case .notHome:
            return Color.statusNotHome
        case .interested:
            return Color.statusInterested
        case .converted:
            return Color.statusConverted
        case .notInterested:
            return Color.statusNotInterested
        }
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
                        iconColor: Color.electricViolet
                    )

                    modernDetailCell(
                        title: "Phone",
                        value: lead.phone ?? "Not provided",
                        icon: "phone.fill",
                        iconColor: Color.statusInterested,
                        isCallable: lead.phone != nil
                    )

                    modernDetailCell(
                        title: "Email",
                        value: lead.email ?? "Not provided",
                        icon: "envelope.fill",
                        iconColor: Color.statusNotHome,
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
                        iconColor: Color.statusNotInterested,
                        hasAddress: lead.address != nil
                    )

                    modernDetailCell(
                        title: "Deal Value",
                        value: String(format: "$%.2f CAD", lead.price),
                        icon: "dollarsign.circle.fill",
                        iconColor: Color.electricViolet
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
                        iconColor: Color.electricViolet
                    )
                    
                }
            }
            
            // Follow-up & Notes Section
            if lead.followUpDate != nil || !(lead.notes?.isEmpty ?? true) {
                modernSectionCard(title: "Follow-up & Notes", icon: "calendar.circle.fill") {
                    VStack(spacing: 16) {
                        if let followUpDate = lead.followUpDate {
                            modernDetailCell(
                                title: "Follow Up Date",
                                value: followUpDate.formatted(.dateTime.day().month().year().hour().minute()),
                                icon: "clock.fill",
                                iconColor: Color.electricViolet
                            )
                        }

                        if let notes = lead.notes, !notes.isEmpty {
                            modernNotesCell(
                                title: "Notes",
                                value: notes,
                                icon: "note.text",
                                iconColor: Color.electricViolet
                            )
                        }
                    }
                }
            }
        }
    }
    
    private var editForm: some View {
        VStack(spacing: 16) {
            editCustomerSection
            editWorkSection
            editNextStepSection
        }
    }

    private var editCustomerSection: some View {
        LeadFormSectionCard(title: "Customer", icon: "person.crop.circle.fill") {
            VStack(spacing: 12) {
                LeadFormTextField(
                    title: "Name",
                    placeholder: "Customer name",
                    text: $editedName,
                    icon: "person.fill",
                    accessibilityIdentifier: "leadDetailNameField"
                )

                LeadFormTextField(
                    title: "Phone",
                    placeholder: "Phone number",
                    text: $editedPhone,
                    icon: "phone.fill",
                    accessibilityIdentifier: "leadDetailPhoneField"
                )
                    .keyboardType(.phonePad)
                    .onChange(of: editedPhone) { _, newValue in
                        DispatchQueue.main.async {
                            editedPhone = Utilities.formatPhoneNumber(newValue)
                        }
                    }

                LeadFormTextField(
                    title: "Email",
                    placeholder: "Email address",
                    text: $editedEmail,
                    icon: "envelope.fill",
                    accessibilityIdentifier: "leadDetailEmailField"
                )
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
        }
    }

    private var editWorkSection: some View {
        LeadFormSectionCard(title: "Work", icon: "map.circle.fill") {
            VStack(spacing: 14) {
                LeadAddressEditor(
                    address: $editedAddress,
                    isUpdatingAddress: isUpdatingAddress,
                    accessibilityIdentifier: "leadDetailAddressField",
                    updateAddressAction: updateAddressFromCurrentLocation
                )

                LeadServiceCategoryPicker(
                    categories: categoryManager.allCategories,
                    selectedCategory: $editedServiceCategory,
                    onAddCategory: {
                        showingServiceCategoryCreator = true
                    }
                )

                LeadFormTextField(
                    title: "Price",
                    placeholder: "0.00",
                    text: Binding(
                        get: { editedPrice == 0 ? "" : String(format: "%.2f", editedPrice) },
                        set: { editedPrice = Double($0) ?? 0 }
                    ),
                    icon: "dollarsign.circle.fill",
                    accessibilityIdentifier: "leadDetailPriceField"
                )
                .keyboardType(.decimalPad)

                LeadStatusChipRow(
                    selection: $editedStatus,
                    selectedAccessibilityIdentifier: "leadDetailStatusMenu",
                    optionAccessibilityPrefix: "leadDetailStatusOption"
                )
            }
        }
    }

    private var editNextStepSection: some View {
        LeadFormSectionCard(title: "Next Step", icon: "calendar.badge.clock") {
            VStack(spacing: 14) {
                LeadFollowUpControls(selectedDate: $editedFollowUpDate) {
                    showingDatePicker = true
                }

                LeadFollowUpCadencePicker(cadence: $editedFollowUpCadence)

                LeadNotesEditor(
                    title: "Notes",
                    text: $editedNotes,
                    minHeight: 108,
                    accessibilityIdentifier: "leadDetailNotesField",
                    keyboardDoneAccessibilityIdentifier: "leadDetailNotesDoneButton"
                )
            }
        }
    }
    
    private var mapSection: some View {
        LeadFormSectionCard(title: "Location", icon: "map.fill") {
            ZStack(alignment: .bottomTrailing) {
                Map(initialPosition: .region(MKCoordinateRegion(
                    center: lead.coordinate,
                    span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                ))) {
                    Annotation(lead.displayName, coordinate: lead.coordinate) {
                        LeadAnnotationView(lead: lead)
                    }
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
                .frame(height: 200)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.obsidianBorder.opacity(0.45), lineWidth: 0.5)
                )

                Button {
                    lookAroundCoordinate = lead.coordinate
                    showingLookAround = true
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "binoculars.fill")
                            .font(.obsidianSmall)
                        Text("Street View")
                            .font(.obsidianSmall)
                    }
                    .foregroundColor(Color.textPrimary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .frame(minHeight: 44)
                    .background(Color.obsidianElevated.opacity(0.94))
                    .clipShape(Capsule())
                    .overlay(
                        Capsule()
                            .stroke(Color.obsidianBorder.opacity(0.5), lineWidth: 0.5)
                    )
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .padding(10)
            }
            .sheet(isPresented: $showingLookAround) {
                LookAroundSheet(
                    coordinate: $lookAroundCoordinate,
                    title: lead.address ?? lead.displayName
                )
            }
        }
    }
    
    
    private var followUpHistorySection: some View {
        LeadFormSectionCard(title: "Follow-up History", icon: "clock.arrow.circlepath") {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(checkIns.isEmpty ? "No check-ins yet" : "\(checkIns.count) check-ins recorded")
                        .font(.obsidianFootnote)
                        .foregroundColor(Color.textSecondary)

                    Spacer()

                    Button(action: {
                        showingAddCheckIn = true
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "plus.circle.fill")
                            Text("Record")
                        }
                        .font(.micro)
                        .fontWeight(.semibold)
                        .foregroundColor(Color.electricViolet)
                        .padding(.horizontal, 12)
                        .frame(minHeight: 44)
                        .background(Capsule().fill(Color.electricViolet.opacity(0.12)))
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("leadDetailHistoryRecordCheckInButton")
                }

                if checkIns.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.obsidianAction)
                            .foregroundColor(Color.textSecondary)

                        Text("No follow-ups recorded yet")
                            .font(.obsidianFootnote)
                            .fontWeight(.semibold)
                            .foregroundColor(Color.textSecondary)

                        Text("Start tracking your interactions with this lead")
                            .font(.micro)
                            .foregroundColor(Color.textSecondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                    .background(Color.obsidianElevated)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.obsidianBorder.opacity(0.45), lineWidth: 0.5)
                    )
                } else {
                    VStack(spacing: 8) {
                        HStack {
                            Text("\(checkIns.count) check-ins recorded")
                                .font(.obsidianFootnote)
                                .foregroundColor(Color.textSecondary)

                            Spacer()

                            if checkIns.count > 2 {
                                Button("View All") {
                                    showingFullHistory = true
                                }
                                .font(.obsidianFootnote)
                                .foregroundColor(Color.electricViolet)
                                .accessibilityIdentifier("leadDetailFullHistoryButton")
                            }
                        }

                        // Show last 2 check-ins
                        ForEach(Array(checkIns.prefix(2)), id: \.id) { checkIn in
                            CheckInRowView(checkIn: checkIn) {
                                deleteCheckIn(checkIn)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
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
        .alert(contactCreationAlertTitle, isPresented: $showingContactCreationAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(contactCreationAlertMessage)
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
        VStack(spacing: 16) {
            LeadFormSectionCard(title: "Quick Actions", icon: "bolt.fill") {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 2), spacing: 10) {
                if lead.address?.isEmpty == false {
                    leadActionButton(
                        title: "Navigate",
                        subtitle: "Route",
                        icon: "location.fill",
                        color: Color.electricViolet,
                        accessibilityIdentifier: "leadDetailNavigateButton"
                    ) {
                        openInMaps()
                    }
                }

                if shouldShowScheduleButton {
                    leadActionButton(
                        title: "Schedule",
                        subtitle: "Appointment",
                        icon: "calendar.badge.plus",
                        color: Color.electricViolet,
                        accessibilityIdentifier: "leadDetailScheduleButton"
                    ) {
                        guard paywallManager.gateAction() else { return }
                        showingScheduleAppointment = true
                    }
                }

                leadActionButton(
                    title: "Check-in",
                    subtitle: "Status",
                    icon: "checkmark.bubble.fill",
                    color: Color.statusInterested,
                    accessibilityIdentifier: "leadDetailRecordCheckInButton"
                ) {
                    showingAddCheckIn = true
                }

                if let phone = lead.phone, !phone.isEmpty {
                    leadActionButton(
                        title: "Call",
                        subtitle: "Customer",
                        icon: "phone.fill",
                        color: Color.statusInterested,
                        accessibilityIdentifier: "leadDetailCallButton"
                    ) {
                        Utilities.makePhoneCall(to: phone)
                    }
                }

                if let phone = lead.phone, !phone.isEmpty {
                    leadActionButton(
                        title: "Message",
                        subtitle: "Customer",
                        icon: "message.fill",
                        color: Color.electricViolet,
                        accessibilityIdentifier: "leadDetailMessageButton"
                    ) {
                        Utilities.sendSMS(to: phone)
                    }
                }

                if LeadContactService.canCreateContactFromLeadDetail(lead) {
                    leadActionButton(
                        title: "Create",
                        subtitle: "Contact",
                        icon: "person.crop.circle.badge.plus",
                        color: Color.statusConverted,
                        isLoading: isCreatingContact,
                        accessibilityIdentifier: "leadDetailCreateContactButton"
                    ) {
                        createContactForLead()
                    }
                    .disabled(isCreatingContact)
                }

                if let email = lead.email, !email.isEmpty {
                    leadActionButton(
                        title: "Email",
                        subtitle: "Customer",
                        icon: "envelope.fill",
                        color: Color.dataCyan,
                        accessibilityIdentifier: "leadDetailEmailButton"
                    ) {
                        Utilities.sendEmail(to: email)
                    }
                }
            }
            }

            if !leadAppointments.isEmpty {
                LeadFormSectionCard(title: "Upcoming Appointments", icon: "calendar.badge.checkmark") {
                    VStack(spacing: 10) {
                    ForEach(leadAppointments.prefix(2), id: \.id) { appointment in
                        AppointmentSummaryRow(appointment: appointment)
                    }

                    if leadAppointments.count > 2 {
                Button("View all \(leadAppointments.count) appointments") {
                    // Navigate to appointments view filtered for this lead
                }
                .font(.obsidianFootnote)
                .foregroundColor(Color.electricViolet)
                    }
                }
                }
            }
        }
    }

    private func leadActionButton(
        title: String,
        subtitle: String,
        icon: String,
        color: Color,
        isLoading: Bool = false,
        accessibilityIdentifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                ZStack {
                    if isLoading {
                        ProgressView()
                            .scaleEffect(0.72)
                            .tint(color)
                    } else {
                        Image(systemName: icon)
                            .font(.obsidianCallout)
                            .foregroundColor(color)
                    }
                }
                .frame(width: 34, height: 34)
                .background(color.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.obsidianFootnote)
                        .fontWeight(.semibold)
                        .foregroundColor(Color.textPrimary)
                        .lineLimit(1)

                    Text(subtitle)
                        .font(.micro)
                        .foregroundColor(Color.textSecondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
            }
            .padding(10)
            .frame(maxWidth: .infinity, minHeight: 58)
            .background(Color.obsidianElevated)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.obsidianBorder.opacity(0.45), lineWidth: 0.5)
            )
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityIdentifier(accessibilityIdentifier)
    }
    
    private var shouldShowScheduleButton: Bool {
        lead.leadStatus == .interested || lead.leadStatus == .converted
    }
    
    private var leadAppointments: [Appointment] {
        AppointmentManager.shared.getAppointments(for: lead)
            .filter { $0.status != .cancelled && $0.status != .completed }
            .sorted { $0.startDate < $1.startDate }
    }

    @ViewBuilder
    private var copyToastOverlay: some View {
        if let copiedFieldName {
            Text("\(copiedFieldName) copied")
                .font(.obsidianFootnote)
                .fontWeight(.semibold)
                .foregroundColor(Color.textPrimary)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color.obsidianElevated.opacity(0.96))
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .stroke(Color.obsidianBorder.opacity(0.5), lineWidth: 0.5)
                )
                .shadow(color: Color.black.opacity(0.28), radius: 10, x: 0, y: 4)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .accessibilityLabel("\(copiedFieldName) copied")
        }
    }

    @ViewBuilder
    private func copyMenuButton(title: String, value: String) -> some View {
        if let copyValue = copyableLeadValue(value) {
            Button {
                copyLeadField(title: title, value: copyValue)
            } label: {
                Label(copyMenuTitle(for: title), systemImage: "doc.on.doc")
            }
        }
    }

    private func copyableLeadValue(_ value: String) -> String? {
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedValue.isEmpty, trimmedValue != "Not provided", trimmedValue != "Unknown" else { return nil }
        return trimmedValue
    }

    private func copyMenuTitle(for fieldTitle: String) -> String {
        fieldTitle.lowercased().hasPrefix("copy ") ? fieldTitle : "Copy \(fieldTitle)"
    }

    private func copyLeadField(title: String, value: String) {
        UIPasteboard.general.string = value
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        UIAccessibility.post(notification: .announcement, argument: "\(title) copied")

        copyToastDismissTask?.cancel()
        withAnimation(.easeInOut(duration: 0.18)) {
            copiedFieldName = title
        }

        copyToastDismissTask = Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.18)) {
                    copiedFieldName = nil
                }
            }
        }
    }
    
    // MARK: - Modern UI Helper Functions
    
    @ViewBuilder
    private func modernSectionCard<Content: View>(title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        LeadFormSectionCard(title: title, icon: icon) {
            content()
        }
    }
    
    private func loadLeadData() {
        editedName = lead.name ?? ""
        editedPhone = lead.phone ?? ""
        editedEmail = lead.email ?? ""
        editedAddress = lead.address ?? ""
        editedNotes = lead.notes ?? ""
        editedPrice = lead.price
        editedLatitude = lead.latitude
        editedLongitude = lead.longitude
        editedStatus = lead.leadStatus
        editedFollowUpDate = lead.followUpDate
        editedFollowUpCadence = lead.followUpCadence
        editedServiceCategory = lead.serviceCategoryObject
    }

    private func startEditing() {
        guard paywallManager.gateAction() else { return }
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
        lead.latitude = editedLatitude
        lead.longitude = editedLongitude
        lead.notes = editedNotes.isEmpty ? nil : editedNotes
        lead.price = editedPrice
        lead.setServiceCategory(editedServiceCategory)
        lead.applyLeadStatus(
            editedStatus,
            followUpDate: editedFollowUpDate,
            shouldReplaceFollowUpDate: true,
            autoSave: false
        )
        lead.followUpCadence = editedFollowUpCadence

        do {
            try viewContext.save()
            print("LeadDetailView: Successfully saved lead with status: \(lead.leadStatus.displayName)")

            // Sync to the selected cloud provider after save
            UserDataSyncManager.shared.syncWithServer()

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

    private func createContactForLead() {
        guard LeadContactService.canCreateContactFromLeadDetail(lead), !isCreatingContact else { return }

        isCreatingContact = true

        LeadContactService.createContact(for: lead) { result in
            isCreatingContact = false
            contactCreationAlertTitle = result.title
            contactCreationAlertMessage = result.message
            showingContactCreationAlert = true

            if result == .saved {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            } else {
                UINotificationFeedbackGenerator().notificationOccurred(.error)
            }
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
                    self.editedLatitude = userLocation.coordinate.latitude
                    self.editedLongitude = userLocation.coordinate.longitude
                    print("✅ Address updated from current location: \(Utilities.redactedText(addressString))")

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
        if let leadId = lead.id {
            NotificationService.shared.cancelFollowUpNotification(for: leadId)
        }
        
        // Get lead ID for potential cloud deletion
        let leadUUID = lead.id
        let leadId = leadUUID?.uuidString
        let leadName = lead.displayName
        
        // Delete from Core Data context
        viewContext.delete(lead)
        
        do {
            try viewContext.save()
            print("✅ Lead '\(leadName)' deleted successfully from Core Data")
            if let leadUUID {
                UserDataSyncManager.markLeadDeletedLocally(leadUUID)
            }
            
            // Force refresh of all contexts to ensure UI updates
            viewContext.refreshAllObjects()
            
            // Notify other views about lead deletion
            NotificationCenter.default.post(name: NSNotification.Name("LeadDeleted"), object: leadId)
            
            // Delete from the selected cloud provider so CloudKit backups do not resurrect deleted leads.
            if let leadId = leadId,
               UserDataSyncManager.shouldDeleteLeadFromCloud(
                provider: CloudSyncProvider.current,
                isAuthenticated: FirebaseService.shared.isAuthenticated
               ) {
                Task {
                    do {
                        try await UserDataSyncManager.shared.deleteLeadFromCloud(leadId: leadId)
                        print("✅ Lead \(leadId) deleted from cloud")
                    } catch {
                        print("❌ Failed to delete lead from cloud: \(error)")
                        ErrorHandler.shared.handle(error, context: "Delete Lead From Cloud")
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

    private func openInMaps() {
        let coordinate = lead.coordinate
        Utilities.openMapsDirections(latitude: coordinate.latitude, longitude: coordinate.longitude)
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
        lead.updatedDate = Date()
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
                .font(.obsidianCallout)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.obsidianFootnote)
                    .foregroundColor(Color.textSecondary)

                Text(value)
                    .font(.obsidianCallout)
                    .foregroundColor(value == "Not provided" ? Color.textSecondary : Color.textPrimary)
            }

            Spacer()

            if isCallable && value != "Not provided" {
                Button(action: {
                    Utilities.makePhoneCall(to: value)
                }) {
                    Image(systemName: "phone.circle.fill")
                        .foregroundColor(Color.statusInterested)
                        .font(.obsidianAction)
                }
            } else if isEmailable && value != "Not provided" {
                Button(action: {
                    Utilities.sendEmail(to: value)
                }) {
                    Image(systemName: "envelope.circle.fill")
                        .foregroundColor(Color.statusNotHome)
                        .font(.obsidianAction)
                }
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .background(Color.obsidianElevated)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.obsidianBorder.opacity(0.45), lineWidth: 0.5)
        )
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .contextMenu {
            copyMenuButton(title: title, value: value)
        }
        .accessibilityHint(copyableLeadValue(value) == nil ? "" : "Long press to copy \(title.lowercased())")
    }
    
    @ViewBuilder
    private func modernAddressCell(title: String, value: String, icon: String, iconColor: Color, hasAddress: Bool) -> some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .foregroundColor(iconColor)
                .frame(width: 24, height: 24)
                .font(.obsidianCallout)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.obsidianFootnote)
                    .foregroundColor(Color.textSecondary)

                Text(value)
                    .font(.obsidianCallout)
                    .foregroundColor(value == "Not provided" ? Color.textSecondary : Color.textPrimary)
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
                    .font(.micro)
                    .fontWeight(.semibold)
                    .foregroundColor(Color.electricViolet)
                    .padding(.horizontal, 12)
                    .frame(minHeight: 44)
                    .background(Capsule().fill(Color.electricViolet.opacity(0.12)))
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .background(Color.obsidianElevated)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.obsidianBorder.opacity(0.45), lineWidth: 0.5)
        )
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .contextMenu {
            copyMenuButton(title: title, value: value)
        }
        .accessibilityHint(copyableLeadValue(value) == nil ? "" : "Long press to copy \(title.lowercased())")
    }
    
    @ViewBuilder
    private func modernStatusCell(title: String, status: Lead.Status, icon: String, iconColor: Color) -> some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .foregroundColor(iconColor)
                .frame(width: 24, height: 24)
                .font(.obsidianCallout)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.obsidianFootnote)
                    .foregroundColor(Color.textSecondary)

                Text(status.displayName)
                    .font(.obsidianCallout)
                    .foregroundColor(Color.textPrimary)
            }

            Spacer()

            StatusBadge(status: status)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .background(Color.obsidianElevated)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.obsidianBorder.opacity(0.45), lineWidth: 0.5)
        )
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .contextMenu {
            copyMenuButton(title: title, value: status.displayName)
        }
        .accessibilityHint("Long press to copy \(title.lowercased())")
    }
    
    
    @ViewBuilder
    private func modernNotesCell(title: String, value: String, icon: String, iconColor: Color) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .foregroundColor(iconColor)
                    .frame(width: 24, height: 24)
                    .font(.obsidianCallout)

                Text(title)
                    .font(.obsidianFootnote)
                    .foregroundColor(Color.textSecondary)

                Spacer()
            }

            Text(value)
                .font(.obsidianCallout)
                .foregroundColor(Color.textPrimary)
                .multilineTextAlignment(.leading)
                .lineLimit(nil)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .background(Color.obsidianElevated)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.obsidianBorder.opacity(0.45), lineWidth: 0.5)
        )
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .contextMenu {
            copyMenuButton(title: title, value: value)
        }
        .accessibilityHint("Long press to copy \(title.lowercased())")
    }

}

struct DetailRow: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.themeHeadline)
            Text(value)
                .font(.themeBody)
                .foregroundColor(value == "Not provided" ? Color.textSecondary : Color.textPrimary)
        }
    }
}

struct AppointmentSummaryRow: View {
    let appointment: Appointment
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(appointment.title)
                    .font(.obsidianFootnote)
                    .fontWeight(.medium)
                    .lineLimit(1)
                
                HStack(spacing: 8) {
                    Image(systemName: appointment.appointmentType.icon)
                        .foregroundColor(appointment.appointmentType.color)
                        .font(.micro)

                    Text(appointment.startDate.formatted(.dateTime.day().month().hour().minute()))
                        .font(.micro)
                        .foregroundColor(Color.textSecondary)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                AppointmentStatusBadge(status: appointment.status)

                if !appointment.location.isEmpty {
                    Text(appointment.location)
                        .font(.micro)
                        .foregroundColor(Color.textSecondary)
                        .lineLimit(1)
                        .multilineTextAlignment(.trailing)
                }
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(Color.obsidianElevated)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.obsidianBorder.opacity(0.45), lineWidth: 0.5)
        )
    }
}

struct AppointmentStatusBadge: View {
    let status: Appointment.AppointmentStatus
    
    var body: some View {
        Text(status.rawValue)
            .font(.micro)
            .fontWeight(.semibold)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(status.color.opacity(0.16)))
            .foregroundColor(status.color)
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
                    .font(.obsidianAction)
                    .foregroundColor(isSelected ? .white : status.uiColor)
                    .frame(width: 32, height: 32)
                
                // Status Text
                Text(status.displayName)
                    .font(.themeCaption)
                    .fontWeight(.semibold)
                    .foregroundColor(isSelected ? .white : Color.textPrimary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .padding(.horizontal, 8)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isSelected ? AnyShapeStyle(status.uiColor.gradient) : AnyShapeStyle(Color.obsidianSurface))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
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
    let lead = Lead.create(in: context)
    lead.name = "John Doe"
    lead.phone = "555-1234"
    
    return LeadDetailView(lead: lead)
        .environment(\.managedObjectContext, context)
}
