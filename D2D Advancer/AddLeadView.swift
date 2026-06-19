import SwiftUI
import CoreData
import CoreLocation
@preconcurrency import UserNotifications
import Contacts
import ContactsUI

struct AddLeadLocationSeed {
    let coordinate: CLLocationCoordinate2D
    let address: String?

    init(coordinate: CLLocationCoordinate2D, address: String? = nil) {
        self.coordinate = coordinate

        let trimmedAddress = address?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.address = trimmedAddress?.isEmpty == false ? trimmedAddress : nil
    }
}

struct AddLeadView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var locationManager = LocationManager.shared
    @ObservedObject private var preferences = AppPreferences.shared
    @ObservedObject private var categoryManager = ServiceCategoryManager.shared
    @ObservedObject private var paywallManager = PaywallManager.shared

    private static let draftKey = "addLeadDraft"

    let locationSeed: AddLeadLocationSeed
    private var coordinate: CLLocationCoordinate2D { locationSeed.coordinate }

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

                // Header Section
                headerSection

                // Contact Information Section
                modernSectionCard(title: "Contact Information", icon: "person.crop.circle.fill") {
                    VStack(spacing: 16) {
                        modernTextField(title: "Name", text: $name, icon: "person.fill")
                        
                        modernTextField(title: "Phone", text: $phone, icon: "phone.fill")
                            .keyboardType(.phonePad)
                            .onChange(of: phone) { oldValue, newValue in
                                DispatchQueue.main.async {
                                    phone = Utilities.formatPhoneNumber(newValue)
                                }
                            }
                        
                        modernTextField(title: "Email", text: $email, icon: "envelope.fill")
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
                                    .foregroundColor(Color.electricViolet)
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
                                                .font(.obsidianSmall)
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
                                            .fill(Color.electricViolet)
                                    )
                                }
                                .disabled(isUpdatingAddress)
                            }

                            TextField("Address", text: $address)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                                .background(Color.obsidianSurface)
                                .cornerRadius(16)
                                .accessibilityIdentifier("addLeadAddressField")
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16)
                                        .stroke(Color.obsidianBorder.opacity(0.5), lineWidth: 0.5)
                                )
                                .onChange(of: address) { oldValue, newValue in
                                    if !newValue.isEmpty && newValue != oldValue {
                                        DispatchQueue.main.async {
                                            geocodeAddressWithDelay()
                                        }
                                    }
                                }

                            // Geocoding status indicator
                            if locationManager.isForwardGeocoding {
                                HStack(spacing: 8) {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                    Text("Finding location...")
                                        .font(.caption)
                                        .foregroundColor(Color.textSecondary)
                                }
                                .padding(.leading, 8)
                            } else if let error = locationManager.lastGeocodingError {
                                HStack(spacing: 8) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .font(.caption)
                                        .foregroundColor(Color.statusNotHome)
                                    Text(error)
                                        .font(.caption)
                                        .foregroundColor(Color.textSecondary)
                                }
                                .padding(.leading, 8)
                            }

                            // Update status indicator
                            if isUpdatingAddress {
                                HStack(spacing: 8) {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                    Text("Updating address from current location...")
                                        .font(.caption)
                                        .foregroundColor(Color.textSecondary)
                                }
                                .padding(.leading, 8)
                            }
                        }
                        
                        modernTextField(title: "Price", text: $priceText, icon: "dollarsign.circle.fill")
                            .keyboardType(.decimalPad)
                            .onChange(of: priceText) { oldValue, newValue in
                                DispatchQueue.main.async {
                                    price = Double(newValue) ?? 0.0
                                }
                            }
                    }
                }
                
                // Lead Details Section
                modernSectionCard(title: "Lead Details", icon: "flag.circle.fill") {
                    VStack(spacing: 16) {
                        // Service Category Field
                        serviceCategoryField
                        
                        // Status Field
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: "flag.fill")
                                    .foregroundColor(Color.electricViolet)
                                    .frame(width: 20)
                                
                                Text("Status")
                                    .font(.headline)
                                    .fontWeight(.semibold)
                            }
                            
                            Menu {
                                Picker("Status", selection: $status) {
                                    ForEach(Lead.Status.allCases, id: \.self) { status in
                                        Text(status.displayName).tag(status)
                                    }
                                }
                            } label: {
                                HStack {
                                    Text(status.displayName)
                                        .foregroundColor(Color.textPrimary)
                                    Spacer()
                                    Image(systemName: "chevron.down")
                                        .foregroundColor(Color.textSecondary)
                                        .font(.caption)
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                                .background(Color.obsidianSurface)
                                .cornerRadius(16)
                            }
                            .accessibilityIdentifier("addLeadStatusMenu")
                        }
                        
                        // Follow Up Date Field
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: "calendar.badge.clock")
                                    .foregroundColor(Color.electricViolet)
                                    .frame(width: 20)

                                Text("Follow Up Date")
                                    .font(.headline)
                                    .fontWeight(.semibold)
                            }

                            HStack(spacing: 8) {
                                quickFollowUpButton("Tomorrow", days: 1)
                                quickFollowUpButton("+3 Days", days: 3)
                                quickFollowUpButton("+1 Week", days: 7)
                            }

                            Button(action: {
                                showingDatePicker = true
                            }) {
                                HStack {
                                    if let selectedDate = followUpDate {
                                        Text(selectedDate.formatted(.dateTime.day().month().year().hour().minute()))
                                            .foregroundColor(Color.textPrimary)

                                        Spacer()

                                        Button(action: {
                                            followUpDate = nil
                                        }) {
                                            Image(systemName: "xmark.circle.fill")
                                                .foregroundColor(Color.textSecondary)
                                        }
                                    } else {
                                        Text("Set follow-up date")
                                            .foregroundColor(Color.textSecondary)

                                        Spacer()

                                        Image(systemName: "calendar")
                                            .foregroundColor(Color.textSecondary)
                                    }
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                                .background(Color.obsidianSurface)
                                .cornerRadius(16)
                            }
                        }
                        
                        // Notes Field
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: "note.text")
                                    .foregroundColor(Color.electricViolet)
                                    .frame(width: 20)
                                
                                Text("Notes")
                                    .font(.headline)
                                    .fontWeight(.semibold)
                            }
                            
                            ZStack(alignment: .topLeading) {
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(Color.obsidianSurface)

                                TextEditor(text: $notes)
                                    .scrollContentBackground(.hidden)
                                    .background(Color.clear)
                                    .foregroundColor(Color.textPrimary)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                            }
                            .frame(minHeight: 124)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .stroke(Color.obsidianBorder.opacity(0.5), lineWidth: 0.5)
                            )
                        }
                    }
                }
            }
            .padding()
        }
        .background(Color.obsidianBlack)
        .navigationTitle("Add Lead")
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
                    .foregroundColor(Color.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color.obsidianSurface)
                            .shadow(color: Color.black, radius: 2, x: 0, y: 1)
                    )
                }
                
                Button(action: {
                    saveLead()
                }) {
                    HStack {
                        Image(systemName: paywallManager.isPremium ? "checkmark.circle.fill" : "lock.fill")
                            .font(.title3)
                        Text("Add Lead")
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
                                        address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.textSecondary : Color.electricViolet,
                                        address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.textSecondary.opacity(0.8) : Color.electricVioletDeep
                                    ]),
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .shadow(color: address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .clear : Color.electricViolet.opacity(0.3), radius: 4, x: 0, y: 2)
                    )
                }
                .accessibilityIdentifier("addLeadSaveButton")
                .disabled(address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
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
            DatePicker("Follow-Up Date", selection: Binding(
                get: { followUpDate ?? Date() },
                set: { followUpDate = $0 }
            ), displayedComponents: [.date, .hourAndMinute])
            .datePickerStyle(.graphical)
            .presentationDetents([.medium])
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
            ServiceCategoryCreatorView(editingCategory: categoryToEdit)
        }
        .onAppear {
            // Geocode first (async), then restore draft — draft fields overwrite
            // except address, which only restores if geocode hasn't set one yet
            reverseGeocodeCoordinate()
            restoreDraft()
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
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    // Status Badge and Save Button
                    HStack {
                        Circle()
                            .fill(statusColor(for: status))
                            .frame(width: 8, height: 8)
                        Text(status.displayName)
                            .font(.subheadline)
                            .foregroundColor(statusColor(for: status))
                            .fontWeight(.medium)

                        Spacer()

                        // Premium indicator
                        if !paywallManager.isPremium {
                            HStack(spacing: 6) {
                                Image(systemName: "crown.fill")
                                    .font(.nano)
                                    .foregroundColor(Color.electricViolet)

                                Text("Premium")
                                    .font(.caption)
                                    .foregroundColor(Color.electricViolet)
                                    .fontWeight(.semibold)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(
                                Capsule()
                                    .fill(Color.electricViolet.opacity(0.12))
                            )
                        }
                    }
                    
                    // Lead Name
                    Text(name.isEmpty ? "New Lead" : name)
                        .font(.themeLargeTitle)

                    // Created Date
                    Text("Created: \(Date().formatted(.dateTime.day().month().year()))")
                        .font(.themeCaption)
                        .foregroundColor(Color.textSecondary)
                }
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
    
    private func modernSectionCard<Content: View>(title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(Color.electricViolet)
                    .font(.title2)

                Text(title)
                    .font(.themeTitle)
                    .foregroundColor(Color.textPrimary)

                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)

            content()
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
        }
        .background(Color.obsidianSurface)
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.obsidianBorder, lineWidth: 0.5)
        )
        .shadow(color: Color.black, radius: 8, x: 0, y: 4)
    }
    
    private func modernTextField(title: String, text: Binding<String>, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(Color.electricViolet)
                    .frame(width: 20)

                Text(title)
                    .font(.headline)
                    .fontWeight(.semibold)
            }

            TextField(title, text: text)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color.obsidianSurface)
                .cornerRadius(16)
                .accessibilityIdentifier("addLead\(title.replacingOccurrences(of: " ", with: ""))Field")
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.obsidianBorder.opacity(0.5), lineWidth: 0.5)
                )
        }
    }
    
    private var serviceCategoryField: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "tag.fill")
                    .foregroundColor(Color.electricViolet)
                    .frame(width: 20)

                Text("Service Type")
                    .font(.headline)
                    .fontWeight(.semibold)

                Spacer()

                Button {
                    showingServiceCategoryCreator = true
                } label: {
                    Image(systemName: "plus")
                        .font(.obsidianFootnote)
                        .foregroundColor(Color.electricViolet)
                }
                .accessibilityLabel("Add new service category")
            }
            
            if categoryManager.allCategories.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "tag")
                        .font(.system(size: 24))
                        .foregroundColor(Color.textSecondary)

                    Text("No service categories available")
                        .font(.subheadline)
                        .foregroundColor(Color.textSecondary)

                    Button("Add Service Category") {
                        showingServiceCategoryCreator = true
                    }
                    .font(.caption)
                    .foregroundColor(Color.electricViolet)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
                .background(Color.obsidianSurface)
                .cornerRadius(16)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        // None option
                        ServiceCategoryChip(
                            category: nil,
                            isSelected: selectedServiceCategory == nil
                        ) {
                            selectedServiceCategory = nil
                        }
                        
                        // Available categories
                        ForEach(categoryManager.allCategories, id: \.id) { category in
                            ServiceCategoryChip(
                                category: category,
                                isSelected: selectedServiceCategory?.id == category.id
                            ) {
                                selectedServiceCategory = category
                            }
                        }
                    }
                    .padding(.horizontal, 4)
                }
            }
        }
    }
    
    private func quickFollowUpButton(_ label: String, days: Int) -> some View {
        let calendar = Calendar.current
        let targetDate: Date? = {
            guard let date = calendar.date(byAdding: .day, value: days, to: Date()),
                  let morning = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: date) else { return nil }
            return morning
        }()
        let isSelected: Bool = {
            guard let target = targetDate, let current = followUpDate else { return false }
            return calendar.isDate(current, inSameDayAs: target)
        }()

        return Button {
            if let date = targetDate {
                followUpDate = date
            }
        } label: {
            Text(label)
                .font(.obsidianSmall)
                .foregroundColor(isSelected ? .white : .electricViolet)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? Color.electricViolet : Color.obsidianSurface)
                .cornerRadius(8)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.obsidianBorder, lineWidth: 0.5))
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

        let newLead = Lead(context: viewContext)
        newLead.id = UUID()
        newLead.createdDate = Date()
        newLead.updatedDate = Date()
        newLead.name = name.isEmpty ? nil : name
        newLead.phone = phone.isEmpty ? nil : phone
        newLead.email = email.isEmpty ? nil : email
        newLead.address = address.isEmpty ? nil : address
        newLead.notes = notes.isEmpty ? nil : notes
        newLead.price = price
        newLead.leadStatus = status
        newLead.setServiceCategory(selectedServiceCategory)

        // Auto-set follow-up for Not Home leads to tomorrow at 9 AM if no date was manually set
        var effectiveFollowUpDate = followUpDate
        if status == .notHome && followUpDate == nil {
            let calendar = Calendar.current
            if let tomorrow = calendar.date(byAdding: .day, value: 1, to: Date()),
               let morning = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow) {
                effectiveFollowUpDate = morning
            }
        }

        newLead.setFollowUpDate(effectiveFollowUpDate, autoSave: false)
        let finalCoordinate = actualCoordinate ?? coordinate
        newLead.latitude = finalCoordinate.latitude
        newLead.longitude = finalCoordinate.longitude
        
        do {
            try viewContext.save()

            syncLeadToTeamIfNeeded(
                name: newLead.displayName,
                address: newLead.address ?? address,
                phone: newLead.phone,
                email: newLead.email,
                coordinate: finalCoordinate,
                status: status,
                notes: newLead.notes ?? "",
                serviceCategory: newLead.serviceCategory,
                price: newLead.price
            )

            // Sync to Firebase after save
            UserDataSyncManager.shared.syncWithServer()

            // Schedule notification if follow-up date is set
            if let followUpDate = effectiveFollowUpDate {
                scheduleNotification(for: newLead, on: followUpDate)
            }

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
        price: Double
    ) {
        let teamService = TeamFirebaseService.shared
        let teamStatus = teamLeadStatus(for: status)

        Task {
            do {
                if teamService.activeTeam == nil || teamService.currentMember == nil {
                    await teamService.loadCurrentTeam()
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
            "address": address,
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
        // Only restore address if the current one is still empty
        // (reverseGeocodeCoordinate may have already set a fresh address for the new location)
        if address.isEmpty, let draftAddress = draft["address"], !draftAddress.isEmpty {
            address = draftAddress
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

    private func reverseGeocodeCoordinate() {
        if address.isEmpty {
            locationManager.reverseGeocode(coordinate: coordinate) { addressString in
                if let addressString = addressString {
                    DispatchQueue.main.async {
                        self.address = addressString
                    }
                }
            }
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

                if let addressString = addressString, !addressString.isEmpty {
                    self.address = addressString
                    self.actualCoordinate = userLocation.coordinate
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

        guard let leadId = lead.id else {
            print("❌ Cannot schedule notification: lead has no ID")
            return
        }
        let leadDisplayName = lead.displayName

        // Check notification permission first
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            guard NotificationService.isAuthorizationAllowed(settings.authorizationStatus) else {
                print("❌ Notification permission not granted, status: \(settings.authorizationStatus.rawValue)")
                return
            }

            let calendar = Calendar.current
            let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)

            let request = UNNotificationRequest(identifier: leadId.uuidString, content: content, trigger: trigger)

            UNUserNotificationCenter.current().add(request) { error in
                if let error = error {
                    ErrorHandler.shared.handle(error, context: "Schedule Notification")
                } else {
                    print("Notification scheduled for \(date) for lead: \(leadDisplayName)")
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
    }
}

#Preview {
    AddLeadView(coordinate: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194))
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}
