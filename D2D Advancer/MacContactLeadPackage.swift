import Foundation

struct MacContactLeadPackage: Codable, Sendable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let exportedAt: String?
    let source: String?
    let contacts: [MacContactPackageRecord]
}

struct MacContactPackageRecord: Codable, Sendable {
    let identifier: String
    let name: String?
    let firstName: String?
    let middleName: String?
    let lastName: String?
    let nickname: String?
    let organization: String?
    let department: String?
    let jobTitle: String?
    let note: String?
    let price: Double?
    let phoneNumbers: [MacContactPackageLabeledValue]?
    let emailAddresses: [MacContactPackageLabeledValue]?
    let postalAddresses: [MacContactPackageAddress]?
}

struct MacContactPackageLabeledValue: Codable, Sendable {
    let label: String?
    let value: String
}

struct MacContactPackageAddress: Codable, Sendable {
    let label: String?
    let formatted: String?
    let street: String?
    let city: String?
    let state: String?
    let postalCode: String?
    let country: String?
    let countryCode: String?
}

enum MacContactLeadPackageError: LocalizedError, Equatable {
    case unreadable(String)
    case unsupportedSchema(Int)
    case invalidPackage

    var errorDescription: String? {
        switch self {
        case .unreadable(let message):
            return "The Mac Contacts file could not be read: \(message)"
        case .unsupportedSchema(let version):
            return "This Mac Contacts export uses unsupported format version \(version)."
        case .invalidPackage:
            return "The selected file is not a valid D2D Advancer Mac Contacts export."
        }
    }
}

enum AppleContactLeadPricePolicy {
    private static let amountPatterns: [NSRegularExpression] = [
        try! NSRegularExpression(
            pattern: #"\b(?:price|quote(?:d)?|estimate(?:d)?|value)\b\s*(?:is\s*)?(?:[:=\-]\s*)?(?:(?:cad|ca)\s*)?(?:\$\s*)?([0-9]+(?:[, ]?[0-9]{3})*(?:\.[0-9]{1,2})?)"#,
            options: [.caseInsensitive]
        ),
        try! NSRegularExpression(
            pattern: #"(?:(?:cad|ca)\s*)?\$\s*([0-9]+(?:[, ]?[0-9]{3})*(?:\.[0-9]{1,2})?)"#,
            options: [.caseInsensitive]
        ),
        try! NSRegularExpression(
            pattern: #"^\s*(?:(?:cad|ca)\s*)?\$?\s*([0-9]+(?:[, ]?[0-9]{3})*(?:\.[0-9]{1,2})?)\s*(?:cad)?\s*$"#,
            options: [.caseInsensitive]
        )
    ]

    static func price(in note: String?) -> Double? {
        guard let note = cleaned(note) else { return nil }
        let searchRange = NSRange(note.startIndex..<note.endIndex, in: note)

        for expression in amountPatterns {
            guard let match = expression.firstMatch(in: note, range: searchRange),
                  match.numberOfRanges > 1,
                  let amountRange = Range(match.range(at: 1), in: note) else {
                continue
            }

            let normalizedAmount = note[amountRange]
                .replacingOccurrences(of: ",", with: "")
                .replacingOccurrences(of: " ", with: "")
            guard let amount = Double(normalizedAmount),
                  amount.isFinite,
                  amount > 0,
                  amount <= 10_000_000 else {
                continue
            }
            return amount
        }

        return nil
    }

    static func resolvedPrice(explicitPrice: Double?, note: String?) -> Double? {
        if let explicitPrice,
           explicitPrice.isFinite,
           explicitPrice > 0,
           explicitPrice <= 10_000_000 {
            return explicitPrice
        }
        return price(in: note)
    }

    private static func cleaned(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }
}

enum MacContactLeadPackageService {
    static func loadCandidates(from url: URL) throws -> [AppleContactLeadCandidate] {
        let didStartAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didStartAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }

