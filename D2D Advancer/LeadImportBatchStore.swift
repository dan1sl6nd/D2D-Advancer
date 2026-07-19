import Combine
import CoreData
import CryptoKit
import Foundation

enum LeadImportSource: String, Codable, Sendable {
    case csv
    case appleContactsDevice
    case appleContactsMac

    var displayName: String {
        switch self {
        case .csv:
            return "CSV"
        case .appleContactsDevice:
            return "Apple Contacts"
        case .appleContactsMac:
            return "Mac Contacts"
        }
    }
}

struct LeadImportSnapshot: Codable, Equatable, Sendable {
    let id: UUID
    let name: String?
    let phone: String?
    let email: String?
    let address: String?
    let status: String
    let priority: Int16
    let price: Double
    let estimatedValue: Double
    let visitCount: Int16
    let source: String?
    let serviceCategory: String?
    let tags: String?
    let notes: String?
    let latitude: Double
    let longitude: Double
    let createdDate: Date?
    let updatedDate: Date?
    let followUpDate: Date?
    let lastContactDate: Date?
    let dateCreated: Date?
    let dateModified: Date?
    let mutationGuard: LeadImportMutationGuard

    @MainActor
    init?(lead: Lead) {
        guard let id = lead.id else { return nil }
        self.id = id
        name = lead.name
        phone = lead.phone
        email = lead.email
        address = lead.address
        status = lead.status ?? Lead.Status.notContacted.rawValue
        priority = lead.priority
        price = lead.price
        estimatedValue = lead.estimatedValue
        visitCount = lead.visitCount
        source = lead.source
        serviceCategory = lead.serviceCategory
        tags = lead.tags
        notes = lead.notes
        latitude = lead.latitude
        longitude = lead.longitude
        createdDate = lead.createdDate
        updatedDate = lead.updatedDate
        followUpDate = lead.followUpDate
        lastContactDate = lead.lastContactDate
        dateCreated = lead.dateCreated
        dateModified = lead.dateModified
        mutationGuard = LeadImportMutationGuard(lead: lead)
    }

    @MainActor
    func apply(to lead: Lead) {
        lead.id = id
        lead.name = name
        lead.phone = phone
        lead.email = email
        lead.address = address
        lead.status = status
        lead.priority = priority
        lead.price = price
        lead.estimatedValue = estimatedValue
        lead.visitCount = visitCount
        lead.source = source
        lead.serviceCategory = serviceCategory
        lead.tags = tags
        lead.notes = notes
        lead.latitude = latitude
        lead.longitude = longitude
        lead.createdDate = createdDate
        lead.updatedDate = updatedDate
        lead.followUpDate = followUpDate
        lead.lastContactDate = lastContactDate
        lead.dateCreated = dateCreated
        lead.dateModified = dateModified
    }
}

struct LeadImportMutationGuard: Codable, Equatable, Sendable {
    struct CheckIn: Codable, Equatable, Sendable {
        let id: UUID?
        let checkInDate: Date?
        let checkInType: String?
        let notes: String?
        let outcome: String?
        let scheduledNextFollowUp: Date?
    }

    let neighborhoodID: UUID?
    let neighborhoodReference: String?
    let photoDigest: String?
    let photoCapturedDate: Date?
    let voiceNoteDigest: String?
    let voiceNoteCapturedDate: Date?
    let voiceNoteTranscript: String?
    let checkIns: [CheckIn]

    @MainActor
    init(lead: Lead) {
        neighborhoodID = lead.neighborhood?.id
        neighborhoodReference = lead.neighborhoodId
        photoDigest = Self.digest(lead.photo)
        photoCapturedDate = lead.photoCapturedDate
        voiceNoteDigest = Self.digest(lead.voiceNote)
        voiceNoteCapturedDate = lead.voiceNoteCapturedDate
        voiceNoteTranscript = lead.voiceNoteTranscript
        checkIns = (lead.checkIns?.allObjects as? [FollowUpCheckIn] ?? [])
            .map {
                CheckIn(
                    id: $0.id,
                    checkInDate: $0.checkInDate,
                    checkInType: $0.checkInType,
                    notes: $0.notes,
                    outcome: $0.outcome,
                    scheduledNextFollowUp: $0.scheduledNextFollowUp
                )
            }
            .sorted { lhs, rhs in
                let left = lhs.id?.uuidString ?? ""
                let right = rhs.id?.uuidString ?? ""
                if left != right { return left < right }
                return (lhs.checkInDate ?? .distantPast) < (rhs.checkInDate ?? .distantPast)
            }
    }

