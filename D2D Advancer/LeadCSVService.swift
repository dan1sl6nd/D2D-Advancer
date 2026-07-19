import Foundation
import CoreData

// MARK: - Identifiable wrappers for SwiftUI .sheet(item:) and .alert(item:)

struct LeadExportFile: Identifiable {
    let id = UUID()
    let url: URL
}

struct LeadImportResult: Identifiable {
    let id = UUID()
    let created: Int
    let updated: Int
    let skipped: Int
    let errors: [String]
    let batchID: UUID?

    init(
        created: Int,
        updated: Int,
        skipped: Int,
        errors: [String],
        batchID: UUID? = nil
    ) {
        self.created = created
        self.updated = updated
        self.skipped = skipped
        self.errors = errors
        self.batchID = batchID
    }

    var summary: String {
        var parts: [String] = []
        if created > 0 { parts.append("\(created) new") }
        if updated > 0 { parts.append("\(updated) updated") }
        if skipped > 0 { parts.append("\(skipped) skipped") }
        return parts.isEmpty ? "No changes" : parts.joined(separator: " · ")
    }
}

struct LeadCSVImportPreview: Identifiable {
    let id = UUID()
    let created: Int
    let updated: Int
    let skipped: Int
    let errors: [String]
    fileprivate let rawCSV: String

    var summary: String {
        var parts = ["\(created) new", "\(updated) updated"]
        if skipped > 0 { parts.append("\(skipped) skipped") }
        return parts.joined(separator: " · ")
    }

    var changeCount: Int { created + updated }
}

struct LeadImportFailure: Identifiable {
    let id = UUID()
    let message: String
}

// MARK: - CSV Service

enum LeadCSVService {

    private enum RowAction {
        case create(UUID?)
        case update(Lead)
        case skip(String)
    }

    private struct ParsedCSV {
        let rows: [[String]]
        let columnIndex: [String: Int]
    }

    private static let columns: [String] = [
        "ID",
        "Name",
        "Phone",
        "Email",
        "Address",
        "Status",
        "Priority",
        "Price",
        "EstimatedValue",
        "VisitCount",
        "Source",
        "ServiceCategory",
        "Tags",
        "Notes",
        "Latitude",
        "Longitude",
        "CreatedDate",
        "UpdatedDate",
        "FollowUpDate",
        "LastContactDate"
    ]

    /// ISO-8601 with fractional seconds is both human-readable and round-trippable
    /// through any spreadsheet app. Avoids localization issues that break on machines
    /// with different date-format preferences.
    private static let iso8601: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let iso8601WithoutFractionalSeconds: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    // MARK: - Export

