import SwiftUI
import CoreData
import CoreLocation
import Contacts
import ContactsUI

struct AddLeadLocationSeed {
    let coordinate: CLLocationCoordinate2D
    let address: String?

    init(coordinate: CLLocationCoordinate2D, address: String? = nil) {
        self.coordinate = coordinate
        self.address = AddLeadAddressPolicy.cleanedAddress(address)
    }
}

enum AddLeadAddressPolicy {
    static func cleanedAddress(_ address: String?) -> String? {
        let trimmed = address?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else { return nil }
        guard !isCoordinateFallback(trimmed) else { return nil }
        return trimmed
    }

    static func shouldApplySystemAddress(
        _ address: String?,
        currentAddress: String,
        hasManuallyEditedAddress: Bool,
        force: Bool = false
    ) -> Bool {
        guard cleanedAddress(address) != nil else { return false }
        guard !hasManuallyEditedAddress else { return false }
        guard !force else { return true }
        return cleanedAddress(currentAddress) == nil
    }

    private static func isCoordinateFallback(_ address: String) -> Bool {
        let lowercased = address.lowercased()
        if lowercased.contains("dropped pin at") {
            return true
        }
        if lowercased.hasPrefix("near "),
           lowercased.contains("(lat:"),
           lowercased.contains("lon:") {
            return true
        }
        if lowercased.hasPrefix("lat:") || lowercased.hasPrefix("lon:") {
            return true
        }
        return false
    }
}

enum AddLeadDraftAddressPolicy {
    static let coordinateTolerance = 0.00001

    static func canRestoreAddress(
        draftLatitude: String?,
        draftLongitude: String?,
        currentCoordinate: CLLocationCoordinate2D
    ) -> Bool {
        guard let draftLatitude,
              let draftLongitude,
              let latitude = Double(draftLatitude),
              let longitude = Double(draftLongitude) else {
            return false
        }

        return abs(latitude - currentCoordinate.latitude) <= coordinateTolerance &&
            abs(longitude - currentCoordinate.longitude) <= coordinateTolerance
    }
}

