import Contacts
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
    let note: String?
    let service: AppleContactLeadServiceKind
    var coordinate: AppleContactLeadCoordinate?
    var didAttemptGeocoding = false

    var isReadyForImport: Bool {
        address != nil && coordinate?.isValid == true
    }
}

struct AppleContactLeadScanResult: Sendable {
    let candidates: [AppleContactLeadCandidate]
    let hasLimitedAccess: Bool
    let didScanNotes: Bool
}

private struct AppleContactLeadFetchResult: Sendable {
    let candidates: [AppleContactLeadCandidate]
    let didScanNotes: Bool
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

struct AppleContactLeadDuplicateIndex: Sendable {
    private let phones: Set<String>
    private let emails: Set<String>
    private let addresses: Set<String>

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
}

enum AppleContactLeadMatchPolicy {
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

    private static func cleaned(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }
}

final class AppleContactLeadImportService {
    static let shared = AppleContactLeadImportService()

    private init() {}

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
            let fetchResult = try await Task.detached(priority: .userInitiated) {
                try Self.fetchMatchingContactsPreferringNotes()
            }.value
            return AppleContactLeadScanResult(
                candidates: fetchResult.candidates,
                hasLimitedAccess: status == .limited,
                didScanNotes: fetchResult.didScanNotes
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

    private static func fetchMatchingContactsPreferringNotes() throws -> AppleContactLeadFetchResult {
        do {
            return AppleContactLeadFetchResult(
                candidates: try fetchMatchingContacts(includeNotes: true),
                didScanNotes: true
            )
        } catch {
            guard isUnauthorizedNotesError(error) else { throw error }
            return AppleContactLeadFetchResult(
                candidates: try fetchMatchingContacts(includeNotes: false),
                didScanNotes: false
            )
        }
    }

    private static func fetchMatchingContacts(includeNotes: Bool) throws -> [AppleContactLeadCandidate] {
        var keys: [CNKeyDescriptor] = [
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
        if includeNotes {
            keys.append(CNContactNoteKey as CNKeyDescriptor)
        }

        let request = CNContactFetchRequest(keysToFetch: keys)
        request.unifyResults = true
        request.sortOrder = .userDefault

        var matches: [AppleContactLeadCandidate] = []
        try CNContactStore().enumerateContacts(with: request) { contact, _ in
            guard let candidate = candidate(from: contact, includeNotes: includeNotes) else { return }
            matches.append(candidate)
        }
        return matches
    }

    private static func isUnauthorizedNotesError(_ error: Error) -> Bool {
        let nsError = error as NSError
        return nsError.domain == CNErrorDomain && nsError.code == CNError.Code.unauthorizedKeys.rawValue
    }

    static func candidate(from contact: CNContact, includeNotes: Bool = false) -> AppleContactLeadCandidate? {
        let displayName = displayName(for: contact)
        let note = includeNotes ? cleaned(contact.note) : nil
        let searchableFields = [
            displayName,
            contact.nickname,
            contact.organizationName,
            contact.departmentName,
            contact.jobTitle,
            note ?? ""
        ]

        guard let service = AppleContactLeadMatchPolicy.matchedService(in: searchableFields) else {
            return nil
        }

        return AppleContactLeadCandidate(
            id: contact.identifier,
            displayName: displayName,
            phone: preferredPhone(from: contact),
            email: preferredEmail(from: contact),
            address: preferredAddress(from: contact),
            note: note,
            service: service,
            coordinate: nil
        )
    }

    private static func cleaned(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
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
