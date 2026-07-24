import Contacts
import CoreData
import CoreLocation
import Foundation
import MapKit

enum AppleContactLeadServiceKind: String, CaseIterable, Hashable, Sendable {
    case windowCleaning
    case gutterCleaning

    var title: String {
        switch self {
        case .windowCleaning: return "Window Cleaning"
        case .gutterCleaning: return "Gutter Cleaning"
        }
    }

    var searchPhrase: String {
        title.lowercased()
    }

    var serviceCategoryID: String {
        switch self {
        case .windowCleaning: return "window_cleaning"
        case .gutterCleaning: return "gutter_cleaning"
        }
    }
}

struct AppleContactLeadCoordinate: Hashable, Sendable {
    let latitude: Double
    let longitude: Double

    var isValid: Bool {
        CLLocationCoordinate2DIsValid(
            CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        ) && !(latitude == 0 && longitude == 0)
    }
}

struct AppleContactLeadCandidate: Identifiable, Hashable, Sendable {
    let id: String
    let displayName: String
    let phone: String?
    let email: String?
    let address: String?
    let service: AppleContactLeadServiceKind
    var notes: String? = nil
    var price: Double? = nil
    var coordinate: AppleContactLeadCoordinate?
    var didAttemptGeocoding = false

    var isReadyForImport: Bool {
        address != nil && coordinate?.isValid == true
    }
}

struct AppleContactLeadNameSanitization: Equatable, Sendable {
    let displayName: String?
    let movedLabels: [String]

    func mergingMovedLabels(into notes: String?) -> String? {
        let existingNotes = notes?.trimmingCharacters(in: .whitespacesAndNewlines)
        let retainedNotes = existingNotes?.isEmpty == false ? existingNotes : nil
        let missingAnnotations = movedLabels.compactMap { label -> String? in
            let annotation = "Contact label: \(label)"
            guard retainedNotes?.range(
                of: annotation,
                options: [.caseInsensitive, .diacriticInsensitive]
            ) == nil else {
                return nil
            }
            return annotation
        }

        guard !missingAnnotations.isEmpty else { return retainedNotes }
        let annotationBlock = missingAnnotations.joined(separator: "\n")
        return retainedNotes.map { $0 + "\n\n" + annotationBlock } ?? annotationBlock
    }
}

struct AppleContactLeadScanResult: Sendable {
    let candidates: [AppleContactLeadCandidate]
    let hasLimitedAccess: Bool
}

enum AppleContactLeadImportError: LocalizedError, Equatable {
    case accessDenied
    case accessRestricted
    case contactsUnavailable
    case fetchFailed(String)

    var errorDescription: String? {
        switch self {
        case .accessDenied:
            return "Contacts access is off. Allow access in Settings, then scan again."
        case .accessRestricted:
            return "Contacts access is restricted on this device."
        case .contactsUnavailable:
            return "Contacts could not be accessed right now."
        case .fetchFailed(let message):
            return "Contacts could not be scanned: \(message)"
        }
    }

    var needsSettings: Bool {
        self == .accessDenied
    }
}

struct AppleContactExistingLeadSnapshot: Hashable, Sendable {
    let name: String?
    let phone: String?
    let email: String?
    let address: String?
}

struct AppleContactExistingLeadReference: Hashable, Sendable {
    let id: UUID
    let phone: String?
    let email: String?
    let address: String?
}

struct AppleContactLeadExistingMatchIndex: Sendable {
    private var leadIDByPhone: [String: UUID] = [:]
    private var leadIDByEmail: [String: UUID] = [:]
    private var leadIDByAddress: [String: UUID] = [:]

    init(existingLeads: [AppleContactExistingLeadReference]) {
        for lead in existingLeads {
            if let phone = AppleContactLeadMatchPolicy.normalizedPhone(lead.phone) {
                if leadIDByPhone[phone] == nil {
                    leadIDByPhone[phone] = lead.id
                }
            }
            if let email = AppleContactLeadMatchPolicy.normalizedEmail(lead.email) {
                if leadIDByEmail[email] == nil {
                    leadIDByEmail[email] = lead.id
                }
            }
            if let address = AppleContactLeadMatchPolicy.normalizedAddress(lead.address) {
                if leadIDByAddress[address] == nil {
                    leadIDByAddress[address] = lead.id
                }
            }
        }
    }