struct AddLeadView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var locationManager = LocationManager.shared
    @ObservedObject private var preferences = AppPreferences.shared
    @ObservedObject private var categoryManager = ServiceCategoryManager.shared
    @ObservedObject private var paywallManager = PaywallManager.shared
    @ObservedObject private var firebaseService = FirebaseService.shared
    @ObservedObject private var teamService = TeamFirebaseService.shared

    private static let draftKey = "addLeadDraft"

    let locationSeed: AddLeadLocationSeed
    private var coordinate: CLLocationCoordinate2D { locationSeed.coordinate }
    private var usableAddress: String? { AddLeadAddressPolicy.cleanedAddress(address) }

    @State private var name = ""
    @State private var phone = ""
    @State private var email = ""
    @State private var address = ""
    @State private var notes = ""
    @State private var price: Double = 0.0
    @State private var priceText: String = ""
    @State private var status = AppPreferences.shared.defaultLeadStatusEnum
    @State private var hasDraft = false
    @State private var didSaveSuccessfully = false
    @State private var followUpDate: Date?
    @State private var showingDatePicker = false
    @State private var isGeocodingAddress = false
    @State private var actualCoordinate: CLLocationCoordinate2D?
    @State private var geocodeTimer: Timer?
    @State private var showingMessageConfirmation = false
    @State private var showingPaywall = false
    @State private var createdLead: Lead?
    @State private var selectedServiceCategory: ServiceCategory?
    @State private var showingServiceCategoryCreator = false
    @State private var categoryToEdit: ServiceCategory?
    @State private var isUpdatingAddress = false
    @State private var selectedTechnicianUserId = ""
    @State private var technicianArrivalDate = Calendar.current.date(byAdding: .hour, value: 2, to: Date()) ?? Date()
    @State private var technicianJobDurationHours = 2
    @State private var hasManuallyEditedAddress = false
    @State private var isApplyingSystemAddress = false

    init(coordinate: CLLocationCoordinate2D, initialAddress: String? = nil) {
        let locationSeed = AddLeadLocationSeed(coordinate: coordinate, address: initialAddress)
        self.locationSeed = locationSeed
        _address = State(initialValue: locationSeed.address ?? "")
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Draft restored banner
                if hasDraft {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.uturn.backward.circle.fill")
                            .foregroundColor(.electricViolet)
                        Text("Previous draft restored")
                            .font(.obsidianCaption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Button("Clear") {
                            name = ""; phone = ""; email = ""; notes = ""; priceText = ""; price = 0
                            status = AppPreferences.shared.defaultLeadStatusEnum
                            clearDraft()
                            // Re-geocode for the current location
                            reverseGeocodeCoordinate()
                        }
                        .font(.obsidianCaption)
                        .foregroundColor(.electricViolet)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color.electricViolet.opacity(0.08))
                    .cornerRadius(12)
                }

                headerSection

                addLeadCustomerSection
                addLeadWorkSection
                addLeadNextStepSection

                if shouldShowTechnicianDispatch {
                    technicianJobSection
                }
            }
            .padding()
        }
        .background(Color.obsidianBackground(for: colorScheme))
        .navigationTitle("Add Lead")
        .obsidianInlineNavigation()
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
                    .foregroundColor(Color.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color.obsidianSurface)
                            .shadow(color: Color.black, radius: 2, x: 0, y: 1)
                    )
                }
                .accessibilityIdentifier("addLeadCancelButton")
                
                Button(action: {
                    saveLead()
                }) {
                    HStack {
                        Image(systemName: paywallManager.isPremium ? "checkmark.circle.fill" : "lock.fill")
                            .font(.title3)
                        Text(selectedTechnicianForJob == nil ? "Add Lead" : "Add & Send Job")
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
                                    gradient: Gradient(colors: [
                                        usableAddress == nil ? Color.textSecondary : Color.electricViolet,
                                        usableAddress == nil ? Color.textSecondary.opacity(0.8) : Color.electricVioletDeep
                                    ]),
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .shadow(color: usableAddress == nil ? .clear : Color.electricViolet.opacity(0.3), radius: 4, x: 0, y: 2)
                    )
                }
                .accessibilityIdentifier("addLeadSaveButton")
                .disabled(usableAddress == nil)
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
            .background(
                Color.obsidianBlack
                    .ignoresSafeArea(edges: .bottom)
            )
        }
        .sheet(isPresented: $showingDatePicker) {
            SeasonalDatePickerView(selectedDate: $followUpDate)
        }
        .sheet(isPresented: $showingMessageConfirmation) {
            if let lead = createdLead {
                FirstMessageConfirmationView(lead: lead) {
                    // On completion, dismiss the add lead view
                    dismiss()
                }
            }
        }
        .sheet(isPresented: $showingServiceCategoryCreator) {
            ServiceCategoryCreatorView(editingCategory: categoryToEdit) { category in
                selectedServiceCategory = category
            }
        }
        .onAppear {
            if let seedAddress = locationSeed.address {
                applySystemAddress(seedAddress)
            }

            // Geocode first (async), then restore draft — draft fields overwrite
            // except address, which only restores if the current pin has not
            // already supplied an address.
            reverseGeocodeCoordinate()
            restoreDraft()
            loadTeamForTechnicianDispatchIfNeeded()
        }
        .onDisappear {
            // Only save draft if the lead wasn't already saved successfully
            if !didSaveSuccessfully {
                saveDraft()
            }
        }
    }
    
    // MARK: - View Components
    
    private var headerSection: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "mappin.and.ellipse")
                .font(.obsidianAction)
                .foregroundColor(.white)
                .frame(width: 46, height: 46)
                .background(statusColor(for: status))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(name.isEmpty ? "New Lead" : name)
                        .font(.themeTitle)
                        .foregroundColor(Color.textPrimary)
                        .lineLimit(1)

                    Spacer(minLength: 6)

                    if !paywallManager.isPremium {
                        Label("Premium", systemImage: "crown.fill")
                            .font(.nano)
                            .foregroundColor(Color.electricViolet)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(Color.electricViolet.opacity(0.12)))
                    }
                }

                Text(address.isEmpty ? status.displayName : address)
                    .font(.obsidianFootnote)
                    .foregroundColor(Color.textSecondary)
                    .lineLimit(2)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.obsidianElevated)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.obsidianBorder.opacity(0.6), lineWidth: 0.5)
        )
    }

    private var addLeadCustomerSection: some View {
        LeadFormSectionCard(title: "Customer", icon: "person.crop.circle.fill") {
            VStack(spacing: 12) {
                LeadFormTextField(
                    title: "Name",
                    placeholder: "Customer name",
                    text: $name,
                    icon: "person.fill",
                    accessibilityIdentifier: "addLeadNameField"
                )

                LeadFormTextField(
                    title: "Phone",
                    placeholder: "Phone number",
                    text: $phone,
                    icon: "phone.fill",
                    accessibilityIdentifier: "addLeadPhoneField"
                )
                    .keyboardType(.phonePad)
                    .onChange(of: phone) { _, newValue in
                        DispatchQueue.main.async {
                            phone = Utilities.formatPhoneNumber(newValue)
                        }
                    }

                LeadFormTextField(
                    title: "Email",
                    placeholder: "Email address",
                    text: $email,
                    icon: "envelope.fill",
                    accessibilityIdentifier: "addLeadEmailField"
                )
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
        }
    }

    private var addLeadWorkSection: some View {
        LeadFormSectionCard(title: "Work", icon: "map.circle.fill") {
            VStack(spacing: 14) {
                LeadAddressEditor(
                    address: $address,
                    isUpdatingAddress: isUpdatingAddress,
                    isGeocodingAddress: locationManager.isForwardGeocoding,
                    geocodingError: locationManager.lastGeocodingError,
                    accessibilityIdentifier: "addLeadAddressField",
                    updateAddressAction: updateAddressFromCurrentLocation,
                    onAddressChange: { oldValue, newValue in
                        guard !isApplyingSystemAddress else { return }
                        if !newValue.isEmpty && newValue != oldValue {
                            hasManuallyEditedAddress = true
                            DispatchQueue.main.async {
                                geocodeAddressWithDelay()
                            }
                        }
                    }
                )

                LeadServiceCategoryPicker(
                    categories: categoryManager.allCategories,
                    selectedCategory: $selectedServiceCategory,
                    onAddCategory: {
                        categoryToEdit = nil
                        showingServiceCategoryCreator = true
                    }
                )

                LeadFormTextField(
                    title: "Price",
                    placeholder: "0.00",
                    text: $priceText,
                    icon: "dollarsign.circle.fill",
                    accessibilityIdentifier: "addLeadPriceField"
                )
                    .keyboardType(.decimalPad)
                    .onChange(of: priceText) { _, newValue in
                        DispatchQueue.main.async {
                            price = Double(newValue) ?? 0.0
                        }
                    }

                LeadStatusChipRow(selection: $status)
                    .accessibilityIdentifier("addLeadStatusMenu")
            }
        }
    }

    private var addLeadNextStepSection: some View {
        LeadFormSectionCard(title: "Next Step", icon: "calendar.badge.clock") {
            VStack(spacing: 14) {
                LeadFollowUpControls(selectedDate: $followUpDate) {
                    showingDatePicker = true
                }

                LeadNotesEditor(title: "Notes", text: $notes, minHeight: 108)
                    .accessibilityIdentifier("addLeadNotesField")
            }
        }
    }
    
    private var shouldShowTechnicianDispatch: Bool {
        guard let team = teamService.activeTeam,
              team.planStatus.allowsTeamWrite,
              teamService.currentMember?.role == .owner else {
            return false
        }
        return true
    }

    private var activeTechnicians: [TeamMember] {
        TeamMemberRoster.normalized(teamService.teamMembers)
            .filter { $0.isTechnician && $0.status == .active && !$0.isPendingInvite }
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    private var selectedTechnicianForJob: TeamMember? {
        activeTechnicians.first { $0.userId == selectedTechnicianUserId }
    }

    private var technicianJobEndDate: Date {
        technicianArrivalDate.addingTimeInterval(TimeInterval(technicianJobDurationHours) * 60 * 60)
    }

    private var technicianJobSection: some View {
        LeadFormSectionCard(title: "Technician Job", icon: "wrench.and.screwdriver.fill") {
            VStack(alignment: .leading, spacing: 16) {
                if activeTechnicians.isEmpty {
                    Text("No active technicians available.")
                        .font(.obsidianFootnote)
                        .foregroundColor(Color.textMuted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 6)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        fieldLabel(title: "Assign Technician", icon: "person.crop.circle.badge.checkmark")

                        Menu {
                            Button {
                                selectedTechnicianUserId = ""
                            } label: {
                                Label("Do not send job", systemImage: "minus.circle")
                            }

                            ForEach(activeTechnicians) { technician in
                                Button {
                                    selectedTechnicianUserId = technician.userId
                                } label: {
                                    Label(technician.displayName, systemImage: technician.userId == selectedTechnicianUserId ? "checkmark.circle.fill" : "person.fill")
                                }
                            }
                        } label: {
                            HStack {
                                Text(selectedTechnicianForJob?.displayName ?? "Select technician")
                                    .foregroundColor(selectedTechnicianForJob == nil ? Color.textSecondary : Color.textPrimary)
                                Spacer()
                                Image(systemName: "chevron.down")
                                    .foregroundColor(Color.textSecondary)
                                    .font(.caption)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .background(Color.obsidianSurface)
                            .cornerRadius(16)
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(Color.obsidianBorder.opacity(0.5), lineWidth: 0.5)
                            )
                        }
                        .accessibilityIdentifier("addLeadTechnicianMenu")
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        fieldLabel(title: "Approx. Arrival", icon: "calendar.badge.clock")

                        DatePicker("Approx. Arrival", selection: $technicianArrivalDate, displayedComponents: [.date, .hourAndMinute])
                            .labelsHidden()
                            .datePickerStyle(.compact)
                            .tint(Color.electricViolet)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(Color.obsidianSurface)
                            .cornerRadius(16)
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(Color.obsidianBorder.opacity(0.5), lineWidth: 0.5)
                            )
                            .accessibilityIdentifier("addLeadTechnicianArrivalDatePicker")
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        fieldLabel(title: "Job Window", icon: "timer")

                        Stepper(value: $technicianJobDurationHours, in: 1...12) {
                            HStack {
                                Text("\(technicianJobDurationHours) hr window")
                                    .font(.obsidianFootnote)
                                    .foregroundColor(Color.textPrimary)
                                Spacer()
                                Text(technicianJobEndDate.formatted(date: .omitted, time: .shortened))
                                    .font(.micro)
                                    .foregroundColor(Color.textSecondary)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(Color.obsidianSurface)
                        .cornerRadius(16)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(Color.obsidianBorder.opacity(0.5), lineWidth: 0.5)
                        )
                        .accessibilityIdentifier("addLeadTechnicianDurationStepper")
                    }
                }
            }
        }
    }

    private func fieldLabel(title: String, icon: String) -> some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(Color.electricViolet)
                .frame(width: 20)

            Text(title)
                .font(.headline)
                .fontWeight(.semibold)
                .foregroundColor(Color.textPrimary)
        }
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
    
    private func saveLead() {
        // Check if user has premium access
        guard paywallManager.gateAction() else { return }
        guard let effectiveAddress = usableAddress else { return }

        let technicianForJob = selectedTechnicianForJob
        let effectiveStatus: Lead.Status = technicianForJob == nil ? status : .converted
        let jobStartDate = technicianArrivalDate
        let jobEndDate = technicianJobEndDate

        let newLead = Lead.create(in: viewContext)
        newLead.name = name.isEmpty ? nil : name
        newLead.phone = phone.isEmpty ? nil : phone
        newLead.email = email.isEmpty ? nil : email
        newLead.address = effectiveAddress
        newLead.notes = notes.isEmpty ? nil : notes
        newLead.price = price
        newLead.setServiceCategory(selectedServiceCategory)

        // Auto-set follow-up for Not Home leads to tomorrow at 9 AM if no date was manually set
        var effectiveFollowUpDate = followUpDate
        if effectiveStatus == .notHome && followUpDate == nil {
            let calendar = Calendar.current
            if let tomorrow = calendar.date(byAdding: .day, value: 1, to: Date()),
               let morning = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow) {
                effectiveFollowUpDate = morning
            }
        }

        newLead.applyLeadStatus(
            effectiveStatus,
            followUpDate: effectiveFollowUpDate,
            shouldReplaceFollowUpDate: true,
            autoSave: false
        )
        let finalCoordinate = actualCoordinate ?? coordinate
        newLead.latitude = finalCoordinate.latitude
        newLead.longitude = finalCoordinate.longitude
        
        do {
            try viewContext.save()

            syncLeadToTeamIfNeeded(
                name: newLead.displayName,
                address: effectiveAddress,
                phone: newLead.phone,
                email: newLead.email,
                coordinate: finalCoordinate,
                status: effectiveStatus,
                notes: newLead.notes ?? "",
                serviceCategory: newLead.serviceCategory,
                price: newLead.price,
                assignedTechnician: technicianForJob,
                technicianStartDate: jobStartDate,
                technicianEndDate: jobEndDate
            )

            // Sync to the selected cloud provider after save
            UserDataSyncManager.shared.syncWithServer()

            // Sync to iOS Contacts if lead has name or phone
            if (!name.isEmpty || !phone.isEmpty) {
                syncToContacts(lead: newLead)
            }

            // Mark as saved so onDisappear doesn't re-create the draft
            didSaveSuccessfully = true
            clearDraft()

            // Check if lead has phone number and show message confirmation
            if !phone.isEmpty {
                createdLead = newLead
                showingMessageConfirmation = true
            } else {
                dismiss()
            }

        } catch {
            ErrorHandler.shared.handle(error, context: "Add Lead")
        }
    }

    private func syncLeadToTeamIfNeeded(
        name: String,
        address: String,
        phone: String?,
        email: String?,
        coordinate: CLLocationCoordinate2D,
        status: Lead.Status,
        notes: String,
        serviceCategory: String?,
        price: Double,
        assignedTechnician: TeamMember?,
        technicianStartDate: Date,
        technicianEndDate: Date
    ) {
        let teamService = TeamFirebaseService.shared
        let teamStatus = teamLeadStatus(for: status)

        Task {
            do {
                if teamService.activeTeam == nil || teamService.currentMember == nil {
                    await teamService.loadCurrentTeam()
                }
                if let assignedTechnician,
                   teamService.activeTeam != nil,
                   teamService.currentMember?.role == .owner {
                    try await teamService.createOwnerTechnicianJobLead(
                        name: name,
                        address: address,
                        phone: phone,
                        email: email,
                        coordinate: TeamCoordinate(latitude: coordinate.latitude, longitude: coordinate.longitude),
                        notes: notes,
                        serviceCategory: serviceCategory,
                        price: price,
                        technician: assignedTechnician,
                        startDate: technicianStartDate,
                        endDate: technicianEndDate
                    )
                    return
                }

                guard teamService.activeTeam != nil,
                      teamService.currentMember?.role == .member else {
                    return
                }

                try await teamService.createRepLead(
                    name: name,
                    address: address,
                    phone: phone,
                    email: email,
                    coordinate: TeamCoordinate(latitude: coordinate.latitude, longitude: coordinate.longitude),
                    status: teamStatus,
                    notes: notes,
                    serviceCategory: serviceCategory,
                    price: price,
                    estimatedValue: price
                )
            } catch {
                print("⚠️ Team lead sync failed: \(error.localizedDescription)")
            }
        }
    }

    private func loadTeamForTechnicianDispatchIfNeeded() {
        guard firebaseService.isAuthenticated else { return }
        guard teamService.activeTeam == nil || teamService.currentMember == nil else { return }

        Task {
            await teamService.loadCurrentTeam()
        }
    }

    private func teamLeadStatus(for status: Lead.Status) -> TeamLeadStatus {
        switch status {
        case .notContacted:
            return .notContacted
        case .notHome:
            return .notHome
        case .interested:
            return .interested
        case .converted:
            return .converted
        case .notInterested:
            return .notInterested
        }
    }
    
    // MARK: - Draft Save/Restore

    private func saveDraft() {
        // Only save if user entered something meaningful
        let hasContent = !name.isEmpty || !phone.isEmpty || !email.isEmpty || !notes.isEmpty || price > 0
        guard hasContent else { return }

        let draft: [String: String] = [
            "name": name,
            "phone": phone,
            "email": email,
            "address": usableAddress ?? "",
            "latitude": String(format: "%.8f", coordinate.latitude),
            "longitude": String(format: "%.8f", coordinate.longitude),
            "notes": notes,
            "price": priceText,
            "status": status.rawValue
        ]
        UserDefaults.standard.set(draft, forKey: Self.draftKey)
        print("📝 Lead draft saved")
    }

    private func restoreDraft() {
        guard let draft = UserDefaults.standard.dictionary(forKey: Self.draftKey) as? [String: String] else { return }

        let draftName = draft["name"] ?? ""
        let draftPhone = draft["phone"] ?? ""
        let draftEmail = draft["email"] ?? ""
        let draftNotes = draft["notes"] ?? ""
        let draftPrice = draft["price"] ?? ""

        let hasContent = !draftName.isEmpty || !draftPhone.isEmpty || !draftEmail.isEmpty || !draftNotes.isEmpty
        guard hasContent else { return }

        name = draftName
        phone = draftPhone
        email = draftEmail
        notes = draftNotes
        priceText = draftPrice
        price = Double(draftPrice) ?? 0.0

        if address.isEmpty,
           let draftAddress = draft["address"],
           let restoredAddress = AddLeadAddressPolicy.cleanedAddress(draftAddress),
           AddLeadDraftAddressPolicy.canRestoreAddress(
                draftLatitude: draft["latitude"],
                draftLongitude: draft["longitude"],
                currentCoordinate: coordinate
           ) {
            address = restoredAddress
        }
        if let statusRaw = draft["status"], let savedStatus = Lead.Status(rawValue: statusRaw) {
            status = savedStatus
        }
        hasDraft = true
        print("📝 Lead draft restored")
    }

    private func clearDraft() {
        UserDefaults.standard.removeObject(forKey: Self.draftKey)
        hasDraft = false
    }

    private func reverseGeocodeCoordinate(force: Bool = false) {
        guard force || address.isEmpty else { return }

        locationManager.reverseGeocode(coordinate: coordinate) { addressString in
            guard let addressString = addressString?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !addressString.isEmpty else {
                return
            }

            DispatchQueue.main.async {
                guard AddLeadAddressPolicy.shouldApplySystemAddress(
                    addressString,
                    currentAddress: address,
                    hasManuallyEditedAddress: hasManuallyEditedAddress,
                    force: force
                ) else {
                    return
                }
                applySystemAddress(addressString)
            }
        }
    }

    private func applySystemAddress(_ value: String) {
        guard let cleanedAddress = AddLeadAddressPolicy.cleanedAddress(value) else { return }

        isApplyingSystemAddress = true
        address = cleanedAddress
        DispatchQueue.main.async {
            isApplyingSystemAddress = false
        }
    }
    
    private func geocodeAddressWithDelay() {
        geocodeTimer?.invalidate()
        geocodeTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: false) { _ in
            self.geocodeCurrentAddress()
        }
    }
    
    private func geocodeCurrentAddress() {
        guard !address.isEmpty else { return }

        isGeocodingAddress = true
        locationManager.geocodeAddress(address) { coordinate in
            DispatchQueue.main.async {
                self.isGeocodingAddress = false
                if let coordinate = coordinate {
                    self.actualCoordinate = coordinate
                    print("Geocoded address to: \(coordinate)")
                }
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

                if let cleanedAddress = AddLeadAddressPolicy.cleanedAddress(addressString) {
                    self.address = cleanedAddress
                    self.actualCoordinate = userLocation.coordinate
                    print("✅ Address updated from current location: \(Utilities.redactedText(cleanedAddress))")

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
    
    private func syncToContacts(lead: Lead) {
        LeadContactService.createContact(for: lead) { result in
            switch result {
            case .saved:
                print("✅ Contact saved successfully for lead: \(lead.displayName)")
            case .permissionDenied:
                print("❌ Contact permission denied")
            case .failed(let reason):
                print("❌ Failed to save contact: \(reason)")
            }
        }
    }
}

extension View {
    func placeholder<Content: View>(
        when shouldShow: Bool,
        alignment: Alignment = .leading,
        @ViewBuilder placeholder: () -> Content) -> some View {

        ZStack(alignment: alignment) {
            self
            placeholder()
                .opacity(shouldShow ? 1 : 0)
                .allowsHitTesting(false)
        }
    }
}

struct LeadFormSectionCard<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(title, systemImage: icon)
                .font(.themeTitle)
                .foregroundColor(Color.textPrimary)
                .labelStyle(.titleAndIcon)

            content
        }
        .padding(16)
        .background(Color.obsidianSurface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.obsidianBorder.opacity(0.55), lineWidth: 0.5)
        )
        .shadow(color: Color.black.opacity(0.25), radius: 8, x: 0, y: 3)
    }
}

