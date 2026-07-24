import Foundation
import OSLog
import UIKit

enum DiagnosticCategory: String, Codable, CaseIterable, Sendable {
    case app
    case authentication
    case cloudSync = "cloud_sync"
    case importData = "import"
    case map
    case storage
    case team

    static func safeValue(for rawCategory: String) -> DiagnosticCategory {
        let normalized = rawCategory.lowercased()
        if normalized.contains("team") { return .team }
        if normalized.contains("auth") || normalized.contains("account") { return .authentication }
        if normalized.contains("cloud") || normalized.contains("sync") { return .cloudSync }
        if normalized.contains("import") || normalized.contains("csv") || normalized.contains("contact") { return .importData }
        if normalized.contains("map") || normalized.contains("location") { return .map }
        if normalized.contains("storage") || normalized.contains("cache") || normalized.contains("file") { return .storage }
        return .app
    }
}

enum DiagnosticSeverity: String, Codable, Sendable {
    case info
    case warning
    case error

    var osLogType: OSLogType {
        switch self {
        case .info: return .info
        case .warning: return .default
        case .error: return .error
        }
    }
}

enum DiagnosticEventCode: String, Codable, Sendable {
    case appLaunched = "app_launched"
    case authenticationFailed = "authentication_failed"
    case cloudSchemaMismatch = "cloud_schema_mismatch"
    case cloudUnavailable = "cloud_unavailable"
    case dataDecodeFailed = "data_decode_failed"
    case genericError = "generic_error"
    case genericWarning = "generic_warning"
    case importCompleted = "import_completed"
    case networkOffline = "network_offline"
    case operationFailed = "operation_failed"
    case permissionDenied = "permission_denied"
    case quotaLimited = "quota_limited"
    case requestTimedOut = "request_timed_out"
    case storageUnavailable = "storage_unavailable"
    case syncCompleted = "sync_completed"
    case syncFailed = "sync_failed"
    case syncStarted = "sync_started"
}

struct DiagnosticEvent: Codable, Equatable, Sendable {
    var category: DiagnosticCategory
    var code: DiagnosticEventCode
    var severity: DiagnosticSeverity
    var firstOccurredAt: Date
    var lastOccurredAt: Date
    var occurrenceCount: Int
}

enum ReleaseDiagnosticClassifier {
    static func code(
        for message: String,
        category: DiagnosticCategory,
        severity: DiagnosticSeverity
    ) -> DiagnosticEventCode {
        let normalized = message.lowercased()

        if normalized.contains("recordname") && normalized.contains("queryable") {
            return .cloudSchemaMismatch
        }
        if normalized.contains("offline")
            || normalized.contains("not connected to the internet")
            || normalized.contains("network connection was lost") {
            return .networkOffline
        }
        if normalized.contains("permission")
            || normalized.contains("unauthorized")
            || normalized.contains("access denied") {
            return .permissionDenied
        }
        if normalized.contains("identity provider")
            || normalized.contains("token")
            || normalized.contains("authentication")
            || normalized.contains("sign in")
            || normalized.contains("session expired") {
            return .authenticationFailed
        }
        if normalized.contains("quota")
            || normalized.contains("resource exhausted")
            || normalized.contains("rate limit") {
            return .quotaLimited
        }
        if normalized.contains("timed out")
            || normalized.contains("timeout")
            || normalized.contains("still waiting") {
            return .requestTimedOut
        }
        if normalized.contains("no space")
            || normalized.contains("disk full")
            || normalized.contains("storage unavailable") {
            return .storageUnavailable
        }
        if normalized.contains("decode")
            || normalized.contains("corrupt")
            || normalized.contains("unreadable") {
            return .dataDecodeFailed
        }
        if normalized.contains("cloudkit")
            || normalized.contains("icloud")
            || normalized.contains("container unavailable") {
            return .cloudUnavailable
        }
        if category == .cloudSync { return .syncFailed }
        if severity == .error { return .genericError }
        if severity == .warning { return .genericWarning }
        return .operationFailed
    }
}

final class ReleaseDiagnosticsStore: @unchecked Sendable {
    static let shared = ReleaseDiagnosticsStore()

    private let lock = NSLock()
    private let fileURL: URL
    private let maximumEventCount: Int
    private let maximumEventAge: TimeInterval
    private let duplicateWindow: TimeInterval
    private var events: [DiagnosticEvent]