    func matchingLeadID(for candidate: AppleContactLeadCandidate) -> UUID? {
        if let phone = AppleContactLeadMatchPolicy.normalizedPhone(candidate.phone),
           let leadID = leadIDByPhone[phone] {
            return leadID
        }
        if let email = AppleContactLeadMatchPolicy.normalizedEmail(candidate.email),
           let leadID = leadIDByEmail[email] {
            return leadID
        }
        if let address = AppleContactLeadMatchPolicy.normalizedAddress(candidate.address),
           let leadID = leadIDByAddress[address] {
            return leadID
        }
        return nil
    }
}

struct AppleContactExistingLeadMergeSnapshot: Equatable, Sendable {
    let name: String?
    let phone: String?
    let email: String?
    let address: String?
    let notes: String?
    let serviceCategory: String?
    let latitude: Double
    let longitude: Double
    let price: Double
    let estimatedValue: Double
}

struct AppleContactLeadMergePlan: Equatable, Sendable {
    let name: String?
    let phone: String?
    let email: String?
    let address: String?
    let notes: String?
    let serviceCategory: String?
    let latitude: Double
    let longitude: Double
    let price: Double
    let estimatedValue: Double

    func hasChanges(comparedWith existing: AppleContactExistingLeadMergeSnapshot) -> Bool {
        self != AppleContactLeadMergePlan(existing)
    }

    private init(_ existing: AppleContactExistingLeadMergeSnapshot) {
        name = existing.name
        phone = existing.phone
        email = existing.email
        address = existing.address
        notes = existing.notes
        serviceCategory = existing.serviceCategory
        latitude = existing.latitude
        longitude = existing.longitude
        price = existing.price
        estimatedValue = existing.estimatedValue
    }

    init(
        name: String?,
        phone: String?,
        email: String?,
        address: String?,
        notes: String?,
        serviceCategory: String?,
        latitude: Double,
        longitude: Double,
        price: Double,
        estimatedValue: Double
    ) {
        self.name = name
        self.phone = phone
        self.email = email
        self.address = address
        self.notes = notes
        self.serviceCategory = serviceCategory
        self.latitude = latitude
        self.longitude = longitude
        self.price = price
        self.estimatedValue = estimatedValue
    }
}

enum AppleContactLeadMergePolicy {
    static func requiresGeocoding(
        existing: AppleContactExistingLeadMergeSnapshot,
        candidate: AppleContactLeadCandidate
    ) -> Bool {
        guard cleaned(candidate.address) != nil else { return false }
        guard !hasValidCoordinate(existing) else { return false }

        guard let existingAddress = cleaned(existing.address) else { return true }
        return AppleContactLeadMatchPolicy.normalizedAddress(existingAddress)
            == AppleContactLeadMatchPolicy.normalizedAddress(candidate.address)
    }

    static func plan(
        existing: AppleContactExistingLeadMergeSnapshot,
        candidate: AppleContactLeadCandidate
    ) -> AppleContactLeadMergePlan {
        let existingAddress = cleaned(existing.address)
        let candidateAddress = cleaned(candidate.address)
        let candidateHasValidCoordinate = candidate.coordinate?.isValid == true
        let addressesMatch = AppleContactLeadMatchPolicy.normalizedAddress(existingAddress)
            == AppleContactLeadMatchPolicy.normalizedAddress(candidateAddress)
        let shouldFillAddress = existingAddress == nil
            && candidateAddress != nil
            && candidateHasValidCoordinate
        let shouldFillCoordinates = candidateHasValidCoordinate
            && !hasValidCoordinate(existing)
            && (existingAddress == nil || addressesMatch)
        let resolvedPrice = existing.price > 0 ? existing.price : (candidate.price ?? existing.price)
        let resolvedEstimatedValue = existing.estimatedValue > 0
            ? existing.estimatedValue
            : (resolvedPrice > 0 ? resolvedPrice : existing.estimatedValue)

        return AppleContactLeadMergePlan(
            name: cleaned(existing.name) ?? cleaned(candidate.displayName),
            phone: cleaned(existing.phone) ?? cleaned(candidate.phone),
            email: cleaned(existing.email) ?? cleaned(candidate.email),
            address: shouldFillAddress ? candidateAddress : existing.address,
            notes: mergedNotes(existing: existing.notes, imported: candidate.notes),
            serviceCategory: cleaned(existing.serviceCategory) ?? candidate.service.serviceCategoryID,
            latitude: shouldFillCoordinates ? (candidate.coordinate?.latitude ?? existing.latitude) : existing.latitude,
            longitude: shouldFillCoordinates ? (candidate.coordinate?.longitude ?? existing.longitude) : existing.longitude,
            price: resolvedPrice,
            estimatedValue: resolvedEstimatedValue
        )
    }

