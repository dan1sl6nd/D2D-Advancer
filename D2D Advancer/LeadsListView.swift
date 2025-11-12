import SwiftUI
import CoreData
import UserNotifications

struct LeadsListView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @ObservedObject private var preferences = AppPreferences.shared
    @ObservedObject private var router = AppRouter.shared
    @StateObject private var searchFilterManager = SearchFilterManager()
    @State private var selectedTab: LeadTab = .active
    @State private var showingFilters = false
    @State private var sortBy: SortOption = .dateUpdated
    @State private var sortAscending = false
    @State private var currentPage = 0
    @State private var isLoadingMore = false
    @State private var hasMoreData = true
    @State private var showingOnboarding = false
    @State private var filterUpdateTask: Task<Void, Never>? = nil
    @State private var selectedLead: Lead?
    @State private var messageLead: Lead?
    
    private let pageSize = 50
    
    enum LeadTab: String, CaseIterable {
        case active = "Active"
        case inactive = "Inactive"
        
        var leadStatuses: [Lead.Status] {
            switch self {
            case .active:
                return [.notContacted, .interested, .converted]
            case .inactive:
                return [.notHome, .notInterested]
            }
        }
    }
    
    enum SortOption: String, CaseIterable {
        case name = "Name"
        case dateCreated = "Date Created"
        case dateUpdated = "Date Updated"
        case status = "Status"
    }
    
    @State private var paginatedLeads: [Lead] = []
    
    var body: some View {
        NavigationView {
            GeometryReader { geometry in
                VStack(spacing: 0) {
                    safeAreaSpacer(geometry: geometry)
                    tabSelectionSection
                    searchAndFiltersSection
                    leadsContentSection
                }
                .ignoresSafeArea(.all, edges: .top)
            }
            .navigationBarHidden(true)
            .background(Color(UIColor.systemGroupedBackground))
            .sheet(item: $selectedLead) { lead in
                LeadDetailView(lead: lead)
            }
            .sheet(item: $messageLead) { lead in
                MessageSelectionView(lead: lead)
            }
            .task {
                loadInitialLeads()
            }
            .onChange(of: selectedTab) {
                resetAndLoadLeads()
            }
            .onChange(of: sortBy) {
                resetAndLoadLeads()
            }
            .onChange(of: sortAscending) {
                resetAndLoadLeads()
            }
            .onChange(of: searchFilterManager.currentFilter) { 
                resetAndLoadLeads()
            }
            .onChange(of: router.targetLeadID) { _, newValue in
                guard let id = newValue else { return }
                if let lead = fetchLead(by: id) {
                    selectedLead = lead
                }
                router.targetLeadID = nil
            }
            .onChange(of: router.openMessageForLeadID) { _, newValue in
                guard let id = newValue else { return }
                if let lead = fetchLead(by: id) {
                    messageLead = lead
                }
                router.openMessageForLeadID = nil
            }
        }
    }
    
    // MARK: - Extracted View Components
    
    private func safeAreaSpacer(geometry: GeometryProxy) -> some View {
        Rectangle()
            .fill(
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color(UIColor.systemBackground),
                        Color(UIColor.systemBackground).opacity(0.98)
                    ]),
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .frame(height: max(geometry.safeAreaInsets.top + 20, 70))
    }
    
    private var tabSelectionSection: some View {
        HStack(spacing: 0) {
            ForEach(LeadTab.allCases, id: \.self) { tab in
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        selectedTab = tab
                    }
                }) {
                    Text(tab.rawValue)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                        .foregroundColor(selectedTab == tab ? .white : .primary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(selectedTab == tab ? Color.blue : Color.clear)
                                .opacity(selectedTab == tab ? 1 : 0)
                        )
                }
                .buttonStyle(PlainButtonStyle())
                .accessibilityLabel("\(tab.rawValue) leads")
                .accessibilityHint("Show \(tab.rawValue.lowercased()) leads")
                .accessibilityAddTraits(selectedTab == tab ? [.isSelected] : [])
                .accessibilityRemoveTraits(.isImage)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Lead filter tabs")
        .padding(.horizontal, 16)
        .padding(.bottom, 4)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(UIColor.tertiarySystemBackground))
                .padding(.horizontal, 12)
        )
    }
    
    private var searchAndFiltersSection: some View {
        VStack(spacing: 0) {
            SearchBar(text: $searchFilterManager.currentFilter.text)
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Search leads")
            
            QuickFilterChipsView(searchFilterManager: searchFilterManager)
                .padding(.horizontal)
            
            FilterBar(
                sortBy: $sortBy,
                sortAscending: $sortAscending,
                showingFilters: $showingFilters
            )
        }
    }
    
    private var leadsContentSection: some View {
        Group {
            if paginatedLeads.isEmpty && !isLoadingMore {
                emptyStateView
            } else {
                leadsScrollView
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Leads list")
        .refreshable {
            await refreshLeads()
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Spacer()
            
            Circle()
                .fill(Color.gray.opacity(0.2))
                .frame(width: 80, height: 80)
                .overlay(
                    Image(systemName: "person.3.fill")
                        .font(.system(size: 32))
                        .foregroundColor(.gray)
                )
            
            VStack(spacing: 8) {
                Text("No Leads Found")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                
                Text(selectedTab == .active ? 
                    "Start adding leads to build your customer database and track your progress." :
                    "Inactive leads will appear here when you mark them as not interested or not home.")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("No leads found")
        .accessibilityValue(selectedTab == .active ? 
            "Start adding leads to build your customer database" :
            "Inactive leads will appear here when marked as not interested or not home")
    }
    
    private var leadsScrollView: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(paginatedLeads, id: \.id) { lead in
                    LeadRowView(
                        lead: lead,
                        onTap: { selectedLead = lead },
                        onDelete: { handleLongPressDelete(lead) },
                        onCall: {
                            if let phone = lead.phone, !phone.isEmpty {
                                Utilities.makePhoneCall(to: phone)
                            }
                        },
                        onMessage: {
                            messageLead = lead
                        },
                        onFollowUp: {
                            quickSetFollowUp(for: lead)
                        }
                    )
                    .onLongPressGesture {
                        handleLongPressDelete(lead)
                    }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("Lead: \(lead.displayName)")
                        .accessibilityHint("Double tap to view lead details, long press to delete")
                        .accessibilityValue(leadAccessibilityValue(for: lead))
                        .onAppear {
                            // Load more when approaching the end
                            if lead == paginatedLeads.last {
                                loadMoreLeadsIfNeeded()
                            }
                        }
                }
                
                // Loading indicator at bottom
                if isLoadingMore && hasMoreData {
                    HStack {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("Loading more leads...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    .accessibilityLabel("Loading more leads")
                }
            }
            .padding(.vertical, 8)
        }
    }
    
    // MARK: - Helper Functions
    
    private func handleLongPressDelete(_ lead: Lead) {
        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
        impactFeedback.impactOccurred()
        
        let alert = UIAlertController(
            title: "Delete Lead",
            message: "Delete \(lead.displayName)? This action cannot be undone.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Delete", style: .destructive) { _ in
            deleteLead(lead)
        })
        
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first {
            window.rootViewController?.present(alert, animated: true)
        }
    }
    
    private func deleteLead(_ lead: Lead) {
        withAnimation(.easeInOut(duration: 0.3)) {
            // Remove from paginated leads immediately for UI feedback
            paginatedLeads.removeAll { $0.id == lead.id }
        }
        
        // Delete from Core Data
        viewContext.delete(lead)
        
        do {
            try viewContext.save()
            
            // Sync with server
            UserDataSyncManager.shared.syncWithServer()
            
            print("✅ Lead deleted successfully: \(lead.displayName)")
        } catch {
            print("❌ Failed to delete lead: \(error)")
            
            // Re-add to list if deletion failed
            Task { @MainActor in
                resetAndLoadLeads()
            }
        }
    }
    
    // MARK: - Pagination Methods
    
    private func loadInitialLeads() {
        Task {
            await performLeadFetch(reset: true)
        }
    }
    
    private func resetAndLoadLeads() {
        currentPage = 0
        hasMoreData = true
        Task {
            await performLeadFetch(reset: true)
        }
    }
    
    private func deduplicateLeads(_ leads: [Lead]) -> [Lead] {
        var seenIDs = Set<UUID>()
        var uniqueLeads: [Lead] = []
        
        for lead in leads {
            if let leadID = lead.id, !seenIDs.contains(leadID) {
                seenIDs.insert(leadID)
                uniqueLeads.append(lead)
            } else if lead.id == nil {
                // Assign a new ID to leads without one
                lead.id = UUID()
                uniqueLeads.append(lead)
            }
        }
        
        return uniqueLeads
    }
    
    private func loadMoreLeadsIfNeeded() {
        guard !isLoadingMore && hasMoreData else { return }
        
        Task {
            await performLeadFetch(reset: false)
        }
    }
    
    @MainActor
    private func refreshLeads() async {
        currentPage = 0
        hasMoreData = true
        await performLeadFetch(reset: true)
    }
    
    @MainActor
    private func performLeadFetch(reset: Bool) async {
        // Capture values on main actor
        let currentTab = selectedTab
        let currentFilter = searchFilterManager.currentFilter
        let currentSortPreference = preferences.leadSortPreference
        var pageToLoad = 0
        
        await MainActor.run {
            if reset {
                isLoadingMore = true
                paginatedLeads.removeAll()
                currentPage = 0
                pageToLoad = 0
            } else {
                isLoadingMore = true
                pageToLoad = currentPage
            }
        }
        
        // Build fetch request (main actor / main context fetch to avoid Sendable crossing)
        let fetchRequest: NSFetchRequest<Lead> = Lead.fetchRequest()

        // Apply search filters from SearchFilterManager
        let filterManager = SearchFilterManager()
        filterManager.currentFilter = currentFilter
        filterManager.applyFilter(to: fetchRequest)

        // Add tab status filter (combine with existing filter)
        var predicates: [NSPredicate] = []
        if let existingPredicate = fetchRequest.predicate {
            predicates.append(existingPredicate)
        }
        let statusStrings = currentTab.leadStatuses.map { $0.rawValue }
        predicates.append(NSPredicate(format: "status IN %@", statusStrings))
        fetchRequest.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)

        // Sort descriptors
        switch currentSortPreference {
        case "name":
            fetchRequest.sortDescriptors = [NSSortDescriptor(keyPath: \Lead.name, ascending: true)]
        case "status":
            fetchRequest.sortDescriptors = [
                NSSortDescriptor(keyPath: \Lead.status, ascending: true),
                NSSortDescriptor(keyPath: \Lead.updatedDate, ascending: false)
            ]
        default:
            fetchRequest.sortDescriptors = [NSSortDescriptor(keyPath: \Lead.updatedDate, ascending: false)]
        }

        fetchRequest.fetchLimit = self.pageSize
        fetchRequest.fetchOffset = pageToLoad * self.pageSize

        do {
            let fetchedLeads = try viewContext.fetch(fetchRequest)
            let hasMore = fetchedLeads.count == self.pageSize

            if reset {
                paginatedLeads = deduplicateLeads(fetchedLeads)
            } else {
                paginatedLeads = deduplicateLeads(paginatedLeads + fetchedLeads)
            }
            hasMoreData = hasMore
            isLoadingMore = false
            if !reset { currentPage += 1 }
            print("📊 Fetched \(fetchedLeads.count) leads for page \(pageToLoad)")
        } catch {
            print("❌ Failed to fetch leads: \(error)")
            hasMoreData = false
            isLoadingMore = false
        }
    }

    private func fetchLead(by id: UUID) -> Lead? {
        let request: NSFetchRequest<Lead> = Lead.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        return (try? viewContext.fetch(request))?.first
    }

    private func deleteLeads(offsets: IndexSet) {
        let allLeads = offsets.map { paginatedLeads[$0] }
        
        // Filter out any leads with nil IDs to prevent corruption
        let leadsToDelete = allLeads.filter { lead in
            if lead.id == nil {
                print("⚠️ Found lead with nil ID during individual delete, skipping: \(lead.displayName)")
                return false
            }
            return true
        }
        
        // Capture lead IDs for Firebase deletion (before Core Data deletion)
        let leadsForFirebaseDelete = leadsToDelete.compactMap { lead -> String? in
            return lead.id?.uuidString
        }
        
        withAnimation {
            // Cancel notifications for leads being deleted
            for lead in leadsToDelete {
                cancelNotification(for: lead)
            }
            
            // STEP 1: Delete from Core Data immediately (removes from UI)
            for lead in leadsToDelete {
                viewContext.delete(lead)
            }
            
            do {
                try viewContext.save()
                print("✅ Individual lead deletion completed: \(leadsToDelete.count) leads")
                
                // Refresh leads after deletion
                Task {
                    await refreshLeads()
                }
            } catch {
                let nsError = error as NSError
                fatalError("Unresolved error \(nsError), \(nsError.userInfo)")
            }
        }
        
        // STEP 2: Delete from Firebase asynchronously (prevent re-sync)
        if FirebaseService.shared.isAuthenticated && !leadsForFirebaseDelete.isEmpty {
            Task {
                for leadId in leadsForFirebaseDelete {
                    do {
                        try await UserDataSyncManager.shared.deleteLeadFromFirebase(leadId: leadId)
                        print("✅ Lead \(leadId) deleted from Firebase")
                    } catch {
                        print("❌ Failed to delete lead \(leadId) from Firebase: \(error)")
                    }
                }
                
                // Individual sync removed - deletions will sync manually, hourly, or before sign-out
                print("🗑️ Lead deleted locally - will sync on next manual/hourly/sign-out sync")
            }
        }
    }

    private func quickSetFollowUp(for lead: Lead) {
        let defaultDate = AppPreferences.shared.defaultFollowUpDate()
        lead.followUpDate = defaultDate
        lead.updatedDate = Date()
        do {
            try viewContext.save()
            NotificationService.shared.scheduleFollowUpNotification(for: lead)
        } catch {
            print("Failed to set follow-up: \(error)")
        }
    }

    private func cancelNotification(for lead: Lead) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [lead.id!.uuidString])
    }
    
    private func leadAccessibilityValue(for lead: Lead) -> String {
        var components: [String] = []
        
        // Add status
        components.append("Status: \(lead.leadStatus.displayName)")
        
        // Add address if available
        if let address = lead.address, !address.isEmpty {
            components.append("Address: \(address)")
        }
        
        // Add follow-up date if available
        if let followUpDate = lead.followUpDate {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            components.append("Follow-up: \(formatter.string(from: followUpDate))")
        }
        
        // Add phone if available
        if let phone = lead.phone, !phone.isEmpty {
            components.append("Phone: \(phone)")
        }
        
        return components.joined(separator: ", ")
    }
}

