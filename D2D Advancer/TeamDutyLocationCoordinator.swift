import Combine
import CoreLocation
import Foundation

@MainActor
final class TeamDutyLocationCoordinator: ObservableObject {
    static let shared = TeamDutyLocationCoordinator()

    @Published private(set) var lastErrorMessage: String?

    private let locationManager = LocationManager.shared
    private let teamService = TeamFirebaseService.shared
    private var cancellables = Set<AnyCancellable>()
    private var isStarted = false
    private var isUploading = false
    private var activeSessionId: String?
    private var lastUploadAt: Date?
    private var lastUploadCoordinate: TeamCoordinate?
    private var retryNotBefore: Date?

    private init() {}

    func start() {
        guard !isStarted else { return }
        isStarted = true

        teamService.$activeDutySession
            .map { $0?.id }
            .removeDuplicates()
            .sink { [weak self] sessionId in
                self?.handleSessionChange(sessionId)
            }
            .store(in: &cancellables)

        locationManager.$location
            .compactMap { $0 }
            .sink { [weak self] location in
                self?.publishIfNeeded(location)
            }
            .store(in: &cancellables)
    }

    func beginActiveSession() {
        activeSessionId = teamService.activeDutySession?.id
        lastUploadAt = nil
        lastUploadCoordinate = nil
        retryNotBefore = nil
        lastErrorMessage = nil
        locationManager.startLocationUpdates()
        locationManager.requestImmediateLocation()

        if let location = locationManager.location {
            publishIfNeeded(location, force: true)
        }
    }

    func endActiveSession() {
        activeSessionId = nil
        lastUploadAt = nil
        lastUploadCoordinate = nil
        retryNotBefore = nil
        lastErrorMessage = nil
    }

    private func handleSessionChange(_ sessionId: String?) {
        guard sessionId != activeSessionId else { return }
        activeSessionId = sessionId
        lastUploadAt = nil
        lastUploadCoordinate = nil
        retryNotBefore = nil
        lastErrorMessage = nil

        guard sessionId != nil else { return }
        locationManager.startLocationUpdates()
        locationManager.requestImmediateLocation()

        if let location = locationManager.location {
            publishIfNeeded(location, force: true)
        }
    }

    private func publishIfNeeded(_ location: CLLocation, force: Bool = false) {
        guard let member = teamService.currentMember,
              let session = teamService.activeDutySession,
              session.id == activeSessionId else {
            return
        }
        let coordinate = TeamCoordinate(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude
        )
        let now = Date()
        guard TeamLocationSharingPolicy.canPublishLocation(
            timestamp: location.timestamp,
            horizontalAccuracy: location.horizontalAccuracy,
            now: now
        ) else {
            return
        }
        guard retryNotBefore.map({ $0 <= now }) ?? true else { return }
        guard force || TeamLocationSharingPolicy.shouldUploadLocation(
            lastUploadAt: lastUploadAt,
            lastCoordinate: lastUploadCoordinate,
            newCoordinate: coordinate,
            usageLevel: teamService.teamUsageControl.level,
            now: now
        ) else {
            return
        }
        guard !isUploading else { return }

        isUploading = true
        Task { [weak self] in
            guard let self else { return }
            do {
                try await self.teamService.recordCurrentLocation(location, member: member, now: now)
                guard self.activeSessionId == session.id else {
                    self.isUploading = false
                    return
                }
                self.lastUploadAt = now
                self.lastUploadCoordinate = coordinate
                self.retryNotBefore = nil
                self.lastErrorMessage = nil
            } catch {
                self.retryNotBefore = now.addingTimeInterval(
                    TeamLocationSharingPolicy.minimumUploadInterval
                )
                self.lastErrorMessage = TeamFirebaseService.userFacingErrorMessage(for: error)
                AppLog.warning("Team", "Duty location upload failed: \(error.localizedDescription)")
            }
            self.isUploading = false
        }
    }
}