    static func mergedNotes(existing: String?, imported: String?) -> String? {
        guard let imported = cleaned(imported) else { return existing }
        guard let existing = cleaned(existing) else { return imported }
        guard existing.range(
            of: imported,
            options: [.caseInsensitive, .diacriticInsensitive]
        ) == nil else {
            return existing
        }

        return existing + "\n\nImported from Apple Contacts:\n" + imported
    }

    private static func cleaned(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }

    private static func hasValidCoordinate(_ existing: AppleContactExistingLeadMergeSnapshot) -> Bool {
        AppleContactLeadCoordinate(
            latitude: existing.latitude,
            longitude: existing.longitude
        ).isValid
    }
}

enum AppleContactLeadImportStatusPolicy {
    static func status(forNew candidate: AppleContactLeadCandidate) -> Lead.Status {
        candidate.price.map { $0 > 0 } == true ? .converted : .interested
    }

    static func status(
        forExisting currentStatus: Lead.Status,
        candidate: AppleContactLeadCandidate
    ) -> Lead.Status {
        if candidate.price.map({ $0 > 0 }) == true {
            return .converted
        }

        switch currentStatus {
        case .converted, .notInterested:
            return currentStatus
        case .notContacted, .notHome, .interested:
            return .interested
        }
    }
}

enum AppleContactLeadCandidateConsolidator {
    static func consolidatingDuplicates(
        _ candidates: [AppleContactLeadCandidate]
    ) -> [AppleContactLeadCandidate] {
        guard candidates.count > 1 else { return candidates }

        var parents = Array(candidates.indices)
        var firstIndexByMatchKey: [String: Int] = [:]

        func root(of index: Int) -> Int {
            var current = index
            while parents[current] != current {
                current = parents[current]
            }
            return current
        }

        func union(_ lhs: Int, _ rhs: Int) {
            let lhsRoot = root(of: lhs)
            let rhsRoot = root(of: rhs)
            if lhsRoot != rhsRoot {
                parents[rhsRoot] = lhsRoot
            }
        }

        for (index, candidate) in candidates.enumerated() {
            for key in matchKeys(for: candidate) {
                if let existingIndex = firstIndexByMatchKey[key] {
                    union(index, existingIndex)
                } else {
                    firstIndexByMatchKey[key] = index
                }
            }
        }

        var groupedIndices: [Int: [Int]] = [:]
        for index in candidates.indices {
            groupedIndices[root(of: index), default: []].append(index)
        }

        return groupedIndices.values
            .sorted { ($0.min() ?? 0) < ($1.min() ?? 0) }
            .map { indices in
                mergedCandidate(indices.map { candidates[$0] })
            }
    }

    private static func matchKeys(for candidate: AppleContactLeadCandidate) -> [String] {
        var keys: [String] = []
        if let phone = AppleContactLeadMatchPolicy.normalizedPhone(candidate.phone) {
            keys.append("phone:\(phone)")
        }
        if let email = AppleContactLeadMatchPolicy.normalizedEmail(candidate.email) {
            keys.append("email:\(email)")
        }
        if let address = AppleContactLeadMatchPolicy.normalizedAddress(candidate.address) {
            keys.append("address:\(address)")
        }
        return keys
    }

    private static func mergedCandidate(
        _ candidates: [AppleContactLeadCandidate]
    ) -> AppleContactLeadCandidate {
        let preferred = candidates.first { $0.price.map({ $0 > 0 }) == true }
            ?? candidates[0]
        let address = cleaned(preferred.address)
            ?? candidates.lazy.compactMap { cleaned($0.address) }.first
        let normalizedAddress = AppleContactLeadMatchPolicy.normalizedAddress(address)
        let coordinate = candidates.first {
            $0.coordinate?.isValid == true
                && AppleContactLeadMatchPolicy.normalizedAddress($0.address) == normalizedAddress
        }?.coordinate
        var notes: String?
        for candidate in candidates {
            notes = AppleContactLeadMergePolicy.mergedNotes(
                existing: notes,
                imported: candidate.notes
            )
        }

        return AppleContactLeadCandidate(
            id: preferred.id,
            displayName: preferred.displayName,
            phone: cleaned(preferred.phone) ?? candidates.lazy.compactMap { cleaned($0.phone) }.first,
            email: cleaned(preferred.email) ?? candidates.lazy.compactMap { cleaned($0.email) }.first,
            address: address,
            service: preferred.service,
            notes: notes,
            price: preferred.price,
            coordinate: coordinate,
            didAttemptGeocoding: candidates.contains(where: \.didAttemptGeocoding)
        )
    }