    private static func digest(_ data: Data?) -> String? {
        guard let data, !data.isEmpty else { return nil }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

struct LeadImportBatch: Codable, Identifiable, Equatable, Sendable {
    struct Entry: Codable, Equatable, Sendable {
        let before: LeadImportSnapshot?
        let after: LeadImportSnapshot

        var isCreatedLead: Bool { before == nil }
    }

    let id: UUID
    let source: LeadImportSource
    let createdAt: Date
    let entries: [Entry]

    var createdCount: Int { entries.filter(\.isCreatedLead).count }
    var updatedCount: Int { entries.count - createdCount }
    var affectedCount: Int { entries.count }
}

struct LeadImportUndoResult: Identifiable, Equatable, Sendable {
    let id = UUID()
    let deleted: Int
    let restored: Int
    let skippedModified: Int
    let skippedMissing: Int

    var summary: String {
        var parts: [String] = []
        if deleted > 0 { parts.append("\(deleted) imported lead\(deleted == 1 ? "" : "s") removed") }
        if restored > 0 { parts.append("\(restored) existing lead\(restored == 1 ? "" : "s") restored") }
        if skippedModified > 0 { parts.append("\(skippedModified) edited lead\(skippedModified == 1 ? " was" : "s were") kept") }
        if skippedMissing > 0 { parts.append("\(skippedMissing) missing lead\(skippedMissing == 1 ? "" : "s") skipped") }
        return parts.isEmpty ? "No leads needed changes." : parts.joined(separator: "\n")
    }
}

@MainActor
final class LeadImportBatchStore: ObservableObject {
    static let shared = LeadImportBatchStore()

    @Published private(set) var batches: [LeadImportBatch] = []

    private let fileURL: URL
    private let maximumBatchCount = 10
    private let maximumBatchAge: TimeInterval = 30 * 24 * 60 * 60

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? Self.defaultFileURL()
        load()
    }

    var latestBatch: LeadImportBatch? {
        batches.max(by: { $0.createdAt < $1.createdAt })
    }

    @discardableResult
    func record(
        source: LeadImportSource,
        createdLeads: [Lead],
        updatedBeforeSnapshots: [UUID: LeadImportSnapshot],
        updatedLeads: [Lead]
    ) throws -> LeadImportBatch? {
        let createdEntries = createdLeads.compactMap { lead -> LeadImportBatch.Entry? in
            guard let after = LeadImportSnapshot(lead: lead) else { return nil }
            return LeadImportBatch.Entry(before: nil, after: after)
        }

        let updatedEntries = updatedLeads.compactMap { lead -> LeadImportBatch.Entry? in
            guard let id = lead.id,
                  let before = updatedBeforeSnapshots[id],
                  let after = LeadImportSnapshot(lead: lead),
                  before != after else {
                return nil
            }
            return LeadImportBatch.Entry(before: before, after: after)
        }

        let entries = createdEntries + updatedEntries
        guard !entries.isEmpty else { return nil }

        let batch = LeadImportBatch(
            id: UUID(),
            source: source,
            createdAt: Date(),
            entries: entries
        )
        batches.insert(batch, at: 0)
        prune()

        do {
            try persist()
            return batch
        } catch {
            batches.removeAll { $0.id == batch.id }
            throw error
        }
    }

    func undoLatest(in context: NSManagedObjectContext) throws -> LeadImportUndoResult? {
        guard let batch = latestBatch else { return nil }

        let ids = batch.entries.map(\.after.id)
        let request: NSFetchRequest<Lead> = Lead.fetchRequest(in: context)
        request.predicate = NSPredicate(format: "id IN %@", ids)
        let currentLeads = try context.fetch(request)
        let leadsByID = Dictionary(uniqueKeysWithValues: currentLeads.compactMap { lead in
            lead.id.map { ($0, lead) }
        })

        var deleted = 0
        var restored = 0
        var skippedModified = 0
        var skippedMissing = 0

        for entry in batch.entries {
            guard let lead = leadsByID[entry.after.id] else {
                skippedMissing += 1
                continue
            }
            guard LeadImportSnapshot(lead: lead) == entry.after else {
                skippedModified += 1
                continue
            }

            if let before = entry.before {
                before.apply(to: lead)
                restored += 1
            } else {
                context.delete(lead)
                deleted += 1
            }
        }

        do {
            if context.hasChanges {
                try context.save()
            }
        } catch {
            context.rollback()
            throw error
        }

        batches.removeAll { $0.id == batch.id }
        do {
            try persist()
        } catch {
            AppLog.warning("Import", "Undo completed, but import history cleanup could not be persisted.")
        }

        return LeadImportUndoResult(
            deleted: deleted,
            restored: restored,
            skippedModified: skippedModified,
            skippedMissing: skippedMissing
        )
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([LeadImportBatch].self, from: data) else {
            batches = []
            return
        }
        batches = decoded
        prune()
    }

    private func prune(now: Date = Date()) {
        let cutoff = now.addingTimeInterval(-maximumBatchAge)
        batches = batches
            .filter { $0.createdAt >= cutoff }
            .sorted { $0.createdAt > $1.createdAt }
        if batches.count > maximumBatchCount {
            batches = Array(batches.prefix(maximumBatchCount))
        }
    }

    private func persist() throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(batches)
        try data.write(to: fileURL, options: [.atomic, .completeFileProtection])
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var protectedURL = fileURL
        try protectedURL.setResourceValues(values)
    }

    private static func defaultFileURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base
            .appendingPathComponent("D2D Advancer", isDirectory: true)
            .appendingPathComponent("lead-import-batches.json")
    }
}