    init(
        fileURL: URL? = nil,
        maximumEventCount: Int = 80,
        maximumEventAge: TimeInterval = 30 * 24 * 60 * 60,
        duplicateWindow: TimeInterval = 60
    ) {
        self.fileURL = fileURL ?? Self.defaultFileURL()
        self.maximumEventCount = maximumEventCount
        self.maximumEventAge = maximumEventAge
        self.duplicateWindow = duplicateWindow
        events = Self.load(from: self.fileURL)
        events = Self.pruned(
            events,
            now: Date(),
            maximumEventCount: maximumEventCount,
            maximumEventAge: maximumEventAge
        )
    }

    func record(
        category: DiagnosticCategory,
        code: DiagnosticEventCode,
        severity: DiagnosticSeverity,
        at date: Date = Date()
    ) {
        lock.lock()
        defer { lock.unlock() }

        if let lastIndex = events.indices.last,
           events[lastIndex].category == category,
           events[lastIndex].code == code,
           events[lastIndex].severity == severity,
           date.timeIntervalSince(events[lastIndex].lastOccurredAt) <= duplicateWindow {
            events[lastIndex].lastOccurredAt = date
            events[lastIndex].occurrenceCount += 1
        } else {
            events.append(
                DiagnosticEvent(
                    category: category,
                    code: code,
                    severity: severity,
                    firstOccurredAt: date,
                    lastOccurredAt: date,
                    occurrenceCount: 1
                )
            )
        }

        events = Self.pruned(
            events,
            now: date,
            maximumEventCount: maximumEventCount,
            maximumEventAge: maximumEventAge
        )
        persistLocked()
    }

    func snapshot(now: Date = Date()) -> [DiagnosticEvent] {
        lock.lock()
        defer { lock.unlock() }
        return Self.pruned(
            events,
            now: now,
            maximumEventCount: maximumEventCount,
            maximumEventAge: maximumEventAge
        )
    }

    func clear() {
        lock.lock()
        defer { lock.unlock() }
        events = []
        try? FileManager.default.removeItem(at: fileURL)
    }

    private func persistLocked() {
        guard let data = try? JSONEncoder().encode(events) else { return }
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: fileURL, options: .atomic)
            try? FileManager.default.setAttributes(
                [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                ofItemAtPath: fileURL.path
            )
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            var protectedURL = fileURL
            try? protectedURL.setResourceValues(values)
        } catch {
            // Diagnostics must never interfere with the user's primary workflow.
        }
    }

    private static func load(from fileURL: URL) -> [DiagnosticEvent] {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([DiagnosticEvent].self, from: data) else {
            return []
        }
        return decoded
    }

    private static func pruned(
        _ events: [DiagnosticEvent],
        now: Date,
        maximumEventCount: Int,
        maximumEventAge: TimeInterval
    ) -> [DiagnosticEvent] {
        Array(
            events
                .filter { now.timeIntervalSince($0.lastOccurredAt) <= maximumEventAge }
                .suffix(maximumEventCount)
        )
    }

    private static func defaultFileURL() -> URL {
        let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return baseURL
            .appendingPathComponent("D2D Advancer", isDirectory: true)
            .appendingPathComponent("release-diagnostics-v1.json")
    }
}

enum ReleaseDiagnostics {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "dan1sland.D2D-Advancer",
        category: "SupportDiagnostics"
    )

    static func record(
        category rawCategory: String,
        severity: DiagnosticSeverity,
        message: String
    ) {
        let category = DiagnosticCategory.safeValue(for: rawCategory)
        let code = ReleaseDiagnosticClassifier.code(
            for: message,
            category: category,
            severity: severity
        )
        record(category: category, code: code, severity: severity)
    }

    static func record(
        category: DiagnosticCategory,
        code: DiagnosticEventCode,
        severity: DiagnosticSeverity = .info
    ) {
        ReleaseDiagnosticsStore.shared.record(category: category, code: code, severity: severity)
        logger.log(
            level: severity.osLogType,
            "\(category.rawValue, privacy: .public).\(code.rawValue, privacy: .public)"
        )
    }
}