    private static func cleaned(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }
}

struct AppleContactLeadDuplicateIndex: Sendable {
    private var phones: Set<String>
    private var emails: Set<String>
    private var addresses: Set<String>

    init(existingLeads: [AppleContactExistingLeadSnapshot]) {
        phones = Set(existingLeads.compactMap { AppleContactLeadMatchPolicy.normalizedPhone($0.phone) })
        emails = Set(existingLeads.compactMap { AppleContactLeadMatchPolicy.normalizedEmail($0.email) })
        addresses = Set(existingLeads.compactMap { AppleContactLeadMatchPolicy.normalizedAddress($0.address) })
    }

    func contains(_ candidate: AppleContactLeadCandidate) -> Bool {
        if let phone = AppleContactLeadMatchPolicy.normalizedPhone(candidate.phone), phones.contains(phone) {
            return true
        }
        if let email = AppleContactLeadMatchPolicy.normalizedEmail(candidate.email), emails.contains(email) {
            return true
        }
        if let address = AppleContactLeadMatchPolicy.normalizedAddress(candidate.address), addresses.contains(address) {
            return true
        }
        return false
    }

    mutating func registerIfUnique(_ candidate: AppleContactLeadCandidate) -> Bool {
        guard !contains(candidate) else { return false }

        if let phone = AppleContactLeadMatchPolicy.normalizedPhone(candidate.phone) {
            phones.insert(phone)
        }
        if let email = AppleContactLeadMatchPolicy.normalizedEmail(candidate.email) {
            emails.insert(email)
        }
        if let address = AppleContactLeadMatchPolicy.normalizedAddress(candidate.address) {
            addresses.insert(address)
        }
        return true
    }
}

enum AppleContactLeadMatchPolicy {
    private static let movableNameLabels: [(canonical: String, expression: NSRegularExpression)] = [
        (
            canonical: "Ad",
            expression: try! NSRegularExpression(
                pattern: #"(?<![\p{L}\p{N}])ad(?=[\s\p{P}]*$)"#,
                options: [.caseInsensitive]
            )
        )
    ]

    static func matchedService(in fields: [String]) -> AppleContactLeadServiceKind? {
        let text = fields
            .map(normalizedSearchText)
            .filter { !$0.isEmpty }
            .joined(separator: " | ")

        return AppleContactLeadServiceKind.allCases
            .compactMap { service -> (AppleContactLeadServiceKind, String.Index)? in
                guard let range = text.range(of: service.searchPhrase) else { return nil }
                return (service, range.lowerBound)
            }
            .min { lhs, rhs in lhs.1 < rhs.1 }?
            .0
    }

    static func normalizedPhone(_ value: String?) -> String? {
        guard let value else { return nil }
        var digits = value.filter(\.isNumber)
        if digits.count == 11, digits.first == "1" {
            digits.removeFirst()
        }
        return digits.count >= 7 ? digits : nil
    }

    static func normalizedEmail(_ value: String?) -> String? {
        cleaned(value)?.lowercased()
    }

    static func normalizedAddress(_ value: String?) -> String? {
        guard let value = cleaned(value) else { return nil }
        let normalized = normalizedSearchText(value).filter { $0.isLetter || $0.isNumber }
        return normalized.isEmpty ? nil : normalized
    }

