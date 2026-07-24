import SwiftUI
import CoreData
import CoreLocation

private struct PendingLeadDeletion: Identifiable {
    let lead: Lead
    let name: String

    var id: NSManagedObjectID { lead.objectID }
}

private enum LeadSourceScope: String, CaseIterable {
    case personal = "Personal"
    case team = "Team"
}

struct LeadsListView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.managedObjectContext) private var viewContext
    @ObservedObject private var preferences = AppPreferences.shared
    @ObservedObject private var router = AppRouter.shared
    @ObservedObject private var userAccountManager = FirebaseUserAccountManager.shared
    @ObservedObject private var teamService = TeamFirebaseService.shared
    @ObservedObject private var locationManager = LocationManager.shared
    @StateObject private var searchFilterManager = SearchFilterManager()
    @State private var selectedTab: LeadTab = .active
    @State private var showingFilters = false
    @State private var sortBy: SortOption
    @State private var sortAscending: Bool
    @State private var currentPage = 0
    @State private var isLoadingMore = false
    @State private var hasMoreData = true
    @State private var selectedLead: Lead?
    @State private var selectedTeamLead: TeamLead?
    @State private var messageLead: Lead?
    @State private var leadOpenErrorMessage: String?
    @State private var teamFieldMapSummary: TeamWorkspaceSurfaceSummary?
    @State private var selectedTeamRepUserId: String?
    @State private var showingAddLead = false
    @State private var leadPendingDeletionConfirmation: Lead?
    @State private var showingLeadDeletionConfirmation = false
    @State private var pendingLeadDeletion: PendingLeadDeletion?
    @State private var pendingLeadDeletionTask: Task<Void, Never>?
    @State private var selectedSource: LeadSourceScope = .personal
    @ObservedObject private var paywallManager = PaywallManager.shared
    
    private let pageSize = 50
    
    enum LeadTab: String, CaseIterable {
        case all = "All"
        case active = "Active"
        case inactive = "Inactive"
        
        var leadStatuses: [Lead.Status] {
            switch self {
            case .all:
                return Lead.Status.allCases
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

        var compactTitle: String {
            switch self {
            case .name: return "Name"
            case .dateCreated: return "Created"
            case .dateUpdated: return "Updated"
            case .status: return "Status"
            }
        }

        var preferenceKey: String {
            switch self {
            case .name: return "name"
            case .dateCreated: return "created"
            case .dateUpdated: return "date"
            case .status: return "status"
            }
        }

        var legacyDefaultAscending: Bool {
            switch self {
            case .name, .status: return true
            case .dateCreated, .dateUpdated: return false
            }
        }

        init(preferenceKey: String) {
            switch preferenceKey {
            case "name": self = .name
            case "created": self = .dateCreated
            case "status": self = .status
            default: self = .dateUpdated
            }
        }
    }
    
    @State private var paginatedLeads: [Lead] = []

    init() {
        let initialSort = SortOption(preferenceKey: AppPreferences.shared.leadSortPreference)
        _sortBy = State(initialValue: initialSort)
        _sortAscending = State(
            initialValue: UserDefaults.standard.object(forKey: "leadSortAscending") as? Bool
                ?? initialSort.legacyDefaultAscending
        )
    }

    private var isRunningUITests: Bool {
        ProcessInfo.processInfo.arguments.contains("-skipOnboardingForUITests")
    }

    private var shouldLoadTeamWorkspace: Bool {
        !isRunningUITests || FirebaseEmulatorConfiguration.isEnabled
    }

    private var teamSurfaceSummary: TeamWorkspaceSurfaceSummary? {
        TeamWorkspaceSurfaceSummary.make(
            team: teamService.activeTeam,
            currentMember: teamService.currentMember,
            members: teamService.teamMembers,
            leads: teamService.teamLeads,
            bookings: teamService.teamBookings,
            dutySessions: teamService.dutySessions,
            dutyLocationPoints: teamService.dutyLocationPoints,
            ownerNotifications: teamService.ownerNotifications
        )
    }

    private var roleContext: TeamRoleContext {
        TeamRoleContext(summary: teamSurfaceSummary)
    }
    
    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                let screenBackground = Color.obsidianBackground(for: colorScheme)

                VStack(spacing: 0) {
                    Rectangle()
                        .fill(screenBackground)
                        .frame(height: ObsidianLayout.safeAreaTop(geometry))
                    ObsidianHeaderView(
                        roleContext.leadScreenTitle,
                        titleAccessibilityIdentifier: "leadsScreen"
                    ) {
                        if roleContext != .technician {
                            ObsidianCompactIconButton(
                                icon: "plus",
                                accessibilityLabel: "Add lead",
                                accessibilityIdentifier: "leadsAddButton",
                                size: 44
                            ) {
                                locationManager.requestImmediateLocation()
                                showingAddLead = true
                            }
                        }
                    }
                    searchAndFiltersSection
                    leadsContentSection
                }
                .ignoresSafeArea(.all, edges: .top)
            }
            .navigationBarHidden(true)
            .background(Color.obsidianBackground(for: colorScheme))
            .sheet(item: $selectedLead) { lead in
                LeadDetailView(lead: lead)
            }
            .sheet(item: $selectedTeamLead) { lead in
                TeamLeadDetailSheet(initialLead: lead)
            }
            .sheet(item: $messageLead) { lead in
                MessageSelectionView(lead: lead)
            }
            .sheet(isPresented: $showingAddLead) {
                AddLeadView(
                    coordinate: locationManager.location?.coordinate ?? locationManager.region.center
                )
            }
            .sheet(isPresented: $showingFilters) {
                LeadFilterSheet(
                    selectedScope: $selectedTab,
                    searchFilterManager: searchFilterManager
                )
            }
            .sheet(item: $teamFieldMapSummary) { summary in
                TeamFieldMapSheet(
                    summary: summary,
                    selectedRepUserId: $selectedTeamRepUserId
                )
            }
            .task {
                loadInitialLeads()
                await loadTeamWorkspaceIfNeeded()
            }
            .onChange(of: selectedTab) {
                resetAndLoadLeads()
            }
            .onChange(of: sortBy) {
                preferences.leadSortPreference = sortBy.preferenceKey
                resetAndLoadLeads()
            }
            .onChange(of: sortAscending) {
                UserDefaults.standard.set(sortAscending, forKey: "leadSortAscending")
                resetAndLoadLeads()
            }
            .onChange(of: searchFilterManager.currentFilter) {
                if !searchFilterManager.currentFilter.selectedStatuses.isEmpty,
                   selectedTab != .all {
                    selectedTab = .all
                } else {
                    resetAndLoadLeads()
                }
            }
            .onChange(of: router.targetLeadID) { _, newValue in
                guard let id = newValue else { return }
                if let lead = openLeadTarget(id) {
                    selectedLead = lead
                }
                router.targetLeadID = nil
            }
            .onChange(of: router.openMessageForLeadID) { _, newValue in
                guard let id = newValue else { return }
                if let lead = openLeadTarget(id) {
                    messageLead = lead
                }
                router.openMessageForLeadID = nil
            }
            .onChange(of: roleContext) { _, newRole in
                if newRole == .technician || newRole == .salesRep {
                    selectedSource = .team
                } else if teamSurfaceSummary == nil {
                    selectedSource = .personal
                }
            }
            .alert(
                "Delete Lead?",
                isPresented: $showingLeadDeletionConfirmation,
                presenting: leadPendingDeletionConfirmation
            ) { lead in
                Button("Delete", role: .destructive) {
                    beginPendingLeadDeletion(lead)
                }
                Button("Cancel", role: .cancel) {}
            } message: { lead in
                Text("Remove \(lead.displayName)? You can undo this for a few seconds.")
            }
            .safeAreaInset(edge: .bottom) {
                if let pendingLeadDeletion {
                    ObsidianUndoBanner(message: "\(pendingLeadDeletion.name) removed") {
                        undoPendingLeadDeletion()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                }
            }
            .onDisappear {
                commitPendingLeadDeletion()
            }
        }
    }
    
    // MARK: - Extracted View Components

    private var searchAndFiltersSection: some View {
        VStack(spacing: 4) {
            SearchBar(text: $searchFilterManager.currentFilter.text)
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Search leads")

            if teamSurfaceSummary != nil && roleContext != .technician {
                leadSourceControl
            }

            if selectedSource == .personal {
                HStack(spacing: 10) {
                Button {
                    showingFilters = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "line.3.horizontal.decrease")
                        Text(filterControlTitle)
                            .lineLimit(1)

                        if activeFilterCount > 0 {
                            Text("\(activeFilterCount)")
                                .font(.nano)
                                .foregroundColor(.white)
                                .frame(minWidth: 22, minHeight: 22)
                                .background(Color.electricViolet)
                                .clipShape(Circle())
                        }
                    }
                    .font(.obsidianFootnote)
                    .foregroundColor(Color.textPrimary)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(Color.obsidianSurface)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.obsidianBorder.opacity(0.6), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("leadsFilterButton")
                .accessibilityLabel("Filter leads")
                .accessibilityValue("\(selectedTab.rawValue) scope, \(activeFilterCount) active filters")

                Menu {
                    Section("Sort by") {
                        ForEach(SortOption.allCases, id: \.self) { option in
                            Button {
                                sortBy = option
                            } label: {
                                Label(option.rawValue, systemImage: sortBy == option ? "checkmark" : "")
                            }
                        }
                    }

                    Section("Direction") {
                        Button {
                            sortAscending = true
                        } label: {
                            Label("Ascending", systemImage: sortAscending ? "checkmark" : "arrow.up")
                        }
                        Button {
                            sortAscending = false
                        } label: {
                            Label("Descending", systemImage: !sortAscending ? "checkmark" : "arrow.down")
                        }
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: sortAscending ? "arrow.up" : "arrow.down")
                        Text(sortBy.compactTitle)
                            .lineLimit(1)
                    }
                    .font(.obsidianFootnote)
                    .foregroundColor(Color.textPrimary)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(Color.obsidianSurface)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.obsidianBorder.opacity(0.6), lineWidth: 1)
                    )
                }
                .accessibilityIdentifier("leadsSortButton")
                .accessibilityLabel("Sort leads")
                .accessibilityValue("\(sortBy.rawValue), \(sortAscending ? "ascending" : "descending")")
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            } else {
                Text("Search and filter the assigned Team leads shown below.")
                    .font(.micro)
                    .foregroundColor(Color.textMuted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
            }
        }
    }

    private var leadSourceControl: some View {
        HStack(spacing: 4) {
            ForEach(LeadSourceScope.allCases, id: \.self) { source in
                let isSelected = selectedSource == source
                Button {
                    selectedSource = source
                } label: {
                    Text(source.rawValue)
                        .font(.obsidianFootnote)
                        .foregroundColor(isSelected ? .white : Color.textSecondary)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(
                            RoundedRectangle(cornerRadius: 13, style: .continuous)
                                .fill(isSelected ? Color.electricViolet : Color.clear)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("leadSource_\(source.rawValue.lowercased())")
                .accessibilityAddTraits(isSelected ? [.isSelected] : [])
            }
        }
        .padding(4)
        .background(Color.obsidianSurface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.obsidianBorder.opacity(0.45), lineWidth: 0.5)
        )
        .padding(.horizontal, 16)
        .padding(.bottom, 4)
    }

    private var activeFilterCount: Int {
        var count = searchFilterManager.currentFilter.selectedStatuses.count
        if searchFilterManager.currentFilter.hasFollowUp != nil { count += 1 }
        if searchFilterManager.currentFilter.dateRange != nil { count += 1 }
        return count
    }

    private var filterControlTitle: String {
        selectedTab == .all ? "Filters" : selectedTab.rawValue
    }
    
    private var leadsContentSection: some View {
        VStack(spacing: 0) {
            if let leadOpenErrorMessage {
                ObsidianStatusBanner(
                    icon: "exclamationmark.triangle.fill",
                    title: "Lead could not open",
                    message: leadOpenErrorMessage,
                    tint: Color.statusNotHome
                )
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 4)
            }

            Group {
                if selectedSource == .personal && paginatedLeads.isEmpty && !isLoadingMore {
                    emptyStateView
                } else if selectedSource == .team && teamSurfaceSummary == nil {
                    emptyStateView
                } else {
                    leadsScrollView
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Leads list")
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 24) {
            Spacer()

            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.electricViolet.opacity(0.12))
                .frame(width: 88, height: 88)
                .overlay(
                    Image(systemName: selectedTab == .inactive ? "tray" : "person.2")
                        .font(.displayLarge)
                        .foregroundColor(Color.electricViolet)
                )

            VStack(spacing: 10) {
                Text(emptyStateTitle)
                    .font(.obsidianHeadline)
                    .foregroundColor(Color.textPrimary)

                Text(emptyStateMessage)
                    .font(.obsidianBody)
                    .foregroundColor(Color.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }

            if selectedTab != .inactive {
                Button {
                    AppRouter.shared.selectedTab = MainAppTab.map.rawValue
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "map.fill")
                        Text("Open Map")
                    }
                }
                .buttonStyle(ObsidianPrimaryButtonStyle())
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("No leads found")
    }

    private var emptyStateTitle: String {
        switch selectedTab {
        case .all: return "No Leads Found"
        case .active: return "No Leads Yet"
        case .inactive: return "No Inactive Leads"
        }
    }

    private var emptyStateMessage: String {
        switch selectedTab {
        case .all:
            return activeFilterCount > 0 || !searchFilterManager.currentFilter.text.isEmpty
                ? "No leads match the current search and filters."
                : activeEmptyMessage
        case .active:
            return activeEmptyMessage
        case .inactive:
            return "Leads marked as Not Home or Not Interested will appear here."
        }
    }

    private var activeEmptyMessage: String {
        switch roleContext {
        case .technician:
            return "Assigned service jobs appear in the Jobs tab. Lead work stays out of the way."
        case .salesRep:
            return "Assigned leads and leads you create will appear here."
        default:
            return "Add leads from the Map tab to start building your pipeline."
        }
    }
    
    private var leadsScrollView: some View {
        List {
            if selectedSource == .team, let summary = teamSurfaceSummary {
                TeamWorkInlineSection(
                    summary: summary,
                    content: .leads,
                    searchText: searchFilterManager.currentFilter.text,
                    selectedRepUserId: $selectedTeamRepUserId,
                    onOpenMap: { teamFieldMapSummary = teamSurfaceSummary },
                    onSelectLead: { selectedTeamLead = $0 }
                )
                .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 8, trailing: 16))
                .listRowBackground(Color.obsidianBackground(for: colorScheme))
                .listRowSeparator(.hidden)
            }

            if selectedSource == .personal && roleContext != .technician {
                ForEach(paginatedLeads, id: \.id) { lead in
                    LeadRowView(
                        lead: lead,
                        onTap: { selectedLead = lead },
                        onDelete: {
                            guard paywallManager.gateAction() else { return }
                            requestLeadDeletion(lead)
                        },
                        onCall: {
                            guard paywallManager.gateAction() else { return }
                            if let phone = lead.phone, !phone.isEmpty {
                                Utilities.makePhoneCall(to: phone)
                            }
                        },
                        onMessage: {
                            guard paywallManager.gateAction() else { return }
                            messageLead = lead
                        },
                        onFollowUp: {
                            guard paywallManager.gateAction() else { return }
                            quickSetFollowUp(for: lead)
                        }
                    )
                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                    .listRowBackground(Color.obsidianBackground(for: colorScheme))
                    .listRowSeparator(.hidden)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Lead: \(lead.displayName)")
                    .accessibilityHint("Double tap to view lead details. Swipe or use the context menu for actions.")
                    .accessibilityValue(leadAccessibilityValue(for: lead))
                    .accessibilityIdentifier("personalLeadRow")
                    .onAppear {
                        if lead == paginatedLeads.last {
                            loadMoreLeadsIfNeeded()
                        }
                    }
                }
            }

            if selectedSource == .personal,
               paginatedLeads.isEmpty,
               !isLoadingMore,
               teamSurfaceSummary != nil {
                Text("No personal leads match this filter.")
                    .font(.obsidianFootnote)
                    .foregroundColor(Color.textMuted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .listRowBackground(Color.obsidianBackground(for: colorScheme))
                    .listRowSeparator(.hidden)
            }

            // Loading indicator at bottom
            if selectedSource == .personal && isLoadingMore && hasMoreData {
                HStack {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Loading more leads...")
                        .font(.obsidianCaption)
                        .foregroundColor(Color.textSecondary)
                }
                .padding()
                .listRowBackground(Color.obsidianBackground(for: colorScheme))
                .accessibilityLabel("Loading more leads")
            }
        }
        .listStyle(.plain)
        .listRowSeparator(.hidden)
        .scrollContentBackground(.hidden)
        .background(Color.obsidianBackground(for: colorScheme))
        .refreshable {
            resetAndLoadLeads()
            UserDataSyncManager.shared.syncWithServer()
            await loadTeamWorkspaceIfNeeded()
        }
    }

    // MARK: - Helper Functions
    private func loadTeamWorkspaceIfNeeded() async {
        guard shouldLoadTeamWorkspace else { return }
        await teamService.loadCurrentTeam(
            displayName: userAccountManager.currentUserDisplayName,
            email: userAccountManager.currentUserEmail
        )
    }
    
    private func requestLeadDeletion(_ lead: Lead) {
        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
        impactFeedback.impactOccurred()

        leadPendingDeletionConfirmation = lead
        showingLeadDeletionConfirmation = true
    }

    private func beginPendingLeadDeletion(_ lead: Lead) {
        commitPendingLeadDeletion()

        let pending = PendingLeadDeletion(lead: lead, name: lead.displayName)
        pendingLeadDeletion = pending
        withAnimation(.easeInOut(duration: 0.2)) {
            paginatedLeads.removeAll { $0.objectID == lead.objectID }
        }

        pendingLeadDeletionTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            guard !Task.isCancelled,
                  pendingLeadDeletion?.id == pending.id else { return }
            commitPendingLeadDeletion()
        }
    }

    private func undoPendingLeadDeletion() {
        pendingLeadDeletionTask?.cancel()
        pendingLeadDeletionTask = nil
        pendingLeadDeletion = nil
        resetAndLoadLeads()
    }

    private func commitPendingLeadDeletion() {
        pendingLeadDeletionTask?.cancel()
        pendingLeadDeletionTask = nil
        guard let pending = pendingLeadDeletion else { return }
        pendingLeadDeletion = nil
        deleteLead(pending.lead)
    }
    
    private func deleteLead(_ lead: Lead) {
        let leadUUID = lead.id
        let firebaseLeadId = lead.id?.uuidString

        withAnimation(.easeInOut(duration: 0.3)) {
            // Remove from paginated leads immediately for UI feedback
            paginatedLeads.removeAll { $0.id == lead.id }
        }

        cancelNotification(for: lead)

        // Delete from Core Data
        viewContext.delete(lead)
        
        do {
            try viewContext.save()
            if let leadUUID {
                UserDataSyncManager.markLeadDeletedLocally(leadUUID)
            }

            if let firebaseLeadId,
               UserDataSyncManager.shouldDeleteLeadFromCloud(
                provider: CloudSyncProvider.current,
                isAuthenticated: FirebaseService.shared.isAuthenticated
               ) {
                Task {
                    do {
                        try await UserDataSyncManager.shared.deleteLeadFromCloud(leadId: firebaseLeadId)
                    } catch {
                        print("❌ Failed to delete lead \(firebaseLeadId) from cloud: \(error)")
                        ErrorHandler.shared.handle(error, context: "Delete Lead From Cloud")
                    }
                }
            }
            
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
        let currentSort = sortBy
        let currentSortAscending = sortAscending
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
        let fetchRequest: NSFetchRequest<Lead> = Lead.fetchRequest(in: viewContext)

        // Apply search filters from SearchFilterManager
        let filterManager = SearchFilterManager()
        filterManager.currentFilter = currentFilter
        filterManager.applyFilter(to: fetchRequest)

        // Add tab status filter (combine with existing filter)
        var predicates: [NSPredicate] = []
        if let existingPredicate = fetchRequest.predicate {
            predicates.append(existingPredicate)
        }
        if currentTab != .all {
            let statusStrings = currentTab.leadStatuses.map { $0.rawValue }
            predicates.append(NSPredicate(format: "status IN %@", statusStrings))
        }
        fetchRequest.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)

        // Sort descriptors
        switch currentSort {
        case .name:
            fetchRequest.sortDescriptors = [
                NSSortDescriptor(keyPath: \Lead.name, ascending: currentSortAscending),
                NSSortDescriptor(keyPath: \Lead.updatedDate, ascending: false)
            ]
        case .dateCreated:
            fetchRequest.sortDescriptors = [NSSortDescriptor(keyPath: \Lead.createdDate, ascending: currentSortAscending)]
        case .dateUpdated:
            fetchRequest.sortDescriptors = [NSSortDescriptor(keyPath: \Lead.updatedDate, ascending: currentSortAscending)]
        case .status:
            fetchRequest.sortDescriptors = [
                NSSortDescriptor(keyPath: \Lead.status, ascending: currentSortAscending),
                NSSortDescriptor(keyPath: \Lead.updatedDate, ascending: false)
            ]
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
            currentPage = reset ? 1 : currentPage + 1
            print("📊 Fetched \(fetchedLeads.count) leads for page \(pageToLoad)")
        } catch {
            print("❌ Failed to fetch leads: \(error)")
            hasMoreData = false
            isLoadingMore = false
        }
    }

    private func openLeadTarget(_ id: UUID) -> Lead? {
        let request: NSFetchRequest<Lead> = Lead.fetchRequest(in: viewContext)
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1

        do {
            guard let lead = try viewContext.fetch(request).first else {
                leadOpenErrorMessage = "That lead is no longer available on this device."
                return nil
            }
            leadOpenErrorMessage = nil
            return lead
        } catch {
            leadOpenErrorMessage = "Lead data could not be read. Try refreshing the Leads tab."
            print("❌ Failed to open lead \(id): \(error)")
            return nil
        }
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
        
        // Capture lead IDs for cloud deletion before removing Core Data objects.
        let leadUUIDsForTombstone = leadsToDelete.compactMap { $0.id }
        let leadsForCloudDelete = leadsToDelete.compactMap { lead -> String? in
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
                for leadId in leadUUIDsForTombstone {
                    UserDataSyncManager.markLeadDeletedLocally(leadId)
                }
                print("✅ Individual lead deletion completed: \(leadsToDelete.count) leads")
                
                // Refresh leads after deletion
                Task {
                    await refreshLeads()
                }
            } catch {
                let nsError = error as NSError
                print("❌ Delete error: \(nsError), \(nsError.userInfo)")
                // Reset context to prevent corruption
                viewContext.rollback()
            }
        }
        
        // STEP 2: Delete from the selected cloud provider asynchronously (prevent re-sync)
        if UserDataSyncManager.shouldDeleteLeadFromCloud(
            provider: CloudSyncProvider.current,
            isAuthenticated: FirebaseService.shared.isAuthenticated
        ) && !leadsForCloudDelete.isEmpty {
            Task {
                for leadId in leadsForCloudDelete {
                    do {
                        try await UserDataSyncManager.shared.deleteLeadFromCloud(leadId: leadId)
                        print("✅ Lead \(leadId) deleted from cloud")
                    } catch {
                        print("❌ Failed to delete lead \(leadId) from cloud: \(error)")
                        ErrorHandler.shared.handle(error, context: "Delete Lead From Cloud")
                    }
                }
                
                // Individual sync removed - deletions will sync manually, hourly, or before sign-out
                print("🗑️ Lead deleted locally - will sync on next manual/hourly/sign-out sync")
            }
        }
    }

    private func quickSetFollowUp(for lead: Lead) {
        let defaultDate = AppPreferences.shared.defaultFollowUpDate()
        lead.setFollowUpDate(lead.leadStatus.resolvedFollowUpDate(defaultDate), autoSave: false)
        do {
            try viewContext.save()
            NotificationService.shared.scheduleFollowUpNotification(for: lead)
            NotificationService.shared.requestPermissionAfterSchedulingIfNeeded()
        } catch {
            print("Failed to set follow-up: \(error)")
        }
    }

    private func cancelNotification(for lead: Lead) {
        guard let leadId = lead.id else {
            print("❌ Cannot cancel notification: lead has no ID")
            return
        }
        NotificationService.shared.cancelFollowUpNotification(for: leadId)
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
                .foregroundColor(Color.electricViolet)
                .font(.obsidianCallout)

            TextField("Search leads...", text: $text)
                .focused($isSearchFocused)
                .font(.obsidianBody)
                .foregroundColor(Color.textPrimary)
                .textFieldStyle(PlainTextFieldStyle())
                .accessibilityLabel("Search leads")
                .accessibilityHint("Enter text to search leads by name, address, phone, or email")
                .accessibilityValue(text.isEmpty ? "Empty" : text)

            if !text.isEmpty {
                Button(action: {
                    text = ""
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(Color.textSecondary)
                        .font(.obsidianCallout)
                }
                .buttonStyle(PlainButtonStyle())
                .accessibilityLabel("Clear search")
                .accessibilityHint("Clear the search text")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.obsidianElevated)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(isSearchFocused ? Color.electricViolet : Color.obsidianBorder.opacity(0.5), lineWidth: 0.5)
        )
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .animation(.easeInOut(duration: 0.2), value: isSearchFocused)
    }
}