struct LeadFormTextField: View {
    let title: String
    let placeholder: String
    @Binding var text: String
    let icon: String
    var accessibilityIdentifier: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Label(title, systemImage: icon)
                .font(.obsidianFootnote)
                .foregroundColor(Color.textSecondary)

            TextField(placeholder, text: $text)
                .font(.obsidianCallout)
                .foregroundColor(Color.textPrimary)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(Color.obsidianElevated)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.obsidianBorder.opacity(0.45), lineWidth: 0.5)
                )
                .accessibilityIdentifier(accessibilityIdentifier ?? "leadForm\(title.replacingOccurrences(of: " ", with: ""))Field")
        }
    }
}

struct LeadAddressEditor: View {
    @Binding var address: String
    let isUpdatingAddress: Bool
    var isGeocodingAddress: Bool = false
    var geocodingError: String? = nil
    var accessibilityIdentifier: String? = nil
    let updateAddressAction: () -> Void
    var onAddressChange: (_ oldValue: String, _ newValue: String) -> Void = { _, _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Label("Address", systemImage: "location.fill")
                    .font(.obsidianFootnote)
                    .foregroundColor(Color.textSecondary)

                Spacer()

                Button(action: updateAddressAction) {
                    HStack(spacing: 5) {
                        if isUpdatingAddress {
                            ProgressView()
                                .scaleEffect(0.72)
                        } else {
                            Image(systemName: "location.viewfinder")
                                .font(.micro)
                        }
                        Text("Use Current")
                            .font(.micro)
                            .fontWeight(.semibold)
                    }
                    .foregroundColor(Color.electricViolet)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Color.electricViolet.opacity(0.12)))
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(isUpdatingAddress)
            }

            TextField("Street address", text: $address)
                .font(.obsidianCallout)
                .foregroundColor(Color.textPrimary)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(Color.obsidianElevated)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.obsidianBorder.opacity(0.45), lineWidth: 0.5)
                )
                .onChange(of: address) { oldValue, newValue in
                    onAddressChange(oldValue, newValue)
                }
                .accessibilityIdentifier(accessibilityIdentifier ?? "leadAddressField")

            if isGeocodingAddress || isUpdatingAddress {
                Label(isUpdatingAddress ? "Updating address..." : "Finding location...", systemImage: "arrow.triangle.2.circlepath")
                    .font(.micro)
                    .foregroundColor(Color.textSecondary)
            } else if let geocodingError, !geocodingError.isEmpty {
                Label(geocodingError, systemImage: "exclamationmark.triangle.fill")
                    .font(.micro)
                    .foregroundColor(Color.statusNotHome)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct LeadServiceCategoryPicker: View {
    let categories: [ServiceCategory]
    @Binding var selectedCategory: ServiceCategory?
    let onAddCategory: () -> Void

    private var displayedCategories: [ServiceCategory] {
        guard let selectedCategory,
              categories.contains(where: { $0.id == selectedCategory.id }) else {
            return categories
        }

        return [selectedCategory] + categories.filter { $0.id != selectedCategory.id }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Service", systemImage: "tag.fill")
                    .font(.obsidianFootnote)
                    .foregroundColor(Color.textSecondary)

                Spacer()

                Button(action: onAddCategory) {
                    Image(systemName: "plus.circle.fill")
                        .font(.obsidianFootnote)
                        .foregroundColor(Color.electricViolet)
                }
                .buttonStyle(PlainButtonStyle())
                .accessibilityLabel("Add service category")
                .accessibilityIdentifier("addLeadServiceCategoryAddButton")
            }

            if categories.isEmpty {
                Button(action: onAddCategory) {
                    Label("Add service", systemImage: "plus")
                        .font(.obsidianFootnote)
                        .foregroundColor(Color.electricViolet)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.obsidianElevated)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(PlainButtonStyle())
                .accessibilityIdentifier("addLeadServiceCategoryEmptyAddButton")
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ServiceCategoryChip(category: nil, isSelected: selectedCategory == nil) {
                            selectedCategory = nil
                        }

                        ForEach(displayedCategories, id: \.id) { category in
                            ServiceCategoryChip(category: category, isSelected: selectedCategory?.id == category.id) {
                                selectedCategory = category
                            }
                        }
                    }
                    .padding(.horizontal, 1)
                }
            }
        }
    }
}