    static func normalizedSearchText(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func sanitizedLeadName(_ value: String?) -> String? {
        sanitizedLeadNameResult(value).displayName
    }

    static func sanitizedLeadNameResult(_ value: String?) -> AppleContactLeadNameSanitization {
        guard var sanitized = cleaned(value) else {
            return AppleContactLeadNameSanitization(displayName: nil, movedLabels: [])
        }

        var movedLabels: [String] = []

        for service in AppleContactLeadServiceKind.allCases {
            while let range = sanitized.range(
                of: service.title,
                options: [.caseInsensitive, .diacriticInsensitive]
            ) {
                sanitized.replaceSubrange(range, with: " ")
            }
        }

        for movableLabel in movableNameLabels {
            let searchRange = NSRange(sanitized.startIndex..<sanitized.endIndex, in: sanitized)
            guard movableLabel.expression.firstMatch(in: sanitized, range: searchRange) != nil else {
                continue
            }

            sanitized = movableLabel.expression.stringByReplacingMatches(
                in: sanitized,
                range: searchRange,
                withTemplate: " "
            )
            movedLabels.append(movableLabel.canonical)
        }

        sanitized = sanitized.replacingOccurrences(
            of: #"\(\s*\)|\[\s*\]|\{\s*\}"#,
            with: " ",
            options: .regularExpression
        )
        sanitized = sanitized.replacingOccurrences(
            of: #"(?:\s*[-_|/,:;]\s*){2,}"#,
            with: " ",
            options: .regularExpression
        )
        sanitized = sanitized.replacingOccurrences(
            of: #"\s+"#,
            with: " ",
            options: .regularExpression
        )

        let edgeCharacters = CharacterSet.whitespacesAndNewlines
            .union(.punctuationCharacters)
            .union(CharacterSet(charactersIn: "&+"))
        sanitized = sanitized.trimmingCharacters(in: edgeCharacters)

        let displayName = sanitized.contains(where: { $0.isLetter || $0.isNumber })
            ? sanitized
            : nil
        return AppleContactLeadNameSanitization(
            displayName: displayName,
            movedLabels: movedLabels
        )
    }

    private static func cleaned(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }
}

final class AppleContactLeadImportService {
    static let shared = AppleContactLeadImportService()

    private init() {}

    static func sanitizeImportedLeadNames(in context: NSManagedObjectContext) throws -> Int {
        let request = Lead.fetchRequest(in: context)
        request.predicate = NSPredicate(format: "source ==[c] %@", "Apple Contacts")

        var updateCount = 0
        for lead in try context.fetch(request) {
            guard let existingName = lead.name?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !existingName.isEmpty else { continue }

            let sanitization = AppleContactLeadMatchPolicy.sanitizedLeadNameResult(existingName)
            let sanitizedName = sanitization.displayName ?? "Apple Contact"
            let sanitizedNotes = sanitization.mergingMovedLabels(into: lead.notes)
            guard sanitizedName != existingName || sanitizedNotes != lead.notes else { continue }

            lead.name = sanitizedName
            lead.notes = sanitizedNotes
            lead.updatedDate = Date()
            updateCount += 1
        }
        return updateCount
    }

    static func createLead(
        from candidate: AppleContactLeadCandidate,
        in context: NSManagedObjectContext
    ) -> Lead? {
        guard let address = candidate.address,
              let coordinate = candidate.coordinate,
              coordinate.isValid else {
            return nil
        }

        let lead = Lead.create(in: context)
        lead.name = candidate.displayName
        lead.phone = candidate.phone
        lead.email = candidate.email
        lead.address = address
        lead.latitude = coordinate.latitude
        lead.longitude = coordinate.longitude
        lead.serviceCategory = candidate.service.serviceCategoryID
        lead.source = "Apple Contacts"
        lead.notes = candidate.notes
        if let price = candidate.price {
            lead.price = price
            lead.estimatedValue = price
        }
        lead.applyLeadStatus(
            AppleContactLeadImportStatusPolicy.status(forNew: candidate),
            autoSave: false
        )
        return lead
    }

    @discardableResult
    static func updateLead(_ lead: Lead, from candidate: AppleContactLeadCandidate) -> Bool {
        let existing = mergeSnapshot(for: lead)
        let plan = AppleContactLeadMergePolicy.plan(existing: existing, candidate: candidate)
        let resolvedStatus = AppleContactLeadImportStatusPolicy.status(
            forExisting: lead.leadStatus,
            candidate: candidate
        )
        let hasFieldChanges = plan.hasChanges(comparedWith: existing)
        let hasStatusChange = resolvedStatus != lead.leadStatus
        guard hasFieldChanges || hasStatusChange else { return false }

        if hasFieldChanges {
            lead.name = plan.name
            lead.phone = plan.phone
            lead.email = plan.email
            lead.address = plan.address
            lead.notes = plan.notes
            lead.serviceCategory = plan.serviceCategory
            lead.latitude = plan.latitude
            lead.longitude = plan.longitude
            lead.price = plan.price
            lead.estimatedValue = plan.estimatedValue
        }
        if hasStatusChange {
            lead.applyLeadStatus(resolvedStatus, autoSave: false)
        } else {
            lead.updatedDate = Date()
        }
        return true
    }

