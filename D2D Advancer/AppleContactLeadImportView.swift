import CoreData
import SwiftUI
import UIKit

struct AppleContactLeadImportView: View {
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
    @State private var hasLimitedAccess = false
    @State private var didScanNotes = false
    @State private var errorMessage: String?
    @State private var permissionNeedsSettings = false
    @State private var lastImportedCount: Int?

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

                if phase == .ready && !didScanNotes && errorMessage == nil {
                    ObsidianStatusBanner(
                        icon: "note.text.badge.plus",
                        title: "Contact Notes Unavailable",
                        message: "Apple Contacts did not allow note access. Name, company, department, and job-title matches are still shown.",
                        tint: Color.statusNotHome
                    )
                }

                if let lastImportedCount {
                    ObsidianStatusBanner(
                        icon: "checkmark.circle.fill",
                        title: "Import Complete",
                        message: "\(lastImportedCount) lead\(lastImportedCount == 1 ? "" : "s") added to Leads and Map.",
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
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !candidates.isEmpty {
                importActionBar
            }
        }
    }

    private var introductionSection: some View {
        LeadFormSectionCard(title: "Find Service Contacts", icon: "person.crop.circle.badge.plus") {
            Text("Scan Apple Contacts for Window Cleaning or Gutter Cleaning, review the matches, then import only the leads you choose.")
                .font(.obsidianBody)
                .foregroundColor(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 9) {
                importFeatureRow(icon: "text.magnifyingglass", text: "Checks name, company, department, job title, and available notes")
                importFeatureRow(icon: "map.fill", text: "Maps each postal address before import")
                importFeatureRow(icon: "person.2.slash.fill", text: "Skips existing phone, email, or address matches")
            }

            if phase == .idle || (phase == .ready && candidates.isEmpty) {
                Button {
                    Task { await scanContacts() }
                } label: {
                    Label("Scan Contacts", systemImage: "magnifyingglass")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(ObsidianPrimaryButtonStyle())
                .accessibilityIdentifier("scanAppleContactsButton")
            }

            Text("Matching contact notes are copied into the lead notes field. Nothing is imported until you confirm the selection.")
                .font(.obsidianFootnote)
                .foregroundColor(Color.textMuted)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("appleContactNotesImportDisclosure")
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
                progressRow(title: "Adding selected leads", detail: "Saving them to your personal workspace")
            }

            summaryRow(title: "Matches", value: candidates.count, tint: Color.electricViolet)
            summaryDivider
            summaryRow(title: "Ready", value: readyCandidates.count, tint: Color.statusInterested)
            summaryDivider
            summaryRow(title: "Already in Leads", value: duplicateCandidateIDs.count, tint: Color.statusNotHome)
            summaryDivider
            summaryRow(title: "Needs a map location", value: unavailableCandidateCount, tint: Color.statusNotInterested)
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

    private func summaryRow(title: String, value: Int, tint: Color) -> some View {
        HStack {
            Text(title)
                .font(.obsidianCallout)
                .foregroundColor(Color.textSecondary)
            Spacer()
            Text("\(value)")
                .font(.obsidianHeadline)
                .foregroundColor(tint)
                .monospacedDigit()
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
                    Text("Only ready contacts can be selected.")
                        .font(.obsidianFootnote)
                        .foregroundColor(Color.textSecondary)
                }

                Spacer()

                Button(selectedCandidateIDs.isEmpty ? "Select Ready" : "Clear") {
                    if selectedCandidateIDs.isEmpty {
                        selectedCandidateIDs = Set(readyCandidates.map(\.id))
                    } else {
                        selectedCandidateIDs.removeAll()
                    }
                }
                .font(.obsidianFootnote)
                .foregroundColor(Color.electricViolet)
                .disabled(readyCandidates.isEmpty)
                .accessibilityIdentifier("toggleReadyAppleContactsButton")
            }

            ForEach(candidates) { candidate in
                candidateCard(candidate)
            }
        }
    }

