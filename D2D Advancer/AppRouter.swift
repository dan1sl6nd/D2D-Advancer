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

enum TeamInviteLink {
    static let universalHost = "d2d-advancer.web.app"
    static let universalScheme = "https"
    static let fallbackScheme = "d2dadvancer"
    static let joinPathComponent = "join"

    static func universalURL(for inviteCode: String) -> URL? {
        guard let code = normalizedCode(inviteCode) else { return nil }

        var components = URLComponents()
        components.scheme = universalScheme
        components.host = universalHost
        components.path = "/\(joinPathComponent)/\(code)"
        return components.url
    }

    static func inviteCode(from url: URL) -> String? {
        guard let scheme = url.scheme?.lowercased() else { return nil }

        if scheme == universalScheme {
            guard url.host?.lowercased() == universalHost else { return nil }
            return codeFromHTTPSPath(url)
        }

        if scheme == fallbackScheme {
            return codeFromFallbackURL(url)
        }

        return nil
    }

    static func normalizedCode(_ rawCode: String) -> String? {
        let code = rawCode
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        guard code.count == 8,
              code.unicodeScalars.allSatisfy({
                  CharacterSet(charactersIn: "0123456789ABCDEF").contains($0)
              }) else {
            return nil
        }
        return code
    }

    private static func codeFromHTTPSPath(_ url: URL) -> String? {
        let components = url.pathComponents.filter { $0 != "/" }
        guard components.count == 2,
              components[0].lowercased() == joinPathComponent else {
            return nil
        }
        return normalizedCode(components[1])
    }

    private static func codeFromFallbackURL(_ url: URL) -> String? {
        guard url.host?.lowercased() == joinPathComponent else { return nil }
        let components = url.pathComponents.filter { $0 != "/" }
        guard components.count == 1 else { return nil }
        return normalizedCode(components[0])
    }
}

// Simple global router to support deep links and tab selection
final class AppRouter: ObservableObject {
    static let shared = AppRouter()

    @Published var selectedTab: Int = MainAppTab.map.rawValue
    @Published var selectedWorkSection: WorkTabSection = .followUps
    @Published var targetLeadID: UUID? = nil
    @Published var targetMapLeadID: UUID? = nil
    @Published var openMessageForLeadID: UUID? = nil
    @Published var targetAppointmentID: UUID? = nil
    @Published private(set) var pendingTeamInviteCode: String? = nil

    private init() {}

    func openLead(_ id: UUID) {
        selectedTab = MainAppTab.leads.rawValue
        targetLeadID = id
    }

    func showLeadOnMap(_ id: UUID) {
        targetMapLeadID = id
        selectedTab = MainAppTab.map.rawValue
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

    @discardableResult
    func handleIncomingURL(_ url: URL) -> Bool {
        guard let inviteCode = TeamInviteLink.inviteCode(from: url) else {
            return false
        }
        openTeamInvite(inviteCode)
        return true
    }

    func openTeamInvite(_ inviteCode: String) {
        guard let code = TeamInviteLink.normalizedCode(inviteCode) else { return }
        pendingTeamInviteCode = code
        selectedTab = MainAppTab.more.rawValue
    }

    func consumePendingTeamInviteCode() -> String? {
        defer { pendingTeamInviteCode = nil }
        return pendingTeamInviteCode
    }
}