struct SearchBar: View {
    @Binding var text: String
    @FocusState private var isSearchFocused: Bool
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
                .font(.system(size: 16, weight: .medium))
            
            TextField("Search leads...", text: $text)
                .focused($isSearchFocused)
                .font(.system(size: 16, weight: .regular, design: .rounded))
                .textFieldStyle(PlainTextFieldStyle())
                .accessibilityLabel("Search leads")
                .accessibilityHint("Enter text to search leads by name, address, phone, or email")
                .accessibilityValue(text.isEmpty ? "Empty" : text)
            
            if !text.isEmpty {
                Button(action: {
                    text = ""
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                        .font(.system(size: 16, weight: .medium))
                }
                .buttonStyle(PlainButtonStyle())
                .accessibilityLabel("Clear search")
                .accessibilityHint("Clear the search text")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(UIColor.tertiarySystemBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(isSearchFocused ? Color.blue : Color.clear, lineWidth: 2)
                )
        )
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .animation(.easeInOut(duration: 0.2), value: isSearchFocused)
    }
}

struct FilterBar: View {
    @Binding var sortBy: LeadsListView.SortOption
    @Binding var sortAscending: Bool
    @Binding var showingFilters: Bool
    
    var body: some View {
        if showingFilters {
            VStack(spacing: 8) {
                HStack {
                    Text("Sort by:")
                        .font(.caption)
                        .foregroundColor(Color.themeTextSecondary)
                    
                    Picker("Sort by", selection: $sortBy) {
                        ForEach(LeadsListView.SortOption.allCases, id: \.self) { option in
                            Text(option.rawValue).tag(option)
                        }
                    }
                    .pickerStyle(MenuPickerStyle())
                    
                    Spacer()
                    
                    Button(action: {
                        sortAscending.toggle()
                    }) {
                        Image(systemName: sortAscending ? "arrow.up" : "arrow.down")
                            .foregroundColor(.blue)
                    }
                }
                
                Divider()
            }
            .padding(.horizontal)
            .padding(.bottom, 8)
            .background(Color(UIColor.tertiarySystemBackground))
        }
    }
}

