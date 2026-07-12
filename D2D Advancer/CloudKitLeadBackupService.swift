import Foundation
import CloudKit

enum CloudKitLeadBackupError: LocalizedError {
    case accountUnavailable(CKAccountStatus)

    var errorDescription: String? {
        switch self {
        case .accountUnavailable(let status):
            return "CloudKit account unavailable (\(status.rawValue))."
        }
    }
}

final class CloudKitLeadBackupService {
    static let shared = CloudKitLeadBackupService()
    static let containerIdentifier = "iCloud.com.dan1sland.d2d.advancer"

    private let container: CKContainer
    private let database: CKDatabase

    private let recordType = "LeadBackup"
    private let batchSize = 200

    private init(container: CKContainer = CKContainer(identifier: CloudKitLeadBackupService.containerIdentifier)) {
        self.container = container
        self.database = container.privateCloudDatabase
    }

    func uploadLeads(_ payloads: [LeadSyncPayload], for userId: String) async throws -> Int {
        guard !payloads.isEmpty else { return 0 }

        try await ensureCloudKitAccountAvailable()
        var savedCount = 0

        for startIndex in stride(from: 0, to: payloads.count, by: batchSize) {
            let endIndex = min(startIndex + batchSize, payloads.count)
            let batch = Array(payloads[startIndex..<endIndex])
            let records = batch.map { record(from: $0, userId: userId) }
            try await saveRecords(records)
            savedCount += records.count
        }

        return savedCount
    }

    func fetchLeads(for userId: String) async throws -> [LeadSyncPayload] {
        try await ensureCloudKitAccountAvailable()

        let predicate = NSPredicate(format: "userId == %@", userId)
        let records = try await fetchRecords(predicate: predicate)

        return records.compactMap { decodePayload(from: $0) }
    }

    func deleteLead(_ leadId: UUID, for userId: String) async throws {
        try await ensureCloudKitAccountAvailable()

        let recordId = CKRecord.ID(recordName: "\(userId)_\(leadId.uuidString)")
        try await deleteRecords(recordIds: [recordId])
    }

    private func ensureCloudKitAccountAvailable() async throws {
        let status = try await container.accountStatus()
        guard status == .available else {
            throw CloudKitLeadBackupError.accountUnavailable(status)
        }
    }

    private func record(from payload: LeadSyncPayload, userId: String) -> CKRecord {
        let recordId = CKRecord.ID(recordName: "\(userId)_\(payload.id.uuidString)")
        let record = CKRecord(recordType: recordType, recordID: recordId)

        record["userId"] = userId
        record["leadId"] = payload.id.uuidString
        record["name"] = payload.name
        record["address"] = payload.address
        record["phone"] = payload.phone
        record["email"] = payload.email
        record["latitude"] = NSNumber(value: payload.latitude)
        record["longitude"] = NSNumber(value: payload.longitude)
        record["status"] = payload.status.isEmpty ? "not_contacted" : payload.status
        record["notes"] = payload.notes
        record["createdDate"] = payload.createdDate
        record["updatedDate"] = payload.updatedDate
        record["priority"] = NSNumber(value: payload.priority)
        record["source"] = payload.source
        record["estimatedValue"] = NSNumber(value: payload.estimatedValue)
        record["price"] = NSNumber(value: payload.price)
        record["tags"] = payload.tags
        record["visitCount"] = NSNumber(value: payload.visitCount)

        if let serviceCategory = payload.serviceCategory, !serviceCategory.isEmpty {
            record["serviceCategory"] = serviceCategory
        } else {
            record["serviceCategory"] = nil
        }

        if let neighborhoodId = payload.neighborhoodId, !neighborhoodId.isEmpty {
            record["neighborhoodId"] = neighborhoodId
        } else {
            record["neighborhoodId"] = nil
        }

        if let lastContactDate = payload.lastContactDate {
            record["lastContactDate"] = lastContactDate
        } else {
            record["lastContactDate"] = nil
        }

        if let followUpDate = payload.followUpDate {
            record["followUpDate"] = followUpDate
        } else {
            record["followUpDate"] = nil
        }

        record["checkInsJSON"] = encodeCheckInsJSON(payload.checkIns)

        return record
    }

