import Foundation
import SwiftUI

// Simple global router to support deep links and tab selection
final class AppRouter: ObservableObject {
    static let shared = AppRouter()

    @Published var selectedTab: Int = 0
    @Published var targetLeadID: UUID? = nil
    @Published var openMessageForLeadID: UUID? = nil
    @Published var targetAppointmentID: UUID? = nil

    private init() {}

    func openLead(_ id: UUID) {
        selectedTab = 1 // Leads
        targetLeadID = id
    }

    func openMessage(forLead id: UUID) {
        selectedTab = 1 // Leads
        openMessageForLeadID = id
    }

    func openAppointments(_ id: UUID? = nil) {
        selectedTab = 3 // Appointments
        targetAppointmentID = id
    }
}