struct SupportDiagnosticsSnapshot: Equatable, Sendable {
    var appVersion: String
    var buildConfiguration: String
    var systemName: String
    var systemVersion: String
    var localeIdentifier: String
    var cloudProvider: String
    var syncState: String
    var autoSyncEnabled: Bool
    var syncInterval: String
    var lastSyncAt: Date?
    var personalLeadCount: Int
    var importBatchCount: Int
    var accountSessionActive: Bool
    var teamWorkspaceActive: Bool
    var teamRole: String?
    var teamWorkType: String?
    var teamPlanStatus: String?
    var teamMemberCount: Int
    var teamLeadCount: Int
    var teamBookingCount: Int
    var teamWriteState: String
    var teamWritesEnabled: Bool
    var teamUsageLevel: String
}

enum SupportDiagnosticsReport {
    static func reportText(
        snapshot: SupportDiagnosticsSnapshot,
        events: [DiagnosticEvent],
        generatedAt: Date = Date()
    ) -> String {
        var lines = [
            "D2D Advancer Support Report",
            "Generated: \(iso8601(generatedAt))",
            "Privacy: No customer names, addresses, phone numbers, email addresses, notes, coordinates, account IDs, team IDs, or raw error messages are included.",
            "",
            "[App]",
            "Version: \(snapshot.appVersion)",
            "Configuration: \(snapshot.buildConfiguration)",
            "System: \(snapshot.systemName) \(snapshot.systemVersion)",
            "Locale: \(snapshot.localeIdentifier)",
            "",
            "[Personal Data]",
            "Cloud provider: \(snapshot.cloudProvider)",
            "Sync state: \(snapshot.syncState)",
            "Auto sync: \(yesNo(snapshot.autoSyncEnabled))",
            "Sync interval: \(snapshot.syncInterval)",
            "Last sync: \(snapshot.lastSyncAt.map(iso8601) ?? "never")",
            "Lead count: \(snapshot.personalLeadCount)",
            "Saved import batches: \(snapshot.importBatchCount)",
            "Account session active: \(yesNo(snapshot.accountSessionActive))",
            "",
            "[Team]",
            "Workspace active: \(yesNo(snapshot.teamWorkspaceActive))",
            "Role: \(snapshot.teamRole ?? "none")",
            "Work type: \(snapshot.teamWorkType ?? "none")",
            "Plan state: \(snapshot.teamPlanStatus ?? "none")",
            "Members: \(snapshot.teamMemberCount)",
            "Leads: \(snapshot.teamLeadCount)",
            "Bookings: \(snapshot.teamBookingCount)",
            "Write state: \(snapshot.teamWriteState)",
            "Service writes enabled: \(yesNo(snapshot.teamWritesEnabled))",
            "Usage level: \(snapshot.teamUsageLevel)",
            "",
            "[Recent Diagnostics]"
        ]

        if events.isEmpty {
            lines.append("None recorded")
        } else {
            for event in events.reversed() {
                lines.append(
                    "\(iso8601(event.lastOccurredAt)) | \(event.severity.rawValue) | \(event.category.rawValue) | \(event.code.rawValue) | occurrences=\(event.occurrenceCount)"
                )
            }
        }

        return lines.joined(separator: "\n") + "\n"
    }

    static func export(
        snapshot: SupportDiagnosticsSnapshot,
        events: [DiagnosticEvent] = ReleaseDiagnosticsStore.shared.snapshot(),
        generatedAt: Date = Date()
    ) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("D2D-Support-Reports", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        removeExpiredReports(in: directory, now: generatedAt)

        let timestamp = fileTimestamp(generatedAt)
        let url = directory.appendingPathComponent("D2D-Support-Report-\(timestamp).txt")
        try reportText(snapshot: snapshot, events: events, generatedAt: generatedAt)
            .write(to: url, atomically: true, encoding: .utf8)
        try? FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: url.path
        )
        return url
    }

    private static func removeExpiredReports(in directory: URL, now: Date) {
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey]
        ) else { return }

        for url in urls {
            let modifiedAt = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            if let modifiedAt, now.timeIntervalSince(modifiedAt) > 24 * 60 * 60 {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }

    private static func iso8601(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    private static func fileTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: date)
    }

    private static func yesNo(_ value: Bool) -> String {
        value ? "yes" : "no"
    }
}