    private func decodePayload(from record: CKRecord) -> LeadSyncPayload? {
        let leadIdString: String
        if let value = record["leadId"] as? String {
            leadIdString = value
        } else {
            let pieces = record.recordID.recordName.split(separator: "_", maxSplits: 1)
            guard pieces.count == 2 else { return nil }
            leadIdString = String(pieces[1])
        }

        guard let leadId = UUID(uuidString: leadIdString) else {
            return nil
        }

        let createdDate = (record["createdDate"] as? Date) ?? Date()
        let updatedDate = (record["updatedDate"] as? Date) ?? createdDate
        let checkInsJSON = record["checkInsJSON"] as? String
        let checkIns = decodeCheckInsJSON(checkInsJSON)
        let includesCheckInsSchema = checkInsJSON != nil

        return LeadSyncPayload(
            id: leadId,
            name: stringValue(record["name"]),
            address: stringValue(record["address"]),
            phone: stringValue(record["phone"]),
            email: stringValue(record["email"]),
            latitude: doubleValue(record["latitude"]),
            longitude: doubleValue(record["longitude"]),
            status: {
                let remoteStatus = stringValue(record["status"])
                return remoteStatus.isEmpty ? "not_contacted" : remoteStatus
            }(),
            notes: stringValue(record["notes"]),
            createdDate: createdDate,
            updatedDate: updatedDate,
            priority: int16Value(record["priority"]),
            source: stringValue(record["source"]),
            estimatedValue: doubleValue(record["estimatedValue"]),
            price: doubleValue(record["price"]),
            tags: stringValue(record["tags"]),
            visitCount: int16Value(record["visitCount"]),
            serviceCategory: optionalStringValue(record["serviceCategory"]),
            neighborhoodId: optionalStringValue(record["neighborhoodId"]),
            lastContactDate: record["lastContactDate"] as? Date,
            followUpDate: record["followUpDate"] as? Date,
            checkIns: checkIns,
            includesCheckInsSchema: includesCheckInsSchema
        )
    }

    private func saveRecords(_ records: [CKRecord]) async throws {
        guard !records.isEmpty else { return }

        try await withCheckedThrowingContinuation { continuation in
            let operation = CKModifyRecordsOperation(recordsToSave: records, recordIDsToDelete: nil)
            operation.savePolicy = .changedKeys
            operation.isAtomic = false
            operation.qualityOfService = .utility
            operation.modifyRecordsResultBlock = { result in
                switch result {
                case .success:
                    continuation.resume(returning: ())
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
            database.add(operation)
        }
    }

    private func deleteRecords(recordIds: [CKRecord.ID]) async throws {
        guard !recordIds.isEmpty else { return }

        try await withCheckedThrowingContinuation { continuation in
            let operation = CKModifyRecordsOperation(recordsToSave: nil, recordIDsToDelete: recordIds)
            operation.isAtomic = false
            operation.qualityOfService = .utility
            operation.modifyRecordsResultBlock = { result in
                switch result {
                case .success:
                    continuation.resume(returning: ())
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
            database.add(operation)
        }
    }

    private func fetchRecords(predicate: NSPredicate) async throws -> [CKRecord] {
        try await withCheckedThrowingContinuation { continuation in
            var fetchedRecords: [CKRecord] = []
            let lock = NSLock()
            var hasResumed = false

            func resumeOnce(with result: Result<[CKRecord], Error>) {
                guard !hasResumed else { return }
                hasResumed = true
                continuation.resume(with: result)
            }

            func runQuery(cursor: CKQueryOperation.Cursor?) {
                let operation: CKQueryOperation
                if let cursor {
                    operation = CKQueryOperation(cursor: cursor)
                } else {
                    let query = CKQuery(recordType: recordType, predicate: predicate)
                    query.sortDescriptors = [NSSortDescriptor(key: "updatedDate", ascending: false)]
                    operation = CKQueryOperation(query: query)
                }

                operation.resultsLimit = batchSize
                operation.qualityOfService = .utility

                operation.recordMatchedBlock = { _, result in
                    switch result {
                    case .success(let record):
                        lock.lock()
                        fetchedRecords.append(record)
                        lock.unlock()
                    case .failure:
                        // Ignore per-record failures so we can continue with the rest.
                        break
                    }
                }

                operation.queryResultBlock = { result in
                    switch result {
                    case .success(let nextCursor):
                        if let nextCursor {
                            runQuery(cursor: nextCursor)
                        } else {
                            resumeOnce(with: .success(fetchedRecords))
                        }
                    case .failure(let error):
                        resumeOnce(with: .failure(error))
                    }
                }

                database.add(operation)
            }

            runQuery(cursor: nil)
        }
    }

    private func stringValue(_ value: Any?) -> String {
        if let string = value as? String {
            return string
        }
        if let number = value as? NSNumber {
            return number.stringValue
        }
        return ""
    }

    private func optionalStringValue(_ value: Any?) -> String? {
        let normalized = stringValue(value).trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? nil : normalized
    }

    private func doubleValue(_ value: Any?) -> Double {
        if let double = value as? Double {
            return double
        }
        if let number = value as? NSNumber {
            return number.doubleValue
        }
        if let string = value as? String, let parsed = Double(string) {
            return parsed
        }
        return 0
    }

    private func int16Value(_ value: Any?) -> Int16 {
        if let int16 = value as? Int16 {
            return int16
        }
        if let int = value as? Int {
            return Int16(clamping: int)
        }
        if let int64 = value as? Int64 {
            return Int16(clamping: Int(int64))
        }
        if let number = value as? NSNumber {
            return Int16(clamping: number.intValue)
        }
        if let string = value as? String, let parsed = Int(string) {
            return Int16(clamping: parsed)
        }
        return 0
    }

    private func encodeCheckInsJSON(_ checkIns: [LeadCheckInSyncPayload]) -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(checkIns),
              let json = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return json
    }

    private func decodeCheckInsJSON(_ json: String?) -> [LeadCheckInSyncPayload] {
        guard let json, !json.isEmpty, let data = json.data(using: .utf8) else {
            return []
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([LeadCheckInSyncPayload].self, from: data)) ?? []
    }
}
