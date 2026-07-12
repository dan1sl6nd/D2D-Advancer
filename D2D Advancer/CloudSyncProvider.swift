import Foundation

enum CloudSyncProvider: String, CaseIterable {
    case off = "off"
    case firebase = "firebase"
    case icloud = "icloud"

    var displayName: String {
        switch self {
        case .off: return "Off"
        case .firebase: return "Firebase"
        case .icloud: return "iCloud"
        }
    }

    var icon: String {
        switch self {
        case .off: return "icloud.slash"
        case .firebase: return "flame"
        case .icloud: return "icloud.fill"
        }
    }

    private static let storageKey = "cloudSyncProvider"

    static var current: CloudSyncProvider {
        get {
            let raw = UserDefaults.standard.string(forKey: storageKey) ?? CloudSyncProvider.icloud.rawValue
            return CloudSyncProvider(rawValue: raw) ?? .icloud
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: storageKey)
        }
    }
}

enum PersonalCloudMigrationPhase: String, Equatable {
    case idle
    case firebaseMerge
    case iCloudUpload
    case completed
}

enum PersonalCloudMigrationStateStore {
    nonisolated static let phaseKey = "personalCloudMigrationPhaseV1"
    nonisolated static let completedAtKey = "personalCloudMigrationCompletedAtV1"

    nonisolated static func phase(in defaults: UserDefaults = .standard) -> PersonalCloudMigrationPhase {
        guard let rawValue = defaults.string(forKey: phaseKey) else { return .idle }
        return PersonalCloudMigrationPhase(rawValue: rawValue) ?? .idle
    }

    nonisolated static func setPhase(
        _ phase: PersonalCloudMigrationPhase,
        in defaults: UserDefaults = .standard
    ) {
        defaults.set(phase.rawValue, forKey: phaseKey)
        if phase == .completed {
            defaults.set(Date(), forKey: completedAtKey)
        }
    }
}

enum PersonalCloudMigrationPolicy {
    nonisolated static func availableProviders(current: CloudSyncProvider) -> [CloudSyncProvider] {
        current == .firebase ? [.firebase, .icloud] : [.icloud]
    }

    nonisolated static func needsFirebaseMerge(current: CloudSyncProvider) -> Bool {
        current == .firebase
    }
}