struct LeadStatusChipRow: View {
    @Binding var selection: Lead.Status

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Status", systemImage: "flag.fill")
                .font(.obsidianFootnote)
                .foregroundColor(Color.textSecondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Lead.Status.allCases, id: \.self) { status in
                        Button {
                            selection = status
                        } label: {
                            Label(status.displayName, systemImage: status.iconName)
                                .font(.obsidianFootnote)
                                .fontWeight(.semibold)
                                .lineLimit(1)
                                .foregroundColor(selection == status ? .white : status.uiColor)
                                .padding(.horizontal, 11)
                                .padding(.vertical, 8)
                                .background(
                                    Capsule()
                                        .fill(selection == status ? status.uiColor : status.uiColor.opacity(0.12))
                                )
                        }
                        .buttonStyle(PlainButtonStyle())
                        .accessibilityIdentifier(selection == status ? "addLeadStatusMenu" : "addLeadStatusOption_\(status.rawValue)")
                        .accessibilityLabel(status.displayName)
                    }
                }
                .padding(.horizontal, 1)
            }
        }
    }
}

struct LeadFollowUpControls: View {
    @Binding var selectedDate: Date?
    let onCustomDate: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Follow Up", systemImage: "calendar.badge.clock")
                .font(.obsidianFootnote)
                .foregroundColor(Color.textSecondary)