struct LeadRowView: View {
    @ObservedObject var lead: Lead
    let onTap: (() -> Void)?
    let onDelete: (() -> Void)?
    let onCall: (() -> Void)?
    let onMessage: (() -> Void)?
    let onFollowUp: (() -> Void)?
    
    init(lead: Lead, onTap: (() -> Void)? = nil, onDelete: (() -> Void)? = nil, onCall: (() -> Void)? = nil, onMessage: (() -> Void)? = nil, onFollowUp: (() -> Void)? = nil) {
        self.lead = lead
        self.onTap = onTap
        self.onDelete = onDelete
        self.onCall = onCall
        self.onMessage = onMessage
        self.onFollowUp = onFollowUp
    }
    
    var body: some View {
        HStack(spacing: 16) {
            // Lead initial circle
            Circle()
                .fill(leadInitialColor)
                .frame(width: 48, height: 48)
                .overlay(
                    Text(leadInitial)
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                        .foregroundColor(.white)
                )
                .accessibilityHidden(true) // Hide decorative element
            
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(lead.displayName)
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
                        .foregroundColor(.primary)
                        .accessibilityAddTraits(.isHeader)
                    
                    Spacer()
                    
                    if let followUpDate = lead.followUpDate {
                        HStack(spacing: 4) {
                            Image(systemName: "calendar.badge.clock")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.orange)
                                .accessibilityHidden(true) // Hide decorative element
                            Text(followUpDate, format: .dateTime.day().month())
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                                .foregroundColor(.orange)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(Color.orange.opacity(0.15))
                        )
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("Follow-up scheduled")
                        .accessibilityValue(DateFormatter.localizedString(from: followUpDate, dateStyle: .medium, timeStyle: .short))
                    }
                }
                
