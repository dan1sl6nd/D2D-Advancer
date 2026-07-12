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
              !teamId.isEmpty else {
            throw TeamBillingServiceError.invalidServerResponse
        }
        return teamId
    }

    func syncTeamEntitlement(signedTransaction: String) async throws {
        _ = try await functions.httpsCallable("syncTeamEntitlement").call([
            "signedTransaction": signedTransaction
        ])
    }
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
