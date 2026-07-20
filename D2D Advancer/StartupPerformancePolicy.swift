import Foundation

enum StartupMaintenancePolicy {
    static let leadCleanupVersion = 1
    static let leadCleanupVersionKey = "startup.leadCleanupVersion"
    static let integrityCheckDateKey = "startup.lastIntegrityCheckDate"
    static let integrityCheckInterval: TimeInterval = 7 * 24 * 60 * 60

    static func shouldRunLeadCleanup(completedVersion: Int) -> Bool {
        completedVersion < leadCleanupVersion
    }

    static func shouldRunIntegrityCheck(lastRunAt: Date?, now: Date = Date()) -> Bool {
        guard let lastRunAt else { return true }
        return now.timeIntervalSince(lastRunAt) >= integrityCheckInterval
    }
}

enum MapRuntimeRetentionPolicy {
    static let idlePrewarmDelay: TimeInterval = 4
    static let hiddenRetentionInterval: TimeInterval = 15

    static func shouldPrewarm(
        isMapSelected: Bool,
        isSyncBusy: Bool,
        isTeamLoading: Bool,
        isLowPowerModeEnabled: Bool,
        thermalState: ProcessInfo.ThermalState,
        applicationIsActive: Bool
    ) -> Bool {
        guard !isMapSelected,
              !isSyncBusy,
              !isTeamLoading,
              !isLowPowerModeEnabled,
              applicationIsActive else {
            return false
        }
        return thermalState == .nominal || thermalState == .fair
    }

    static func shouldReleaseForThermalState(_ thermalState: ProcessInfo.ThermalState) -> Bool {
        thermalState == .serious || thermalState == .critical
    }
}
