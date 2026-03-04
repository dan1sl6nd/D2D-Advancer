import Foundation

/// Canonical follow-up check-in payload nested under a lead sync payload.
struct LeadCheckInSyncPayload: Sendable, Codable {
    let id: UUID
    let checkInDate: Date
    let checkInType: String
    let outcome: String?
    let notes: String?
    let scheduledNextFollowUp: Date?

    var syncDictionary: [String: Any] {
        var data: [String: Any] = [
            "id": id.uuidString,
            "checkInDate": checkInDate,
            "checkInType": checkInType
        ]

        if let outcome {
            data["outcome"] = outcome
        }

        if let notes {
            data["notes"] = notes
        }

        if let scheduledNextFollowUp {
            data["scheduledNextFollowUp"] = scheduledNextFollowUp
        }

        return data
    }
}

/// Canonical lead payload used by all cloud sync providers.
struct LeadSyncPayload: Sendable {
    let id: UUID
    let name: String
    let address: String
    let phone: String
    let email: String
    let latitude: Double
    let longitude: Double
    let status: String
    let notes: String
    let createdDate: Date
    let updatedDate: Date
    let priority: Int16
    let source: String
    let estimatedValue: Double
    let price: Double
    let tags: String
    let visitCount: Int16
    let serviceCategory: String?
    let neighborhoodId: String?
    let lastContactDate: Date?
    let followUpDate: Date?
    let checkIns: [LeadCheckInSyncPayload]
    let includesCheckInsSchema: Bool

    init(
        id: UUID,
        name: String,
        address: String,
        phone: String,
        email: String,
        latitude: Double,
        longitude: Double,
        status: String,
        notes: String,
        createdDate: Date,
        updatedDate: Date,
        priority: Int16,
        source: String,
        estimatedValue: Double,
        price: Double,
        tags: String,
        visitCount: Int16,
        serviceCategory: String?,
        neighborhoodId: String?,
        lastContactDate: Date?,
        followUpDate: Date?,
        checkIns: [LeadCheckInSyncPayload],
        includesCheckInsSchema: Bool = true
    ) {
        self.id = id
        self.name = name
        self.address = address
        self.phone = phone
        self.email = email
        self.latitude = latitude
        self.longitude = longitude
        self.status = status
        self.notes = notes
        self.createdDate = createdDate
        self.updatedDate = updatedDate
        self.priority = priority
        self.source = source
        self.estimatedValue = estimatedValue
        self.price = price
        self.tags = tags
        self.visitCount = visitCount
        self.serviceCategory = serviceCategory
        self.neighborhoodId = neighborhoodId
        self.lastContactDate = lastContactDate
        self.followUpDate = followUpDate
        self.checkIns = checkIns
        self.includesCheckInsSchema = includesCheckInsSchema
    }

    private var normalizedStatus: String {
        status.isEmpty ? "not_contacted" : status
    }

    var firestoreData: [String: Any] {
        var data: [String: Any] = [
            "name": name,
            "address": address,
            "phone": phone,
            "email": email,
            "latitude": latitude,
            "longitude": longitude,
            "status": normalizedStatus,
            "notes": notes,
            "createdDate": createdDate,
            "updatedDate": updatedDate,
            // Keep legacy keys for backwards compatibility.
            "dateCreated": createdDate,
            "dateModified": updatedDate,
            "priority": Int(priority),
            "source": source,
            "estimatedValue": estimatedValue,
            "price": price,
            "tags": tags,
            "visitCount": Int(visitCount),
            "serviceCategory": serviceCategory ?? "",
            "neighborhoodId": neighborhoodId ?? ""
        ]

        if let lastContactDate {
            data["lastContactDate"] = lastContactDate
        }

        if let followUpDate {
            data["followUpDate"] = followUpDate
        }

        if includesCheckInsSchema {
            data["checkInsSchemaVersion"] = 1
            data["checkIns"] = checkIns.map(\.syncDictionary)
        }

        return data
    }

    var syncDictionary: [String: Any] {
        firestoreData
    }
}
