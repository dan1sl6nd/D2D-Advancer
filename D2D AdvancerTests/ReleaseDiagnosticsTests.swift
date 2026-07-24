import Foundation
import Testing
@testable import D2D_Advancer

struct ReleaseDiagnosticsTests {
    @Test func classifierTurnsSensitiveFailuresIntoCoarseCodes() {
        let message = "Daniil at 123 Main Street is offline; account user-123 failed."
        let code = ReleaseDiagnosticClassifier.code(
            for: message,
            category: .cloudSync,
            severity: .error
        )

        #expect(code == .networkOffline)
        #expect(!code.rawValue.contains("Daniil"))
        #expect(!code.rawValue.contains("123 Main"))
        #expect(!code.rawValue.contains("user-123"))
    }

    @Test func localDiagnosticStoreCollapsesRepeatsAndBoundsHistory() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("diagnostics-\(UUID().uuidString).json")
        let store = ReleaseDiagnosticsStore(
            fileURL: url,
            maximumEventCount: 2,
            maximumEventAge: 1_000,
            duplicateWindow: 60
        )
        defer { store.clear() }

        let start = Date().addingTimeInterval(-200)
        store.record(category: .team, code: .networkOffline, severity: .warning, at: start)
        store.record(category: .team, code: .networkOffline, severity: .warning, at: start.addingTimeInterval(30))
        store.record(category: .cloudSync, code: .syncCompleted, severity: .info, at: start.addingTimeInterval(100))
        store.record(category: .importData, code: .importCompleted, severity: .info, at: start.addingTimeInterval(200))

        let events = store.snapshot(now: start.addingTimeInterval(200))
        #expect(events.count == 2)
        #expect(events.map(\.code) == [.syncCompleted, .importCompleted])

        let reloaded = ReleaseDiagnosticsStore(
            fileURL: url,
            maximumEventCount: 2,
            maximumEventAge: 1_000,
            duplicateWindow: 60
        )
        #expect(reloaded.snapshot(now: start.addingTimeInterval(200)) == events)
    }

    @Test func supportReportContainsHealthCodesButNoRawFailureDetails() {
        let sensitiveMessage = "Permission denied for Daniil at 123 Main Street, user-id-456"
        let code = ReleaseDiagnosticClassifier.code(
            for: sensitiveMessage,
            category: .team,
            severity: .error
        )
        let event = DiagnosticEvent(
            category: .team,
            code: code,
            severity: .error,
            firstOccurredAt: Date(timeIntervalSince1970: 10_000),
            lastOccurredAt: Date(timeIntervalSince1970: 10_000),
            occurrenceCount: 1
        )
        let snapshot = SupportDiagnosticsSnapshot(
            appVersion: "1.2.3 (45)",
            buildConfiguration: "release",
            systemName: "iOS",
            systemVersion: "26.0",
            localeIdentifier: "en_CA",
            cloudProvider: "icloud",
            syncState: "failed:permission_denied",
            autoSyncEnabled: true,
            syncInterval: "one_hour",
            lastSyncAt: nil,
            personalLeadCount: 12,
            importBatchCount: 1,
            accountSessionActive: true,
            teamWorkspaceActive: true,
            teamRole: "owner",
            teamWorkType: "owner",
            teamPlanStatus: "active",
            teamMemberCount: 3,
            teamLeadCount: 5,
            teamBookingCount: 2,
            teamWriteState: "idle",
            teamWritesEnabled: true,
            teamUsageLevel: "normal"
        )

        let report = SupportDiagnosticsReport.reportText(
            snapshot: snapshot,
            events: [event],
            generatedAt: Date(timeIntervalSince1970: 20_000)
        )

        #expect(report.contains("permission_denied"))
        #expect(report.contains("No customer names"))
        #expect(!report.contains("Daniil"))
        #expect(!report.contains("123 Main Street"))
        #expect(!report.contains("user-id-456"))
    }
}
