import CoreData
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct AppleContactLeadImportView: View {
    private enum CandidateSource {
        case device
        case macPackage
    }

    private struct ImportOutcome {
        let created: Int
        let updated: Int
        let undoAvailable: Bool

        var message: String {
            let result: String
            if updated == 0 {
                result = "\(created) lead\(created == 1 ? "" : "s") added to Leads and Map."
            } else if created == 0 {
                result = "\(updated) existing lead\(updated == 1 ? "" : "s") updated with Mac contact details."
            } else {
                result = "\(created) added and \(updated) updated with Mac contact details."
            }
            return undoAvailable ? result + " Undo is available in Data & Sync." : result
        }
    }

    private enum ImportPhase: Equatable {
        case idle
        case scanning
        case geocoding(current: Int, total: Int)
        case ready
        case importing

        var isBusy: Bool {
            switch self {
            case .scanning, .geocoding, .importing: return true
            case .idle, .ready: return false
            }
        }
    }

    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.openURL) private var openURL
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Lead.createdDate, ascending: false)],
        animation: .default
    ) private var existingLeads: FetchedResults<Lead>

    @State private var phase: ImportPhase = .idle
    @State private var candidates: [AppleContactLeadCandidate] = []
    @State private var selectedCandidateIDs: Set<String> = []
    @State private var duplicateCandidateIDs: Set<String> = []
    @State private var updateCandidateIDs: Set<String> = []
    @State private var existingLeadIDByCandidateID: [String: UUID] = [:]
    @State private var hasLimitedAccess = false
    @State private var errorMessage: String?
    @State private var permissionNeedsSettings = false
    @State private var lastImportOutcome: ImportOutcome?
    @State private var showingMacPackagePicker = false
    @State private var candidateSource = CandidateSource.device

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                introductionSection

                if let errorMessage {
                    errorSection(message: errorMessage)
                }

                if hasLimitedAccess {
                    ObsidianStatusBanner(
                        icon: "person.crop.circle.badge.questionmark",
                        title: "Limited Contacts Access",
                        message: "Only contacts currently shared with D2D Advancer can be scanned.",
                        tint: Color.statusNotHome
                    )
                }

                if let lastImportOutcome {
                    ObsidianStatusBanner(
                        icon: "checkmark.circle.fill",
                        title: "Import Complete",
                        message: lastImportOutcome.message,
                        tint: Color.statusInterested
                    )
                }

                if phase != .idle {
                    scanSummarySection
                }

                if !candidates.isEmpty {
                    candidateSection
                } else if phase == .ready && errorMessage == nil {
                    ObsidianStatusBanner(
                        icon: "person.crop.circle.badge.xmark",
                        title: "No Matching Contacts",
                        message: noMatchesMessage,
                        tint: Color.textSecondary
                    )
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 18)
            .padding(.bottom, candidates.isEmpty ? 28 : 104)
        }
        .obsidianScreenBackground()
        .obsidianPushedNavigation(
            "Apple Contacts",
            titleAccessibilityIdentifier: "appleContactImportScreen",
            backButtonAccessibilityIdentifier: "appleContactImportBackButton"
        )
        .fileImporter(
            isPresented: $showingMacPackagePicker,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            handleMacPackageSelection(result)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !candidates.isEmpty {
                importActionBar
            }
        }
    }

    private var introductionSection: some View {
        LeadFormSectionCard(title: "Find Service Contacts", icon: "person.crop.circle.badge.plus") {
            Text("Scan this iPhone or import a Mac Contacts export, review the matches, then add only the leads you choose.")
                .font(.obsidianBody)
                .foregroundColor(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 9) {
                importFeatureRow(icon: "text.magnifyingglass", text: "Checks supported service phrases")
                importFeatureRow(icon: "map.fill", text: "Maps each postal address before import")
                importFeatureRow(icon: "arrow.triangle.2.circlepath", text: "Safely fills missing details on matching leads")
                importFeatureRow(icon: "note.text", text: "Mac exports preserve notes and recognized prices")
            }

            if phase == .idle || (phase == .ready && candidates.isEmpty) {
                VStack(spacing: 10) {
                    Button {
                        Task { await scanContacts() }
                    } label: {
                        Label("Scan This iPhone", systemImage: "iphone.gen3")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(ObsidianPrimaryButtonStyle())
                    .accessibilityIdentifier("scanAppleContactsButton")

                    Button {
                        showingMacPackagePicker = true
                    } label: {
                        Label("Import Mac Export", systemImage: "laptopcomputer.and.arrow.down")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(ObsidianSecondaryButtonStyle())
                    .accessibilityIdentifier("importMacContactsPackageButton")
                }
            }

            Text("Direct iPhone scans cannot read contact notes. Mac exports can include them. Nothing is imported until you confirm the selection.")
                .font(.obsidianFootnote)
                .foregroundColor(Color.textMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func importFeatureRow(icon: String, text: String) -> some View {
        Label {
            Text(text)
                .font(.obsidianFootnote)
                .foregroundColor(Color.textSecondary)
        } icon: {
            Image(systemName: icon)
                .foregroundColor(Color.electricViolet)
                .frame(width: 22)
        }
    }

    private func errorSection(message: String) -> some View {
        VStack(spacing: 10) {
            ObsidianStatusBanner(
                icon: "exclamationmark.triangle.fill",
                title: "Contacts Import Unavailable",
                message: message,
                tint: Color.statusNotInterested
            )

            if permissionNeedsSettings {
                Button {
                    guard let settingsURL = URL(string: UIApplication.openSettingsURLString) else { return }
                    openURL(settingsURL)
                } label: {
                    Label("Open Settings", systemImage: "gearshape.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(ObsidianSecondaryButtonStyle())
                .accessibilityIdentifier("openContactSettingsButton")
            }
        }
    }

    private var scanSummarySection: some View {
        LeadFormSectionCard(title: "Scan Summary", icon: phase.isBusy ? "arrow.triangle.2.circlepath" : "checklist") {
            if case .scanning = phase {
                progressRow(title: "Reading accessible contacts", detail: "Looking for service matches")
            } else if case .geocoding(let current, let total) = phase {
                progressRow(title: "Checking map locations", detail: "Address \(current) of \(total)")
            } else if case .importing = phase {
                progressRow(title: "Saving selected contacts", detail: "Adding and updating your personal workspace")
            }

            summaryRow(
                title: "Matches",
                value: candidates.count,
                tint: Color.electricViolet,
                accessibilityIdentifier: "appleContactSummaryMatchesValue"
            )
            summaryDivider
            summaryRow(
                title: "Ready",
                value: readyCandidates.count,
                tint: Color.statusInterested,
                accessibilityIdentifier: "appleContactSummaryReadyValue"
            )
            if candidateSource == .macPackage {
                summaryDivider
                summaryRow(
                    title: "Updates Available",
                    value: updateCandidateIDs.count,
                    tint: Color.statusInterested,
                    accessibilityIdentifier: "appleContactSummaryUpdateValue"
                )
            }
            summaryDivider
            summaryRow(
                title: "Already in Leads",
                value: duplicateCandidateIDs.count,
                tint: Color.statusNotHome,
                accessibilityIdentifier: "appleContactSummaryDuplicateValue"
            )
            summaryDivider
            summaryRow(
                title: "Needs a map location",
                value: unavailableCandidateCount,
                tint: Color.statusNotInterested,
                accessibilityIdentifier: "appleContactSummaryUnavailableValue"
            )
        }
    }

    private func progressRow(title: String, detail: String) -> some View {
        HStack(spacing: 12) {
            ProgressView()
                .tint(Color.electricViolet)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.obsidianCallout)
                    .foregroundColor(Color.textPrimary)
                Text(detail)
                    .font(.obsidianFootnote)
                    .foregroundColor(Color.textSecondary)
            }

            Spacer(minLength: 0)
        }
        .padding(.bottom, 2)
    }

    private func summaryRow(
        title: String,
        value: Int,
        tint: Color,
        accessibilityIdentifier: String
    ) -> some View {
        HStack {
            Text(title)
                .font(.obsidianCallout)
                .foregroundColor(Color.textSecondary)
            Spacer()
            Text("\(value)")
                .font(.obsidianHeadline)
                .foregroundColor(tint)
                .monospacedDigit()
                .accessibilityIdentifier(accessibilityIdentifier)
        }
    }

    private var summaryDivider: some View {
        Divider().overlay(Color.obsidianBorder.opacity(0.55))
    }

    private var candidateSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Matched Contacts")
                        .font(.obsidianTitle)
                        .foregroundColor(Color.textPrimary)
                    Text("Map-ready contacts and safe updates can be selected.")
                        .font(.obsidianFootnote)
                        .foregroundColor(Color.textSecondary)
                }

                Spacer()

                Button(selectedCandidateIDs.isEmpty ? "Select Available" : "Clear") {
                    if selectedCandidateIDs.isEmpty {
                        selectedCandidateIDs = Set(selectableCandidates.map(\.id))
                    } else {
                        selectedCandidateIDs.removeAll()
                    }
                }
                .font(.obsidianFootnote)
                .foregroundColor(Color.electricViolet)
                .disabled(selectableCandidates.isEmpty)
                .accessibilityIdentifier("toggleReadyAppleContactsButton")
            }

            ForEach(candidates) { candidate in
                candidateCard(candidate)
            }
        }
    }

    private func candidateCard(_ candidate: AppleContactLeadCandidate) -> some View {
        let selectable = (candidate.isReadyForImport || updateCandidateIDs.contains(candidate.id))
            && !duplicateCandidateIDs.contains(candidate.id)
            && !phase.isBusy
        let selected = selectedCandidateIDs.contains(candidate.id)
        let status = candidateStatus(candidate)

        return Button {
            guard selectable else { return }
            if selected {
                selectedCandidateIDs.remove(candidate.id)
            } else {
                selectedCandidateIDs.insert(candidate.id)
            }
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.obsidianAction)
                    .foregroundColor(selected ? Color.electricViolet : (selectable ? Color.textSecondary : Color.textMuted))
                    .frame(width: 28, height: 32)

                VStack(alignment: .leading, spacing: 7) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(candidate.displayName)
                            .font(.obsidianCallout)
                            .foregroundColor(Color.textPrimary)
                            .lineLimit(2)

                        Spacer(minLength: 0)

                        Text(candidate.service.title)
                            .font(.micro)
                            .foregroundColor(candidate.service.tintColor)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(candidate.service.tintColor.opacity(0.12))
                            .clipShape(Capsule())
                            .lineLimit(1)
                    }

                    if let address = candidate.address {
                        Label(address, systemImage: "mappin.and.ellipse")
                            .font(.obsidianFootnote)
                            .foregroundColor(Color.textSecondary)
                            .lineLimit(3)
                    }

                    let contactLine = [candidate.phone, candidate.email].compactMap { $0 }.joined(separator: " | ")
                    if !contactLine.isEmpty {
                        Text(contactLine)
                            .font(.micro)
                            .foregroundColor(Color.textMuted)
                            .lineLimit(2)
                    }

                    if let price = candidate.price {
                        Label(
                            price.formatted(
                                .currency(code: "CAD")
                                    .precision(.fractionLength(0...2))
                            ),
                            systemImage: "dollarsign.circle.fill"
                        )
                        .font(.obsidianFootnote)
                        .foregroundColor(Color.statusInterested)
                    }

                    if let notes = candidate.notes {
                        Text(notes)
                            .font(.obsidianFootnote)
                            .foregroundColor(Color.textSecondary)
                            .lineLimit(3)
                    }

                    Label(status.text, systemImage: status.icon)
                        .font(.obsidianFootnote)
                        .foregroundColor(status.tint)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.obsidianSurface)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(selected ? Color.electricViolet : Color.obsidianBorder.opacity(0.55), lineWidth: selected ? 1.5 : 0.5)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(!selectable)
        .accessibilityIdentifier("appleContactCandidate_\(candidate.id)")
    }

    private func candidateStatus(_ candidate: AppleContactLeadCandidate) -> (text: String, icon: String, tint: Color) {
        if updateCandidateIDs.contains(candidate.id) {
            return ("Update Details & Status", "arrow.triangle.2.circlepath", Color.statusInterested)
        }
        if duplicateCandidateIDs.contains(candidate.id) {
            return ("Already in Leads", "checkmark.circle", Color.statusNotHome)
        }
        guard candidate.address != nil else {
            return ("No postal address", "mappin.slash", Color.statusNotInterested)
        }
        if candidate.isReadyForImport {
            return ("Ready for Map", "map.fill", Color.statusInterested)
        }
        if candidate.didAttemptGeocoding {
            return ("Address not found", "location.slash.fill", Color.statusNotInterested)
        }
        return ("Checking address", "location.magnifyingglass", Color.textSecondary)
    }

    private var importActionBar: some View {
        ObsidianBottomActionBar(
            isPrimaryDisabled: selectedCandidateIDs.isEmpty || phase.isBusy,
            primaryAccessibilityIdentifier: "importSelectedAppleContactsButton",
            secondaryAccessibilityIdentifier: "rescanAppleContactsButton",
            primaryAction: { importSelectedContacts() },
            secondaryAction: {
                switch candidateSource {
                case .device:
                    Task { await scanContacts() }
                case .macPackage:
                    showingMacPackagePicker = true
                }
            },
            primaryLabel: {
                Label("Import \(selectedCandidateIDs.count)", systemImage: "square.and.arrow.down.fill")
            },
            secondaryLabel: {
                switch candidateSource {
                case .device:
                    Label("Rescan", systemImage: "arrow.clockwise")
                case .macPackage:
                    Label("Choose File", systemImage: "doc.badge.ellipsis")
                }
            }
        )
    }

    private var noMatchesMessage: String {
        switch candidateSource {
        case .device:
            return "No accessible contact contains Window Cleaning or Gutter Cleaning in its name, company, department, or job title."
        case .macPackage:
            return "No contact in this Mac export contains Window Cleaning or Gutter Cleaning in its contact fields or notes."
        }
    }

    private var readyCandidates: [AppleContactLeadCandidate] {
        candidates.filter {
            $0.isReadyForImport
                && !duplicateCandidateIDs.contains($0.id)
                && !updateCandidateIDs.contains($0.id)
        }
    }

    private var selectableCandidates: [AppleContactLeadCandidate] {
        candidates.filter {
            ($0.isReadyForImport || updateCandidateIDs.contains($0.id))
                && !duplicateCandidateIDs.contains($0.id)
        }
    }

    private var unavailableCandidateCount: Int {
        candidates.filter {
            !duplicateCandidateIDs.contains($0.id)
                && !updateCandidateIDs.contains($0.id)
                && !$0.isReadyForImport
        }.count
    }

    @MainActor
    private func scanContacts() async {
        resetScanState(source: .device)

        do {
            let result = try await AppleContactLeadImportService.shared.loadMatchingContacts()
            await prepareCandidates(result.candidates, hasLimitedAccess: result.hasLimitedAccess)
        } catch let importError as AppleContactLeadImportError {
            candidates = []
            hasLimitedAccess = false
            errorMessage = importError.localizedDescription
            permissionNeedsSettings = importError.needsSettings
            phase = .ready
        } catch {
            candidates = []
            hasLimitedAccess = false
            errorMessage = error.localizedDescription
            phase = .ready
        }
    }

    private func handleMacPackageSelection(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            Task { await loadMacPackage(from: url) }
        case .failure(let error):
            errorMessage = "The Mac Contacts file could not be selected: \(error.localizedDescription)"
            permissionNeedsSettings = false
            phase = .ready
        }
    }

    @MainActor
    private func loadMacPackage(from url: URL) async {
        resetScanState(source: .macPackage)

        do {
            let packageCandidates = try await Task.detached(priority: .userInitiated) {
                try MacContactLeadPackageService.loadCandidates(from: url)
            }.value
            await prepareCandidates(
                AppleContactLeadCandidateConsolidator.consolidatingDuplicates(packageCandidates),
                hasLimitedAccess: false
            )
        } catch {
            candidates = []
            hasLimitedAccess = false
            errorMessage = error.localizedDescription
            permissionNeedsSettings = false
            phase = .ready
        }
    }

    @MainActor
    private func resetScanState(source: CandidateSource) {
        candidateSource = source
        phase = .scanning
        errorMessage = nil
        permissionNeedsSettings = false
        lastImportOutcome = nil
        selectedCandidateIDs.removeAll()
        duplicateCandidateIDs.removeAll()
        updateCandidateIDs.removeAll()
        existingLeadIDByCandidateID.removeAll()
    }

    @MainActor
    private func prepareCandidates(
        _ loadedCandidates: [AppleContactLeadCandidate],
        hasLimitedAccess: Bool
    ) async {
        self.hasLimitedAccess = hasLimitedAccess
        candidates = loadedCandidates

        let leadByID = existingLeadsByID
        let matchIndex = AppleContactLeadExistingMatchIndex(existingLeads: existingLeadReferences)
        var duplicateIndex = AppleContactLeadDuplicateIndex(existingLeads: existingLeadSnapshots)
        var duplicates: Set<String> = []
        var updates: Set<String> = []
        var matchedLeadIDs: [String: UUID] = [:]

        for candidate in candidates {
            if let leadID = matchIndex.matchingLeadID(for: candidate),
               let existingLead = leadByID[leadID] {
                matchedLeadIDs[candidate.id] = leadID
                if candidateSource == .macPackage,
                   AppleContactLeadImportService.canUpdateLead(existingLead, from: candidate)
                    || AppleContactLeadImportService.needsGeocodingForUpdate(
                        existingLead,
                        from: candidate
                    ) {
                    updates.insert(candidate.id)
                } else {
                    duplicates.insert(candidate.id)
                }
            } else if !duplicateIndex.registerIfUnique(candidate) {
                duplicates.insert(candidate.id)
            }
        }

        duplicateCandidateIDs = duplicates
        updateCandidateIDs = updates
        existingLeadIDByCandidateID = matchedLeadIDs

        let indicesToGeocode = candidates.indices.filter { index in
            let candidate = candidates[index]
            guard candidate.address != nil,
                  !duplicateCandidateIDs.contains(candidate.id) else {
                return false
            }
            guard updateCandidateIDs.contains(candidate.id) else { return true }
            guard let leadID = matchedLeadIDs[candidate.id],
                  let existingLead = leadByID[leadID] else {
                return false
            }
            return AppleContactLeadImportService.needsGeocodingForUpdate(
                existingLead,
                from: candidate
            )
        }

        for (offset, index) in indicesToGeocode.enumerated() {
            phase = .geocoding(current: offset + 1, total: indicesToGeocode.count)
            candidates[index].didAttemptGeocoding = true
            if let address = candidates[index].address {
                candidates[index].coordinate = await AppleContactAddressGeocoder.shared.coordinate(for: address)
            }
        }

        for candidate in candidates where updateCandidateIDs.contains(candidate.id) {
            guard let leadID = matchedLeadIDs[candidate.id],
                  let existingLead = leadByID[leadID],
                  AppleContactLeadImportService.canUpdateLead(existingLead, from: candidate) else {
                updateCandidateIDs.remove(candidate.id)
                duplicateCandidateIDs.insert(candidate.id)
                continue
            }
        }

        selectedCandidateIDs = Set(selectableCandidates.map(\.id))
        phase = .ready
    }

    @MainActor
    private func importSelectedContacts() {
        guard PaywallManager.shared.gateAction() else { return }

        var currentDuplicateIndex = AppleContactLeadDuplicateIndex(existingLeads: existingLeadSnapshots)
        var selectedNewCandidates: [AppleContactLeadCandidate] = []
        var newlyDuplicateIDs: Set<String> = []

        for candidate in candidates where
            selectedCandidateIDs.contains(candidate.id) &&
            candidate.isReadyForImport &&
            !updateCandidateIDs.contains(candidate.id) &&
            !duplicateCandidateIDs.contains(candidate.id) {
            if currentDuplicateIndex.registerIfUnique(candidate) {
                selectedNewCandidates.append(candidate)
            } else {
                newlyDuplicateIDs.insert(candidate.id)
            }
        }

        duplicateCandidateIDs.formUnion(newlyDuplicateIDs)
        selectedCandidateIDs.subtract(newlyDuplicateIDs)
        let selectedUpdateCandidates = candidates.filter {
            selectedCandidateIDs.contains($0.id) && updateCandidateIDs.contains($0.id)
        }
        guard !selectedNewCandidates.isEmpty || !selectedUpdateCandidates.isEmpty else { return }

        phase = .importing
        errorMessage = nil
        let leadByID = existingLeadsByID
        var updatedCandidateIDs: Set<String> = []
        var updatedLeadIDs: Set<UUID> = []
        var updatedLeads: [Lead] = []
        var updatedBeforeSnapshots: [UUID: LeadImportSnapshot] = [:]
        for candidate in selectedUpdateCandidates {
            guard let leadID = existingLeadIDByCandidateID[candidate.id],
                  let existingLead = leadByID[leadID] else {
                continue
            }
            let beforeSnapshot = LeadImportSnapshot(lead: existingLead)
            if AppleContactLeadImportService.updateLead(existingLead, from: candidate) {
                updatedLeadIDs.insert(leadID)
                updatedLeads.append(existingLead)
                if let beforeSnapshot {
                    updatedBeforeSnapshots[leadID] = beforeSnapshot
                }
            }
            updatedCandidateIDs.insert(candidate.id)
        }

        let insertedLeads: [Lead] = selectedNewCandidates.compactMap {
            AppleContactLeadImportService.createLead(from: $0, in: viewContext)
        }

        do {
            try viewContext.save()
            let batchSource: LeadImportSource = candidateSource == .device
                ? .appleContactsDevice
                : .appleContactsMac
            var undoAvailable = false
            do {
                undoAvailable = try LeadImportBatchStore.shared.record(
                    source: batchSource,
                    createdLeads: insertedLeads,
                    updatedBeforeSnapshots: updatedBeforeSnapshots,
                    updatedLeads: updatedLeads
                ) != nil
            } catch {
                AppLog.warning("Import", "Apple Contacts import history could not be persisted.")
            }
            let importedIDs = Set(selectedNewCandidates.map(\.id)).union(updatedCandidateIDs)
            duplicateCandidateIDs.formUnion(importedIDs)
            updateCandidateIDs.subtract(updatedCandidateIDs)
            selectedCandidateIDs.subtract(importedIDs)
            lastImportOutcome = ImportOutcome(
                created: insertedLeads.count,
                updated: updatedLeadIDs.count,
                undoAvailable: undoAvailable
            )
            phase = .ready
            NotificationService.shared.refreshAllNotifications()
            UserDataSyncManager.shared.syncWithServer()
        } catch {
            viewContext.rollback()
            errorMessage = "The selected contacts were not imported: \(error.localizedDescription)"
            phase = .ready
        }
    }

    private var existingLeadSnapshots: [AppleContactExistingLeadSnapshot] {
        existingLeads.map {
            AppleContactExistingLeadSnapshot(
                name: $0.name,
                phone: $0.phone,
                email: $0.email,
                address: $0.address
            )
        }
    }

    private var existingLeadReferences: [AppleContactExistingLeadReference] {
        existingLeads.compactMap { lead in
            guard let id = lead.id else { return nil }
            return AppleContactExistingLeadReference(
                id: id,
                phone: lead.phone,
                email: lead.email,
                address: lead.address
            )
        }
    }

    private var existingLeadsByID: [UUID: Lead] {
        existingLeads.reduce(into: [:]) { result, lead in
            if let id = lead.id, result[id] == nil {
                result[id] = lead
            }
        }
    }
}

private extension AppleContactLeadServiceKind {
    var tintColor: Color {
        switch self {
        case .windowCleaning: return Color.electricViolet
        case .gutterCleaning: return Color.statusInterested
        }
    }
}
