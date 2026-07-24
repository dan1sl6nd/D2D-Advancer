import Foundation

/// Canonical account profile payload used for Firebase + CloudKit mirror sync.
struct AccountProfileSyncPayload: Sendable {
    let userId: String
    let email: String
    let displayName: String
    let isEmailVerified: Bool
    let isPremium: Bool
    let onboardingCompleted: Bool
    let onboardingProfileJSON: String?
    let preferencesJSON: String?
    let createdAt: Date
    let updatedAt: Date
    let lastSignInAt: Date?

    var firestoreData: [String: Any] {
        var data: [String: Any] = [
            "email": email,
            "displayName": displayName,
            "isEmailVerified": isEmailVerified,
            "isPremium": isPremium,
            "onboardingCompleted": onboardingCompleted,
            "createdAt": createdAt,
            "updatedAt": updatedAt,
            "profileVersion": 2
        ]

        if let onboardingProfileJSON {
            data["onboardingProfileJSON"] = onboardingProfileJSON
        }

        if let preferencesJSON {
            data["preferencesJSON"] = preferencesJSON
        }

        if let lastSignInAt {
            data["lastSignInAt"] = lastSignInAt
        }

        return data
    }
}
