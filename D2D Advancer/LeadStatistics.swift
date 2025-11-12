import SwiftUI
import CoreData

// Minimal statistics model used by MoreView. Previously defined in StatisticsView.
struct LeadStatistics {
    var activeLeadsCount: Int = 0
    var convertedCount: Int = 0
    var interestedCount: Int = 0
    var notContactedCount: Int = 0
    var leadsAddedToday: Int = 0
    var leadsUpdatedThisWeek: Int = 0
    var followUpsDueThisWeek: Int = 0

    var statusCounts: [Lead.Status: Int] = [:]
}

