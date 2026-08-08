import Foundation
import FirebaseFunctions

@MainActor
final class TeamBillingService {
    static let shared = TeamBillingService()

    private let functions: Functions

    private init() {
        FirebaseBootstrap.configureIfNeeded()
        FirebaseEmulatorConfiguration.applyIfNeeded()
        functions = Functions.functions()
    }

    func createTeam(
        name: String,
        displayName: String?,
        email: String?,
        signedTransaction: String
    ) async throws -> String {
        let result = try await functions.httpsCallable("createTeamWorkspace").call([
            "name": name,
            "displayName": displayName ?? "",
            "email": email ?? "",
            "signedTransaction": signedTransaction
        ])
        guard let payload = result.data as? [String: Any],
              let teamId = payload["teamId"] as? String,
              !teamId.isEmpty,
              let planStatus = payload["planStatus"] as? String,
              planStatus == TeamBillingEntitlement.Status.active.rawValue,
              let memberLimit = (payload["memberLimit"] as? NSNumber)?.intValue,
              memberLimit == 3 else {
            throw TeamBillingServiceError.invalidServerResponse
        }
        return teamId
    }

    func syncTeamEntitlement(signedTransaction: String) async throws -> TeamBillingEntitlement {
        let result = try await functions.httpsCallable("syncTeamEntitlement").call([
            "signedTransaction": signedTransaction
        ])
        guard let payload = result.data as? [String: Any],
              let rawStatus = payload["planStatus"] as? String,
              let status = TeamBillingEntitlement.Status(rawValue: rawStatus) else {
            throw TeamBillingServiceError.invalidServerResponse
        }
        return TeamBillingEntitlement(
            planStatus: status,
            teamId: payload["teamId"] as? String
        )
    }

    func fetchInvitePreview(inviteCode: String) async throws -> TeamInvitePreview {
        let result = try await functions.httpsCallable("getTeamInvitePreview").call([
            "inviteCode": inviteCode
        ])
        guard let payload = result.data as? [String: Any],
              let code = payload["code"] as? String,
              let teamId = payload["teamId"] as? String,
              let workTypeValue = payload["workType"] as? String,
              let workType = TeamMemberWorkType(rawValue: workTypeValue),
              let expiresAtMillis = payload["expiresAtMillis"] as? NSNumber,
              let planStatusValue = payload["planStatus"] as? String,
              let planStatus = TeamPlanStatus(rawValue: planStatusValue) else {
            throw TeamBillingServiceError.invalidServerResponse
        }

        return TeamInvitePreview(
            code: code,
            teamId: teamId,
            teamName: payload["teamName"] as? String,
            ownerDisplayName: payload["ownerDisplayName"] as? String,
            workType: workType,
            expiresAt: Date(timeIntervalSince1970: expiresAtMillis.doubleValue / 1_000),
            planStatus: planStatus
        )
    }
}

struct TeamBillingEntitlement: Equatable {
    enum Status: String {
        case active
        case grace
        case paused
    }

    let planStatus: Status
    let teamId: String?
}

enum TeamBillingServiceError: LocalizedError {
    case invalidServerResponse

    var errorDescription: String? {
        switch self {
        case .invalidServerResponse:
            return "Team billing was verified, but the workspace response was incomplete. Try again."
        }
    }
}