struct LeadFilterSheet: View {
    @Binding var selectedScope: LeadsListView.LeadTab
    @ObservedObject var searchFilterManager: SearchFilterManager
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let screenBackground = Color.obsidianBackground(for: colorScheme)

        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 16) {
                    ObsidianSectionCard(
                        title: "Lead Scope",
                        icon: "person.2.fill",
                        subtitle: "Choose the broad group before applying detailed filters."
                    ) {
                        HStack(spacing: 4) {
                            ForEach(LeadsListView.LeadTab.allCases, id: \.self) { scope in
                                scopeButton(scope)
                            }
                        }
                        .padding(4)
                        .background(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(Color.obsidianElevated)
                        )
                    }

                    ObsidianSectionCard(
                        title: "Quick Filters",
                        icon: "line.3.horizontal.decrease.circle.fill",
                        subtitle: "Status, follow-up timing, and reusable presets."
                    ) {
                        QuickFilterChipsView(searchFilterManager: searchFilterManager)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 18)
                .padding(.bottom, 28)
            }
            .background(screenBackground.ignoresSafeArea())
            .obsidianPushedNavigation(
                "Filter Leads",
                backButtonAccessibilityIdentifier: "leadsFilterBackButton",
                onBack: { dismiss() }
            )
            .safeAreaInset(edge: .bottom) {
                Button(action: { dismiss() }) {
                    Label("Done", systemImage: "checkmark.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(ObsidianPrimaryButtonStyle())
                .accessibilityIdentifier("leadsFilterDoneButton")
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(screenBackground.ignoresSafeArea(edges: .bottom))
            }
        }
        .obsidianModalBackground()
        .accessibilityIdentifier("leadsFilterSheet")
    }

    private func scopeButton(_ scope: LeadsListView.LeadTab) -> some View {
        let isSelected = selectedScope == scope

        return Button {
            selectedScope = scope
        } label: {
            Text(scope.rawValue)
                .font(.obsidianFootnote)
                .foregroundColor(isSelected ? .white : .textSecondary)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(isSelected ? Color.electricViolet : Color.clear)
                )
                .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("leadScope_\(scope.rawValue.lowercased())")
        .accessibilityLabel("\(scope.rawValue) leads")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

struct LeadRowView: View {
    @Environment(\.managedObjectContext) private var viewContext
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
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: lead.leadStatus.iconName)
                    .font(.obsidianCallout)
                    .foregroundColor(.white)
                    .frame(width: 46, height: 46)
                    .background(statusColor)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(lead.displayName)
                            .font(.themeTitle)
                            .dynamicTypeSize(...DynamicTypeSize.accessibility2)
                            .foregroundColor(Color.textPrimary)
                            .lineLimit(1)
                            .accessibilityAddTraits(.isHeader)

                        Spacer(minLength: 6)

                        if lead.price > 0 {
                            Text(lead.price, format: .currency(code: "CAD"))
                                .font(.micro)
                                .fontWeight(.semibold)
                                .foregroundColor(Color.statusConverted)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Capsule().fill(Color.statusConverted.opacity(0.12)))
                        }
                    }

                    Text((lead.address?.isEmpty == false ? lead.address : nil) ?? lead.leadStatus.displayName)
                        .font(.obsidianFootnote)
                        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                        .foregroundColor(Color.textSecondary)
                        .lineLimit(2)
                        .accessibilityLabel((lead.address?.isEmpty == false ? "Address: \(lead.address ?? "")" : nil) ?? "Status: \(lead.leadStatus.displayName)")
                }
            }

            HStack(spacing: 8) {
                ModernStatusBadge(status: lead.leadStatus)

                if let followUpDate = lead.followUpDate {
                    leadMetaChip(
                        icon: "calendar.badge.clock",
                        text: followUpDate.formatted(.dateTime.day().month()),
                        color: Color.statusNotHome
                    )
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Follow-up scheduled")
                    .accessibilityValue(DateFormatter.localizedString(from: followUpDate, dateStyle: .medium, timeStyle: .short))
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.micro)
                    .foregroundColor(Color.textMuted)
                    .accessibilityHidden(true)
            }
        }
        .padding(14)
        .background(Color.obsidianSurface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.obsidianBorder.opacity(0.55), lineWidth: 0.5)
        )
        .shadow(color: Color.black.opacity(0.22), radius: 8, x: 0, y: 3)
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
                .tint(Color.statusNotHome)
            }
            if onMessage != nil {
                Button {
                    onMessage?()
                } label: {
                    Label("Message", systemImage: "message")
                }
                .tint(Color.electricViolet)
            }
            if onCall != nil {
                Button {
                    onCall?()
                } label: {
                    Label("Call", systemImage: "phone")
                }
                .tint(Color.statusInterested)
            }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            Button {
                updateLeadStatus(.interested, context: viewContext)
            } label: {
                Label("Interested", systemImage: "star.fill")
            }
            .tint(.statusInterested)

            Button {
                updateLeadStatus(.converted, context: viewContext)
            } label: {
                Label("Sold", systemImage: "checkmark.circle.fill")
            }
            .tint(.statusConverted)

            Button {
                updateLeadStatus(.notInterested, context: viewContext)
            } label: {
                Label("No Interest", systemImage: "hand.raised.fill")
            }
            .tint(.statusNotInterested)
        }
        .accessibilityElement(children: .combine)
    }

    private func updateLeadStatus(_ status: Lead.Status, context: NSManagedObjectContext) {
        lead.applyLeadStatus(status, autoSave: false)

        do {
            try context.save()
            UserDataSyncManager.shared.syncWithServer()
        } catch {
            context.rollback()
            ErrorHandler.shared.handle(error, context: "Update Lead Status")
        }
    }
    
    private var leadInitial: String {
        String(lead.displayName.prefix(1)).uppercased()
    }

    private var statusColor: Color {
        switch lead.leadStatus {
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

    private func leadMetaChip(icon: String, text: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.micro)
            Text(text)
                .font(.micro)
                .fontWeight(.semibold)
        }
        .foregroundColor(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Capsule().fill(color.opacity(0.12)))
    }
    
}

struct ModernStatusBadge: View {
    let status: Lead.Status

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(statusColor)
                .frame(width: 6, height: 6)
                .accessibilityHidden(true)

            Text(status.displayName)
                .font(.micro)
                .textCase(.uppercase)
                .tracking(0.5)
                .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                .foregroundColor(statusColor)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill(statusColor.opacity(0.12))
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Status")
        .accessibilityValue(status.displayName)
    }
    
    private var statusColor: Color {
        switch status {
        case .notContacted:
            return Color.statusNotContacted
        case .interested:
            return Color.statusInterested
        case .notInterested:
            return Color.statusNotInterested
        case .notHome:
            return Color.statusNotHome
        case .converted:
            return Color.statusConverted
        }
    }
}

#Preview {
    LeadsListView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}