        do {
            return try candidates(from: Data(contentsOf: url))
        } catch let error as MacContactLeadPackageError {
            throw error
        } catch {
            throw MacContactLeadPackageError.unreadable(error.localizedDescription)
        }
    }

    static func candidates(from data: Data) throws -> [AppleContactLeadCandidate] {
        let package: MacContactLeadPackage
        do {
            package = try JSONDecoder().decode(MacContactLeadPackage.self, from: data)
        } catch {
            throw MacContactLeadPackageError.invalidPackage
        }

        guard package.schemaVersion == MacContactLeadPackage.currentSchemaVersion else {
            throw MacContactLeadPackageError.unsupportedSchema(package.schemaVersion)
        }

        var seenIdentifiers: Set<String> = []
        return package.contacts
            .compactMap { record -> AppleContactLeadCandidate? in
                guard seenIdentifiers.insert(record.identifier).inserted else { return nil }
                return candidate(from: record)
            }
            .sorted {
                $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
            }
    }

    static func candidate(from record: MacContactPackageRecord) -> AppleContactLeadCandidate? {
        guard let identifier = cleaned(record.identifier) else { return nil }

        let componentName = [record.firstName, record.middleName, record.lastName]
            .compactMap(cleaned)
            .joined(separator: " ")
        let rawDisplayName = cleaned(record.name)
            ?? cleaned(componentName)
            ?? cleaned(record.nickname)
            ?? cleaned(record.organization)
            ?? "Apple Contact"
        let note = cleaned(record.note)
        let searchableFields = [
            rawDisplayName,
            record.nickname,
            record.organization,
            record.department,
            record.jobTitle,
            note
        ].compactMap { $0 }

        guard let service = AppleContactLeadMatchPolicy.matchedService(in: searchableFields) else {
            return nil
        }

        let displayName = [rawDisplayName, record.nickname, record.organization]
            .compactMap(AppleContactLeadMatchPolicy.sanitizedLeadName)
            .first ?? "Apple Contact"

        return AppleContactLeadCandidate(
            id: identifier,
            displayName: displayName,
            phone: preferredValue(record.phoneNumbers, kind: .phone),
            email: preferredValue(record.emailAddresses, kind: .email),
            address: preferredAddress(record.postalAddresses),
            service: service,
            notes: note,
            price: AppleContactLeadPricePolicy.resolvedPrice(
                explicitPrice: record.price,
                note: note
            ),
            coordinate: nil
        )
    }

    private enum LabeledValueKind {
        case phone
        case email
    }

    private static func preferredValue(
        _ values: [MacContactPackageLabeledValue]?,
        kind: LabeledValueKind
    ) -> String? {
        values?
            .sorted { priority(for: $0.label, kind: kind) < priority(for: $1.label, kind: kind) }
            .compactMap { cleaned($0.value) }
            .first
    }

    private static func preferredAddress(_ addresses: [MacContactPackageAddress]?) -> String? {
        addresses?
            .sorted { addressPriority($0.label) < addressPriority($1.label) }
            .compactMap(formattedAddress)
            .first
    }

    private static func formattedAddress(_ address: MacContactPackageAddress) -> String? {
        if let formatted = cleaned(address.formatted) {
            return formatted
                .components(separatedBy: .newlines)
                .compactMap(cleaned)
                .joined(separator: ", ")
        }

        let region = [cleaned(address.state), cleaned(address.postalCode)]
            .compactMap { $0 }
            .joined(separator: " ")
        return [
            cleaned(address.street)?.replacingOccurrences(of: "\r", with: ", "),
            cleaned(address.city),
            cleaned(region),
            cleaned(address.country)
        ]
        .compactMap { $0 }
        .joined(separator: ", ")
        .nilIfEmpty
    }

    private static func priority(for label: String?, kind: LabeledValueKind) -> Int {
        let normalized = normalizedLabel(label)
        switch kind {
        case .phone:
            if normalized.contains("mobile") || normalized.contains("iphone") { return 0 }
            if normalized.contains("main") || normalized.contains("work") { return 1 }
            if normalized.contains("home") { return 2 }
        case .email:
            if normalized.contains("home") { return 0 }
            if normalized.contains("work") { return 1 }
        }
        return 3
    }

    private static func addressPriority(_ label: String?) -> Int {
        let normalized = normalizedLabel(label)
        if normalized.contains("home") { return 0 }
        if normalized.contains("work") { return 1 }
        return 2
    }

    private static func normalizedLabel(_ value: String?) -> String {
        value?
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
            .filter { $0.isLetter || $0.isNumber } ?? ""
    }

    private static func cleaned(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