            HStack(spacing: 8) {
                quickButton("Tomorrow", days: 1)
                    .accessibilityIdentifier("leadFollowUpQuick_1")
                quickButton("3 days", days: 3)
                    .accessibilityIdentifier("leadFollowUpQuick_3")
                quickButton("1 week", days: 7)
                    .accessibilityIdentifier("leadFollowUpQuick_7")
            }

            HStack(spacing: 8) {
                Button(action: onCustomDate) {
                    HStack {
                        Text(selectedDate?.formatted(.dateTime.day().month().year().hour().minute()) ?? "Set date and time")
                            .font(.obsidianFootnote)
                            .foregroundColor(selectedDate == nil ? Color.textSecondary : Color.textPrimary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Image(systemName: "calendar")
                            .foregroundColor(Color.textSecondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(PlainButtonStyle())
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(Color.obsidianElevated)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.obsidianBorder.opacity(0.45), lineWidth: 0.5)
                )
                .accessibilityIdentifier("leadFollowUpCustomDateButton")

                if selectedDate != nil {
                    Button {
                        selectedDate = nil
                    } label: {
                        Image(systemName: "xmark")
                            .font(.obsidianSmall)
                            .fontWeight(.semibold)
                            .foregroundColor(Color.textSecondary)
                            .frame(width: 42, height: 42)
                            .background(Color.obsidianElevated)
                            .clipShape(Circle())
                    }
                    .buttonStyle(PlainButtonStyle())
                    .accessibilityLabel("Clear follow up date")
                    .accessibilityIdentifier("leadFollowUpClearDateButton")
                }
            }
        }
    }

