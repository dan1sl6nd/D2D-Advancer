import Foundation
import CloudKit

final class CloudKitAccountBackupService {
    static let shared = CloudKitAccountBackupService()

    private let container: CKContainer
    private let database: CKDatabase

    private let recordType = "AccountProfileBackup"

    private init(container: CKContainer = CKContainer(identifier: CloudKitLeadBackupService.containerIdentifier)) {
        self.container = container
        self.database = container.privateCloudDatabase
    }

    func uploadProfile(_ payload: AccountProfileSyncPayload) async throws {
        try await ensureCloudKitAccountAvailable()

        let record = CKRecord(
            recordType: recordType,
            recordID: CKRecord.ID(recordName: payload.userId)
        )

        record["userId"] = payload.userId
        record["email"] = payload.email
        record["displayName"] = payload.displayName
        record["isEmailVerified"] = NSNumber(value: payload.isEmailVerified)
        record["isPremium"] = NSNumber(value: payload.isPremium)
        record["onboardingCompleted"] = NSNumber(value: payload.onboardingCompleted)
        record["createdAt"] = payload.createdAt
        record["updatedAt"] = payload.updatedAt

        if let onboardingProfileJSON = payload.onboardingProfileJSON, !onboardingProfileJSON.isEmpty {
            record["onboardingProfileJSON"] = onboardingProfileJSON
        } else {
            record["onboardingProfileJSON"] = nil
        }

        if let preferencesJSON = payload.preferencesJSON, !preferencesJSON.isEmpty {
            record["preferencesJSON"] = preferencesJSON
        } else {
            record["preferencesJSON"] = nil
        }

        if let lastSignInAt = payload.lastSignInAt {
            record["lastSignInAt"] = lastSignInAt
        } else {
            record["lastSignInAt"] = nil
        }

        try await save(record)
    }

    func fetchProfile(for userId: String) async throws -> AccountProfileSyncPayload? {
        try await ensureCloudKitAccountAvailable()

        let recordId = CKRecord.ID(recordName: userId)
        let record: CKRecord
        do {
            record = try await database.record(for: recordId)
        } catch let error as CKError {
            if error.code == .unknownItem {
                return nil
            }
            throw error
        }

        let createdAt = (record["createdAt"] as? Date) ?? Date()
        let updatedAt = (record["updatedAt"] as? Date) ?? createdAt

        return AccountProfileSyncPayload(
            userId: userId,
            email: stringValue(record["email"]),
            displayName: stringValue(record["displayName"]),
            isEmailVerified: boolValue(record["isEmailVerified"]),
            isPremium: boolValue(record["isPremium"]),
            onboardingCompleted: boolValue(record["onboardingCompleted"]),
            onboardingProfileJSON: optionalStringValue(record["onboardingProfileJSON"]),
            preferencesJSON: optionalStringValue(record["preferencesJSON"]),
            createdAt: createdAt,
            updatedAt: updatedAt,
            lastSignInAt: record["lastSignInAt"] as? Date
        )
    }

    private func ensureCloudKitAccountAvailable() async throws {
        let status = try await container.accountStatus()
        guard status == .available else {
            throw CloudKitLeadBackupError.accountUnavailable(status)
        }
    }

    private func save(_ record: CKRecord) async throws {
        try await withCheckedThrowingContinuation { continuation in
            let operation = CKModifyRecordsOperation(recordsToSave: [record], recordIDsToDelete: nil)
            operation.savePolicy = .changedKeys
            operation.isAtomic = true
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

    private func boolValue(_ value: Any?) -> Bool {
        if let bool = value as? Bool {
            return bool
        }
        if let number = value as? NSNumber {
            return number.boolValue
        }
        if let string = value as? String {
            return NSString(string: string).boolValue
        }
        return false
    }
}