    static func exportAllLeads(from context: NSManagedObjectContext) throws -> URL {
        let request: NSFetchRequest<Lead> = Lead.fetchRequest(in: context)
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Lead.createdDate, ascending: false)]
        let leads = try context.fetch(request)

        var csv = columns.joined(separator: ",") + "\n"
        for lead in leads {
            csv += csvRow(for: lead) + "\n"
        }

        let stamp = filenameTimestamp()
        let filename = "leads_export_\(stamp).csv"
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        try csv.write(to: tempURL, atomically: true, encoding: .utf8)
        return tempURL
    }

    /// Build one CSV row for a Lead. Kept as a separate function so the Swift
    /// type-checker doesn't time out on a single 20-element array literal with
    /// mixed optional / function-reference expressions.
    private static func csvRow(for lead: Lead) -> String {
        var fields: [String] = []
        fields.reserveCapacity(columns.count)
        fields.append(lead.id?.uuidString ?? "")
        fields.append(lead.name ?? "")
        fields.append(lead.phone ?? "")
        fields.append(lead.email ?? "")
        fields.append(lead.address ?? "")
        fields.append(lead.status ?? "")
        fields.append(String(lead.priority))
        fields.append(String(lead.price))
        fields.append(String(lead.estimatedValue))
        fields.append(String(lead.visitCount))
        fields.append(lead.source ?? "")
        fields.append(lead.serviceCategory ?? "")
        fields.append(lead.tags ?? "")
        fields.append(lead.notes ?? "")
        fields.append(String(lead.latitude))
        fields.append(String(lead.longitude))
        fields.append(dateToISO(lead.createdDate))
        fields.append(dateToISO(lead.updatedDate))
        fields.append(dateToISO(lead.followUpDate))
        fields.append(dateToISO(lead.lastContactDate))
        return fields.map(escape).joined(separator: ",")
    }

    private static func dateToISO(_ date: Date?) -> String {
        guard let date = date else { return "" }
        return iso8601.string(from: date)
    }

    private static func dateFromISO(_ value: String) -> Date? {
        iso8601.date(from: value) ?? iso8601WithoutFractionalSeconds.date(from: value)
    }

    private static func filenameTimestamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd_HHmm"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: Date())
    }

    private static func escape(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") || value.contains("\r") {
            return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return value
    }

    // MARK: - Import

    @MainActor
    static func previewImport(from url: URL, in context: NSManagedObjectContext) throws -> LeadCSVImportPreview {
        try previewImport(contents: readCSV(from: url), in: context)
    }

    @MainActor
    static func previewImport(contents rawCSV: String, in context: NSManagedObjectContext) throws -> LeadCSVImportPreview {
        let parsed = try parseAndValidate(rawCSV)
        let existingByID = try fetchExistingLeadsByID(in: context)
        var seenIDs: Set<UUID> = []
        var created = 0
        var updated = 0
        var skipped = 0
        var errors: [String] = []

        for (offset, row) in parsed.rows.dropFirst().enumerated() {
            guard row.contains(where: { !$0.isEmpty }) else { continue }
            let rowNumber = offset + 2
            let action = rowAction(
                for: row,
                rowNumber: rowNumber,
                columnIndex: parsed.columnIndex,
                existingByID: existingByID,
                seenIDs: &seenIDs
            )
            switch action {
            case .create:
                created += 1
            case .update:
                updated += 1
            case .skip(let reason):
                skipped += 1
                errors.append(reason)
            }

            if let warning = statusWarning(
                for: row,
                rowNumber: rowNumber,
                columnIndex: parsed.columnIndex,
                action: action
            ) {
                errors.append(warning)
            }
        }

        return LeadCSVImportPreview(
            created: created,
            updated: updated,
            skipped: skipped,
            errors: errors,
            rawCSV: rawCSV
        )
    }

    @MainActor
    static func commitImport(
        _ preview: LeadCSVImportPreview,
        into context: NSManagedObjectContext,
        batchStore: LeadImportBatchStore? = nil
    ) throws -> LeadImportResult {
        let parsed = try parseAndValidate(preview.rawCSV)
        let existingByID = try fetchExistingLeadsByID(in: context)
        var seenIDs: Set<UUID> = []
        var createdLeads: [Lead] = []
        var updatedLeads: [Lead] = []
        var updatedBeforeSnapshots: [UUID: LeadImportSnapshot] = [:]
        var skipped = 0
        var errors: [String] = []

        for (offset, row) in parsed.rows.dropFirst().enumerated() {
            guard row.contains(where: { !$0.isEmpty }) else { continue }
            let rowNumber = offset + 2
            let action = rowAction(
                for: row,
                rowNumber: rowNumber,
                columnIndex: parsed.columnIndex,
                existingByID: existingByID,
                seenIDs: &seenIDs
            )

            let lead: Lead
            let isNew: Bool
            switch action {
            case .create(let importedID):
                lead = Lead.create(in: context)
                if let importedID { lead.id = importedID }
                createdLeads.append(lead)
                isNew = true
            case .update(let existing):
                if let id = existing.id, updatedBeforeSnapshots[id] == nil {
                    updatedBeforeSnapshots[id] = LeadImportSnapshot(lead: existing)
                }
                lead = existing
                updatedLeads.append(existing)
                isNew = false
            case .skip(let reason):
                skipped += 1
                errors.append(reason)
                continue
            }

            apply(row, columnIndex: parsed.columnIndex, to: lead, isNew: isNew, rowNumber: rowNumber, errors: &errors)
            if isNew, lead.createdDate == nil { lead.createdDate = Date() }
            lead.updatedDate = Date()
        }

        do {
            if context.hasChanges {
                try context.save()
            }
        } catch {
            context.rollback()
            throw error
        }

        var batchID: UUID?
        if let batchStore {
            do {
                batchID = try batchStore.record(
                    source: .csv,
                    createdLeads: createdLeads,
                    updatedBeforeSnapshots: updatedBeforeSnapshots,
                    updatedLeads: updatedLeads
                )?.id
            } catch {
                errors.append("The import succeeded, but its Undo history could not be saved.")
                AppLog.warning("Import", "CSV import history could not be persisted.")
            }
        }

        let result = LeadImportResult(
            created: createdLeads.count,
            updated: updatedLeads.count,
            skipped: skipped,
            errors: errors,
            batchID: batchID
        )
        AppLog.event(.importData, .importCompleted)
        return result
    }

    @MainActor
    static func importLeads(from url: URL, into context: NSManagedObjectContext) throws -> LeadImportResult {
        let preview = try previewImport(from: url, in: context)
        return try commitImport(preview, into: context, batchStore: nil)
    }

    nonisolated static func isUsableImportedCoordinate(latitude: Double?, longitude: Double?) -> Bool {
        guard let latitude, let longitude else { return false }
        guard (-90...90).contains(latitude), (-180...180).contains(longitude) else { return false }
        return latitude != 0 || longitude != 0
    }

    private static func readCSV(from url: URL) throws -> String {
        let didStartAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didStartAccess { url.stopAccessingSecurityScopedResource() }
        }

        do {
            return try String(contentsOf: url, encoding: .utf8)
        } catch {
            if let alternate = try? String(contentsOf: url, encoding: .utf16) {
                return alternate
            }
            if let alternate = try? String(contentsOf: url, encoding: .isoLatin1) {
                return alternate
            }
            throw error
        }
    }

    private static func parseAndValidate(_ rawCSV: String) throws -> ParsedCSV {
        let rows = parseCSV(rawCSV)
        guard let header = rows.first, !header.isEmpty else {
            throw NSError(
                domain: "LeadCSVService",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "The CSV file is empty or unreadable."]
            )
        }

        var columnIndex: [String: Int] = [:]
        for (index, column) in header.enumerated() {
            let key = column.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            if !key.isEmpty { columnIndex[key] = index }
        }
        return ParsedCSV(rows: rows, columnIndex: columnIndex)
    }

    @MainActor
    private static func fetchExistingLeadsByID(in context: NSManagedObjectContext) throws -> [UUID: Lead] {
        let request: NSFetchRequest<Lead> = Lead.fetchRequest(in: context)
        request.fetchBatchSize = 500
        return Dictionary(uniqueKeysWithValues: try context.fetch(request).compactMap { lead in
            lead.id.map { ($0, lead) }
        })
    }

    @MainActor
    private static func rowAction(
        for row: [String],
        rowNumber: Int,
        columnIndex: [String: Int],
        existingByID: [UUID: Lead],
        seenIDs: inout Set<UUID>
    ) -> RowAction {
        let importedID = field(row, "ID", columnIndex: columnIndex).flatMap(UUID.init(uuidString:))
        if let importedID {
            guard seenIDs.insert(importedID).inserted else {
                return .skip("Row \(rowNumber): duplicate ID in this file, skipped")
            }
            if let existing = existingByID[importedID] {
                return .update(existing)
            }
        }

        guard field(row, "Name", columnIndex: columnIndex) != nil else {
            return .skip("Row \(rowNumber): missing Name, skipped")
        }
        let latitude = field(row, "Latitude", columnIndex: columnIndex).flatMap(Double.init)
        let longitude = field(row, "Longitude", columnIndex: columnIndex).flatMap(Double.init)
        guard isUsableImportedCoordinate(latitude: latitude, longitude: longitude) else {
            return .skip("Row \(rowNumber): missing valid Latitude/Longitude, skipped")
        }
        return .create(importedID)
    }

    @MainActor
    private static func apply(
        _ row: [String],
        columnIndex: [String: Int],
        to lead: Lead,
        isNew: Bool,
        rowNumber: Int,
        errors: inout [String]
    ) {
        if let value = field(row, "Name", columnIndex: columnIndex) { lead.name = value }
        if let value = field(row, "Phone", columnIndex: columnIndex) { lead.phone = value }
        if let value = field(row, "Email", columnIndex: columnIndex) { lead.email = value }
        if let value = field(row, "Address", columnIndex: columnIndex) { lead.address = value }
        if let value = field(row, "Status", columnIndex: columnIndex) {
            if let normalized = Lead.Status.normalizedRawValue(from: value),
               let importedStatus = Lead.Status(rawValue: normalized) {
                lead.applyLeadStatus(importedStatus, autoSave: false)
            } else if isNew {
                lead.applyLeadStatus(.notContacted, autoSave: false)
            } else {
                errors.append("Row \(rowNumber): unknown Status, kept existing status")
            }
        }
        if let value = field(row, "Priority", columnIndex: columnIndex), let parsed = Int16(value) { lead.priority = parsed }
        if let value = field(row, "Price", columnIndex: columnIndex), let parsed = Double(value) { lead.price = parsed }
        if let value = field(row, "EstimatedValue", columnIndex: columnIndex), let parsed = Double(value) { lead.estimatedValue = parsed }
        if let value = field(row, "VisitCount", columnIndex: columnIndex), let parsed = Int16(value) { lead.visitCount = parsed }
        if let value = field(row, "Source", columnIndex: columnIndex) { lead.source = value }
        if let value = field(row, "ServiceCategory", columnIndex: columnIndex) { lead.serviceCategory = value }
        if let value = field(row, "Tags", columnIndex: columnIndex) { lead.tags = value }
        if let value = field(row, "Notes", columnIndex: columnIndex) { lead.notes = value }

        let latitude = field(row, "Latitude", columnIndex: columnIndex).flatMap(Double.init)
        let longitude = field(row, "Longitude", columnIndex: columnIndex).flatMap(Double.init)
        if isUsableImportedCoordinate(latitude: latitude, longitude: longitude),
           let latitude,
           let longitude {
            lead.latitude = latitude
            lead.longitude = longitude
        }
        if let value = field(row, "CreatedDate", columnIndex: columnIndex), let date = dateFromISO(value) {
            lead.createdDate = date
        }
        if let value = field(row, "FollowUpDate", columnIndex: columnIndex), let date = dateFromISO(value) {
            lead.followUpDate = lead.leadStatus.resolvedFollowUpDate(date)
        }
        if let value = field(row, "LastContactDate", columnIndex: columnIndex), let date = dateFromISO(value) {
            lead.lastContactDate = date
        }
    }

    private static func statusWarning(
        for row: [String],
        rowNumber: Int,
        columnIndex: [String: Int],
        action: RowAction
    ) -> String? {
        guard let value = field(row, "Status", columnIndex: columnIndex),
              Lead.Status.normalizedRawValue(from: value) == nil else {
            return nil
        }
        switch action {
        case .create:
            return "Row \(rowNumber): unknown Status; the new lead will use Not Contacted"
        case .update:
            return "Row \(rowNumber): unknown Status; the existing status will be kept"
        case .skip:
            return nil
        }
    }

    private static func field(
        _ row: [String],
        _ name: String,
        columnIndex: [String: Int]
    ) -> String? {
        guard let index = columnIndex[name.lowercased()], index < row.count else { return nil }
        let value = row[index].trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    // MARK: - CSV Parser (state machine, handles quoted fields with embedded commas/quotes/newlines)

    private static func parseCSV(_ input: String) -> [[String]] {
        var rows: [[String]] = []
        var currentRow: [String] = []
        var currentField = ""
        var inQuotes = false
        var iter = input.makeIterator()
        var pushback: Character? = nil

        func commitField() {
            currentRow.append(currentField)
            currentField = ""
        }
        func commitRow() {
            commitField()
            rows.append(currentRow)
            currentRow = []
        }

        while let c = pushback ?? iter.next() {
            pushback = nil

            if inQuotes {
                if c == "\"" {
                    // Either escaped quote ("") or end of quoted field
                    if let next = iter.next() {
                        if next == "\"" {
                            currentField.append("\"")
                        } else {
                            inQuotes = false
                            pushback = next
                        }
                    } else {
                        inQuotes = false
                    }
                } else {
                    currentField.append(c)
                }
            } else {
                switch c {
                case ",":
                    commitField()
                case "\n":
                    commitRow()
                case "\r":
                    // Normalize CRLF → single row break
                    if let next = iter.next(), next != "\n" {
                        pushback = next
                    }
                    commitRow()
                case "\"":
                    if currentField.isEmpty {
                        inQuotes = true
                    } else {
                        currentField.append(c)
                    }
                default:
                    currentField.append(c)
                }
            }
        }

        // Tail row (no trailing newline)
        if !currentField.isEmpty || !currentRow.isEmpty {
            commitRow()
        }

        return rows
    }
}