    static func canUpdateLead(_ lead: Lead, from candidate: AppleContactLeadCandidate) -> Bool {
        let existing = mergeSnapshot(for: lead)
        let fieldsCanChange = AppleContactLeadMergePolicy
            .plan(existing: existing, candidate: candidate)
            .hasChanges(comparedWith: existing)
        let resolvedStatus = AppleContactLeadImportStatusPolicy.status(
            forExisting: lead.leadStatus,
            candidate: candidate
        )
        return fieldsCanChange || resolvedStatus != lead.leadStatus
    }

    static func needsGeocodingForUpdate(
        _ lead: Lead,
        from candidate: AppleContactLeadCandidate
    ) -> Bool {
        AppleContactLeadMergePolicy.requiresGeocoding(
            existing: mergeSnapshot(for: lead),
            candidate: candidate
        )
    }

    private static func mergeSnapshot(for lead: Lead) -> AppleContactExistingLeadMergeSnapshot {
        AppleContactExistingLeadMergeSnapshot(
            name: lead.name,
            phone: lead.phone,
            email: lead.email,
            address: lead.address,
            notes: lead.notes,
            serviceCategory: lead.serviceCategory,
            latitude: lead.latitude,
            longitude: lead.longitude,
            price: lead.price,
            estimatedValue: lead.estimatedValue
        )
    }

    func loadMatchingContacts() async throws -> AppleContactLeadScanResult {
        var status = CNContactStore.authorizationStatus(for: .contacts)

        if status == .notDetermined {
            let granted = try await requestAccess()
            guard granted else { throw AppleContactLeadImportError.accessDenied }
            status = CNContactStore.authorizationStatus(for: .contacts)
        }

        switch status {
        case .authorized, .limited:
            break
        case .denied:
            throw AppleContactLeadImportError.accessDenied
        case .restricted:
            throw AppleContactLeadImportError.accessRestricted
        case .notDetermined:
            throw AppleContactLeadImportError.contactsUnavailable
        @unknown default:
            throw AppleContactLeadImportError.contactsUnavailable
        }

        do {
            let candidates = try await Task.detached(priority: .userInitiated) {
                try Self.fetchMatchingContacts()
            }.value
            return AppleContactLeadScanResult(
                candidates: candidates,
                hasLimitedAccess: status == .limited
            )
        } catch let error as AppleContactLeadImportError {
            throw error
        } catch {
            throw AppleContactLeadImportError.fetchFailed(error.localizedDescription)
        }
    }

