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