    private func quickButton(_ title: String, days: Int) -> some View {
        let date = Self.targetDate(days: days)
        let selected = date.map { target in
            guard let selectedDate else { return false }
            return Calendar.current.isDate(selectedDate, inSameDayAs: target)
        } ?? false

        return Button {
            selectedDate = date
        } label: {
            Text(title)
                .font(.micro)
                .fontWeight(.semibold)
                .foregroundColor(selected ? .white : Color.electricViolet)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(selected ? Color.electricViolet : Color.electricViolet.opacity(0.12))
                )
        }
        .buttonStyle(PlainButtonStyle())
    }

    private static func targetDate(days: Int) -> Date? {
        let calendar = Calendar.current
        guard let date = calendar.date(byAdding: .day, value: days, to: Date()) else { return nil }
        return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: date)
    }
}

struct LeadFollowUpCadencePicker: View {
    @Binding var cadence: Lead.FollowUpCadence

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Repeat", systemImage: "repeat")
                .font(.obsidianFootnote)
                .foregroundColor(Color.textSecondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Lead.FollowUpCadence.allCases, id: \.self) { option in
                        Button {
                            cadence = option
                        } label: {
                            Text(option.displayName)
                                .font(.micro)
                                .fontWeight(.semibold)
                                .lineLimit(1)
                                .foregroundColor(cadence == option ? .white : Color.textSecondary)
                                .padding(.horizontal, 11)
                                .padding(.vertical, 8)
                                .background(
                                    Capsule()
                                        .fill(cadence == option ? Color.electricViolet : Color.obsidianElevated)
                                )
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .padding(.horizontal, 1)
            }
        }
    }
}