                if let address = lead.address, !address.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "location.fill")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.secondary)
                            .accessibilityHidden(true) // Hide decorative element
                        Text(address)
                            .font(.system(size: 14, weight: .regular, design: .rounded))
                            .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Address")
                    .accessibilityValue(address)
                }
                
                HStack {
                    ModernStatusBadge(status: lead.leadStatus)
                    Spacer()
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(
                    LinearGradient(
                        gradient: Gradient(colors: [
                            Color(UIColor.tertiarySystemBackground),
                            Color(UIColor.tertiarySystemBackground).opacity(0.8)
                        ]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color(UIColor.separator).opacity(0.3), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.08), radius: 4, x: 0, y: 2)
        )
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            onTap?()
        }
        .contextMenu {
            Button {
                onTap?()
            } label: {
                Label("View Details", systemImage: "eye")
            }
            
            Divider()
            
            Button(role: .destructive) {
                onDelete?()
            } label: {
                Label("Delete Lead", systemImage: "trash")
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if onFollowUp != nil {
                Button {
                    onFollowUp?()
                } label: {
                    Label("Follow-up", systemImage: "calendar.badge.plus")
                }
                .tint(.orange)
            }
            if onMessage != nil {
                Button {
                    onMessage?()
                } label: {
                    Label("Message", systemImage: "message")
                }
                .tint(.blue)
            }
            if onCall != nil {
                Button {
                    onCall?()
                } label: {
                    Label("Call", systemImage: "phone")
                }
                .tint(.green)
            }
        }
        .accessibilityElement(children: .combine)
    }
    
    private var leadInitial: String {
        String(lead.displayName.prefix(1)).uppercased()
    }
    
    private var leadInitialColor: Color {
        let colors: [Color] = [.blue, .green, .orange, .purple, .pink, .red, .indigo, .teal]
        let hash = lead.displayName.hash
        return colors[abs(hash) % colors.count]
    }
}

struct ModernStatusBadge: View {
    let status: Lead.Status
    
    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
                .accessibilityHidden(true) // Hide decorative element
            
            Text(status.displayName)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                .foregroundColor(statusColor)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(statusColor.opacity(0.15))
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Status")
        .accessibilityValue(status.displayName)
    }
    
    private var statusColor: Color {
        switch status {
        case .notContacted:
            return .gray
        case .interested:
            return .green
        case .notInterested:
            return .red
        case .notHome:
            return .orange
        case .converted:
            return .blue
        }
    }
}

#Preview {
    LeadsListView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}