    private func candidateCard(_ candidate: AppleContactLeadCandidate) -> some View {
        let selectable = candidate.isReadyForImport && !duplicateCandidateIDs.contains(candidate.id) && !phase.isBusy
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

                    if let note = candidate.note {
                        Label(note, systemImage: "note.text")
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
            secondaryAction: { Task { await scanContacts() } },
            primaryLabel: {
                Label("Import \(selectedCandidateIDs.count)", systemImage: "square.and.arrow.down.fill")
            },
            secondaryLabel: {
                Label("Rescan", systemImage: "arrow.clockwise")
            }
        )
    }

    private var readyCandidates: [AppleContactLeadCandidate] {
        candidates.filter { $0.isReadyForImport && !duplicateCandidateIDs.contains($0.id) }
    }

    private var unavailableCandidateCount: Int {
        candidates.filter {
            !duplicateCandidateIDs.contains($0.id) && !$0.isReadyForImport
        }.count
    }

    @MainActor
    private func scanContacts() async {
        phase = .scanning
        errorMessage = nil
        permissionNeedsSettings = false
        lastImportedCount = nil
        didScanNotes = false
        selectedCandidateIDs.removeAll()
        duplicateCandidateIDs.removeAll()

        do {
            let result = try await AppleContactLeadImportService.shared.loadMatchingContacts()
            hasLimitedAccess = result.hasLimitedAccess
            didScanNotes = result.didScanNotes
            candidates = result.candidates

            let duplicateIndex = AppleContactLeadDuplicateIndex(existingLeads: existingLeadSnapshots)
            duplicateCandidateIDs = Set(
                candidates.filter(duplicateIndex.contains).map(\.id)
            )

            let indicesToGeocode = candidates.indices.filter { index in
                candidates[index].address != nil && !duplicateCandidateIDs.contains(candidates[index].id)
            }

            for (offset, index) in indicesToGeocode.enumerated() {
                phase = .geocoding(current: offset + 1, total: indicesToGeocode.count)
                candidates[index].didAttemptGeocoding = true
                if let address = candidates[index].address {
                    candidates[index].coordinate = await AppleContactAddressGeocoder.shared.coordinate(for: address)
                }
            }

            selectedCandidateIDs = Set(readyCandidates.map(\.id))
            phase = .ready
        } catch let importError as AppleContactLeadImportError {
            candidates = []
            hasLimitedAccess = false
            didScanNotes = false
            errorMessage = importError.localizedDescription
            permissionNeedsSettings = importError.needsSettings
            phase = .ready
        } catch {
            candidates = []
            hasLimitedAccess = false
            didScanNotes = false
            errorMessage = error.localizedDescription
            phase = .ready
        }
    }

    @MainActor
    private func importSelectedContacts() {
        guard PaywallManager.shared.gateAction() else { return }

        let selected = candidates.filter {
            selectedCandidateIDs.contains($0.id) &&
                $0.isReadyForImport &&
                !duplicateCandidateIDs.contains($0.id)
        }
        guard !selected.isEmpty else { return }

        phase = .importing
        errorMessage = nil
        let insertedLeads: [Lead] = selected.compactMap { candidate in
            guard let address = candidate.address, let coordinate = candidate.coordinate else { return nil }

            let lead = Lead.create(in: viewContext)
            lead.name = candidate.displayName
            lead.phone = candidate.phone
            lead.email = candidate.email
            lead.address = address
            lead.latitude = coordinate.latitude
            lead.longitude = coordinate.longitude
            lead.serviceCategory = candidate.service.serviceCategoryID
            lead.source = "Apple Contacts"
            lead.notes = candidate.note
            lead.applyLeadStatus(.notContacted, autoSave: false)
            return lead
        }

        do {
            try viewContext.save()
            let importedIDs = Set(selected.map(\.id))
            duplicateCandidateIDs.formUnion(importedIDs)
            selectedCandidateIDs.subtract(importedIDs)
            lastImportedCount = insertedLeads.count
            phase = .ready
            UserDataSyncManager.shared.syncWithServer()
        } catch {
            insertedLeads.forEach(viewContext.delete)
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

    private var noMatchesMessage: String {
        let fields = didScanNotes
            ? "name, company, department, job title, or notes"
            : "name, company, department, or job title"
        return "No accessible contact contains Window Cleaning or Gutter Cleaning in its \(fields)."
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
