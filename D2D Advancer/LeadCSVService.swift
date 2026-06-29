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

    var summary: String {
        var parts: [String] = []
        if created > 0 { parts.append("\(created) new") }
        if updated > 0 { parts.append("\(updated) updated") }
        if skipped > 0 { parts.append("\(skipped) skipped") }
        return parts.isEmpty ? "No changes" : parts.joined(separator: " · ")
    }
}

struct LeadImportFailure: Identifiable {
    let id = UUID()
    let message: String
}

// MARK: - CSV Service

enum LeadCSVService {

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

    static func importLeads(from url: URL, into context: NSManagedObjectContext) throws -> LeadImportResult {
        // Files picked via .fileImporter are often security-scoped (e.g., from Files.app).
        let didStartAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didStartAccess { url.stopAccessingSecurityScopedResource() }
        }

        let raw: String
        do {
            raw = try String(contentsOf: url, encoding: .utf8)
        } catch {
            // Fallback for files saved by Excel on Windows which default to UTF-16 or Latin-1.
            if let alt = try? String(contentsOf: url, encoding: .utf16) {
                raw = alt
            } else if let alt = try? String(contentsOf: url, encoding: .isoLatin1) {
                raw = alt
            } else {
                throw error
            }
        }

        let rows = parseCSV(raw)
        guard let header = rows.first, !header.isEmpty else {
            throw NSError(
                domain: "LeadCSVService",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "The CSV file is empty or unreadable."]
            )
        }

        // Case-insensitive column name → index lookup, resilient to reordering.
        var columnIndex: [String: Int] = [:]
        for (i, col) in header.enumerated() {
            let key = col.lowercased().trimmingCharacters(in: .whitespaces)
            if !key.isEmpty { columnIndex[key] = i }
        }

        func field(_ row: [String], _ name: String) -> String? {
            guard let idx = columnIndex[name.lowercased()], idx < row.count else { return nil }
            let v = row[idx].trimmingCharacters(in: .whitespaces)
            return v.isEmpty ? nil : v
        }

        var created = 0
        var updated = 0
        var skipped = 0
        var errors: [String] = []

        for (offset, row) in rows.dropFirst().enumerated() {
            let rowNum = offset + 2 // header is row 1, first data row is row 2
            guard row.contains(where: { !$0.isEmpty }) else { continue }

            let importedName = field(row, "Name")
            let importedLatitude = field(row, "Latitude").flatMap(Double.init)
            let importedLongitude = field(row, "Longitude").flatMap(Double.init)

            let lead: Lead
            let isNew: Bool
            if let idStr = field(row, "ID"), let uuid = UUID(uuidString: idStr) {
                let fetch: NSFetchRequest<Lead> = Lead.fetchRequest(in: context)
                fetch.predicate = NSPredicate(format: "id == %@", uuid as CVarArg)
                fetch.fetchLimit = 1
                if let existing = try context.fetch(fetch).first {
                    lead = existing
                    isNew = false
                } else {
                    guard importedName?.isEmpty == false else {
                        skipped += 1
                        errors.append("Row \(rowNum): missing Name, skipped")
                        continue
                    }
                    guard isUsableImportedCoordinate(latitude: importedLatitude, longitude: importedLongitude) else {
                        skipped += 1
                        errors.append("Row \(rowNum): missing valid Latitude/Longitude, skipped")
                        continue
                    }

                    lead = Lead.create(in: context)
                    lead.id = uuid
                    isNew = true
                }
            } else {
                guard importedName?.isEmpty == false else {
                    skipped += 1
                    errors.append("Row \(rowNum): missing Name, skipped")
                    continue
                }
                guard isUsableImportedCoordinate(latitude: importedLatitude, longitude: importedLongitude) else {
                    skipped += 1
                    errors.append("Row \(rowNum): missing valid Latitude/Longitude, skipped")
                    continue
                }

                lead = Lead.create(in: context)
                isNew = true
            }

            if let v = importedName { lead.name = v }
            if let v = field(row, "Phone") { lead.phone = v }
            if let v = field(row, "Email") { lead.email = v }
            if let v = field(row, "Address") { lead.address = v }
            if let v = field(row, "Status") {
                if let normalizedStatus = Lead.Status.normalizedRawValue(from: v),
                   let importedStatus = Lead.Status(rawValue: normalizedStatus) {
                    lead.applyLeadStatus(importedStatus, autoSave: false)
                } else if isNew {
                    lead.applyLeadStatus(.notContacted, autoSave: false)
                } else {
                    errors.append("Row \(rowNum): unknown Status, kept existing status")
                }
            }
            if let v = field(row, "Priority"), let i = Int16(v) { lead.priority = i }
            if let v = field(row, "Price"), let d = Double(v) { lead.price = d }
            if let v = field(row, "EstimatedValue"), let d = Double(v) { lead.estimatedValue = d }
            if let v = field(row, "VisitCount"), let i = Int16(v) { lead.visitCount = i }
            if let v = field(row, "Source") { lead.source = v }
            if let v = field(row, "ServiceCategory") { lead.serviceCategory = v }
            if let v = field(row, "Tags") { lead.tags = v }
            if let v = field(row, "Notes") { lead.notes = v }
            if isUsableImportedCoordinate(latitude: importedLatitude, longitude: importedLongitude),
               let importedLatitude,
               let importedLongitude {
                lead.latitude = importedLatitude
                lead.longitude = importedLongitude
            }
            if let v = field(row, "CreatedDate"), let d = dateFromISO(v) { lead.createdDate = d }
            if let v = field(row, "UpdatedDate"), let d = dateFromISO(v) { lead.updatedDate = d }
            if let v = field(row, "FollowUpDate"), let d = dateFromISO(v) {
                lead.followUpDate = lead.leadStatus.resolvedFollowUpDate(d)
            }
            if let v = field(row, "LastContactDate"), let d = dateFromISO(v) { lead.lastContactDate = d }

            // Require at least a name
            if (lead.name ?? "").isEmpty {
                if isNew { context.delete(lead) }
                skipped += 1
                errors.append("Row \(rowNum): missing Name, skipped")
                continue
            }

            if isNew {
                if lead.createdDate == nil { lead.createdDate = Date() }
                lead.updatedDate = Date()
                if (lead.status ?? "").isEmpty { lead.status = "not_contacted" }
                created += 1
            } else {
                lead.updatedDate = Date()
                updated += 1
            }
        }

        if context.hasChanges {
            try context.save()
        }

        return LeadImportResult(created: created, updated: updated, skipped: skipped, errors: errors)
    }

    nonisolated static func isUsableImportedCoordinate(latitude: Double?, longitude: Double?) -> Bool {
        guard let latitude, let longitude else { return false }
        guard (-90...90).contains(latitude), (-180...180).contains(longitude) else { return false }
        return latitude != 0 || longitude != 0
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
