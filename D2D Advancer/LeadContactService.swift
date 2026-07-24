import Contacts
import Foundation

struct LeadContactPayload {
    let displayName: String
    let name: String?
    let phone: String?
    let email: String?
    let address: String?
    let notes: String?
    let price: Double
    let statusDisplayName: String
    let serviceCategoryName: String?
}

enum LeadContactSaveResult: Equatable {
    case saved
    case permissionDenied
    case failed(String)

    var title: String {
        switch self {
        case .saved:
            return "Contact Created"
        case .permissionDenied:
            return "Contacts Access Needed"
        case .failed:
            return "Could Not Create Contact"
        }
    }

    var message: String {
        switch self {
        case .saved:
            return "This lead was saved to your Contacts app."
        case .permissionDenied:
            return "Allow Contacts access in Settings to save leads as contacts."
        case .failed(let reason):
            return reason
        }
    }
}

enum LeadContactService {
    static func canCreateContactFromLeadDetail(_ lead: Lead) -> Bool {
        hasText(lead.phone)
    }

    static func payload(for lead: Lead) -> LeadContactPayload {
        LeadContactPayload(
            displayName: lead.displayName,
            name: cleaned(lead.name),
            phone: cleaned(lead.phone),
            email: cleaned(lead.email),
            address: cleaned(lead.address),
            notes: cleaned(lead.notes),
            price: lead.price,
            statusDisplayName: lead.leadStatus.displayName,
            serviceCategoryName: cleaned(lead.serviceCategoryObject?.name)
        )
    }

    static func makeContact(
        from payload: LeadContactPayload,
        createdAt: Date = Date()
    ) -> CNMutableContact {
        let contact = CNMutableContact()

        applyName(from: payload, to: contact)

        if let phone = payload.phone {
            let phoneNumber = CNPhoneNumber(stringValue: phone)
            contact.phoneNumbers = [CNLabeledValue(label: CNLabelWork, value: phoneNumber)]
        }

        if let email = payload.email {
            contact.emailAddresses = [CNLabeledValue(label: CNLabelWork, value: email as NSString)]
        }

        if let address = payload.address {
            let postalAddress = CNMutablePostalAddress()
            postalAddress.street = address
            contact.postalAddresses = [CNLabeledValue(label: CNLabelWork, value: postalAddress as CNPostalAddress)]
        }

        contact.note = noteText(for: payload, createdAt: createdAt)
        contact.organizationName = "D2D Lead"

        return contact
    }

    static func createContact(
        for lead: Lead,
        completion: @escaping (LeadContactSaveResult) -> Void
    ) {
        createContact(from: payload(for: lead), completion: completion)
    }

    static func createContact(
        from payload: LeadContactPayload,
        store: CNContactStore = CNContactStore(),
        completion: @escaping (LeadContactSaveResult) -> Void
    ) {
        store.requestAccess(for: .contacts) { granted, error in
            if let error {
                complete(.failed(error.localizedDescription), completion: completion)
                return
            }

            guard granted else {
                complete(.permissionDenied, completion: completion)
                return
            }

            let saveRequest = CNSaveRequest()
            saveRequest.add(makeContact(from: payload), toContainerWithIdentifier: nil)

            do {
                try store.execute(saveRequest)
                complete(.saved, completion: completion)
            } catch {
                complete(.failed(error.localizedDescription), completion: completion)
            }
        }
    }

    private static func applyName(from payload: LeadContactPayload, to contact: CNMutableContact) {
        if let name = payload.name {
            let components = name
                .split(separator: " ")
                .map(String.init)

            contact.givenName = components.first ?? ""

            if let serviceCategoryName = payload.serviceCategoryName {
                contact.familyName = serviceCategoryName
            } else if components.count > 1 {
                contact.familyName = components.dropFirst().joined(separator: " ")
            }
        } else if let serviceCategoryName = payload.serviceCategoryName {
            contact.givenName = "Lead"
            contact.familyName = serviceCategoryName
        }
    }

    private static func noteText(for payload: LeadContactPayload, createdAt: Date) -> String {
        var notes: [String] = [
            "D2D Lead - \(createdAt.formatted(.dateTime.day().month().year()))"
        ]

        if let note = payload.notes {
            notes.append("Notes: \(note)")
        }

        if payload.price > 0 {
            let formatter = NumberFormatter()
            formatter.numberStyle = .currency
            if let priceString = formatter.string(from: NSNumber(value: payload.price)) {
                notes.append("Quote: \(priceString)")
            }
        }

        notes.append("Status: \(payload.statusDisplayName)")

        if let serviceCategoryName = payload.serviceCategoryName {
            notes.append("Service: \(serviceCategoryName)")
        }

        return notes.joined(separator: "\n")
    }

    private static func complete(
        _ result: LeadContactSaveResult,
        completion: @escaping (LeadContactSaveResult) -> Void
    ) {
        DispatchQueue.main.async {
            completion(result)
        }
    }

    private static func hasText(_ value: String?) -> Bool {
        cleaned(value) != nil
    }

    private static func cleaned(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }
}
