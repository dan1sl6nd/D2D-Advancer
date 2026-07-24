import Foundation
import CloudKit

final class CloudKitAppointmentBackupService {
    static let shared: CloudKitAppointmentBackupService? = {
        guard let container = CloudKitLeadBackupService.makeEntitledContainer() else { return nil }
        return CloudKitAppointmentBackupService(container: container)
    }()

    private let container: CKContainer
    private let database: CKDatabase

    private let recordType = "AppointmentBackup"
    private let batchSize = 200

    private init(container: CKContainer) {
        self.container = container
        self.database = container.privateCloudDatabase
    }

    func uploadAppointment(_ payload: AppointmentSyncPayload, for userId: String) async throws {
        _ = try await uploadAppointments([payload], for: userId)
    }

    func uploadAppointments(_ payloads: [AppointmentSyncPayload], for userId: String) async throws -> Int {
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

    func fetchAppointments(for userId: String) async throws -> [AppointmentSyncPayload] {
        try await ensureCloudKitAccountAvailable()

        let records: [CKRecord]
        do {
            records = try await fetchRecords(predicate: NSPredicate(value: true))
                .filter { recordBelongsToUser($0, userId: userId) }
        } catch {
            guard CloudKitQueryCompatibility.isRecordNameNotQueryableError(error) else {
                throw error
            }

            print("☁️ CloudKit appointment restore scan skipped: recordName is not queryable in this schema. Continuing with direct record-ID backup uploads.")
            return []
        }

        return records.compactMap(decodePayload(from:))
    }

    func deleteAppointment(_ appointmentId: UUID, for userId: String) async throws {
        try await ensureCloudKitAccountAvailable()
        let recordId = CKRecord.ID(recordName: "\(userId)_\(appointmentId.uuidString)")
        try await deleteRecords(recordIds: [recordId])
    }

    func deleteAllAppointments(for userId: String) async throws {
        try await ensureCloudKitAccountAvailable()
        let records = try await fetchRecords(predicate: NSPredicate(value: true))
            .filter { recordBelongsToUser($0, userId: userId) }
        let recordIds = records.map(\.recordID)
        try await deleteRecords(recordIds: recordIds)
    }

    private func recordBelongsToUser(_ record: CKRecord, userId: String) -> Bool {
        stringValue(record["userId"]) == userId || record.recordID.recordName.hasPrefix("\(userId)_")
    }

    private func ensureCloudKitAccountAvailable() async throws {
        let status = try await container.accountStatus()
        guard status == .available else {
            throw CloudKitLeadBackupError.accountUnavailable(status)
        }
    }

    private func record(from payload: AppointmentSyncPayload, userId: String) -> CKRecord {
        let recordId = CKRecord.ID(recordName: "\(userId)_\(payload.id.uuidString)")
        let record = CKRecord(recordType: recordType, recordID: recordId)

        record["userId"] = userId
        record["appointmentId"] = payload.id.uuidString
        record["title"] = payload.title
        record["notes"] = payload.notes
        record["startDate"] = payload.startDate
        record["endDate"] = payload.endDate
        record["location"] = payload.location
        record["appointmentType"] = payload.appointmentType
        record["status"] = payload.status
        record["updatedAt"] = payload.updatedAt

        if let leadId = payload.leadId {
            record["leadId"] = leadId.uuidString
        } else {
            record["leadId"] = nil
        }

        if let calendarEventId = payload.calendarEventId, !calendarEventId.isEmpty {
            record["calendarEventId"] = calendarEventId
        } else {
            record["calendarEventId"] = nil
        }

        if let customAppointmentTypeId = payload.customAppointmentTypeId, !customAppointmentTypeId.isEmpty {
            record["customAppointmentTypeId"] = customAppointmentTypeId
        } else {
            record["customAppointmentTypeId"] = nil
        }

        return record
    }

    private func decodePayload(from record: CKRecord) -> AppointmentSyncPayload? {
        let appointmentId: UUID
        if let appointmentIdString = record["appointmentId"] as? String,
           let parsed = UUID(uuidString: appointmentIdString) {
            appointmentId = parsed
        } else {
            let pieces = record.recordID.recordName.split(separator: "_", maxSplits: 1)
            guard pieces.count == 2, let parsed = UUID(uuidString: String(pieces[1])) else {
                return nil
            }
            appointmentId = parsed
        }

        guard let startDate = record["startDate"] as? Date,
              let endDate = record["endDate"] as? Date else {
            return nil
        }

        let updatedAt = (record["updatedAt"] as? Date) ?? endDate

        return AppointmentSyncPayload(
            id: appointmentId,
            title: stringValue(record["title"]),
            notes: stringValue(record["notes"]),
            startDate: startDate,
            endDate: endDate,
            location: stringValue(record["location"]),
            leadId: uuidValue(record["leadId"]),
            calendarEventId: optionalStringValue(record["calendarEventId"]),
            appointmentType: {
                let type = stringValue(record["appointmentType"])
                return type.isEmpty ? Appointment.AppointmentType.consultation.rawValue : type
            }(),
            customAppointmentTypeId: optionalStringValue(record["customAppointmentTypeId"]),
            status: {
                let status = stringValue(record["status"])
                return status.isEmpty ? Appointment.AppointmentStatus.scheduled.rawValue : status
            }(),
            updatedAt: updatedAt
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

    private func uuidValue(_ value: Any?) -> UUID? {
        guard let value = optionalStringValue(value) else {
            return nil
        }
        return UUID(uuidString: value)
    }
}