struct LeadNotesEditor: View {
    let title: String
    @Binding var text: String
    var minHeight: CGFloat = 110
    var accessibilityIdentifier: String? = nil
    var keyboardDoneAccessibilityIdentifier: String = "leadNotesEditorDoneButton"

    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(title, systemImage: "note.text")
                    .font(.obsidianFootnote)
                    .foregroundColor(Color.textSecondary)

                Spacer()

                Button("Done") {
                    isFocused = false
                }
                .font(.obsidianFootnote.weight(.semibold))
                .foregroundColor(Color.electricViolet)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.electricViolet.opacity(0.1))
                .clipShape(Capsule())
                .accessibilityIdentifier(keyboardDoneAccessibilityIdentifier)
            }

            if let accessibilityIdentifier {
                TextEditor(text: $text)
                    .focused($isFocused)
                    .frame(minHeight: minHeight)
                    .obsidianEditorSurface(cornerRadius: 14)
                    .accessibilityIdentifier(accessibilityIdentifier)
            } else {
                TextEditor(text: $text)
                    .focused($isFocused)
                    .frame(minHeight: minHeight)
                    .obsidianEditorSurface(cornerRadius: 14)
            }
        }
    }
}

struct ServiceCategoryChip: View {
    let category: ServiceCategory?
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let category = category {
                    Image(systemName: category.icon)
                        .font(.caption)
                        .foregroundColor(isSelected ? .white : category.displayColor)
                    Text(category.name)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(isSelected ? .white : Color.textPrimary)
                } else {
                    Image(systemName: "minus.circle")
                        .font(.caption)
                        .foregroundColor(isSelected ? .white : Color.textSecondary)
                    Text("None")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(isSelected ? .white : Color.textPrimary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(
                        isSelected ?
                        (category?.displayColor ?? Color.textSecondary) :
                        Color.obsidianSurface
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(
                        isSelected ?
                        (category?.displayColor ?? Color.textSecondary) :
                        Color.obsidianBorder.opacity(0.3),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityIdentifier("addLeadServiceCategoryChip_\(category?.id ?? "none")")
    }
}

#Preview {
    AddLeadView(coordinate: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194))
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}
