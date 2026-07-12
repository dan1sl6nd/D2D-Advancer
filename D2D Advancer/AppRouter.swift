import Foundation
import SwiftUI

enum MainAppTab: Int {
    case map = 0
    case leads = 1
    case work = 2
    case more = 3
}

enum WorkTabSection: String, CaseIterable, Identifiable {
    case followUps
    case schedule

    var id: String { rawValue }
}

// Simple global router to support deep links and tab selection
final class AppRouter: ObservableObject {
    static let shared = AppRouter()

    @Published var selectedTab: Int = MainAppTab.map.rawValue
    @Published var selectedWorkSection: WorkTabSection = .followUps
    @Published var targetLeadID: UUID? = nil
    @Published var openMessageForLeadID: UUID? = nil
    @Published var targetAppointmentID: UUID? = nil

    private init() {}

    func openLead(_ id: UUID) {
        selectedTab = MainAppTab.leads.rawValue
        targetLeadID = id
    }

    func openMessage(forLead id: UUID) {
        selectedTab = MainAppTab.leads.rawValue
        openMessageForLeadID = id
    }

    func openAppointments(_ id: UUID? = nil) {
        selectedWorkSection = .schedule
        selectedTab = MainAppTab.work.rawValue
        targetAppointmentID = id
    }

    func openFollowUps() {
        selectedWorkSection = .followUps
        selectedTab = MainAppTab.work.rawValue
    }

    func openMore() {
        selectedTab = MainAppTab.more.rawValue
    }
}
