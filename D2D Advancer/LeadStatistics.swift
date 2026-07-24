import Foundation

// Minimal statistics model used by MoreView. Previously defined in StatisticsView.
struct LeadStatistics {
    var activeLeadsCount: Int = 0
    var convertedCount: Int = 0
    var interestedCount: Int = 0
    var notContactedCount: Int = 0
    var overdueFollowUpsCount: Int = 0
    var soldRevenue: Double = 0

    var conversionRate: Double {
        guard activeLeadsCount > 0 else { return 0 }
        return Double(convertedCount) / Double(activeLeadsCount)
    }
}

enum LeadCountDisplay {
    static func leadPhrase(for count: Int?) -> String {
        guard let count else { return "your local leads" }
        return "\(count) \(count == 1 ? "lead" : "leads")"
    }

    static func localDataPhrase(for count: Int?) -> String {
        guard let count else { return "your local lead data" }
        return "your local data (\(leadPhrase(for: count)))"
    }

    static func firebaseToICloudMessage(for count: Int?) -> String {
        let subject = count == nil ? "Your local leads" : "All \(leadPhrase(for: count))"
        return "A final Firebase sync will run first to ensure all your data is up to date. \(subject) will then sync automatically via iCloud."
    }

    static func iCloudUploadMessage(for count: Int?) -> String {
        "\(localDataPhrase(for: count).capitalizedFirstSentence) will be automatically uploaded to iCloud."
    }

    static func iCloudSyncMessage(for count: Int?) -> String {
        let subject = count == nil ? "Your local leads" : "All \(leadPhrase(for: count))"
        return "\(subject) will sync automatically via iCloud using your Apple ID."
    }
}

private extension String {
    var capitalizedFirstSentence: String {
        guard let first else { return self }
        return first.uppercased() + String(dropFirst())
    }
}