    private func requestAccess() async throws -> Bool {
        try await withCheckedThrowingContinuation { continuation in
            CNContactStore().requestAccess(for: .contacts) { granted, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: granted)
                }
            }
        }
    }

    private static func fetchMatchingContacts() throws -> [AppleContactLeadCandidate] {
        let keys: [CNKeyDescriptor] = [
            CNContactIdentifierKey as CNKeyDescriptor,
            CNContactGivenNameKey as CNKeyDescriptor,
            CNContactMiddleNameKey as CNKeyDescriptor,
            CNContactFamilyNameKey as CNKeyDescriptor,
            CNContactNicknameKey as CNKeyDescriptor,
            CNContactOrganizationNameKey as CNKeyDescriptor,
            CNContactDepartmentNameKey as CNKeyDescriptor,
            CNContactJobTitleKey as CNKeyDescriptor,
            CNContactPhoneNumbersKey as CNKeyDescriptor,
            CNContactEmailAddressesKey as CNKeyDescriptor,
            CNContactPostalAddressesKey as CNKeyDescriptor
        ]
        let request = CNContactFetchRequest(keysToFetch: keys)
        request.unifyResults = true
        request.sortOrder = .userDefault

        var matches: [AppleContactLeadCandidate] = []
        try CNContactStore().enumerateContacts(with: request) { contact, _ in
            guard let candidate = candidate(from: contact) else { return }
            matches.append(candidate)
        }
        return matches
    }

    static func candidate(from contact: CNContact) -> AppleContactLeadCandidate? {
        let rawDisplayName = displayName(for: contact)
        let searchableFields = [
            rawDisplayName,
            contact.nickname,
            contact.organizationName,
            contact.departmentName,
            contact.jobTitle
        ]

        guard let service = AppleContactLeadMatchPolicy.matchedService(in: searchableFields) else {
            return nil
        }

        let nameSanitization = [rawDisplayName, contact.nickname, contact.organizationName]
            .map(AppleContactLeadMatchPolicy.sanitizedLeadNameResult)
            .first { $0.displayName != nil }
            ?? AppleContactLeadNameSanitization(displayName: "Apple Contact", movedLabels: [])

        return AppleContactLeadCandidate(
            id: contact.identifier,
            displayName: nameSanitization.displayName ?? "Apple Contact",
            phone: preferredPhone(from: contact),
            email: preferredEmail(from: contact),
            address: preferredAddress(from: contact),
            service: service,
            notes: nameSanitization.mergingMovedLabels(into: nil),
            coordinate: nil
        )
    }

    private static func displayName(for contact: CNContact) -> String {
        let name = [contact.givenName, contact.middleName, contact.familyName]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        if !name.isEmpty { return name }
        if !contact.nickname.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return contact.nickname
        }
        if !contact.organizationName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return contact.organizationName
        }
        return "Apple Contact"
    }

    private static func preferredPhone(from contact: CNContact) -> String? {
        contact.phoneNumbers
            .sorted { phonePriority($0.label) < phonePriority($1.label) }
            .map(\.value.stringValue)
            .first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    private static func phonePriority(_ label: String?) -> Int {
        switch label {
        case CNLabelPhoneNumberMobile, CNLabelPhoneNumberiPhone: return 0
        case CNLabelPhoneNumberMain, CNLabelWork: return 1
        case CNLabelHome: return 2
        default: return 3
        }
    }

    private static func preferredEmail(from contact: CNContact) -> String? {
        contact.emailAddresses
            .sorted { contactValuePriority($0.label) < contactValuePriority($1.label) }
            .map { String($0.value) }
            .first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    private static func preferredAddress(from contact: CNContact) -> String? {
        contact.postalAddresses
            .sorted { contactValuePriority($0.label) < contactValuePriority($1.label) }
            .compactMap { value in
                CNPostalAddressFormatter
                    .string(from: value.value, style: .mailingAddress)
                    .components(separatedBy: .newlines)
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                    .joined(separator: ", ")
            }
            .first { !$0.isEmpty }
    }

    private static func contactValuePriority(_ label: String?) -> Int {
        switch label {
        case CNLabelHome: return 0
        case CNLabelWork: return 1
        default: return 2
        }
    }
}

@MainActor
final class AppleContactAddressGeocoder {
    static let shared = AppleContactAddressGeocoder()

    private enum CachedResult {
        case coordinate(AppleContactLeadCoordinate)
        case notFound
    }

    private var cache: [String: CachedResult] = [:]

    private init() {}

    func coordinate(for address: String) async -> AppleContactLeadCoordinate? {
        let cacheKey = AppleContactLeadMatchPolicy.normalizedAddress(address) ?? address.lowercased()
        if let cached = cache[cacheKey] {
            switch cached {
            case .coordinate(let coordinate): return coordinate
            case .notFound: return nil
            }
        }

        let result: AppleContactLeadCoordinate?
        if #available(iOS 26.0, *) {
            result = await geocodeWithMapKit(address)
        } else {
            result = await geocodeWithCoreLocation(address)
        }

        cache[cacheKey] = result.map(CachedResult.coordinate) ?? .notFound
        return result
    }

    @available(iOS 26.0, *)
    private func geocodeWithMapKit(_ address: String) async -> AppleContactLeadCoordinate? {
        guard let request = MKGeocodingRequest(addressString: address) else { return nil }
        request.preferredLocale = .current

        do {
            guard let coordinate = try await request.mapItems.first?.location.coordinate else { return nil }
            return AppleContactLeadCoordinate(latitude: coordinate.latitude, longitude: coordinate.longitude)
        } catch {
            return nil
        }
    }

    private func geocodeWithCoreLocation(_ address: String) async -> AppleContactLeadCoordinate? {
        await withCheckedContinuation { continuation in
            CLGeocoder().geocodeAddressString(address) { placemarks, _ in
                guard let coordinate = placemarks?.first?.location?.coordinate else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(
                    returning: AppleContactLeadCoordinate(
                        latitude: coordinate.latitude,
                        longitude: coordinate.longitude
                    )
                )
            }
        }
    }
}
